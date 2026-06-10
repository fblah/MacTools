import AppKit
import ApplicationServices
import Combine

/// Outcome of applying a window action, so the UI can show a precise message.
public enum WindowApplyResult: Equatable, Sendable {
    /// The window moved; carries the localized name of the app whose window was snapped so the
    /// UI can show *which* window was acted on (the wrong-target failure mode is otherwise
    /// invisible to the user).
    case success(appName: String?)
    case needsPermission
    case noFocusedWindow
    case failed
}

/// Outcome of assigning a custom shortcut.
public enum ShortcutAssignment: Equatable, Sendable {
    case assigned
    /// The shortcut is already bound to another action in this tool.
    case conflict(WindowAction)
    /// The shortcut lacks ⌘⌃⌥ (and isn't a bare function key), so it would swallow typing.
    case needsModifiers
}

/// Drives the Window Manager: tracks Accessibility permission, registers the global snap
/// shortcuts, and applies a `WindowAction` to the frontmost app's focused window through the
/// Accessibility API. The geometry itself comes from the pure `WindowManagerKit`.
@MainActor
public final class WindowManagerController: ObservableObject {
    /// Whether this process is trusted for Accessibility (required to move other apps' windows).
    @Published public private(set) var hasAccessibility = false

    /// The most recent apply outcome, for transient UI feedback.
    @Published public private(set) var lastResult: WindowApplyResult?

    /// Effective shortcuts (user overrides over defaults), keyed by action.
    @Published public private(set) var shortcuts: [WindowAction: WindowShortcut] = [:]

    /// Actions whose hotkey could not be registered, with the failing OSStatus. Shown inline on
    /// the shortcut rows ("in use by macOS or another app").
    @Published public private(set) var registrationFailures: [WindowAction: Int32] = [:]

    /// Whether macOS Secure Event Input is currently suppressing all global hotkeys (password
    /// fields, lock screen, or a stuck loginwindow). Registration succeeds but no events arrive.
    @Published public private(set) var secureInputBlocked = false

    private var hotKeys: [GlobalHotKey] = []
    private var permissionTimer: Timer?
    private let shortcutStore: WindowShortcutStore

    /// Bundle-id prefix shared by the Toolbox and every helper. Snaps never target our own
    /// windows: when the Toolbox is frontmost (e.g. right after launching this helper with
    /// `--open`), the user means the window *underneath*, not the Toolbox.
    private static let suiteBundlePrefix = "com.havokentity.mactools"

    /// How long an AX call may block before we give up, so one hung app can't beachball us.
    private static let axMessagingTimeoutSeconds: Float = 3.0

    public init(defaults: UserDefaults? = nil) {
        let store = WindowShortcutStore(defaults: defaults ?? AppDefaults.shared)
        shortcutStore = store
        shortcuts = store.effectiveShortcuts()
        hasAccessibility = AXIsProcessTrusted()
        secureInputBlocked = SecureInputState.isBlockingHotKeys
    }

    // No `deinit` cleanup: under Swift 6 a nonisolated deinit may not touch the @MainActor,
    // non-Sendable `permissionTimer` (same constraint as FocusTimer/KeepAwake). The timer is a
    // repeating poll that captures only `[weak self]`, so it cannot keep the controller alive;
    // it is invalidated deterministically on the main actor once permission is granted, and the
    // controller is app-lifetime in practice.

    // MARK: - Permission

