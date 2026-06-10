import Carbon.HIToolbox
import Foundation

/// Why a `GlobalHotKey` registration failed — surfaced so callers can tell the user *which*
/// shortcut could not be claimed and why, instead of dropping the failure on the floor.
public enum GlobalHotKeyRegistrationError: Error, Equatable, Sendable {
    /// The per-process Carbon id is already live (a caller forgot to release the old key first).
    case duplicateID
    /// The shared Carbon event handler could not be installed.
    case eventHandlerUnavailable
    /// `RegisterEventHotKey` itself failed; the OSStatus says why (e.g. -9878
    /// `eventHotKeyExistsErr` when another process holds the combo exclusively).
    case registrationFailed(OSStatus)
}

/// Whether some process currently holds Secure Event Input (password fields, the lock screen,
/// or — notoriously — a stuck `loginwindow` after unlocking). While it is held, the system
/// suppresses *all* Carbon hotkey delivery even though registration succeeds, so surfacing this
/// is the difference between "the app is broken" and "macOS is blocking shortcuts right now".
public enum SecureInputState {
    public static var isBlockingHotKeys: Bool { IsSecureEventInputEnabled() }
}

/// A process-wide hotkey registered with Carbon's `RegisterEventHotKey`, which works from a
/// background (accessory) app without Accessibility permission. The handler fires on the main
/// thread (Carbon dispatches on the main run loop).
///
/// All instances share a single Carbon event handler (installed lazily when the first key
/// registers). The shared callback reads the fired `EventHotKeyID` off the event and routes to
/// the matching key's handler, so a process can register many hotkeys — a per-instance handler
/// that ignores the event id would swallow every hotkey press with the first-installed handler.
public final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// Four-char code 'CLIP' — the signature half of Carbon's `(signature, id)` hotkey key.
    /// The shared callback only handles events carrying this signature.
    private static let signature = OSType(0x434C_4950 /* 'CLIP' */)

    // Registry of live hotkey handlers keyed by Carbon id, plus the one shared Carbon handler.
    // `nonisolated(unsafe)` is justified because every access is main-thread-only: Carbon
    // dispatches hotkey events on the main run loop, and init/deinit run from main-thread
    // owners (app delegates / @MainActor controllers). Storing the closure (not the instance)
    // means the registry never keeps a GlobalHotKey alive beyond its owner; deinit removes the
    // entry. Internal (not private) so dispatch routing is unit-testable without real hotkeys.
    nonisolated(unsafe) static var handlersByID: [UInt32: @Sendable () -> Void] = [:]
    nonisolated(unsafe) private static var sharedEventHandler: EventHandlerRef?

    /// ⇧⌘V — the default summon shortcut, matching Paste/Pastebot.
    public static func commandShiftV(handler: @escaping @Sendable () -> Void) -> GlobalHotKey? {
        GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey),
            handler: handler
        )
    }

    /// - Parameter id: A per-process-unique identifier. Carbon keys each registration by
    ///   `(signature, id)` and the shared callback routes the event by `id`, so a process that
    ///   registers more than one hotkey (e.g. Window Manager's snap shortcuts) must pass a
    ///   distinct `id` per key — registering an `id` that is already live fails (returns `nil`).
    ///   The default of `1` keeps existing single-hotkey callers unchanged.
    ///
    /// Returns `nil` on any failure; callers that need to know *why* (to surface "shortcut in
    /// use" in the UI) should use `register(keyCode:modifiers:id:handler:)` instead.
    public convenience init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, handler: @escaping @Sendable () -> Void) {
        do {
            try self.init(registering: keyCode, modifiers: modifiers, id: id, handler: handler)
        } catch {
            return nil
        }
    }

    /// Failure-surfacing factory: like `init?`, but throws `GlobalHotKeyRegistrationError` so the
    /// caller can record the OSStatus and tell the user which shortcut could not be claimed.
    public static func register(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32 = 1,
        handler: @escaping @Sendable () -> Void
    ) throws -> GlobalHotKey {
        try GlobalHotKey(registering: keyCode, modifiers: modifiers, id: id, handler: handler)
    }

    private init(registering keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping @Sendable () -> Void) throws {
        self.id = id

        // A duplicate id would make the dispatch table ambiguous (both keys routed to one
        // handler — the very bug the registry exists to prevent), so refuse it up front.
        // `hotKeyRef` is still nil here, so deinit won't disturb the existing entry.
        guard Self.handlersByID[id] == nil else { throw GlobalHotKeyRegistrationError.duplicateID }
        guard Self.installSharedHandlerIfNeeded() else { throw GlobalHotKeyRegistrationError.eventHandlerUnavailable }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            hotKeyRef = nil
            throw GlobalHotKeyRegistrationError.registrationFailed(registerStatus)
        }

        Self.handlersByID[id] = handler
    }

    deinit {
        // A nil hotKeyRef means init failed before inserting into the registry — nothing to
        // undo (and the id may belong to another live key).
        guard let hotKeyRef else { return }
        Self.handlersByID[id] = nil
        UnregisterEventHotKey(hotKeyRef)
    }

    // MARK: - Shared dispatch

    /// Routes a fired hotkey to its registered handler. Returns `true` if the event matched a
    /// live key (signature and id) and its handler ran. Factored out of the Carbon callback so
    /// the routing decision is unit-testable without registering real hotkeys.
    static func dispatch(signature: OSType, id: UInt32) -> Bool {
        guard signature == Self.signature, let handler = handlersByID[id] else { return false }
        handler()
        return true
    }

    /// Installs the one process-wide Carbon handler for `kEventHotKeyPressed` on first use.
    /// It is intentionally never removed: it costs nothing while the registry is empty, and
    /// removing/reinstalling around the last/first key would only add states to get wrong.
    private static func installSharedHandlerIfNeeded() -> Bool {
        if sharedEventHandler != nil { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                // Return eventNotHandledErr for ids we don't know so the event propagates to
                // any other handlers in the process instead of being silently swallowed.
                return GlobalHotKey.dispatch(signature: hotKeyID.signature, id: hotKeyID.id)
                    ? noErr
                    : OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            nil,
            &sharedEventHandler
        )

        return installStatus == noErr
    }
}
