import AppKit
import os

/// Tracks recent app activations so a status-item helper can answer "which app was the user
/// working in just before the click that opened our popover/panel?" — the snap target for the
/// Window Manager, the paste target for the Clipboard.
///
/// Why a history, and not just `NSWorkspace.frontmostApplication` at open time: with "Displays
/// have separate Spaces" enabled, clicking a status item in display X's menu bar makes X the
/// active display, and macOS re-activates the topmost app *on X*. The frontmost app at open time
/// is therefore the top app on the popover's display, not the app the user was working in.
/// Worse, that spurious activation's timing relative to the status-item action is not fixed
/// (both orders observed live on a three-display Mac Studio): ~30–70 ms *before* the action on a
/// warm click (display already active, pointer already on the bar) and ~300 ms *after* it on a
/// cold one. So the newest history entry must be skippable (`resolveTarget()`), and a session
/// must freeze recording so the late-arriving shift can't poison the next open
/// (`beginSession()`/`endSession()`).
///
/// Observation is selector-based, not block-based: a block observer cannot move the non-Sendable
/// `Notification` onto the main actor under Swift 6 strict concurrency. Workspace notifications
/// are delivered on the main thread, which is what the `@objc` main-actor method relies on.
@MainActor
public final class ActivationTracker: NSObject {
    /// One observed app activation. Plain values, not a weak `NSRunningApplication`: the
    /// instances delivered in notification userInfo are not retained by NSWorkspace or anyone
    /// else, so a weak reference dies within a runloop turn (observed live: the history pruned
    /// itself empty) and a strong one would pin a quit app. The pid is re-resolved to a live app
    /// at resolve time; the name is kept for logging only.
    struct Entry: Equatable, Sendable {
        let pid: pid_t
        let name: String?
        let at: Date
        let windowSnapshot: WindowSnapshot?
        let isUserSelection: Bool

        init(pid: pid_t, name: String?, at: Date, windowSnapshot: WindowSnapshot? = nil, isUserSelection: Bool = false) {
            self.pid = pid
            self.name = name
            self.at = at
            self.windowSnapshot = windowSnapshot
            self.isUserSelection = isUserSelection
        }
    }

    public struct WindowSnapshot: Equatable, Sendable {
        let frame: CGRect?
        let number: Int?

        public init(frame: CGRect?, number: Int?) {
            self.frame = frame
            self.number = number
        }
    }

    /// Outcome of the pure resolution step (`resolve(history:now:suspiciousWindow:isLive:)`),
    /// kept separate from live-process lookup so the logic is testable without real processes.
    enum Resolution: Equatable, Sendable {
        /// No live history exists, e.g. right after launch. Callers fall back as they see fit.
        case noLiveHistory
        /// The most recent live activation is trustworthy.
        case mostRecent(Entry)
        /// The most recent activation was young enough to have been caused by the opening click
        /// itself; the entry before it (different pid) is the real target. The skipped entry has
        /// been dropped from the history so a reopened popover resolves consistently.
        case skippedSuspicious(target: Entry, skipped: Entry)
    }

    /// How close to session-open an activation must be to count as caused *by* the opening click
    /// rather than by the user. Measured live (three-display Mac Studio, separate Spaces): the
    /// spurious re-activation of the popover display's top app landed ~30–70 ms before the
    /// status-item action on a warm click and ~300 ms after it on a cold one. Late cold-click
    /// activations are absorbed by the active-session freeze, so this pre-open skip stays tight:
    /// a genuine user switch followed by a menu-bar click can happen quickly, and should not be
    /// mistaken for display-activation noise.
    public nonisolated static let spuriousActivationWindow: TimeInterval = 0.18

    /// Resolution only ever looks at the last entry and the nearest different-pid predecessor;
    /// the rest is slack for dead-process pruning.
    nonisolated static let maxHistory = 8

    /// Short history of activations (most recent last). Internal so tests can inspect it.
    private(set) var history: [Entry] = []

    /// Whether a popover/panel session is active. While true, activations are not recorded: the
    /// only ones that can arrive are the late-arriving spurious shift from the opening click
    /// (the user cannot click another window without closing the popover first — the
    /// outside-click monitor closes it on mouse-down, before that click's activation is
    /// delivered), and recording those would poison the next session's target.
    public private(set) var isSessionActive = false

    private let log: Logger

    /// Activations matching this predicate are never recorded. The Window Manager excludes the
    /// whole suite (activating our own Toolbox/helpers says nothing about which window the user
    /// wants snapped); the Clipboard excludes only its own bundle id.
    private let isExcluded: @MainActor (NSRunningApplication) -> Bool

