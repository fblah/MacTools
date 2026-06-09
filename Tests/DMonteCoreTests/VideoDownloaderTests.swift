import XCTest
@testable import DMonteCore

final class VideoDownloaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testDownloadedFileURLFindsDestinationFile() throws {
        let videoURL = temporaryDirectory.appendingPathComponent("Clip.mp4")
        FileManager.default.createFile(atPath: videoURL.path, contents: Data())

        let output = "[download] Destination: \(videoURL.path)\n[download] 100% of 1.00MiB"

        XCTAssertEqual(
            VideoDownloaderRunner.downloadedFileURL(from: output, saveDirectory: temporaryDirectory),
            videoURL
        )
    }

    func testDownloadedFileURLPrefersMergedFileOverIntermediateDestination() throws {
        let intermediateURL = temporaryDirectory.appendingPathComponent("Clip.f137.mp4")
        let mergedURL = temporaryDirectory.appendingPathComponent("Clip.mp4")
        FileManager.default.createFile(atPath: intermediateURL.path, contents: Data())
        FileManager.default.createFile(atPath: mergedURL.path, contents: Data())

        let output = """
        [download] Destination: \(intermediateURL.path)
        [download] 100% of 1.00MiB
        [Merger] Merging formats into "\(mergedURL.path)"
        """

        XCTAssertEqual(
            VideoDownloaderRunner.downloadedFileURL(from: output, saveDirectory: temporaryDirectory),
            mergedURL
        )
    }
}
