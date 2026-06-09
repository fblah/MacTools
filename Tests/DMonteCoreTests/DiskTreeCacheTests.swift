import XCTest
@testable import DMonteCore

final class DiskTreeCacheTests: XCTestCase {
    func testIndexesAncestorPathForEveryNode() {
        let file = DiskNode(path: "/root/apps/tool.bin", name: "tool.bin", isDirectory: false, size: 12, children: [])
        let apps = DiskNode(path: "/root/apps", name: "apps", isDirectory: true, size: 12, children: [file])
        let logs = DiskNode(path: "/root/logs", name: "logs", isDirectory: true, size: 4, children: [])
        let root = DiskNode(path: "/root", name: "root", isDirectory: true, size: 16, children: [apps, logs])

        let cache = DiskTreeCache(root: root)

        XCTAssertEqual(cache.nodeCount, 4)
        XCTAssertEqual(cache.path(to: file)?.map(\.name), ["root", "apps", "tool.bin"])
        XCTAssertEqual(cache.path(to: logs)?.map(\.name), ["root", "logs"])
        XCTAssertEqual(cache.path(to: root)?.map(\.name), ["root"])
    }
}
