import XCTest
@testable import BrewFocus

@MainActor
final class SessionManagerTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testLatteStartsWithoutSelectionOrRestriction() {
        let harness = makeHarness(applications: [])

        harness.manager.start(.latte)

        XCTAssertEqual(harness.manager.currentSession?.coffee, .latte)
        XCTAssertEqual(harness.manager.currentSession?.plannedDuration, 25 * 60)
        XCTAssertEqual(
            harness.manager.currentSession?.effectiveRestrictionMode,
            ApplicationRestrictionMode.none
        )
        XCTAssertTrue(harness.restriction.startCalls.isEmpty)

        harness.manager.pause()
        XCTAssertTrue(harness.restriction.stopCalls.isEmpty)
    }

    func testCappuccinoBlocksOneToFourSelectedDistractions() {
        let distraction = application(1)
        let harness = makeHarness(applications: [distraction])

        harness.manager.toggleSelection(for: distraction, coffee: .cappuccino)
        harness.manager.start(.cappuccino)

        XCTAssertEqual(harness.manager.currentSession?.coffee, .cappuccino)
        XCTAssertEqual(harness.manager.currentSession?.blockedApplications, [distraction])
        XCTAssertEqual(harness.manager.currentSession?.plannedDuration, 30 * 60)
        XCTAssertEqual(
            harness.restriction.startCalls,
            [ApplicationRestriction(
                mode: .blockList,
                bundleIdentifiers: [distraction.bundleIdentifier]
            )]
        )
    }

    func testAmericanoAllowsUpToEightEssentialApps() {
        let applications = (1...9).map(application)
        let harness = makeHarness(applications: applications)

        applications.prefix(8).forEach {
            harness.manager.toggleSelection(for: $0, coffee: .americano)
        }
        harness.manager.toggleSelection(for: applications[8], coffee: .americano)

        XCTAssertEqual(harness.manager.selectedBundleIdentifiers.count, 8)
        XCTAssertEqual(
            harness.manager.lastError,
            "Americano allows at most 8 selected apps."
        )

        harness.manager.start(.americano)

        XCTAssertEqual(harness.manager.currentSession?.coffee, .americano)
        XCTAssertEqual(harness.manager.currentSession?.allowedApplications.count, 8)
        XCTAssertEqual(harness.manager.currentSession?.plannedDuration, 45 * 60)
        XCTAssertEqual(harness.restriction.startCalls.first?.mode, .allowList)
    }

    func testEspressoRequiresOneToFourApps() {
        let applications = (1...5).map(application)
        let harness = makeHarness(applications: applications)

        harness.manager.start(.espresso)
        XCTAssertNil(harness.manager.currentSession)

        applications.prefix(4).forEach {
            harness.manager.toggleSelection(for: $0, coffee: .espresso)
        }
        harness.manager.toggleSelection(for: applications[4], coffee: .espresso)

        XCTAssertEqual(harness.manager.selectedBundleIdentifiers.count, 4)
        XCTAssertEqual(
            harness.manager.lastError,
            "Espresso allows at most 4 selected apps."
        )

        harness.manager.start(.espresso)
        XCTAssertEqual(harness.manager.currentSession?.allowedApplications.count, 4)
        XCTAssertEqual(harness.manager.currentSession?.plannedDuration, 30 * 60)
        XCTAssertEqual(harness.restriction.startCalls.count, 1)
    }

    func testPauseRestoresAppsAndResumeReengagesRestriction() {
        let app = application(1)
        let harness = makeHarness(applications: [app])
        harness.manager.toggleSelection(for: app, coffee: .espresso)
        harness.manager.start(.espresso)

        harness.restriction.simulateHidden(
            RestrictedApplication(bundleIdentifier: "test.distraction", name: "Distraction")
        )
        XCTAssertEqual(
            harness.manager.currentSession?.hiddenBundleIdentifiers,
            ["test.distraction"]
        )

        harness.manager.pause()

        XCTAssertEqual(harness.manager.currentSession?.status, .paused)
        XCTAssertEqual(harness.restriction.stopCalls, [["test.distraction"]])
        XCTAssertEqual(harness.manager.currentSession?.hiddenBundleIdentifiers, [])

        harness.manager.resume()

        XCTAssertEqual(harness.manager.currentSession?.status, .active)
        XCTAssertEqual(harness.restriction.startCalls.count, 2)
    }

    func testElapsedCoffeeCompletesAndCreatesCup() {
        let app = application(1)
        let harness = makeHarness(applications: [app], duration: 60)
        harness.manager.toggleSelection(for: app, coffee: .espresso)
        harness.manager.start(.espresso)

        harness.clock.date = startDate.addingTimeInterval(61)
        harness.manager.refreshTime()

        XCTAssertNil(harness.manager.currentSession)
        XCTAssertEqual(harness.manager.completedSessions.count, 1)
        XCTAssertEqual(harness.manager.completedSessions[0].status, .completed)
        XCTAssertEqual(harness.manager.completedSessions[0].focusedDuration, 60)
        XCTAssertNotNil(harness.manager.lastCompletedSession)
    }

    func testAbortIsRecordedButDoesNotCreateCup() {
        let app = application(1)
        let harness = makeHarness(applications: [app])
        harness.manager.toggleSelection(for: app, coffee: .espresso)
        harness.manager.start(.espresso)
        harness.manager.abort()

        XCTAssertNil(harness.manager.currentSession)
        XCTAssertTrue(harness.manager.completedSessions.isEmpty)
        XCTAssertEqual(harness.store.snapshot.history.first?.status, .aborted)
    }

    func testRestrictionFailureIsSurfacedAndClearedAfterSuccessfulHide() {
        let app = application(1)
        let harness = makeHarness(applications: [app])
        harness.manager.toggleSelection(for: app, coffee: .espresso)
        harness.manager.start(.espresso)
        let distraction = RestrictedApplication(
            bundleIdentifier: "test.distraction",
            name: "Distraction"
        )

        harness.restriction.simulateRestrictionFailure(distraction)

        XCTAssertEqual(harness.manager.lastRestrictionFailure, distraction)
        XCTAssertEqual(harness.presenter.restrictionFailures, ["Distraction"])

        harness.restriction.simulateHidden(distraction)

        XCTAssertNil(harness.manager.lastRestrictionFailure)
    }

    func testFutureSessionIsReengagedAfterRelaunch() {
        let app = application(1)
        let session = FocusSession(
            startedAt: startDate,
            plannedDuration: 600,
            scheduledEndAt: startDate.addingTimeInterval(600),
            selectedApplications: [app]
        )
        let harness = makeHarness(
            applications: [app],
            initialSnapshot: FocusSnapshot(currentSession: session),
            currentDate: startDate.addingTimeInterval(120)
        )

        XCTAssertEqual(harness.manager.currentSession?.status, .active)
        XCTAssertEqual(
            harness.restriction.startCalls,
            [ApplicationRestriction(mode: .allowList, bundleIdentifiers: ["test.app.1"])]
        )
        XCTAssertEqual(harness.manager.remainingSeconds, 480)
    }

    func testExpiredSessionIsCompletedAndHiddenAppsAreRestored() {
        let app = application(1)
        var session = FocusSession(
            startedAt: startDate,
            plannedDuration: 60,
            scheduledEndAt: startDate.addingTimeInterval(60),
            selectedApplications: [app]
        )
        session.hiddenBundleIdentifiers = ["test.distraction"]

        let harness = makeHarness(
            applications: [app],
            initialSnapshot: FocusSnapshot(currentSession: session),
            currentDate: startDate.addingTimeInterval(120)
        )

        XCTAssertNil(harness.manager.currentSession)
        XCTAssertEqual(harness.manager.completedSessions.count, 1)
        XCTAssertEqual(harness.restriction.restoreCalls, [["test.distraction"]])
    }

    private func application(_ index: Int) -> AllowedApplication {
        AllowedApplication(
            bundleIdentifier: "test.app.\(index)",
            name: "App \(index)",
            bundleURLPath: nil
        )
    }

    private func makeHarness(
        applications: [AllowedApplication],
        initialSnapshot: FocusSnapshot = FocusSnapshot(),
        duration: TimeInterval? = nil,
        currentDate: Date? = nil
    ) -> Harness {
        let store = InMemorySessionStore(snapshot: initialSnapshot)
        let catalog = StubApplicationCatalog(applications: applications)
        let restriction = RecordingRestriction()
        let presenter = RecordingBlockNoticePresenter()
        let clock = MutableClock(date: currentDate ?? startDate)
        let manager = SessionManager(
            store: store,
            applicationCatalog: catalog,
            restriction: restriction,
            blockNoticePresenter: presenter,
            sessionDuration: duration,
            now: { clock.date },
            schedulesTimer: false
        )
        manager.bootstrap()

        return Harness(
            manager: manager,
            store: store,
            restriction: restriction,
            presenter: presenter,
            clock: clock
        )
    }
}

