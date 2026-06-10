import XCTest
@testable import DMonteCore

/// Cross-checks the three artifacts a tool must be registered in to actually ship:
///
/// 1. `ToolboxCatalog.all` — drives the dashboard and launcher (`executableName`).
/// 2. The `HELPERS` array in `Scripts/package_app.sh` — bundles the helper into the app.
/// 3. The executable products/targets in `Package.swift` — builds the helper at all.
///
/// These have drifted before: commit fa19e40 shipped Window Manager in the catalog and
/// packaging script while it was missing from `Package.swift`, producing an unlaunchable
/// tool. This test fails loudly, naming the tool and the artifact it is missing from.
final class ToolRegistrationConsistencyTests: XCTestCase {
    /// Executables that are deliberately NOT bundled helpers. Each entry must be justified:
    ///
    /// - `DMonte`: the main Tool Box app itself. It is an executable product/target in
    ///   `Package.swift` and is copied to `Contents/MacOS/DMonte` by `package_app.sh`
    ///   outside the `HELPERS` loop, so it correctly appears in the manifest but not in
    ///   the catalog or the `HELPERS` array.
    private static let nonHelperExecutables: Set<String> = ["DMonte"]

    /// The repo ships well over this many helpers. If any parser yields fewer, the
    /// artifact's formatting has likely changed and the parser broke — fail instead of
    /// vacuously passing on an empty/truncated set.
    private static let minimumPlausibleHelperCount = 10

    /// `#filePath` is `<repoRoot>/Tests/DMonteCoreTests/ToolRegistrationConsistencyTests.swift`,
    /// so the repo root is two directories above this file's directory. This is reliable
    /// under `swift test` in this repo, which always builds from a local checkout.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/DMonteCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root

    // MARK: - Tests

    func testCatalogPackagingScriptAndManifestAgree() throws {
        let catalog = Set(ToolboxCatalog.all.map(\.executableName))
        let script = try packagingScriptHelpers()
        let manifest = try packageManifestExecutables()

        XCTAssertGreaterThanOrEqual(
            catalog.count, Self.minimumPlausibleHelperCount,
            "Parser broke (or catalog gutted): ToolboxCatalog.all yielded only \(catalog.count) tools"
        )
        XCTAssertGreaterThanOrEqual(
            script.count, Self.minimumPlausibleHelperCount,
            "Parser broke: HELPERS array in Scripts/package_app.sh yielded only \(script.count) entries"
        )
        XCTAssertGreaterThanOrEqual(
            manifest.products.count, Self.minimumPlausibleHelperCount,
            "Parser broke: .executable products in Package.swift yielded only \(manifest.products.count) entries"
        )
        XCTAssertGreaterThanOrEqual(
            manifest.targets.count, Self.minimumPlausibleHelperCount,
            "Parser broke: .executableTarget entries in Package.swift yielded only \(manifest.targets.count) entries"
        )

        // Every executable product must have a matching executable target and vice versa.
        assertConsistent(
            manifest.products, named: "Package.swift .executable products",
            manifest.targets, named: "Package.swift .executableTarget targets"
        )

        // The documented exceptions must be real: present in the manifest, absent elsewhere.
        // If this fires, the exception list above is stale.
        for exception in Self.nonHelperExecutables.sorted() {
            XCTAssertTrue(
                manifest.products.contains(exception),
                "Stale exception list: \(exception) is excepted as a non-helper executable but is not a Package.swift executable product"
            )
            XCTAssertFalse(
                catalog.contains(exception),
                "Stale exception list: \(exception) is excepted as a non-helper but appears in ToolboxCatalog"
            )
            XCTAssertFalse(
                script.contains(exception),
                "Stale exception list: \(exception) is excepted as a non-helper but appears in the HELPERS array of Scripts/package_app.sh"
            )
        }

        let manifestHelpers = manifest.products.subtracting(Self.nonHelperExecutables)

        assertConsistent(
            catalog, named: "ToolboxCatalog",
            script, named: "HELPERS array in Scripts/package_app.sh"
        )
        assertConsistent(
            catalog, named: "ToolboxCatalog",
            manifestHelpers, named: "Package.swift executable products (excluding \(Self.nonHelperExecutables.sorted().joined(separator: ", ")))"
        )
        assertConsistent(
            script, named: "HELPERS array in Scripts/package_app.sh",
            manifestHelpers, named: "Package.swift executable products (excluding \(Self.nonHelperExecutables.sorted().joined(separator: ", ")))"
        )
    }

    // MARK: - Assertion helper

    /// Asserts two sets are equal, naming exactly which tool is missing from which artifact.
    private func assertConsistent(
        _ left: Set<String>, named leftName: String,
        _ right: Set<String>, named rightName: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let missingFromRight = left.subtracting(right).sorted()
        let missingFromLeft = right.subtracting(left).sorted()

        XCTAssertTrue(
            missingFromRight.isEmpty,
            "\(missingFromRight.joined(separator: ", ")) registered in \(leftName) but MISSING from \(rightName)",
            file: file, line: line
        )
        XCTAssertTrue(
            missingFromLeft.isEmpty,
            "\(missingFromLeft.joined(separator: ", ")) registered in \(rightName) but MISSING from \(leftName)",
            file: file, line: line
        )
    }

    // MARK: - Parsers

    /// Extracts the executable names (first `|`-separated field of each quoted entry) from
    /// the `HELPERS=( ... )` array in `Scripts/package_app.sh`.
    private func packagingScriptHelpers() throws -> Set<String> {
        let url = Self.repoRoot.appendingPathComponent("Scripts/package_app.sh")
        let text = try String(contentsOf: url, encoding: .utf8)

        guard let arrayRange = text.range(of: #"HELPERS=\(([^)]*)\)"#, options: .regularExpression) else {
            XCTFail("Parser broke: could not find a HELPERS=( ... ) array in Scripts/package_app.sh")
            return []
        }

        let body = String(text[arrayRange])
        return try matches(of: #""([A-Za-z0-9_]+)\|"#, in: body)
    }

    /// Extracts executable product and executable target names from `Package.swift`.
    private func packageManifestExecutables() throws -> (products: Set<String>, targets: Set<String>) {
        let url = Self.repoRoot.appendingPathComponent("Package.swift")
        let text = try String(contentsOf: url, encoding: .utf8)

        let products = try matches(of: #"\.executable\(\s*name:\s*"([A-Za-z0-9_]+)""#, in: text)
        let targets = try matches(of: #"\.executableTarget\(\s*name:\s*"([A-Za-z0-9_]+)""#, in: text)
        return (products, targets)
    }

    /// Returns the set of first-capture-group values for every match of `pattern` in `text`.
    private func matches(of pattern: String, in text: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(text.startIndex..., in: text)

        var names = Set<String>()
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return
            }
            names.insert(String(text[range]))
        }
        return names
    }
}
