import AppKit
import XCTest
import os
@testable import DMonteCore

/// Covers the activation-history resolution shared by the Window Manager (snap target) and the
/// Clipboard (paste target): dead-process pruning, the suspicious-activation skip near
/// popover-open, history bounding, and the session freeze. The resolution core is exercised via
/// the pure `ActivationTracker.resolve` with a fake `isLive` predicate so no live processes are
/// needed.
final class ActivationTrackerTests: XCTestCase {

    /// Fixed "now" so ages are deterministic.
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)

    private func entry(pid: pid_t, name: String? = nil, age: TimeInterval, isUserSelection: Bool = false) -> ActivationTracker.Entry {
        ActivationTracker.Entry(pid: pid, name: name, at: now.addingTimeInterval(-age), isUserSelection: isUserSelection)
    }

    // MARK: - Pure resolution

    func testEmptyHistoryResolvesToNothing() {
        var history: [ActivationTracker.Entry] = []
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .noLiveHistory)
    }

    func testDeadEntriesArePrunedBeforeResolution() {
        var history = [entry(pid: 1, age: 10), entry(pid: 2, age: 5)]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in false })
        XCTAssertEqual(result, .noLiveHistory)
        XCTAssertTrue(history.isEmpty, "dead entries must not linger for the next resolution")
    }

    func testMostRecentActivationWinsWhenOldEnough() {
        let older = entry(pid: 1, age: 30)
        let recent = entry(pid: 2, age: 2)
        var history = [older, recent]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(recent))
        XCTAssertEqual(history, [older, recent], "a trustworthy entry must not be dropped")
    }

    func testSuspiciouslyYoungActivationIsSkippedAndDropped() {
        // The cross-display popover-open shift: the click re-activated pid 2 ~50 ms before we
        // ran, so the target is the app the user was actually in (pid 1).
        let user = entry(pid: 1, name: "Claude", age: 30)
        let spurious = entry(pid: 2, name: "Unity", age: 0.05)
        var history = [user, spurious]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: user, skipped: spurious))
        XCTAssertEqual(history, [user], "the skipped entry is dropped so reopening resolves consistently")
    }

    func testRecentRealActivationOutsideWarmClickWindowIsKept() {
        // Selecting a new window and then going to the menu bar can be quick. Only the very tight
        // warm status-item reactivation window should be skipped; otherwise the newly selected
        // window is the user's real target.
        let older = entry(pid: 1, name: "Older", age: 30)
        let selected = entry(pid: 2, name: "Selected", age: 0.25)
        var history = [older, selected]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(selected))
        XCTAssertEqual(history, [older, selected])
    }

    func testYoungUserWindowSelectionIsNotSkipped() {
        // Same-app window switches do not send an app activation notification, so the controller
        // records mouse-selected windows separately. Those explicit selections must survive even
        // when they are very close to opening the tray.
        let older = entry(pid: 1, name: "Older", age: 30)
        let selected = entry(pid: 2, name: "Selected", age: 0.05, isUserSelection: true)
        var history = [older, selected]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(selected))
        XCTAssertEqual(history, [older, selected])
    }

    func testSuspiciousShiftResolvesToTheSameAppTheUserWasInNotAnOlderApp() {
        // The multi-monitor "snapped the wrong window" bug. The display-switch shift re-activates an
        // app that is *already* the user's app (pid 2) — it owns the top window on the popover's
        // display too. The skip must land on that same-app entry, whose snapshot still points at the
        // window on the other display, NOT jump past it to the unrelated older app (pid 1).
        let other = entry(pid: 1, age: 30)
        let earlierSame = entry(pid: 2, name: "Target", age: 10)
        let spurious = entry(pid: 2, age: 0.1)
        var history = [other, earlierSame, spurious]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: earlierSame, skipped: spurious))
        XCTAssertEqual(history, [other, earlierSame], "only the suspicious reactivation is dropped")
    }

    func testUserSelectionSurvivesSameAppDisplaySwitchReactivation() {
        // The reported bug end-to-end at the resolver: the user clicked into app 2's window on the
        // left display (a user selection), then opened the popover from the primary display's menu
        // bar, which re-activated app 2 (now its window on the primary display). The resolver must
        // return the user's selection — with the left-window snapshot — not the reactivation.
        let selection = entry(pid: 2, name: "LeftWindow", age: 8, isUserSelection: true)
        let reactivation = entry(pid: 2, name: "PrimaryWindow", age: 0.05)
        var history = [selection, reactivation]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: selection, skipped: reactivation))
        XCTAssertEqual(history, [selection])
    }

    func testEntireTrailingShiftRunIsPeeled() {
        // The display switch can emit more than one activation in quick succession; every one is
        // noise and must be peeled to reach the user's real target.
        let target = entry(pid: 1, name: "Real", age: 20)
        let shiftA = entry(pid: 3, age: 0.12)
        let shiftB = entry(pid: 2, age: 0.06)
        var history = [target, shiftA, shiftB]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: target, skipped: shiftB))
        XCTAssertEqual(history, [target], "both suspicious activations are dropped")
    }

    func testYoungActivationWithNoDifferentPredecessorIsKept() {
        // Right after launch the history may hold only the click's own activation — better to
        // target it than nothing.
        let only = entry(pid: 2, age: 0.05)
        var history = [only]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(only))
        XCTAssertEqual(history, [only])
    }

    func testYoungSamePidActivationResolvesToTheOlderPreShiftEntry() {
        // Only same-pid history: the recent one is the display-switch reactivation (its snapshot is
        // the window now focused on the popover's display); the older one holds the window the user
        // was actually in. Prefer the older, pre-shift entry. If no display switch actually
        // happened the frames match, so the AXWindowNumber lookup lands on the same window anyway —
        // preferring the older snapshot is strictly safer.
        let preShift = entry(pid: 2, name: "Before", age: 20)
        let shift = entry(pid: 2, name: "AfterClick", age: 0.05)
        var history = [preShift, shift]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: preShift, skipped: shift))
        XCTAssertEqual(history, [preShift])
    }

    func testAgeJustOutsideTheWindowIsNotSuspicious() {
        let older = entry(pid: 1, age: 30)
        let boundary = entry(pid: 2, age: ActivationTracker.spuriousActivationWindow + 0.001)
        var history = [older, boundary]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(boundary))
    }

    func testDeadPredecessorIsPrunedBeforeTheSkipSearch() {
        // pid 1 quit since it was recorded; the skip must land on the live pid 3, not resolve
        // against a corpse.
        let dead = entry(pid: 1, age: 60)
        let live = entry(pid: 3, age: 30)
        let spurious = entry(pid: 2, age: 0.05)
        var history = [dead, live, spurious]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { $0 != 1 })
        XCTAssertEqual(result, .skippedSuspicious(target: live, skipped: spurious))
        XCTAssertEqual(history, [live])
    }

    func testCustomSuspiciousWindowIsHonored() {
        let older = entry(pid: 1, age: 30)
        let recent = entry(pid: 2, age: 0.8)
        var history = [older, recent]
        let result = ActivationTracker.resolve(history: &history, now: now, suspiciousWindow: 1.0, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: older, skipped: recent))
    }

    // MARK: - Recording & session freeze

    @MainActor
    private func makeTracker() -> ActivationTracker {
        ActivationTracker(
            logger: Logger(subsystem: "com.havokentity.mactools.tests", category: "activation-tracker"),
            excluding: { _ in false }
        )
    }

    @MainActor
    func testHistoryIsBounded() {
        let tracker = makeTracker()
        defer { tracker.stopObserving() }
        for pid in 1...12 {
            tracker.record(entry(pid: pid_t(pid), age: 0))
        }
        XCTAssertEqual(tracker.history.count, ActivationTracker.maxHistory)
        XCTAssertEqual(tracker.history.first?.pid, 5, "oldest entries are evicted first")
        XCTAssertEqual(tracker.history.last?.pid, 12)
    }

    @MainActor
    func testSessionFreezesRecording() {
        let tracker = makeTracker()
        defer { tracker.stopObserving() }
        tracker.record(entry(pid: 1, age: 10))

        tracker.beginSession()
        XCTAssertTrue(tracker.isSessionActive)
        tracker.record(entry(pid: 2, age: 0))
        XCTAssertEqual(tracker.history.map(\.pid), [1], "activations during a session must not be recorded")

        tracker.endSession()
        XCTAssertFalse(tracker.isSessionActive)
        tracker.record(entry(pid: 3, age: 0))
        XCTAssertEqual(tracker.history.map(\.pid), [1, 3])
    }

    @MainActor
    func testResolveTargetIsNilWithoutHistory() {
        let tracker = makeTracker()
        defer { tracker.stopObserving() }
        XCTAssertNil(tracker.resolveTarget(now: now))
    }

    @MainActor
    func testResolveTargetPrunesDeadPids() {
        // pid_t is Int32; no real process can hold a pid this large, so liveApp must fail and
        // the entry must be pruned rather than resolved.
        let tracker = makeTracker()
        defer { tracker.stopObserving() }
        tracker.record(entry(pid: pid_t.max, age: 10))
        XCTAssertNil(tracker.resolveTarget(now: now))
        XCTAssertTrue(tracker.history.isEmpty)
    }
}