@MainActor
private struct Harness {
    let manager: SessionManager
    let store: InMemorySessionStore
    let restriction: RecordingRestriction
    let presenter: RecordingBlockNoticePresenter
    let clock: MutableClock
}

private final class MutableClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

private final class InMemorySessionStore: SessionStoring {
    var snapshot: FocusSnapshot

    init(snapshot: FocusSnapshot) {
        self.snapshot = snapshot
    }

    func load() throws -> FocusSnapshot {
        snapshot
    }

    func save(_ snapshot: FocusSnapshot) throws {
        self.snapshot = snapshot
    }
}

private struct StubApplicationCatalog: ApplicationCataloging {
    let applications: [AllowedApplication]

    func runningApplications() -> [AllowedApplication] {
        applications
    }
}

@MainActor
private final class RecordingRestriction: FocusRestricting {
    private(set) var startCalls: [ApplicationRestriction] = []
    private(set) var stopCalls: [Set<String>] = []
    private(set) var restoreCalls: [Set<String>] = []
    private var onHidden: ((RestrictedApplication) -> Void)?
    private var onBlockedAttempt: ((RestrictedApplication) -> Void)?
    private var onRestrictionFailure: ((RestrictedApplication) -> Void)?

    func start(
        restriction: ApplicationRestriction,
        onHidden: @escaping (RestrictedApplication) -> Void,
        onBlockedAttempt: @escaping (RestrictedApplication) -> Void,
        onRestrictionFailure: @escaping (RestrictedApplication) -> Void
    ) {
        startCalls.append(restriction)
        self.onHidden = onHidden
        self.onBlockedAttempt = onBlockedAttempt
        self.onRestrictionFailure = onRestrictionFailure
    }

    func stop(restoring bundleIdentifiers: Set<String>) {
        stopCalls.append(bundleIdentifiers)
    }

    func restore(bundleIdentifiers: Set<String>) {
        restoreCalls.append(bundleIdentifiers)
    }

    func simulateHidden(_ application: RestrictedApplication) {
        onHidden?(application)
    }

    func simulateRestrictionFailure(_ application: RestrictedApplication) {
        onRestrictionFailure?(application)
    }
}

@MainActor
private final class RecordingBlockNoticePresenter: BlockNoticePresenting {
    private(set) var notices: [(applicationName: String, remainingSeconds: Int)] = []
    private(set) var restrictionFailures: [String] = []

    func show(applicationName: String, coffee: CoffeeKind, remainingSeconds: Int) {
        notices.append((applicationName, remainingSeconds))
    }

    func showRestrictionFailure(applicationName: String, coffee: CoffeeKind) {
        restrictionFailures.append(applicationName)
    }
}
