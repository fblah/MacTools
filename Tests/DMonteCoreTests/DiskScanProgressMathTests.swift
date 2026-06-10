import XCTest
@testable import DMonteCore

/// Pins the scan-progress arithmetic in DiskScanProgressMath. This math shipped a
/// >100% display bug (fixed in 0.8.6 without a regression test) while it was buried
/// in a private view; these tables exist so the constants and clamps can't regress
/// silently again. Where a case pins a quirk rather than a desideratum it says so —
/// the goal is to freeze current behavior, not to bless it.
final class DiskScanProgressMathTests: XCTestCase {
    private let accuracy = 1e-12

    // MARK: - byteRatio

    func testByteRatio() {
        let cases: [(scanned: UInt64, estimated: UInt64, expected: Double, note: String)] = [
            (0, 1_000, 0, "nothing scanned"),
            (500, 1_000, 0.5, "mid-scan"),
            (1_000, 1_000, 1, "exactly at the estimate"),
            (1_500, 1_000, 1.5, "past the estimate — must NOT clamp, callers detect the regime from >= 1"),
            (42, 0, 42, "zero estimate floors the denominator at 1 instead of dividing by zero")
        ]

        for c in cases {
            XCTAssertEqual(
                DiskScanProgressMath.byteRatio(scannedBytes: c.scanned, estimatedBytes: c.estimated),
                c.expected,
                accuracy: accuracy,
                c.note
            )
        }
    }

    // MARK: - Regime switch

    func testExceededEstimateRegimeHandoffIsAtExactlyOne() {
        XCTAssertFalse(DiskScanProgressMath.exceededEstimate(byteRatio: 0))
        XCTAssertFalse(DiskScanProgressMath.exceededEstimate(byteRatio: 0.999999))
        XCTAssertTrue(DiskScanProgressMath.exceededEstimate(byteRatio: 1), "regime switch is >= 1, not > 1")
        XCTAssertTrue(DiskScanProgressMath.exceededEstimate(byteRatio: 2.5))
    }

    // MARK: - directoryFraction

    func testDirectoryFraction() {
        let cases: [(scanned: Int, discovered: Int, expected: Double, note: String)] = [
            (0, 0, 0, "empty progress"),
            (50, 100, 0.5, "mid-scan"),
            (99, 100, 0.99, "approaching completion"),
            (100, 100, 1, "complete"),
            // THE 0.8.6 REGRESSION: the tracker can momentarily report fewer
            // discovered than scanned; dividing by raw `discovered` yielded 2.0 and a
            // >100% display. The denominator must absorb scanned so this clamps to 1.
            (10, 5, 1, "discovered lagging scanned must clamp to 1, never exceed it"),
            (10, 0, 1, "zero discovered with progress still clamps")
        ]

        for c in cases {
            XCTAssertEqual(
                DiskScanProgressMath.directoryFraction(directoriesScanned: c.scanned, directoriesDiscovered: c.discovered),
                c.expected,
                accuracy: accuracy,
                c.note
            )
        }
    }

    // MARK: - scanProgressFraction

    func testScanProgressFraction() {
        let cases: [(byteRatio: Double, folder: Double, expected: Double, note: String)] = [
            (0, 0, 0, "scan start"),
            (0, 1, 0, "folders alone contribute nothing before bytes move"),
            (0.5, 0.5, 0.5 * (0.96 + 0.025 * 0.5), "mid-scan: bytes dominate, folders nudge the slope"),
            (0.99, 1, min(0.985, 0.99 * 0.985), "approaching the estimate"),
            (0.9999, 0, 0.9999 * 0.96, "just below the handoff, no folder help"),
            (1, 0, 0.96, "handoff: exceeded regime floor"),
            (1, 0.5, 0.96 + 0.035 * 0.5, "exceeded regime, folders half done"),
            (1, 1, 0.995, "exceeded regime tops out at the 0.995 cap"),
            (2, 0.5, 0.96 + 0.035 * 0.5, "byteRatio magnitude is irrelevant past the switch"),
            (-0.5, 0.5, 0, "negative byte ratio clamps to zero"),
            (0.5, 2, 0.5 * 0.985, "out-of-range folder fraction clamps to 1")
        ]

        for c in cases {
            XCTAssertEqual(
                DiskScanProgressMath.scanProgressFraction(byteRatio: c.byteRatio, folderFraction: c.folder),
                c.expected,
                accuracy: accuracy,
                c.note
            )
        }
    }

    func testScanProgressFractionNeverReachesOne() {
        // The percent label derives from this fraction; the panel disappears when the
        // scan finishes, so the fraction itself must stay strictly below 1 in both
        // regimes (caps: 0.985 normal, 0.995 exceeded).
        for byteRatio in stride(from: 0.0, through: 3.0, by: 0.125) {
            for folder in stride(from: 0.0, through: 1.0, by: 0.25) {
                let fraction = DiskScanProgressMath.scanProgressFraction(byteRatio: byteRatio, folderFraction: folder)
                XCTAssertLessThanOrEqual(fraction, 0.995, "byteRatio \(byteRatio), folder \(folder)")
            }
        }
    }

    // MARK: - scanBarFraction

