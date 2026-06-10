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

    private func entry(pid: pid_t, name: String? = nil, age: TimeInterval) -> ActivationTracker.Entry {
        ActivationTracker.Entry(pid: pid, name: name, at: now.addingTimeInterval(-age))
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

    func testSkipSearchesPastSamePidPredecessors() {
        // The spurious shift can re-activate an app that already has history entries; the skip
        // must find the nearest *different* pid, not just the literal previous entry.
        let other = entry(pid: 1, age: 30)
        let earlierSame = entry(pid: 2, age: 10)
        let spurious = entry(pid: 2, age: 0.1)
        var history = [other, earlierSame, spurious]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .skippedSuspicious(target: other, skipped: spurious))
        XCTAssertEqual(history, [other, earlierSame])
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

    func testYoungActivationWithOnlySamePidHistoryIsKept() {
        var history = [entry(pid: 2, age: 20), entry(pid: 2, age: 0.05)]
        let result = ActivationTracker.resolve(history: &history, now: now, isLive: { _ in true })
        XCTAssertEqual(result, .mostRecent(history[1]))
        XCTAssertEqual(history.count, 2)
    }

    func testAgeAtExactlyTheWindowIsNotSuspicious() {
        let older = entry(pid: 1, age: 30)
        let boundary = entry(pid: 2, age: ActivationTracker.spuriousActivationWindow)
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
