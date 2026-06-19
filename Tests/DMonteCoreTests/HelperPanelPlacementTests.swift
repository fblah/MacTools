import XCTest
@testable import DMonteCore

final class HelperPanelPlacementTests: XCTestCase {
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let panelSize = NSSize(width: 320, height: 400)

    // MARK: - screenIndex

    func testScreenIndexFindsScreenContainingPoint() {
        let screens = [
            NSRect(x: -1440, y: 0, width: 1440, height: 900),
            NSRect(x: 0, y: 0, width: 2560, height: 1440),
            NSRect(x: 2560, y: 0, width: 1920, height: 1080)
        ]

        XCTAssertEqual(HelperPanelPlacement.screenIndex(containing: NSPoint(x: -200, y: 880), in: screens), 0)
        XCTAssertEqual(HelperPanelPlacement.screenIndex(containing: NSPoint(x: 100, y: 1400), in: screens), 1)
        XCTAssertEqual(HelperPanelPlacement.screenIndex(containing: NSPoint(x: 3000, y: 1000), in: screens), 2)
    }

    func testScreenIndexUsesHalfOpenEdgesForAdjacentScreens() {
        let screens = [
            NSRect(x: 0, y: 0, width: 1000, height: 900),
            NSRect(x: 1000, y: 0, width: 1000, height: 900)
        ]

        XCTAssertEqual(HelperPanelPlacement.screenIndex(containing: NSPoint(x: 999.99, y: 100), in: screens), 0)
        XCTAssertEqual(HelperPanelPlacement.screenIndex(containing: NSPoint(x: 1000, y: 100), in: screens), 1)
        XCTAssertNil(HelperPanelPlacement.screenIndex(containing: NSPoint(x: 2000, y: 100), in: screens))
    }

    // MARK: - centeredFrame

    func testCenteredFrameCentersOnVisibleFrame() {
        let frame = HelperPanelPlacement.centeredFrame(for: panelSize, visibleFrame: visibleFrame)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertEqual(frame.size, panelSize)
    }

    func testCenteredFrameWithOffsetVisibleFrame() {
        let offsetVisible = NSRect(x: -1920, y: 200, width: 1920, height: 1055)
        let frame = HelperPanelPlacement.centeredFrame(for: panelSize, visibleFrame: offsetVisible)
        XCTAssertEqual(frame.midX, offsetVisible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, offsetVisible.midY, accuracy: 0.001)
    }

    // MARK: - anchoredFrame

    func testAnchoredFrameCentersUnderAnchorWithGap() {
        // Status item near the middle of the menu bar: no clamping should kick in.
        let anchor = NSRect(x: 700, y: 875, width: 30, height: 24)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: panelSize,
            anchorFrame: anchor,
            visibleFrame: visibleFrame,
            gap: 8
        )
        XCTAssertEqual(frame.midX, anchor.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, anchor.minY - 8, accuracy: 0.001)
        XCTAssertEqual(frame.size, panelSize)
    }

    func testAnchoredFrameClampsToRightEdge() {
        // Status item at the far right: the panel must stay 8 pts inside the screen.
        let anchor = NSRect(x: 1420, y: 875, width: 20, height: 24)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: panelSize,
            anchorFrame: anchor,
            visibleFrame: visibleFrame,
            gap: 8
        )
        XCTAssertEqual(frame.maxX, visibleFrame.maxX - 8, accuracy: 0.001)
    }

    func testAnchoredFrameClampsToLeftEdge() {
        let anchor = NSRect(x: 0, y: 875, width: 20, height: 24)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: panelSize,
            anchorFrame: anchor,
            visibleFrame: visibleFrame,
            gap: 8
        )
        XCTAssertEqual(frame.minX, visibleFrame.minX + 8, accuracy: 0.001)
    }

    func testAnchoredFrameClampsToBottomEdge() {
        // A panel taller than the space under the anchor is pinned 8 pts above the bottom.
        let shortVisible = NSRect(x: 0, y: 0, width: 1440, height: 300)
        let anchor = NSRect(x: 700, y: 300, width: 30, height: 24)
        let tallPanel = NSSize(width: 320, height: 600)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: tallPanel,
            anchorFrame: anchor,
            visibleFrame: shortVisible,
            gap: 8
        )
        XCTAssertEqual(frame.minY, shortVisible.minY + 8, accuracy: 0.001)
    }

    func testAnchoredFrameRightEdgeWinsWhenPanelWiderThanScreen() {
        // Historic behaviour of min(max(...)): when the panel cannot fit, the
        // right-edge clamp takes precedence over the left-edge clamp.
        let narrowVisible = NSRect(x: 0, y: 0, width: 200, height: 875)
        let anchor = NSRect(x: 90, y: 875, width: 20, height: 24)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: panelSize,
            anchorFrame: anchor,
            visibleFrame: narrowVisible,
            gap: 8
        )
        XCTAssertEqual(frame.minX, narrowVisible.maxX - panelSize.width - 8, accuracy: 0.001)
    }

    func testAnchoredFrameHonorsCustomGap() {
        // Color Picker and Maintenance historically used a 6 pt gap instead of 8.
        let anchor = NSRect(x: 700, y: 875, width: 30, height: 24)
        let frame = HelperPanelPlacement.anchoredFrame(
            for: panelSize,
            anchorFrame: anchor,
            visibleFrame: visibleFrame,
            gap: 6
        )
        XCTAssertEqual(frame.maxY, anchor.minY - 6, accuracy: 0.001)
    }

    // MARK: - unclampedAnchoredOrigin

    func testUnclampedAnchoredOriginIgnoresScreenEdges() {
        let anchor = NSRect(x: 1430, y: 875, width: 20, height: 24)
        let origin = HelperPanelPlacement.unclampedAnchoredOrigin(
            for: panelSize,
            anchorFrame: anchor,
            gap: 6
        )
        XCTAssertEqual(origin.x, anchor.midX - panelSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(origin.y, anchor.minY - panelSize.height - 6, accuracy: 0.001)
    }

    // MARK: - topRightOrigin

    func testTopRightOriginInsetsFromCorner() {
        let origin = HelperPanelPlacement.topRightOrigin(for: panelSize, visibleFrame: visibleFrame)
        XCTAssertEqual(origin.x, visibleFrame.maxX - panelSize.width - 8, accuracy: 0.001)
        XCTAssertEqual(origin.y, visibleFrame.maxY - panelSize.height - 8, accuracy: 0.001)
    }

    // MARK: - fallback constants

    func testFallbackVisibleFrameMatchesHistoricValue() {
        // Every helper hard-coded this 1440x900 fallback; the shared constant must match.
        XCTAssertEqual(HelperPanelPlacement.fallbackVisibleFrame, NSRect(x: 0, y: 0, width: 1440, height: 900))
    }
}
