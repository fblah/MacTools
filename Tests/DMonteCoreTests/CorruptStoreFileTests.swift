import Foundation
import XCTest
@testable import DMonteCore

/// A store file that no longer decodes still holds the user's data, and the store's next ordinary
/// write lands on the same path. These pin the rename that keeps those bytes rescuable.
final class CorruptStoreFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorruptStoreFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    private func write(_ contents: String, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - The helper

    func testQuarantineMovesTheFileAsideKeepingItsBytes() throws {
        let url = try write("{ this is not json", named: "store.json")

        let moved = try XCTUnwrap(CorruptStoreFile.quarantine(at: url))

        XCTAssertEqual(moved.lastPathComponent, "store.json.corrupt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "The original path must be free for the next write")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "{ this is not json")
    }

    /// A second casualty must not overwrite the first — that would lose the older copy, which is
    /// the exact failure this helper exists to prevent.
    func testASecondQuarantineDoesNotClobberTheFirst() throws {
        let url = try write("first casualty", named: "store.json")
        XCTAssertNotNil(CorruptStoreFile.quarantine(at: url))

        _ = try write("second casualty", named: "store.json")
        let second = try XCTUnwrap(CorruptStoreFile.quarantine(at: url))

        XCTAssertEqual(second.lastPathComponent, "store.json.corrupt-2")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("store.json.corrupt"), encoding: .utf8),
            "first casualty"
        )
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second casualty")
    }

    func testQuarantiningAFileThatIsNotThereDoesNothing() {
        XCTAssertNil(CorruptStoreFile.quarantine(at: directory.appendingPathComponent("absent.json")))
    }

    // MARK: - The stores that use it

    func testACorruptShelfIsMovedAsideRatherThanSilentlyOverwritten() throws {
        let url = try write("not a shelf", named: "shelf.json")

        XCTAssertTrue(FileShelfKit.load(from: url).isEmpty, "An undecodable shelf still reads as empty")

        let quarantined = directory.appendingPathComponent("shelf.json.corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
        XCTAssertEqual(try String(contentsOf: quarantined, encoding: .utf8), "not a shelf")

        // The point of the rename: the store's next write cannot destroy what was rescued.
        FileShelfKit.write([], to: url)
        XCTAssertEqual(try String(contentsOf: quarantined, encoding: .utf8), "not a shelf")
    }

    func testACorruptSnippetLibraryIsMovedAsideRatherThanSilentlyOverwritten() throws {
        let url = try write("not a library", named: "snippets.json")

        XCTAssertTrue(SnippetsKit.load(from: url).isEmpty)

        let quarantined = directory.appendingPathComponent("snippets.json.corrupt")
        XCTAssertEqual(try String(contentsOf: quarantined, encoding: .utf8), "not a library")
    }

    /// The healthy path must never rename anything — a store that quarantined its own good file
    /// would lose the shelf on every launch.
    func testAReadableStoreFileIsNeverQuarantined() throws {
        let url = directory.appendingPathComponent("shelf.json")
        FileShelfKit.write([], to: url)

        XCTAssertTrue(FileShelfKit.load(from: url).isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path + ".corrupt"),
            "A file that decodes cleanly must be left exactly where it is"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAMissingStoreFileIsNotTreatedAsCorruption() {
        let url = directory.appendingPathComponent("never-written.json")

        XCTAssertTrue(FileShelfKit.load(from: url).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".corrupt"))
    }
}
