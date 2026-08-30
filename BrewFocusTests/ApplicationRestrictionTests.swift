import XCTest
@testable import BrewFocus

final class ApplicationRestrictionTests: XCTestCase {
    func testNoRestrictionNeverRestrictsAnApp() {
        let restriction = ApplicationRestriction(mode: .none, bundleIdentifiers: [])

        XCTAssertFalse(restriction.restricts(bundleIdentifier: "test.app"))
    }

    func testBlockListRestrictsOnlySelectedApps() {
        let restriction = ApplicationRestriction(
            mode: .blockList,
            bundleIdentifiers: ["test.distraction"]
        )

        XCTAssertTrue(restriction.restricts(bundleIdentifier: "test.distraction"))
        XCTAssertFalse(restriction.restricts(bundleIdentifier: "test.editor"))
    }

    func testAllowListRestrictsAppsOutsideSelection() {
        let restriction = ApplicationRestriction(
            mode: .allowList,
            bundleIdentifiers: ["test.editor"]
        )

        XCTAssertFalse(restriction.restricts(bundleIdentifier: "test.editor"))
        XCTAssertTrue(restriction.restricts(bundleIdentifier: "test.distraction"))
    }
}
