import XCTest
@testable import DMonteCore

final class ToolboxRecentToolsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ToolboxRecentToolsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordStoresNewestFirst() {
        ToolboxRecentTools.record(toolID: "calendar", in: defaults)
        ToolboxRecentTools.record(toolID: "clipboard", in: defaults)

        XCTAssertEqual(ToolboxRecentTools.ids(in: defaults), ["clipboard", "calendar"])
    }

    func testRecordMovesExistingToolToFrontWithoutDuplicating() {
        ToolboxRecentTools.record(toolID: "calendar", in: defaults)
        ToolboxRecentTools.record(toolID: "clipboard", in: defaults)
        ToolboxRecentTools.record(toolID: "calendar", in: defaults)

        XCTAssertEqual(ToolboxRecentTools.ids(in: defaults), ["calendar", "clipboard"])
    }

    func testRecordCapsRecentToolsAtEight() {
        let ids = ToolboxCatalog.all.prefix(10).map(\.id)
        ids.forEach { ToolboxRecentTools.record(toolID: $0, in: defaults) }

        XCTAssertEqual(ToolboxRecentTools.ids(in: defaults), Array(ids.reversed().prefix(8)))
    }

    func testRecordIgnoresUnknownToolIDs() {
        ToolboxRecentTools.record(toolID: "calendar", in: defaults)
        ToolboxRecentTools.record(toolID: "not-a-tool", in: defaults)

        XCTAssertEqual(ToolboxRecentTools.ids(in: defaults), ["calendar"])
    }
}
