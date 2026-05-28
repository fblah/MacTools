import Foundation
import XCTest
@testable import DMonteCore

final class BulkDirectoryReaderTests: XCTestCase {
    func testReadsFilesAndSubdirectory() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let smallByteCount = 4_096
        let largeByteCount = 100_000

        let smallURL = tempDir.appendingPathComponent("small.bin")
        let largeURL = tempDir.appendingPathComponent("large.bin")
        try Data(count: smallByteCount).write(to: smallURL)
        try Data(count: largeByteCount).write(to: largeURL)

        let subdirURL = tempDir.appendingPathComponent("subdir")
        try fileManager.createDirectory(at: subdirURL, withIntermediateDirectories: true)

        let result = try XCTUnwrap(
            BulkDirectoryReader.read(at: tempDir.path),
            "BulkDirectoryReader.read returned nil for \(tempDir.path)"
        )

        let names = Set(result.entries.map(\.name))
        XCTAssertTrue(names.contains("small.bin"))
        XCTAssertTrue(names.contains("large.bin"))
        XCTAssertTrue(names.contains("subdir"))
        XCTAssertFalse(names.contains("."))
        XCTAssertFalse(names.contains(".."))

        let subdirEntry = try XCTUnwrap(result.entries.first { $0.name == "subdir" })
        XCTAssertTrue(subdirEntry.isDirectory)
        XCTAssertFalse(subdirEntry.isSymlink)

        let smallEntry = try XCTUnwrap(result.entries.first { $0.name == "small.bin" })
        XCTAssertFalse(smallEntry.isDirectory)
        XCTAssertGreaterThanOrEqual(smallEntry.allocatedSize, UInt64(smallByteCount))

        let largeEntry = try XCTUnwrap(result.entries.first { $0.name == "large.bin" })
        XCTAssertFalse(largeEntry.isDirectory)
        XCTAssertGreaterThanOrEqual(largeEntry.allocatedSize, UInt64(largeByteCount))
    }

    // Regression: directories/symlinks don't carry ATTR_FILE_ALLOCSIZE, so their
    // packed records are shorter than a file's. The parser must keep walking the
    // batch across these shorter entries — not bail — or every entry after the
    // first directory gets silently dropped (which zeroed out boot-volume scans).
    func testDirectoriesDoNotTruncateTheBatch() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        // Interleave directories and files, with directories appearing early, so a
        // "bail on the first alloc-less entry" bug would drop the later entries.
        var expected: Set<String> = []
        for index in 0..<12 {
            let dirName = "dir_\(index)"
            try fileManager.createDirectory(at: tempDir.appendingPathComponent(dirName), withIntermediateDirectories: true)
            expected.insert(dirName)

            let fileName = "file_\(index).bin"
            try Data(count: 1_024).write(to: tempDir.appendingPathComponent(fileName))
            expected.insert(fileName)
        }

        let result = try XCTUnwrap(BulkDirectoryReader.read(at: tempDir.path))
        let names = Set(result.entries.map(\.name))

        XCTAssertTrue(expected.isSubset(of: names), "missing entries: \(expected.subtracting(names).sorted())")
        XCTAssertEqual(result.entries.filter { $0.isDirectory }.count, 12)
    }
}
