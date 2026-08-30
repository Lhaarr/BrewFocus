import XCTest
@testable import BrewFocus

final class JSONSessionStoreTests: XCTestCase {
    func testSnapshotRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewFocusTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sessions.json", isDirectory: false)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let app = AllowedApplication(
            bundleIdentifier: "test.editor",
            name: "Editor",
            bundleURLPath: "/Applications/Editor.app"
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            startedAt: startedAt,
            plannedDuration: 1_800,
            scheduledEndAt: startedAt.addingTimeInterval(1_800),
            selectedApplications: [app]
        )
        let expected = FocusSnapshot(currentSession: session)
        let store = JSONSessionStore(fileURL: fileURL)

        try store.save(expected)
        let actual = try store.load()

        XCTAssertEqual(actual, expected)
    }

    func testCappuccinoBlockListRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewFocusTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sessions.json", isDirectory: false)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let distraction = AllowedApplication(
            bundleIdentifier: "test.chat",
            name: "Chat",
            bundleURLPath: nil
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            coffee: .cappuccino,
            startedAt: startedAt,
            plannedDuration: 1_800,
            scheduledEndAt: startedAt.addingTimeInterval(1_800),
            selectedApplications: [distraction]
        )
        let store = JSONSessionStore(fileURL: fileURL)

        try store.save(FocusSnapshot(currentSession: session))
        let restored = try store.load().currentSession

        XCTAssertEqual(restored?.effectiveRestrictionMode, .blockList)
        XCTAssertEqual(restored?.blockedApplications, [distraction])
        XCTAssertEqual(restored?.applicationRestriction.bundleIdentifiers, ["test.chat"])
    }

    func testEspressoOnlySnapshotRemainsReadable() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewFocusLegacyTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("sessions.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let legacyJSON = """
        {
          "currentSession" : {
            "allowedApplications" : [
              {
                "bundleIdentifier" : "test.editor",
                "name" : "Editor"
              }
            ],
            "coffee" : "espresso",
            "hiddenBundleIdentifiers" : [],
            "id" : "811F2BCB-1D10-45AA-B9E8-E8A71E221292",
            "plannedDuration" : 1800,
            "scheduledEndAt" : "2023-11-14T22:43:20Z",
            "startedAt" : "2023-11-14T22:13:20Z",
            "status" : "active"
          },
          "history" : [],
          "version" : 1
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let snapshot = try JSONSessionStore(fileURL: fileURL).load()

        XCTAssertEqual(snapshot.currentSession?.coffee, .espresso)
        XCTAssertNil(snapshot.currentSession?.restrictionMode)
        XCTAssertEqual(
            snapshot.currentSession?.effectiveRestrictionMode,
            ApplicationRestrictionMode.allowList
        )
        XCTAssertEqual(
            snapshot.currentSession?.selectedApplications.map(\.bundleIdentifier),
            ["test.editor"]
        )
    }
}
