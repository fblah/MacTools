import XCTest
@testable import DMonteCore

final class DiskAnalyzerSizingTests: XCTestCase {
    func testCurrentScaleWithinExpectedRange() {
        let scale = DiskAnalyzerSizing.currentScale
        XCTAssertGreaterThanOrEqual(scale, 0.78)
        XCTAssertLessThanOrEqual(scale, 1.0)
    }

    func testPreferredSizeHasPositiveDimensions() {
        let size = DiskAnalyzerSizing.preferredSize()
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
