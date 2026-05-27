import CoreGraphics
import XCTest
@testable import DMonteCore

final class TreemapLayoutTests: XCTestCase {
    private func makeNode(name: String, size: UInt64) -> DiskNode {
        DiskNode(path: "/tmp/\(name)", name: name, isDirectory: false, size: size, children: [])
    }

    private func area(_ rect: CGRect) -> Double {
        Double(rect.width) * Double(rect.height)
    }

    func testSingleNodeFillsBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nodes = [makeNode(name: "only", size: 1_000)]

        let rects = TreemapLayout.compute(nodes: nodes, in: bounds)

        XCTAssertEqual(rects.count, 1)
        let boundsArea = area(bounds)
        XCTAssertEqual(area(rects[0].rect), boundsArea, accuracy: 1.0)
    }

    func testMultipleNodesTileFullBounds() {
        let bounds = CGRect(x: 10, y: 20, width: 500, height: 360)
        let nodes = [
            makeNode(name: "a", size: 5_000),
            makeNode(name: "b", size: 3_000),
            makeNode(name: "c", size: 1_500),
            makeNode(name: "d", size: 800),
            makeNode(name: "e", size: 200)
        ]

        let rects = TreemapLayout.compute(nodes: nodes, in: bounds)

        XCTAssertEqual(rects.count, nodes.count)

        let tolerance: CGFloat = 1.0
        for entry in rects {
            let rect = entry.rect
            XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX - tolerance)
            XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY - tolerance)
            XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + tolerance)
            XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY + tolerance)
        }

        let summedArea = rects.reduce(0.0) { $0 + area($1.rect) }
        XCTAssertEqual(summedArea, area(bounds), accuracy: 1.0)
    }

    func testEmptyInputReturnsEmpty() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertTrue(TreemapLayout.compute(nodes: [], in: bounds).isEmpty)
    }

    func testZeroSizeNodesReturnEmpty() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nodes = [
            makeNode(name: "a", size: 0),
            makeNode(name: "b", size: 0)
        ]
        XCTAssertTrue(TreemapLayout.compute(nodes: nodes, in: bounds).isEmpty)
    }

    func testMaxItemsCapsResultCount() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let maxItems = 50
        let nodes = (0..<(maxItems + 75)).map { makeNode(name: "n\($0)", size: UInt64(1_000 + $0)) }

        let rects = TreemapLayout.compute(nodes: nodes, in: bounds, maxItems: maxItems)

        XCTAssertLessThanOrEqual(rects.count, maxItems)
    }
}
