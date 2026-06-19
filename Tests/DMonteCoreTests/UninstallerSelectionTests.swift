import XCTest
@testable import DMonteCore

final class UninstallerSelectionTests: XCTestCase {
    private let alpha = InstalledApplication(
        id: "/Applications/Alpha.app",
        name: "Alpha",
        path: "/Applications/Alpha.app",
        size: nil,
        bundleIdentifier: "com.example.alpha"
    )
    private let beta = InstalledApplication(
        id: "/Applications/Beta.app",
        name: "Beta",
        path: "/Applications/Beta.app",
        size: nil,
        bundleIdentifier: "com.example.beta"
    )

    func testSelectedAppFallsBackWithinFilteredResultsOnly() {
        let filtered = UninstallerSelection.filteredApps([alpha, beta], query: "Beta")
        let selected = UninstallerSelection.selectedApp(in: filtered, selectedID: alpha.id)

        XCTAssertEqual(selected, beta)
    }

    func testSelectedAppKeepsVisibleSelection() {
        let filtered = UninstallerSelection.filteredApps([alpha, beta], query: "Beta")
        let selected = UninstallerSelection.selectedApp(in: filtered, selectedID: beta.id)

        XCTAssertEqual(selected, beta)
    }

    func testSelectedAppIsNilWhenFilterMatchesNothing() {
        let filtered = UninstallerSelection.filteredApps([alpha, beta], query: "Gamma")
        let selected = UninstallerSelection.selectedApp(in: filtered, selectedID: alpha.id)

        XCTAssertNil(selected)
    }
}