    /// Refreshes the cached permission flag (the system grant can change while we run) and
    /// reconciles hotkey registration with it:
    /// - false → true (grant detected at popover-open or via polling): register.
    /// - true → false (revoked): release every hotkey so the combos aren't swallowed while unusable.
    /// - still true but keys are missing or some failed earlier (e.g. the conflicting app quit):
    ///   re-attempt, so opening the popover doubles as a retry.
    public func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        secureInputBlocked = SecureInputState.isBlockingHotKeys
        if trusted != hasAccessibility {
            hasAccessibility = trusted
        }
        if trusted {
            if hotKeys.isEmpty || !registrationFailures.isEmpty {
                registerHotKeys()
            }
        } else if !hotKeys.isEmpty || !registrationFailures.isEmpty {
            unregisterHotKeys()
        }
    }

    /// Shows the system Accessibility prompt and opens the relevant Settings pane. Also starts a
    /// light poll so the UI updates (and hotkeys register) as soon as the grant is given, since the
    /// system sends no notification for it.
    public func requestPermission() {
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPermission()
                if self.hasAccessibility {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Hotkeys

    /// Registers the effective (user-customized, defaults as fallback) global shortcuts. Each
    /// action gets a unique Carbon hotkey id so the registrations don't collide. Safe to call
    /// repeatedly — it releases the old set first (required: `GlobalHotKey` refuses an id that is
    /// still live) and rebuilds. Failures are recorded per action instead of vanishing.
    public func registerHotKeys() {
        hotKeys.removeAll() // releases old registrations (deinit frees each Carbon id) before re-claiming
        registrationFailures = [:]

        var nextID: UInt32 = 1
        for action in WindowAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            let id = nextID
            nextID += 1
            do {
                let key = try GlobalHotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, id: id) { [weak self] in
                    Task { @MainActor in
                        self?.apply(action)
                    }
                }
                hotKeys.append(key)
            } catch let error as GlobalHotKeyRegistrationError {
                registrationFailures[action] = Self.statusCode(for: error)
            } catch {
                registrationFailures[action] = -1
            }
        }
        secureInputBlocked = SecureInputState.isBlockingHotKeys
    }

    /// Releases every registered hotkey (used when Accessibility is revoked: holding combos we
    /// can't act on would swallow the user's keystrokes for nothing).
    public func unregisterHotKeys() {
        hotKeys.removeAll()
        registrationFailures = [:]
    }

    private static func statusCode(for error: GlobalHotKeyRegistrationError) -> Int32 {
        switch error {
        case .duplicateID: -2
        case .eventHandlerUnavailable: -3
        case .registrationFailed(let status): status
        }
    }

    // MARK: - Shortcut customization

    /// The effective shortcut for an action (user override, else built-in default).
    public func shortcut(for action: WindowAction) -> WindowShortcut? {
        shortcuts[action]
    }

    /// The action currently holding `shortcut`, if any (used for duplicate prevention).
    public func actionUsing(_ shortcut: WindowShortcut, excluding excluded: WindowAction? = nil) -> WindowAction? {
        shortcuts.first { action, existing in action != excluded && existing == shortcut }?.key
    }

    /// Assigns a custom shortcut, persists it, and re-registers the hotkeys live. Refuses
    /// duplicates within the tool and modifier-less non-function keys.
    @discardableResult
    public func assignShortcut(_ shortcut: WindowShortcut, to action: WindowAction) -> ShortcutAssignment {
        guard shortcut.isUsableGlobally else { return .needsModifiers }
        if let holder = actionUsing(shortcut, excluding: action) { return .conflict(holder) }

        shortcutStore.save(shortcut, for: action)
        shortcuts = shortcutStore.effectiveShortcuts()
        if hasAccessibility { registerHotKeys() }
        return .assigned
    }

    /// Drops every custom shortcut and re-registers the built-in defaults.
    public func resetShortcutsToDefaults() {
        shortcutStore.reset()
        shortcuts = shortcutStore.effectiveShortcuts()
        if hasAccessibility { registerHotKeys() }
    }

    // MARK: - Apply

    /// Applies `action` to the target app's focused window. Returns the outcome and also
    /// publishes it to `lastResult`.
    @discardableResult
    public func apply(_ action: WindowAction) -> WindowApplyResult {
        lastResult = applyResult(for: action)
        return lastResult ?? .failed
    }

    private func applyResult(for action: WindowAction) -> WindowApplyResult {
        guard AXIsProcessTrusted() else {
            hasAccessibility = false
            return .needsPermission
        }
        hasAccessibility = true

        guard let targetApp = targetApplication(), let window = focusedWindow(of: targetApp) else {
            return .noFocusedWindow
        }

        guard let currentFrame = frame(of: window) else {
            return .failed
        }

        // Pick the screen the window mostly lives on, then compute the target in AX (top-left)
        // space. The pure matcher gets the real screens as plain rects; if the window overlaps no
        // screen at all, fall back to the primary screen (never NSScreen.main — when a snap tile
        // is clicked, the key window is our own popover, so NSScreen.main is the popover's screen,
        // not anything to do with the target window).
        let screens = NSScreen.screens
        let areas = screens.map { Self.axRect(fromCocoa: $0.visibleFrame) }
        let matched = WindowManagerKit.areaIndex(forWindow: currentFrame, in: areas).map { screens[$0] }
        guard let screen = matched ?? screens.first else {
            return .failed
        }
        let axArea = Self.axRect(fromCocoa: screen.visibleFrame)
        let target = WindowManagerKit.frame(for: action, in: axArea)

        // Apply position → size → position: shrinking/positioning in two passes lets a window move
        // to a smaller display before its final size is set, which a single pass can clamp.
        let positionResult = setPosition(target.origin, on: window)
        let sizeResult = setSize(target.size, on: window)
        let finalPositionResult = setPosition(target.origin, on: window)

        // The set calls used to be fire-and-forget, which made every failure on any display look
        // like "nothing happened" while the UI claimed success. Check all three.
        let results = [positionResult, sizeResult, finalPositionResult]
        if results.contains(.apiDisabled) {
            return .needsPermission
        }
        guard results.allSatisfy({ $0 == .success }) else {
            return .failed
        }

        return .success(appName: targetApp.localizedName)
    }

    // MARK: - Target selection

    /// The app whose focused window should be snapped. Normally the frontmost app — but never
    /// one of our own (Toolbox/helpers): right after the Toolbox launches this helper with
    /// `--open`, the Toolbox itself is frontmost, and snapping *its* window on the primary
    /// display while the user's window on another display stays put is exactly the
    /// "moves the wrong window" bug. In that case we target the topmost ordinary window owned
    /// by any other app instead.
    private func targetApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if !isSuiteApplication(frontmost) { return frontmost }
        return topmostOtherApplication()
    }

    private func isSuiteApplication(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        return app.bundleIdentifier?.hasPrefix(Self.suiteBundlePrefix) == true
    }

    /// Walks the on-screen window list front-to-back and returns the owner of the first
    /// normal-layer window that doesn't belong to this suite. Only layer and owner PID are read,
    /// neither of which requires Screen Recording permission.
    private func topmostOtherApplication() -> NSRunningApplication? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in windowList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid),
                  !isSuiteApplication(app) else { continue }
            return app
        }
        return nil
    }

    // MARK: - Accessibility element access

    private func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Bound how long a hung app may block us; without this a beachballing app freezes the
        // helper (and the popover) for the system default of several seconds per call.
        AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeoutSeconds)
        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard status == .success, let windowRef,
              CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, Self.axMessagingTimeoutSeconds)
        return window
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute, type: .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, type: .cgSize, as: CGSize.self) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    private func setPosition(_ point: CGPoint, on window: AXUIElement) -> AXError {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
    }

    @discardableResult
    private func setSize(_ size: CGSize, on window: AXUIElement) -> AXError {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
    }

    /// Reads an AXValue attribute and unwraps it to a concrete CG type.
    private func axValue<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType, as: T.Type) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let axValue = ref as! AXValue
        guard AXValueGetType(axValue) == type else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }

    // MARK: - Coordinate conversion (Cocoa bottom-left ↔ AX top-left)

    /// Converts a Cocoa global rect (origin bottom-left of the primary screen, y up) to AX/Quartz
    /// global space (origin top-left of the primary screen, y down). `nonisolated` so the pure
    /// geometry is callable (and testable) off the main actor; it only reads the primary screen's
    /// height, which is safe to touch from any thread. The math itself lives in
    /// `WindowManagerKit.axRect(fromCocoa:primaryScreenHeight:)`.
    nonisolated static func axRect(fromCocoa rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.height
        return WindowManagerKit.axRect(fromCocoa: rect, primaryScreenHeight: primaryHeight)
    }
}
