import AppKit
import ApplicationServices
import Combine

/// Outcome of applying a window action, so the UI can show a precise message.
public enum WindowApplyResult: Equatable, Sendable {
    case success
    case needsPermission
    case noFocusedWindow
    case failed
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

    private var hotKeys: [GlobalHotKey] = []
    private var permissionTimer: Timer?

    public init() {
        hasAccessibility = AXIsProcessTrusted()
    }

    // No `deinit` cleanup: under Swift 6 a nonisolated deinit may not touch the @MainActor,
    // non-Sendable `permissionTimer` (same constraint as FocusTimer/KeepAwake). The timer is a
    // repeating poll that captures only `[weak self]`, so it cannot keep the controller alive;
    // it is invalidated deterministically on the main actor once permission is granted, and the
    // controller is app-lifetime in practice.

    // MARK: - Permission

    /// Refreshes the cached permission flag (the system grant can change while we run).
    public func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility {
            hasAccessibility = trusted
            if trusted { registerHotKeys() }
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

    /// Registers the default global shortcuts. Each action gets a unique Carbon hotkey id so the
    /// registrations don't collide. Safe to call repeatedly — it rebuilds the set.
    public func registerHotKeys() {
        hotKeys.removeAll()
        var nextID: UInt32 = 1
        for action in WindowAction.allCases {
            guard let shortcut = action.defaultShortcut else { continue }
            let id = nextID
            nextID += 1
            let key = GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, id: id) { [weak self] in
                Task { @MainActor in
                    self?.apply(action)
                }
            }
            if let key { hotKeys.append(key) }
        }
    }

    // MARK: - Apply

    /// Applies `action` to the frontmost app's focused window. Returns the outcome and also
    /// publishes it to `lastResult`.
    @discardableResult
    public func apply(_ action: WindowAction) -> WindowApplyResult {
        guard AXIsProcessTrusted() else {
            hasAccessibility = false
            lastResult = .needsPermission
            return .needsPermission
        }
        hasAccessibility = true

        guard let window = focusedWindow() else {
            lastResult = .noFocusedWindow
            return .noFocusedWindow
        }

        guard let currentFrame = frame(of: window) else {
            lastResult = .failed
            return .failed
        }

        // Pick the screen the window mostly lives on, then compute the target in AX (top-left) space.
        let screen = screenForAXFrame(currentFrame) ?? NSScreen.main
        guard let screen else {
            lastResult = .failed
            return .failed
        }
        let axArea = Self.axRect(fromCocoa: screen.visibleFrame)
        let target = WindowManagerKit.frame(for: action, in: axArea)

        // Apply position → size → position: shrinking/positioning in two passes lets a window move
        // to a smaller display before its final size is set, which a single pass can clamp.
        setPosition(target.origin, on: window)
        setSize(target.size, on: window)
        setPosition(target.origin, on: window)

        lastResult = .success
        return .success
    }

    // MARK: - Accessibility element access

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard status == .success, let windowRef else { return nil }
        // A CFTypeRef carrying an AXUIElement; bridge it back.
        let element = windowRef as! AXUIElement
        return element
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute, type: .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, type: .cgSize, as: CGSize.self) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setPosition(_ point: CGPoint, on window: AXUIElement) {
        var value = point
        if let axValue = AXValueCreate(.cgPoint, &value) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
        }
    }

    private func setSize(_ size: CGSize, on window: AXUIElement) {
        var value = size
        if let axValue = AXValueCreate(.cgSize, &value) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
        }
    }

    /// Reads an AXValue attribute and unwraps it to a concrete CG type.
    private func axValue<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType, as: T.Type) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref else { return nil }
        let axValue = ref as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }

    // MARK: - Coordinate conversion (Cocoa bottom-left ↔ AX top-left)

    /// Converts a Cocoa global rect (origin bottom-left of the primary screen, y up) to AX/Quartz
    /// global space (origin top-left of the primary screen, y down). `nonisolated` so the pure
    /// geometry is callable (and testable) off the main actor; it only reads the primary screen's
    /// height, which is safe to touch from any thread.
    nonisolated static func axRect(fromCocoa rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.height
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Finds the NSScreen whose AX-space visible area best contains the centre of `axFrame`.
    private func screenForAXFrame(_ axFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
        for screen in NSScreen.screens {
            let axVisible = Self.axRect(fromCocoa: screen.visibleFrame)
            if axVisible.contains(center) { return screen }
        }
        // Fall back to the screen with the largest AX-space overlap.
        return NSScreen.screens.max { a, b in
            Self.axRect(fromCocoa: a.visibleFrame).intersection(axFrame).area
                < Self.axRect(fromCocoa: b.visibleFrame).intersection(axFrame).area
        }
    }
}

private extension CGRect {
    /// Area, treating a null/empty intersection as zero.
    var area: CGFloat { isNull ? 0 : width * height }
}
