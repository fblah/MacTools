import XCTest
@testable import DMonteCore

/// Geometry tests for the window-snap engine. All work in a top-left-origin area so the math is
/// independent of any real display; the controller handles Cocoa↔AX conversion separately.
final class WindowManagerKitTests: XCTestCase {

    /// A non-zero-origin area (like a real visible frame inset below the menu bar) so off-by-origin
    /// bugs surface.
    private let area = CGRect(x: 100, y: 50, width: 1200, height: 800)

    private func frame(_ action: WindowAction) -> CGRect {
        WindowManagerKit.frame(for: action, in: area)
    }

    func testLeftHalf() {
        XCTAssertEqual(frame(.leftHalf), CGRect(x: 100, y: 50, width: 600, height: 800))
    }

    func testRightHalf() {
        XCTAssertEqual(frame(.rightHalf), CGRect(x: 700, y: 50, width: 600, height: 800))
    }

    func testTopHalf() {
        XCTAssertEqual(frame(.topHalf), CGRect(x: 100, y: 50, width: 1200, height: 400))
    }

    func testBottomHalf() {
        XCTAssertEqual(frame(.bottomHalf), CGRect(x: 100, y: 450, width: 1200, height: 400))
    }

    func testHalvesTileWithoutGapOrOverlap() {
        // Left + right halves must exactly cover the area with no gap and no overlap.
        let left = frame(.leftHalf)
        let right = frame(.rightHalf)
        XCTAssertEqual(left.maxX, right.minX, accuracy: 0.001)
        XCTAssertEqual(left.width + right.width, area.width, accuracy: 0.001)
    }

    func testCorners() {
        XCTAssertEqual(frame(.topLeft), CGRect(x: 100, y: 50, width: 600, height: 400))
        XCTAssertEqual(frame(.topRight), CGRect(x: 700, y: 50, width: 600, height: 400))
        XCTAssertEqual(frame(.bottomLeft), CGRect(x: 100, y: 450, width: 600, height: 400))
        XCTAssertEqual(frame(.bottomRight), CGRect(x: 700, y: 450, width: 600, height: 400))
    }

    func testThirdsTileTheFullWidth() {
        let l = frame(.leftThird)
        let c = frame(.centerThird)
        let r = frame(.rightThird)
        XCTAssertEqual(l.minX, area.minX, accuracy: 0.001)
        XCTAssertEqual(l.maxX, c.minX, accuracy: 0.001)
        XCTAssertEqual(c.maxX, r.minX, accuracy: 0.001)
        XCTAssertEqual(r.maxX, area.maxX, accuracy: 0.001)
        // Right third absorbs any rounding remainder so the edge lands exactly on the area edge.
        XCTAssertEqual(l.width + c.width + r.width, area.width, accuracy: 0.001)
    }

    func testTwoThirds() {
        XCTAssertEqual(frame(.firstTwoThirds).width, area.width * 2 / 3, accuracy: 0.001)
        XCTAssertEqual(frame(.lastTwoThirds).maxX, area.maxX, accuracy: 0.001)
        XCTAssertEqual(frame(.lastTwoThirds).minX, area.minX + area.width / 3, accuracy: 0.001)
    }

    func testMaximizeEqualsArea() {
        XCTAssertEqual(frame(.maximize), area)
    }

    func testCenterIsCenteredAndSmallerThanArea() {
        let f = frame(.center)
        XCTAssertEqual(f.midX, area.midX, accuracy: 0.001)
        XCTAssertEqual(f.midY, area.midY, accuracy: 0.001)
        XCTAssertLessThan(f.width, area.width)
        XCTAssertLessThan(f.height, area.height)
    }

    func testAlmostMaximizeStaysInsideArea() {
        let f = frame(.almostMaximize)
        XCTAssertGreaterThanOrEqual(f.minX, area.minX)
        XCTAssertGreaterThanOrEqual(f.minY, area.minY)
        XCTAssertLessThanOrEqual(f.maxX, area.maxX + 0.001)
        XCTAssertLessThanOrEqual(f.maxY, area.maxY + 0.001)
        XCTAssertEqual(f.midX, area.midX, accuracy: 0.001)
    }

    func testAllActionsProduceFinitePositiveSizes() {
        for action in WindowAction.allCases {
            let f = WindowManagerKit.frame(for: action, in: area)
            XCTAssertTrue(f.width > 0 && f.height > 0, "\(action.rawValue) produced non-positive size \(f)")
            XCTAssertTrue(f.width.isFinite && f.height.isFinite, "\(action.rawValue) produced non-finite size")
        }
    }

    func testAllActionsStayWithinArea() {
        for action in WindowAction.allCases {
            let f = WindowManagerKit.frame(for: action, in: area)
            XCTAssertGreaterThanOrEqual(f.minX, area.minX - 0.001, "\(action.rawValue) escaped left")
            XCTAssertGreaterThanOrEqual(f.minY, area.minY - 0.001, "\(action.rawValue) escaped top")
            XCTAssertLessThanOrEqual(f.maxX, area.maxX + 0.001, "\(action.rawValue) escaped right")
            XCTAssertLessThanOrEqual(f.maxY, area.maxY + 0.001, "\(action.rawValue) escaped bottom")
        }
    }

    func testActionMetadataIsComplete() {
        for action in WindowAction.allCases {
            XCTAssertFalse(action.title.isEmpty, "\(action.rawValue) missing title")
            XCTAssertFalse(action.symbol.isEmpty, "\(action.rawValue) missing symbol")
            XCTAssertEqual(action.id, action.rawValue)
        }
    }

    func testDefaultShortcutsAreUnique() {
        // No two actions may share the same (keyCode, modifiers) or the hotkeys would clash.
        var seen = Set<String>()
        for action in WindowAction.allCases {
            guard let sc = action.defaultShortcut else { continue }
            let key = "\(sc.keyCode)-\(sc.modifiers)"
            XCTAssertTrue(seen.insert(key).inserted, "Duplicate default shortcut for \(action.rawValue)")
        }
    }

    func testAXRectConversionRoundTripsThroughPrimaryHeight() {
        // With a known primary height, Cocoa(bottom-left) → AX(top-left) flips y about the height.
        // We verify the inverse is symmetric: converting twice returns the original rect.
        let cocoa = CGRect(x: 10, y: 20, width: 300, height: 200)
        let once = WindowManagerController.axRect(fromCocoa: cocoa)
        let twice = WindowManagerController.axRect(fromCocoa: once)
        XCTAssertEqual(twice, cocoa)
    }
}
