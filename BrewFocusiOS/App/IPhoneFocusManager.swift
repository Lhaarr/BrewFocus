import DeviceActivity
import FamilyControls
import Foundation
import UserNotifications

@MainActor
final class IPhoneFocusManager: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published var morningSelection = FamilyActivitySelection()
    @Published var morningStartTime: Date
    @Published private(set) var selectedCoffee: CoffeeKind = .espresso
    @Published private(set) var quickCoffee: CoffeeKind?
    @Published private(set) var coffeeHistory: [CoffeeActivityRecord] = []
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var session: IPhoneFocusSession?
    @Published private(set) var currentDate = Date()
    @Published private(set) var morningSchedule: MorningQuarantineSchedule?
    @Published private(set) var morningDailyEndsAt: Date?
    @Published private(set) var morningShortcutEndsAt: Date?
    @Published private(set) var isMorningPrepared = false
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var completionMessage: String?
    @Published var lastError: String?

    private let authorizationCenter: AuthorizationCenter
    private let activityCenter: DeviceActivityCenter
    private let notificationCenter: UNUserNotificationCenter
    private let calendar: Calendar
    private let now: () -> Date
    private var timer: Timer?
    private var hasBootstrapped = false

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        notificationCenter: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.authorizationCenter = authorizationCenter
        self.activityCenter = activityCenter
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.now = now

        let referenceDate = now()
        morningStartTime = calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: referenceDate
        ) ?? referenceDate
    }

    var isAuthorized: Bool {
        authorizationStatus == .approved
    }

    var selectedApplicationCount: Int {
        selection.applicationTokens.count
    }

    var hasUnsupportedSelection: Bool {
        !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var isCoffeeSelectionValid: Bool {
        ScreenTimeShared.isValidCoffeeSelection(selection, for: selectedCoffee)
    }

    var canStartCoffee: Bool {
        isAuthorized
            && isCoffeeSelectionValid
            && session == nil
            && !isMorningQuarantineActive
    }

    var canSaveQuickCoffee: Bool {
        isAuthorized && isCoffeeSelectionValid
    }

    var isSelectedCoffeeQuick: Bool {
        quickCoffee == selectedCoffee && ScreenTimeShared.isQuickCoffeeReady(selectedCoffee)
    }

    var remainingSeconds: Int {
        session?.remainingSeconds(at: currentDate) ?? 0
    }

    var remainingText: String {
        formatDuration(remainingSeconds)
    }

    var morningSelectedApplicationCount: Int {
        morningSelection.applicationTokens.count
    }

    var hasUnsupportedMorningSelection: Bool {
        !morningSelection.categoryTokens.isEmpty
            || !morningSelection.webDomainTokens.isEmpty
    }

    var canPrepareMorningQuarantine: Bool {
        isAuthorized
            && morningSelectedApplicationCount <= 4
            && !hasUnsupportedMorningSelection
    }

    var isMorningScheduled: Bool {
        morningSchedule != nil
    }

    var activeMorningEnd: Date? {
        [morningDailyEndsAt, morningShortcutEndsAt]
            .compactMap { $0 }
            .filter { $0 > currentDate }
            .max()
    }

    var isMorningQuarantineActive: Bool {
        activeMorningEnd != nil
    }

    var morningRemainingText: String {
        guard let activeMorningEnd else { return "00:00" }
        let remaining = max(0, Int(ceil(activeMorningEnd.timeIntervalSince(currentDate))))
        return formatDuration(remaining)
    }

    func bootstrap() {
        guard !hasBootstrapped else {
            refreshAfterBecomingActive()
            return
        }

        hasBootstrapped = true
        quickCoffee = ScreenTimeShared.loadQuickCoffee()
        coffeeHistory = ScreenTimeShared.loadCoffeeHistory()
        selectedCoffee = quickCoffee ?? .espresso
        selection = ScreenTimeShared.loadCoffeeSelection(for: selectedCoffee)
        morningSelection = ScreenTimeShared.loadMorningSelection()
        isMorningPrepared = ScreenTimeShared.isMorningPrepared
        morningSchedule = ScreenTimeShared.loadMorningSchedule()
        if let morningSchedule {
            morningStartTime = date(for: morningSchedule)
        }
        refreshAfterBecomingActive()
    }

    func refreshAfterBecomingActive() {
        authorizationStatus = authorizationCenter.authorizationStatus
        currentDate = now()
        coffeeHistory = ScreenTimeShared.loadCoffeeHistory()

        guard isAuthorized else {
            ScreenTimeShared.stopActiveCoffee(activityCenter: activityCenter)
            activityCenter.stopMonitoring([
                .brewFocusMorningDaily,
                .brewFocusMorningShortcut
            ])
            session = nil
            ScreenTimeShared.clearAllMorningRestrictions()
            ScreenTimeShared.removeMorningSchedule()
            morningSchedule = nil
            morningDailyEndsAt = nil
            morningShortcutEndsAt = nil
            stopTimer()
            return
        }

        refreshCoffeeState()
        refreshMorningState()
        quickCoffee = ScreenTimeShared.loadQuickCoffee()
        updateTimer()
    }

    func requestAuthorization() async {
        guard !isRequestingAuthorization else { return }

        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
            lastError = nil
            refreshAfterBecomingActive()
        } catch {
            authorizationStatus = authorizationCenter.authorizationStatus
            lastError = error.localizedDescription
        }
    }

    func selectCoffee(_ coffee: CoffeeKind) {
        if isCoffeeSelectionValid {
            try? ScreenTimeShared.saveCoffeeSelection(selection, for: selectedCoffee)
        }
        selectedCoffee = coffee
        selection = ScreenTimeShared.loadCoffeeSelection(for: coffee)
        lastError = nil
    }

    func saveQuickCoffee() {
        guard validateCoffeeConfiguration() else { return }

        do {
            try ScreenTimeShared.saveQuickCoffee(selectedCoffee, selection: selection)
            quickCoffee = selectedCoffee
            completionMessage = "\(selectedCoffee.name) saved as Quick Coffee."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startCoffee() async {
        guard validateCoffeeConfiguration() else { return }
        guard session == nil else {
            lastError = ScreenTimeSharedError.coffeeAlreadyActive.localizedDescription
            return
        }
        guard !isMorningQuarantineActive else {
            lastError = ScreenTimeSharedError.morningQuarantineActive.localizedDescription
            return
        }

        do {
            let startedSession = try ScreenTimeShared.startCoffee(
                selectedCoffee,
                selection: selection,
                activityCenter: activityCenter,
                now: now(),
                calendar: calendar
            )
            acceptStartedSession(startedSession)
            await scheduleSessionNotifications(for: startedSession)
        } catch {
            session = nil
            lastError = error.localizedDescription
        }
    }

    func startQuickCoffee() async {
        bootstrap()
        guard isAuthorized else {
            lastError = "Allow Screen Time access before starting Quick Coffee."
            return
        }

        do {
            let startedSession = try ScreenTimeShared.startQuickCoffee(
                activityCenter: activityCenter,
                now: now(),
                calendar: calendar
            )
            selectedCoffee = startedSession.coffee
            selection = ScreenTimeShared.loadCoffeeSelection(for: startedSession.coffee)
            acceptStartedSession(startedSession)
            await scheduleSessionNotifications(for: startedSession)
        } catch ScreenTimeSharedError.coffeeAlreadyActive {
            refreshCoffeeState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == "brewfocus" else { return }
        if url.host == "quick-start" {
            Task { await startQuickCoffee() }
        } else {
            refreshAfterBecomingActive()
        }
    }

    func abort() {
        finishCoffee(showingCompletion: false)
        updateTimer()
    }

    func prepareMorningQuarantine() {
        guard validateMorningConfiguration() else { return }

        do {
            try ScreenTimeShared.saveMorningSelection(morningSelection)
            isMorningPrepared = true
            lastError = nil
            refreshMorningState()
            updateTimer()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scheduleMorningQuarantine() {
        guard validateMorningConfiguration() else { return }

        let schedule = MorningQuarantineSchedule(
            date: morningStartTime,
            calendar: calendar
        )

        do {
            try ScreenTimeShared.saveMorningSelection(morningSelection)
            try ScreenTimeShared.saveMorningSchedule(schedule)
            ScreenTimeShared.clearDailyMorningSuppression()
            activityCenter.stopMonitoring([.brewFocusMorningDaily])
            try activityCenter.startMonitoring(
                .brewFocusMorningDaily,
                during: ScreenTimeShared.dailyDeviceActivitySchedule(
                    for: schedule,
                    calendar: calendar
                )
            )

            morningSchedule = schedule
            isMorningPrepared = true
            lastError = nil
            refreshMorningState()
            updateTimer()
        } catch {
            activityCenter.stopMonitoring([.brewFocusMorningDaily])
            ScreenTimeShared.clearMorningRestriction(source: .daily)
            ScreenTimeShared.removeMorningSchedule()
            morningSchedule = nil
            lastError = error.localizedDescription
        }
    }

    func removeMorningSchedule() {
        activityCenter.stopMonitoring([.brewFocusMorningDaily])
        ScreenTimeShared.clearMorningRestriction(source: .daily)
        ScreenTimeShared.removeMorningSchedule()
        morningSchedule = nil
        morningDailyEndsAt = nil
        updateTimer()
    }

    func startMorningQuarantineNow() {
        guard validateMorningConfiguration() else { return }

        do {
            try ScreenTimeShared.saveMorningSelection(morningSelection)
            let startDate = now()
            morningShortcutEndsAt = try ScreenTimeShared.startOneHourMorningQuarantine(
                activityCenter: activityCenter,
                now: startDate,
                calendar: calendar
            )
            currentDate = startDate
            isMorningPrepared = true
            completionMessage = nil
            lastError = nil
            updateTimer()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func endMorningQuarantine() {
        if let morningDailyEndsAt, morningDailyEndsAt > currentDate {
            try? ScreenTimeShared.suppressDailyMorningQuarantine(until: morningDailyEndsAt)
        }
        activityCenter.stopMonitoring([.brewFocusMorningShortcut])
        ScreenTimeShared.clearAllMorningRestrictions()
        morningDailyEndsAt = nil
        morningShortcutEndsAt = nil
        updateTimer()
    }

    func clearError() {
        lastError = nil
    }

    func clearCompletion() {
        completionMessage = nil
    }

    private func validateCoffeeConfiguration() -> Bool {
        guard isAuthorized else {
            lastError = "Allow Screen Time access before ordering a coffee."
            return false
        }
        guard !hasUnsupportedSelection else {
            lastError = "Choose individual apps only; remove category and website selections."
            return false
        }
        guard selectedCoffee.applicationSelectionRange.contains(selectedApplicationCount) else {
            let range = selectedCoffee.applicationSelectionRange
            if range.lowerBound == range.upperBound {
                lastError = "\(selectedCoffee.name) doesn’t use an app selection."
            } else {
                lastError = "Choose \(range.lowerBound) to \(range.upperBound) apps for \(selectedCoffee.name)."
            }
            return false
        }
        return true
    }

    private func validateMorningConfiguration() -> Bool {
        guard isAuthorized else {
            lastError = "Allow Screen Time access before preparing Morning Quarantine."
            return false
        }
        guard morningSelectedApplicationCount <= 4 else {
            lastError = "Choose no more than four apps that should stay available."
            return false
        }
        guard !hasUnsupportedMorningSelection else {
            lastError = "Morning Quarantine accepts individual apps only. Remove category and website selections."
            return false
        }
        return true
    }

    private func acceptStartedSession(_ startedSession: IPhoneFocusSession) {
        currentDate = startedSession.startedAt
        session = startedSession
        quickCoffee = startedSession.coffee
        completionMessage = nil
        lastError = nil
        updateTimer()
    }

    private func refreshCoffeeState() {
        guard let storedSession = ScreenTimeShared.loadActiveCoffeeSession() else {
            if session != nil {
                session = nil
                completionMessage = "Coffee finished."
                coffeeHistory = ScreenTimeShared.loadCoffeeHistory()
            }
            return
        }

        guard storedSession.isActive(at: currentDate) else {
            finishCoffee(showingCompletion: true)
            return
        }

        let recoveredSelection = ScreenTimeShared.loadCoffeeSelection(for: storedSession.coffee)
        guard ScreenTimeShared.isValidCoffeeSelection(
            recoveredSelection,
            for: storedSession.coffee
        ) else {
            finishCoffee(showingCompletion: false)
            lastError = "The saved app selection is no longer valid. Choose your apps again."
            return
        }

        selectedCoffee = storedSession.coffee
        selection = recoveredSelection
        session = storedSession
        ScreenTimeShared.reapplyActiveCoffee(
            for: ScreenTimeShared.activityName(for: storedSession.coffee),
            at: currentDate
        )
    }

    private func refreshMorningState() {
        morningSchedule = ScreenTimeShared.loadMorningSchedule()
        isMorningPrepared = ScreenTimeShared.isMorningPrepared
        let storedSelection = ScreenTimeShared.loadMorningSelection()

        if let shortcutEnd = ScreenTimeShared.loadMorningEndsAt(source: .shortcut),
           shortcutEnd > currentDate,
           isMorningPrepared,
           ScreenTimeShared.isValidMorningSelection(storedSelection) {
            morningShortcutEndsAt = shortcutEnd
            ScreenTimeShared.applyMorningShield(using: storedSelection, source: .shortcut)
        } else {
            ScreenTimeShared.clearMorningRestriction(source: .shortcut)
            morningShortcutEndsAt = nil
        }

        if let morningSchedule,
           let dailyEnd = morningSchedule.activeEndDate(at: currentDate, calendar: calendar),
           !ScreenTimeShared.isDailyMorningQuarantineSuppressed(at: currentDate),
           isMorningPrepared,
           ScreenTimeShared.isValidMorningSelection(storedSelection) {
            do {
                try ScreenTimeShared.saveMorningEndsAt(dailyEnd, source: .daily)
                ScreenTimeShared.applyMorningShield(using: storedSelection, source: .daily)
                morningDailyEndsAt = dailyEnd
            } catch {
                ScreenTimeShared.clearMorningRestriction(source: .daily)
                morningDailyEndsAt = nil
                lastError = error.localizedDescription
            }
        } else {
            ScreenTimeShared.clearMorningRestriction(source: .daily)
            morningDailyEndsAt = nil
        }
    }

    private func refreshTime() {
        currentDate = now()

        if let session, !session.isActive(at: currentDate) {
            finishCoffee(showingCompletion: true)
        }

        if let morningDailyEndsAt, morningDailyEndsAt <= currentDate {
            ScreenTimeShared.clearMorningRestriction(source: .daily)
            self.morningDailyEndsAt = nil
        }

        if let morningShortcutEndsAt, morningShortcutEndsAt <= currentDate {
            activityCenter.stopMonitoring([.brewFocusMorningShortcut])
            ScreenTimeShared.clearMorningRestriction(source: .shortcut)
            self.morningShortcutEndsAt = nil
        }

        updateTimer()
    }

    private func finishCoffee(showingCompletion: Bool) {
        let finishedSession = session ?? ScreenTimeShared.loadActiveCoffeeSession()
        let coffee = finishedSession?.coffee
        if showingCompletion, let finishedSession {
            ScreenTimeShared.completeCoffee(
                finishedSession,
                activityCenter: activityCenter
            )
        } else {
            ScreenTimeShared.stopActiveCoffee(activityCenter: activityCenter)
        }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: NotificationIdentifier.all
        )
        session = nil
        coffeeHistory = ScreenTimeShared.loadCoffeeHistory()
        if showingCompletion {
            completionMessage = "\(coffee?.name ?? "Coffee") finished."
        }
    }

    private func scheduleSessionNotifications(for session: IPhoneFocusSession) async {
        do {
            let settings = await notificationCenter.notificationSettings()
            let canNotify: Bool

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                canNotify = true
            case .notDetermined:
                canNotify = try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound]
                )
            case .denied:
                canNotify = false
            @unknown default:
                canNotify = false
            }

            guard canNotify else { return }

            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: NotificationIdentifier.all
            )

            let nudge = UNMutableNotificationContent()
            nudge.title = "Your \(session.coffee.name) is ready."
            nudge.body = "Put your iPhone down and let it cool."
            nudge.sound = .default
            try await notificationCenter.add(
                UNNotificationRequest(
                    identifier: NotificationIdentifier.nudge,
                    content: nudge,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: 5,
                        repeats: false
                    )
                )
            )

            let completion = UNMutableNotificationContent()
            completion.title = "\(session.coffee.name) finished."
            completion.body = "\(Int(session.coffee.duration / 60)) focused minutes."
            completion.sound = .default
            try await notificationCenter.add(
                UNNotificationRequest(
                    identifier: NotificationIdentifier.completion,
                    content: completion,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: session.coffee.duration,
                        repeats: false
                    )
                )
            )
        } catch {
            // Notifications are optional; restriction must continue independently.
        }
    }

    private func date(for schedule: MorningQuarantineSchedule) -> Date {
        calendar.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: now()
        ) ?? now()
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func updateTimer() {
        if session != nil || isMorningQuarantineActive {
            startTimerIfNeeded()
        } else {
            stopTimer()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
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

private enum NotificationIdentifier {
    static let nudge = "brewfocus.coffee.nudge"
    static let completion = "brewfocus.coffee.completion"
    static let all = [nudge, completion]
}
