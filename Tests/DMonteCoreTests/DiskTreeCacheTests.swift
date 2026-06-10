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

    func testIndexingStopsWhenBuildTaskIsCancelled() async {
        // The cache is built on a detached task (scheduleTreeCacheBuild) so that a
        // boot-volume index — millions of nodes — never blocks the main actor. A
        // superseded build is cancelled and its result discarded; the walk must
        // observe that cancellation and bail instead of burning CPU to completion.
        let file = DiskNode(path: "/root/apps/tool.bin", name: "tool.bin", isDirectory: false, size: 12, children: [])
        let apps = DiskNode(path: "/root/apps", name: "apps", isDirectory: true, size: 12, children: [file])
        let root = DiskNode(path: "/root", name: "root", isDirectory: true, size: 12, children: [apps])

        let build = Task.detached { () -> DiskTreeCache in
            // Cancel ourselves before constructing so the walk sees the cancelled
            // flag from the very first node — deterministic, no timing dependence.
            withUnsafeCurrentTask { $0?.cancel() }
            return DiskTreeCache(root: root)
        }
        let cache = await build.value

        XCTAssertEqual(cache.nodeCount, 0, "a cancelled build must abandon the walk")
        XCTAssertNil(cache.path(to: root))
        XCTAssertNil(cache.path(to: file))
    }
}