    /// Optional focused-window fingerprint captured at activation time. The Window Manager uses
    /// this to snap the exact selected window later, instead of only remembering the app and then
    /// asking that app for whatever window is focused after the menu-bar click.
    private let windowSnapshot: @MainActor (NSRunningApplication) -> WindowSnapshot?

    public init(
        logger: Logger,
        excluding isExcluded: @escaping @MainActor (NSRunningApplication) -> Bool,
        windowSnapshot: @escaping @MainActor (NSRunningApplication) -> WindowSnapshot? = { _ in nil }
    ) {
        self.log = logger
        self.isExcluded = isExcluded
        self.windowSnapshot = windowSnapshot
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // No `deinit` cleanup: under Swift 6 a nonisolated deinit may not touch the main actor, and
    // removing a selector-based workspace observer needs it. Trackers are app-lifetime in
    // practice; `stopObserving()` exists for owners that tear down on termination.

    /// Stops observing workspace activations (for app-termination cleanup).
    public func stopObserving() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func applicationDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              !isExcluded(app) else { return }
        record(Entry(pid: app.processIdentifier, name: app.localizedName, at: Date(), windowSnapshot: windowSnapshot(app)))
    }

    /// Appends one activation, unless a session has frozen the history. Internal so tests can
    /// drive recording without posting workspace notifications.
    func record(_ entry: Entry) {
        guard !isSessionActive else {
            log.debug("activation ignored (session active): \(entry.name ?? "?", privacy: .public)")
            return
        }
        log.debug("activation: \(entry.name ?? "?", privacy: .public)")
        history.append(entry)
        if history.count > Self.maxHistory {
            history.removeFirst(history.count - Self.maxHistory)
        }
    }

    /// Freezes the history for a popover/panel session. Call *after* resolving the target (the
    /// resolution consumes the history) and as part of handling the status-item click — see
    /// `resolveTarget()` for why the order matters.
    public func beginSession() {
        isSessionActive = true
    }

    /// Ends the session: activations are recorded again.
    public func endSession() {
        isSessionActive = false
    }

    /// The app the user was meaningfully working in, resolved from the history. Most recent
    /// activation wins, except one young enough to have been caused by the opening click itself,
    /// which is skipped (and dropped, so a reopened popover resolves consistently) in favor of
    /// the app activated before it. Nil when no live history exists yet, e.g. right after launch;
    /// callers supply their own fallback.
    func resolveTargetEntry(now: Date = Date()) -> Entry? {
        switch Self.resolve(history: &history, now: now, isLive: { Self.liveApp($0) != nil }) {
        case .noLiveHistory:
            return nil
        case .mostRecent(let entry):
            let age = now.timeIntervalSince(entry.at)
            log.debug("resolve: history \(entry.name ?? "?", privacy: .public) (\(age, format: .fixed(precision: 3))s old)")
            return entry
        case .skippedSuspicious(let target, let skipped):
            let age = now.timeIntervalSince(skipped.at)
            log.debug("resolve: skipping suspicious \(skipped.name ?? "?", privacy: .public) (\(age, format: .fixed(precision: 3))s old) for \(target.name ?? "?", privacy: .public)")
            return target
        }
    }

    public func resolveTarget(now: Date = Date()) -> NSRunningApplication? {
        guard let entry = resolveTargetEntry(now: now) else { return nil }
        return Self.liveApp(entry.pid)
    }

    /// The pure resolution core. Prunes dead entries, then applies the suspicious-window skip.
    /// Mutates `history` (prune + drop of the skipped entry) exactly as `resolveTarget()` does.
    nonisolated static func resolve(
        history: inout [Entry],
        now: Date,
        suspiciousWindow: TimeInterval = spuriousActivationWindow,
        isLive: (pid_t) -> Bool
    ) -> Resolution {
        history.removeAll { !isLive($0.pid) }

        guard let last = history.last else { return .noLiveHistory }
        let age = now.timeIntervalSince(last.at)
        if age < suspiciousWindow,
           !last.isUserSelection,
           let previous = history.dropLast().last(where: { $0.pid != last.pid }) {
            history.removeLast()
            return .skippedSuspicious(target: previous, skipped: last)
        }
        return .mostRecent(last)
    }

    /// The running, non-terminated app for `pid`, or nil when it is gone.
    public nonisolated static func liveApp(_ pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
        return app
    }
}
