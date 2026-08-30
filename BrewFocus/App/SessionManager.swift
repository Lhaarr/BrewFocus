import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var snapshot = FocusSnapshot()
    @Published private(set) var availableApplications: [AllowedApplication] = []
    @Published private(set) var selectedBundleIdentifiers: Set<String> = []
    @Published private(set) var currentDate = Date()
    @Published private(set) var lastCompletedSession: FocusSession?
    @Published private(set) var lastBlockedApplicationName: String?
    @Published private(set) var lastRestrictionFailure: RestrictedApplication?
    @Published var lastError: String?

    private let store: SessionStoring
    private let applicationCatalog: ApplicationCataloging
    private let restriction: FocusRestricting
    private let blockNoticePresenter: BlockNoticePresenting
    private let now: () -> Date
    private let sessionDurationOverride: TimeInterval?
    private let schedulesTimer: Bool
    private var timer: Timer?
    private var hasBootstrapped = false

    init(
        store: SessionStoring,
        applicationCatalog: ApplicationCataloging,
        restriction: FocusRestricting,
        blockNoticePresenter: BlockNoticePresenting,
        sessionDuration: TimeInterval? = nil,
        now: @escaping () -> Date = Date.init,
        schedulesTimer: Bool = true
    ) {
        self.store = store
        self.applicationCatalog = applicationCatalog
        self.restriction = restriction
        self.blockNoticePresenter = blockNoticePresenter
        self.sessionDurationOverride = sessionDuration
        self.now = now
        self.schedulesTimer = schedulesTimer
        self.currentDate = now()
    }

    static func live() -> SessionManager {
        SessionManager(
            store: JSONSessionStore(),
            applicationCatalog: WorkspaceApplicationCatalog(),
            restriction: WorkspaceRestrictionMonitor(),
            blockNoticePresenter: AppKitBlockNoticePresenter()
        )
    }

    var currentSession: FocusSession? {
        snapshot.currentSession
    }

    var completedSessions: [FocusSession] {
        snapshot.history
            .filter { $0.status == .completed }
            .sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
    }

    func canStart(_ coffee: CoffeeKind) -> Bool {
        let selectionCount = coffee.restrictionMode == .none
            ? 0
            : selectedBundleIdentifiers.count
        return coffee.applicationSelectionRange.contains(selectionCount)
            && currentSession == nil
    }

    var remainingSeconds: Int {
        guard let session = currentSession else { return 0 }

        switch session.status {
        case .active:
            guard let scheduledEndAt = session.scheduledEndAt else { return 0 }
            return max(0, Int(ceil(scheduledEndAt.timeIntervalSince(currentDate))))
        case .paused:
            return max(0, Int(ceil(session.pausedRemaining ?? 0)))
        case .completed, .aborted:
            return 0
        }
    }

    var remainingText: String {
        DurationFormatting.timerText(seconds: remainingSeconds)
    }

    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        currentDate = now()

        do {
            snapshot = try store.load()
            recoverPersistedSession()
        } catch {
            snapshot = FocusSnapshot()
            lastError = error.localizedDescription
        }

        refreshApplications()
    }

    func refreshApplications() {
        availableApplications = applicationCatalog.runningApplications()
        let visibleIdentifiers = Set(availableApplications.map(\.bundleIdentifier))
        selectedBundleIdentifiers.formIntersection(visibleIdentifiers)
    }

    func prepareOrder(for _: CoffeeKind) {
        guard currentSession == nil else { return }
        selectedBundleIdentifiers = []
        lastError = nil
        refreshApplications()
    }

    func toggleSelection(for application: AllowedApplication, coffee: CoffeeKind) {
        guard currentSession == nil else { return }

        if selectedBundleIdentifiers.contains(application.bundleIdentifier) {
            selectedBundleIdentifiers.remove(application.bundleIdentifier)
            lastError = nil
            return
        }

        let maximum = coffee.applicationSelectionRange.upperBound
        guard selectedBundleIdentifiers.count < maximum else {
            lastError = "\(coffee.name) allows at most \(maximum) selected apps."
            return
        }

        selectedBundleIdentifiers.insert(application.bundleIdentifier)
        lastError = nil
    }

    func start(_ coffee: CoffeeKind) {
        refreshApplications()

        let selectedApplications = coffee.restrictionMode == .none
            ? []
            : availableApplications.filter {
                selectedBundleIdentifiers.contains($0.bundleIdentifier)
            }

        guard coffee.applicationSelectionRange.contains(selectedApplications.count) else {
            lastError = selectionError(for: coffee)
            return
        }

        let startDate = now()
        let duration = sessionDurationOverride ?? coffee.duration
        currentDate = startDate
        let session = FocusSession(
            coffee: coffee,
            startedAt: startDate,
            plannedDuration: duration,
            scheduledEndAt: startDate.addingTimeInterval(duration),
            selectedApplications: selectedApplications
        )

        snapshot.currentSession = session
        guard persist() else {
            snapshot.currentSession = nil
            return
        }

        lastCompletedSession = nil
        lastBlockedApplicationName = nil
        lastRestrictionFailure = nil
        engageRestriction(for: session)
        startTimerIfNeeded()
    }

    func pause() {
        guard var session = currentSession, session.status == .active else { return }

        currentDate = now()
        let remaining = max(
            0,
            session.scheduledEndAt?.timeIntervalSince(currentDate) ?? 0
        )

        session.status = .paused
        session.pausedRemaining = remaining
        session.scheduledEndAt = nil
        snapshot.currentSession = session
        _ = persist()

        disengageRestriction(for: session)
        session.hiddenBundleIdentifiers = []
        snapshot.currentSession = session
        _ = persist()
        stopTimer()
        lastRestrictionFailure = nil
    }

    func resume() {
        guard var session = currentSession, session.status == .paused else { return }

        let resumeDate = now()
        let remaining = max(0, session.pausedRemaining ?? 0)
        guard remaining > 0 else {
            completeCurrentSession(at: resumeDate)
            return
        }

        currentDate = resumeDate
        session.status = .active
        session.scheduledEndAt = resumeDate.addingTimeInterval(remaining)
        session.pausedRemaining = nil
        session.hiddenBundleIdentifiers = []
        snapshot.currentSession = session
        _ = persist()

        engageRestriction(for: session)
        startTimerIfNeeded()
    }

    func abort() {
        guard var session = currentSession else { return }

        disengageRestriction(for: session)
        session.hiddenBundleIdentifiers = []
        session.status = .aborted
        session.finishedAt = now()
        session.pausedRemaining = nil
        snapshot.currentSession = nil
        snapshot.history.insert(session, at: 0)
        _ = persist()

        stopTimer()
        selectedBundleIdentifiers = []
        lastBlockedApplicationName = nil
        lastRestrictionFailure = nil
    }

    func refreshTime() {
        currentDate = now()
        guard
            let session = currentSession,
            session.status == .active,
            let scheduledEndAt = session.scheduledEndAt,
            currentDate >= scheduledEndAt
        else {
            return
        }

        completeCurrentSession(at: scheduledEndAt)
    }

    func clearError() {
        lastError = nil
    }

    func clearCompletion() {
        lastCompletedSession = nil
    }

    private func recoverPersistedSession() {
        guard var session = currentSession else { return }

        switch session.status {
        case .active:
            guard let scheduledEndAt = session.scheduledEndAt else {
                restriction.restore(bundleIdentifiers: session.hiddenBundleIdentifiers)
                session.status = .aborted
                session.finishedAt = currentDate
                session.hiddenBundleIdentifiers = []
                archiveRecoveredSession(session)
                return
            }

            if scheduledEndAt <= currentDate {
                restriction.restore(bundleIdentifiers: session.hiddenBundleIdentifiers)
                completeRecoveredSession(session, at: scheduledEndAt)
            } else {
                engageRestriction(for: session)
                startTimerIfNeeded()
            }

        case .paused:
            restriction.restore(bundleIdentifiers: session.hiddenBundleIdentifiers)
            if !session.hiddenBundleIdentifiers.isEmpty {
                session.hiddenBundleIdentifiers = []
                snapshot.currentSession = session
                _ = persist()
            }

        case .completed, .aborted:
            restriction.restore(bundleIdentifiers: session.hiddenBundleIdentifiers)
            session.hiddenBundleIdentifiers = []
            archiveRecoveredSession(session)
        }
    }

    private func engageRestriction(for session: FocusSession) {
        guard session.effectiveRestrictionMode != .none else { return }

        let sessionID = session.id
        restriction.start(
            restriction: session.applicationRestriction,
            onHidden: { [weak self] application in
                self?.recordHidden(application, for: sessionID)
            },
            onBlockedAttempt: { [weak self] application in
                self?.showBlockNotice(for: application, sessionID: sessionID)
            },
            onRestrictionFailure: { [weak self] application in
                self?.handleRestrictionFailure(application, sessionID: sessionID)
            }
        )
    }

    private func recordHidden(_ application: RestrictedApplication, for sessionID: UUID) {
        guard
            var session = currentSession,
            session.id == sessionID,
            session.status == .active,
            !session.hiddenBundleIdentifiers.contains(application.bundleIdentifier)
        else {
            return
        }

        session.hiddenBundleIdentifiers.insert(application.bundleIdentifier)
        snapshot.currentSession = session
        if lastRestrictionFailure?.bundleIdentifier == application.bundleIdentifier {
            lastRestrictionFailure = nil
        }
        _ = persist()
    }

    private func handleRestrictionFailure(
        _ application: RestrictedApplication,
        sessionID: UUID
    ) {
        guard let session = currentSession, session.id == sessionID else { return }
        lastRestrictionFailure = application
        blockNoticePresenter.showRestrictionFailure(
            applicationName: application.name,
            coffee: session.coffee
        )
    }

    private func showBlockNotice(for application: RestrictedApplication, sessionID: UUID) {
        guard let session = currentSession, session.id == sessionID else { return }
        refreshTime()
        lastBlockedApplicationName = application.name
        blockNoticePresenter.show(
            applicationName: application.name,
            coffee: session.coffee,
            remainingSeconds: remainingSeconds
        )
    }

    private func completeCurrentSession(at completionDate: Date) {
        guard var session = currentSession else { return }

        disengageRestriction(for: session)
        session.hiddenBundleIdentifiers = []
        session.status = .completed
        session.finishedAt = completionDate
        session.pausedRemaining = nil
        snapshot.currentSession = nil
        snapshot.history.insert(session, at: 0)
        _ = persist()

        stopTimer()
        selectedBundleIdentifiers = []
        lastBlockedApplicationName = nil
        lastRestrictionFailure = nil
        lastCompletedSession = session
    }

    private func completeRecoveredSession(_ session: FocusSession, at completionDate: Date) {
        var completedSession = session
        completedSession.hiddenBundleIdentifiers = []
        completedSession.status = .completed
        completedSession.finishedAt = completionDate
        completedSession.pausedRemaining = nil
        snapshot.currentSession = nil
        snapshot.history.insert(completedSession, at: 0)
        _ = persist()
        lastCompletedSession = completedSession
    }

    private func archiveRecoveredSession(_ session: FocusSession) {
        snapshot.currentSession = nil
        snapshot.history.insert(session, at: 0)
        _ = persist()
    }

    private func disengageRestriction(for session: FocusSession) {
        guard session.effectiveRestrictionMode != .none else { return }
        restriction.stop(restoring: session.hiddenBundleIdentifiers)
    }

    private func selectionError(for coffee: CoffeeKind) -> String {
        switch coffee.restrictionMode {
        case .none:
            return "\(coffee.name) does not need an app selection."
        case .blockList:
            return "Choose one to \(coffee.applicationSelectionRange.upperBound) distractions to block."
        case .allowList:
            return "Choose one to \(coffee.applicationSelectionRange.upperBound) running apps for this \(coffee.name)."
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try store.save(snapshot)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func startTimerIfNeeded() {
        stopTimer()
        guard schedulesTimer else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTime()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