    func testScanBarFraction() {
        let cases: [(byteRatio: Double, folder: Double, expected: Double, note: String)] = [
            (0, 0, 0.02, "visibility floor: the bar never looks empty mid-scan"),
            (0.001, 0, 0.02, "tiny progress still sits on the floor"),
            (0.5, 0.5, 0.5 * (0.96 + 0.025 * 0.5), "above the floor the bar tracks scanProgressFraction exactly"),
            (1, 0, 0.96, "exceeded regime floor"),
            (1, 1, 0.995, "the bar cap: 0.995, never full"),
            (1, 2, 0.995, "out-of-range folder fraction still respects the cap")
        ]

        for c in cases {
            XCTAssertEqual(
                DiskScanProgressMath.scanBarFraction(byteRatio: c.byteRatio, folderFraction: c.folder),
                c.expected,
                accuracy: accuracy,
                c.note
            )
        }
    }

    func testBarMatchesProgressFractionInExceededRegime() {
        // Both functions must share the exceeded-regime curve — the duplicate
        // expressions that used to live in the view were one constant-tweak away from
        // a label and a bar that disagree.
        for folder in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(
                DiskScanProgressMath.scanBarFraction(byteRatio: 1.2, folderFraction: folder),
                DiskScanProgressMath.scanProgressFraction(byteRatio: 1.2, folderFraction: folder),
                accuracy: accuracy
            )
        }
    }

    // MARK: - Monotonicity (where the existing code guarantees it)

    func testProgressIsMonotonicInByteRatioBelowEstimate() {
        for folder in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var previous = -Double.infinity
            for byteRatio in stride(from: 0.0, through: 0.999, by: 0.001) {
                let fraction = DiskScanProgressMath.scanProgressFraction(byteRatio: byteRatio, folderFraction: folder)
                XCTAssertGreaterThanOrEqual(fraction, previous, "byteRatio \(byteRatio), folder \(folder)")
                previous = fraction
            }
        }
    }

    func testProgressIsMonotonicAcrossTheRegimeHandoff() {
        // Crossing byteRatio 1 jumps from the byte-driven curve onto the
        // exceeded-regime band (0.96+) — for any folder fraction the bar may leap
        // forward at the handoff, but it must never leap backward.
        for folder in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let justBelow = DiskScanProgressMath.scanProgressFraction(byteRatio: 0.999999, folderFraction: folder)
            let atHandoff = DiskScanProgressMath.scanProgressFraction(byteRatio: 1, folderFraction: folder)
            XCTAssertGreaterThanOrEqual(atHandoff, justBelow, "folder \(folder)")
        }
    }

    func testProgressIsMonotonicInFolderFractionWithinEachRegime() {
        for byteRatio in [0.3, 0.7, 1.0, 1.8] {
            var previous = -Double.infinity
            for folder in stride(from: 0.0, through: 1.0, by: 0.01) {
                let fraction = DiskScanProgressMath.scanProgressFraction(byteRatio: byteRatio, folderFraction: folder)
                XCTAssertGreaterThanOrEqual(fraction, previous, "byteRatio \(byteRatio), folder \(folder)")
                previous = fraction
            }
        }
    }

    func testKnownQuirkBarTicksBackwardWhenDiscoveryGrowsInExceededRegime() {
        // KNOWN COSMETIC QUIRK — pinned, not endorsed: in the exceeded regime the bar
        // is folder-driven, and discovering new directories grows the denominator
        // before any of them are scanned, so the folder fraction (and therefore the
        // bar) ticks backward. Current behavior; a redesign would change this test.
        let before = DiskScanProgressMath.scanBarFraction(
            byteRatio: 1.5,
            folderFraction: DiskScanProgressMath.directoryFraction(directoriesScanned: 100, directoriesDiscovered: 100)
        )
        let afterDiscovery = DiskScanProgressMath.scanBarFraction(
            byteRatio: 1.5,
            folderFraction: DiskScanProgressMath.directoryFraction(directoriesScanned: 100, directoriesDiscovered: 200)
        )

        XCTAssertLessThan(afterDiscovery, before, "discovery burst moves the exceeded-regime bar backward (pinned quirk)")
    }

    // MARK: - displayPercent

    func testDisplayPercent() {
        let cases: [(fraction: Double, expected: Int, note: String)] = [
            (0, 0, "scan start"),
            (0.48625, 48, "floors rather than rounds — never announces an unreached milestone"),
            (0.985, 98, "normal-regime cap shows 98"),
            (0.989999, 98, "still floors just under 99"),
            (0.995, 99, "exceeded-regime cap shows 99"),
            (1, 99, "the display percent caps at 99 — the panel vanishes before 100 is true"),
            (1.7, 99, "garbage above 1 still caps"),
            (-0.4, 0, "negative input clamps to 0")
        ]

        for c in cases {
            XCTAssertEqual(DiskScanProgressMath.displayPercent(scanFraction: c.fraction), c.expected, c.note)
        }
    }

    // MARK: - remainingDirectories

    func testRemainingDirectories() {
        XCTAssertEqual(DiskScanProgressMath.remainingDirectories(directoriesScanned: 50, directoriesDiscovered: 80), 30)
        XCTAssertEqual(DiskScanProgressMath.remainingDirectories(directoriesScanned: 80, directoriesDiscovered: 80), 0)
        // Same discovered-lags-scanned input as the >100% regression: must clamp at
        // zero, never go negative.
        XCTAssertEqual(DiskScanProgressMath.remainingDirectories(directoriesScanned: 10, directoriesDiscovered: 5), 0)
    }
}
