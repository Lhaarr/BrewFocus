import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ScreenTimeSharedError: LocalizedError {
    case appGroupUnavailable
    case invalidCoffeeConfiguration(CoffeeKind)
    case invalidMorningConfiguration
    case coffeeAlreadyActive
    case morningQuarantineActive
    case quickCoffeeNotConfigured

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "BrewFocus couldn’t access its shared App Group. Check target provisioning."
        case let .invalidCoffeeConfiguration(coffee):
            "The saved \(coffee.name) app selection is incomplete. Open BrewFocus and choose it again."
        case .invalidMorningConfiguration:
            "Choose no more than four individual apps as morning exceptions."
        case .coffeeAlreadyActive:
            "A coffee is already running."
        case .morningQuarantineActive:
            "Morning Quarantine is active. End it before starting another coffee."
        case .quickCoffeeNotConfigured:
            "Open BrewFocus and save a Quick Coffee first."
        }
    }
}

struct IPhoneFocusSession: Codable, Equatable, Sendable {
    let coffee: CoffeeKind
    let startedAt: Date
    let endsAt: Date
    let selectedApplicationCount: Int

    func remainingSeconds(at date: Date) -> Int {
        max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }

    func isActive(at date: Date) -> Bool {
        endsAt > date
    }
}

struct BrewFocusWidgetState: Equatable, Sendable {
    enum ActiveMode: Equatable, Sendable {
        case coffee(CoffeeKind)
        case morningQuarantine
    }

    let activeMode: ActiveMode?
    let startedAt: Date?
    let endsAt: Date?
    let quickCoffee: CoffeeKind?
    let isQuickCoffeeReady: Bool

    var activeTitle: String? {
        switch activeMode {
        case let .coffee(coffee): coffee.name
        case .morningQuarantine: "Morning Quarantine"
        case nil: nil
        }
    }

    var activeSymbolName: String {
        switch activeMode {
        case .morningQuarantine: "sunrise.fill"
        case .coffee, nil: "cup.and.saucer.fill"
        }
    }
}

struct MorningQuarantineSchedule: Codable, Equatable, Sendable {
    static let duration: TimeInterval = 60 * 60

    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }

    var endHour: Int {
        (hour + 1) % 24
    }

    func activeEndDate(at date: Date, calendar: Calendar = .current) -> Date? {
        guard let todayStart = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) else {
            return nil
        }

        let start = todayStart <= date
            ? todayStart
            : calendar.date(byAdding: .day, value: -1, to: todayStart)
        guard let start else { return nil }

        let end = start.addingTimeInterval(Self.duration)
        return date >= start && date < end ? end : nil
    }
}

enum MorningQuarantineSource: CaseIterable {
    case daily
    case shortcut
}

enum ScreenTimeShared {
    static let appGroupIdentifier = "group.app.brewfocus.shared"

    private static let activeCoffeeKey = "coffee.active.kind"
    private static let activeCoffeeStartedAtKey = "coffee.active.startedAt"
    private static let activeCoffeeEndsAtKey = "prototype.espresso.endsAt"
    private static let coffeeHistoryKey = "coffee.completed.history"
    private static let quickCoffeeKey = "coffee.quick.kind"
    private static let legacyEspressoSelectionKey = "prototype.espresso.selection"
    private static let morningSelectionKey = "morning.quarantine.selection"
    private static let morningPreparedKey = "morning.quarantine.prepared"
    private static let morningScheduleKey = "morning.quarantine.daily.schedule"
    private static let morningDailyEndsAtKey = "morning.quarantine.daily.endsAt"
    private static let morningShortcutEndsAtKey = "morning.quarantine.shortcut.endsAt"
    private static let morningDailySuppressedUntilKey = "morning.quarantine.daily.suppressedUntil"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var allCoffeeActivities: [DeviceActivityName] {
        CoffeeKind.allCases.map(activityName(for:))
    }

    static func saveCoffeeSelection(
        _ selection: FamilyActivitySelection,
        for coffee: CoffeeKind
    ) throws {
        guard isValidCoffeeSelection(selection, for: coffee) else {
            throw ScreenTimeSharedError.invalidCoffeeConfiguration(coffee)
        }
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }

        defaults.set(
            try PropertyListEncoder().encode(selection),
            forKey: selectionKey(for: coffee)
        )
    }

    static func loadCoffeeSelection(for coffee: CoffeeKind) -> FamilyActivitySelection {
        guard
            let data = defaults?.data(forKey: selectionKey(for: coffee)),
            let selection = try? PropertyListDecoder().decode(
                FamilyActivitySelection.self,
                from: data
            )
        else {
            return FamilyActivitySelection()
        }

        return selection
    }

    static func isValidCoffeeSelection(
        _ selection: FamilyActivitySelection,
        for coffee: CoffeeKind
    ) -> Bool {
        coffee.applicationSelectionRange.contains(selection.applicationTokens.count)
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    static func saveQuickCoffee(
        _ coffee: CoffeeKind,
        selection: FamilyActivitySelection
    ) throws {
        try saveCoffeeSelection(selection, for: coffee)
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }
        defaults.set(coffee.rawValue, forKey: quickCoffeeKey)
        reloadWidgets()
    }

    static func loadQuickCoffee() -> CoffeeKind? {
        guard
            let rawValue = defaults?.string(forKey: quickCoffeeKey),
            let coffee = CoffeeKind(rawValue: rawValue)
        else {
            return nil
        }
        return coffee
    }

    static func isQuickCoffeeReady(_ coffee: CoffeeKind? = loadQuickCoffee()) -> Bool {
        guard let coffee else { return false }
        return isValidCoffeeSelection(loadCoffeeSelection(for: coffee), for: coffee)
    }

    @discardableResult
    static func startCoffee(
        _ coffee: CoffeeKind,
        selection: FamilyActivitySelection,
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        now: Date = Date(),
        calendar: Calendar = .current,
        saveAsQuickCoffee: Bool = true
    ) throws -> IPhoneFocusSession {
        guard isValidCoffeeSelection(selection, for: coffee) else {
            throw ScreenTimeSharedError.invalidCoffeeConfiguration(coffee)
        }
        if let session = loadActiveCoffeeSession(), session.isActive(at: now) {
            throw ScreenTimeSharedError.coffeeAlreadyActive
        }
        if activeMorningEnd(at: now) != nil {
            throw ScreenTimeSharedError.morningQuarantineActive
        }

        let session = IPhoneFocusSession(
            coffee: coffee,
            startedAt: now,
            endsAt: now.addingTimeInterval(coffee.duration),
            selectedApplicationCount: selection.applicationTokens.count
        )

        activityCenter.stopMonitoring(allCoffeeActivities)
        clearAllCoffeeRestrictions()

        do {
            try saveCoffeeSelection(selection, for: coffee)
            try saveActiveCoffeeSession(session)
            try activityCenter.startMonitoring(
                activityName(for: coffee),
                during: oneShotDeviceActivitySchedule(
                    startingAt: session.startedAt,
                    endingAt: session.endsAt,
                    calendar: calendar
                )
            )
            applyCoffeeShield(coffee, using: selection)
            if saveAsQuickCoffee {
                try saveQuickCoffee(coffee, selection: selection)
            }
            reloadWidgets()
            return session
        } catch {
            activityCenter.stopMonitoring(allCoffeeActivities)
            clearAllCoffeeRestrictions()
            removeActiveCoffeeSession()
            throw error
        }
    }

    @discardableResult
    static func startQuickCoffee(
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> IPhoneFocusSession {
        guard let coffee = loadQuickCoffee(), isQuickCoffeeReady(coffee) else {
            throw ScreenTimeSharedError.quickCoffeeNotConfigured
        }
        return try startCoffee(
            coffee,
            selection: loadCoffeeSelection(for: coffee),
            activityCenter: activityCenter,
            now: now,
            calendar: calendar
        )
    }

    static func loadActiveCoffeeSession() -> IPhoneFocusSession? {
        guard let endsAt = defaults?.object(forKey: activeCoffeeEndsAtKey) as? Date else {
            return nil
        }

        let coffee = defaults?.string(forKey: activeCoffeeKey)
            .flatMap(CoffeeKind.init(rawValue:)) ?? .espresso
        let startedAt = defaults?.object(forKey: activeCoffeeStartedAtKey) as? Date
            ?? endsAt.addingTimeInterval(-15 * 60)

        return IPhoneFocusSession(
            coffee: coffee,
            startedAt: startedAt,
            endsAt: endsAt,
            selectedApplicationCount: loadCoffeeSelection(for: coffee).applicationTokens.count
        )
    }

    static func stopActiveCoffee(
        activityCenter: DeviceActivityCenter = DeviceActivityCenter()
    ) {
        activityCenter.stopMonitoring(allCoffeeActivities)
        clearAllCoffeeRestrictions()
        removeActiveCoffeeSession()
    }

    static func completeCoffee(
        _ session: IPhoneFocusSession,
        activityCenter: DeviceActivityCenter = DeviceActivityCenter()
    ) {
        activityCenter.stopMonitoring(allCoffeeActivities)
        clearAllCoffeeRestrictions()
        archiveCompletedCoffee(session)
        removeActiveCoffeeSession()
    }

    static func loadCoffeeHistory() -> [CoffeeActivityRecord] {
        guard
            let data = defaults?.data(forKey: coffeeHistoryKey),
            let records = try? PropertyListDecoder().decode(
                [CoffeeActivityRecord].self,
                from: data
            )
        else {
            return []
        }

        return records.sorted { $0.completedAt > $1.completedAt }
    }

    static func finishCoffeeInterval(for activity: DeviceActivityName) {
        guard let coffee = coffee(for: activity) else { return }
        clearCoffeeRestriction(coffee)

        guard let session = loadActiveCoffeeSession(), session.coffee == coffee else {
            reloadWidgets()
            return
        }
        archiveCompletedCoffee(session)
        removeActiveCoffeeSession()
    }

    static func reapplyActiveCoffee(for activity: DeviceActivityName, at date: Date = Date()) {
        guard let coffee = coffee(for: activity) else { return }
        guard let session = loadActiveCoffeeSession(), session.coffee == coffee else {
            clearCoffeeRestriction(coffee)
            reloadWidgets()
            return
        }
        guard session.isActive(at: date) else {
            finishCoffeeInterval(for: activity)
            return
        }

        let selection = loadCoffeeSelection(for: coffee)
        guard isValidCoffeeSelection(selection, for: coffee) else {
            clearCoffeeRestriction(coffee)
            removeActiveCoffeeSession()
            return
        }
        applyCoffeeShield(coffee, using: selection)
        reloadWidgets()
    }

    static func widgetState(at date: Date = Date()) -> BrewFocusWidgetState {
        let quickCoffee = loadQuickCoffee()
        let quickReady = isQuickCoffeeReady(quickCoffee)

        if let session = loadActiveCoffeeSession(), session.isActive(at: date) {
            return BrewFocusWidgetState(
                activeMode: .coffee(session.coffee),
                startedAt: session.startedAt,
                endsAt: session.endsAt,
                quickCoffee: quickCoffee,
                isQuickCoffeeReady: quickReady
            )
        }

        if let morningEnd = activeMorningEnd(at: date) {
            return BrewFocusWidgetState(
                activeMode: .morningQuarantine,
                startedAt: morningEnd.addingTimeInterval(-MorningQuarantineSchedule.duration),
                endsAt: morningEnd,
                quickCoffee: quickCoffee,
                isQuickCoffeeReady: quickReady
            )
        }

        return BrewFocusWidgetState(
            activeMode: nil,
            startedAt: nil,
            endsAt: nil,
            quickCoffee: quickCoffee,
            isQuickCoffeeReady: quickReady
        )
    }

    static var isMorningPrepared: Bool {
        defaults?.bool(forKey: morningPreparedKey) == true
    }

    static func saveMorningSelection(_ selection: FamilyActivitySelection) throws {
        guard isValidMorningSelection(selection) else {
            throw ScreenTimeSharedError.invalidMorningConfiguration
        }
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }

        let data = try PropertyListEncoder().encode(selection)
        defaults.set(data, forKey: morningSelectionKey)
        defaults.set(true, forKey: morningPreparedKey)
    }

    static func loadMorningSelection() -> FamilyActivitySelection {
        guard
            let data = defaults?.data(forKey: morningSelectionKey),
            let selection = try? PropertyListDecoder().decode(
                FamilyActivitySelection.self,
                from: data
            )
        else {
            return FamilyActivitySelection()
        }

        return selection
    }

    static func isValidMorningSelection(_ selection: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.count <= 4
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    static func saveMorningSchedule(_ schedule: MorningQuarantineSchedule) throws {
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }
        defaults.set(try PropertyListEncoder().encode(schedule), forKey: morningScheduleKey)
    }

    static func loadMorningSchedule() -> MorningQuarantineSchedule? {
        guard
            let data = defaults?.data(forKey: morningScheduleKey),
            let schedule = try? PropertyListDecoder().decode(
                MorningQuarantineSchedule.self,
                from: data
            )
        else {
            return nil
        }

        return schedule
    }

    static func removeMorningSchedule() {
        defaults?.removeObject(forKey: morningScheduleKey)
        defaults?.removeObject(forKey: morningDailySuppressedUntilKey)
    }

    static func suppressDailyMorningQuarantine(until date: Date) throws {
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }
        defaults.set(date, forKey: morningDailySuppressedUntilKey)
    }

    static func isDailyMorningQuarantineSuppressed(at date: Date) -> Bool {
        guard let suppressedUntil = defaults?.object(
            forKey: morningDailySuppressedUntilKey
        ) as? Date else {
            return false
        }

        if suppressedUntil > date {
            return true
        }

        defaults?.removeObject(forKey: morningDailySuppressedUntilKey)
        return false
    }

    static func clearDailyMorningSuppression() {
        defaults?.removeObject(forKey: morningDailySuppressedUntilKey)
    }

    static func saveMorningEndsAt(_ date: Date, source: MorningQuarantineSource) throws {
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }
        defaults.set(date, forKey: morningEndsAtKey(for: source))
        reloadWidgets()
    }

    static func loadMorningEndsAt(source: MorningQuarantineSource) -> Date? {
        defaults?.object(forKey: morningEndsAtKey(for: source)) as? Date
    }

    static func applyMorningShield(
        using selection: FamilyActivitySelection,
        source: MorningQuarantineSource
    ) {
        morningStore(for: source).shield.applicationCategories = .all(
            except: selection.applicationTokens
        )
    }

    static func clearMorningRestriction(source: MorningQuarantineSource) {
        morningStore(for: source).clearAllSettings()
        defaults?.removeObject(forKey: morningEndsAtKey(for: source))
        reloadWidgets()
    }

    static func clearAllMorningRestrictions() {
        MorningQuarantineSource.allCases.forEach(clearMorningRestriction)
    }

    static func dailyDeviceActivitySchedule(
        for schedule: MorningQuarantineSchedule,
        calendar: Calendar = .current
    ) -> DeviceActivitySchedule {
        var start = DateComponents(hour: schedule.hour, minute: schedule.minute)
        var end = DateComponents(hour: schedule.endHour, minute: schedule.minute)
        start.calendar = calendar
        start.timeZone = calendar.timeZone
        end.calendar = calendar
        end.timeZone = calendar.timeZone
        return DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )
    }

    static func oneShotDeviceActivitySchedule(
        startingAt startDate: Date,
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) -> DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: dateComponents(
                for: startDate.addingTimeInterval(-1),
                calendar: calendar
            ),
            intervalEnd: dateComponents(for: endDate, calendar: calendar),
            repeats: false
        )
    }

    static func startOneHourMorningQuarantine(
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Date {
        let selection = loadMorningSelection()
        guard isMorningPrepared, isValidMorningSelection(selection) else {
            throw ScreenTimeSharedError.invalidMorningConfiguration
        }

        let endsAt = now.addingTimeInterval(MorningQuarantineSchedule.duration)
        activityCenter.stopMonitoring([.brewFocusMorningShortcut])
        clearMorningRestriction(source: .shortcut)

        do {
            try saveMorningEndsAt(endsAt, source: .shortcut)
            try activityCenter.startMonitoring(
                .brewFocusMorningShortcut,
                during: oneShotDeviceActivitySchedule(
                    startingAt: now,
                    endingAt: endsAt,
                    calendar: calendar
                )
            )
            applyMorningShield(using: selection, source: .shortcut)
            reloadWidgets()
            return endsAt
        } catch {
            activityCenter.stopMonitoring([.brewFocusMorningShortcut])
            clearMorningRestriction(source: .shortcut)
            throw error
        }
    }

    static func activityName(for coffee: CoffeeKind) -> DeviceActivityName {
        switch coffee {
        case .latte: .brewFocusLatte
        case .cappuccino: .brewFocusCappuccino
        case .americano: .brewFocusAmericano
        case .espresso: .brewFocusEspresso
        }
    }

    static func coffee(for activity: DeviceActivityName) -> CoffeeKind? {
        switch activity {
        case .brewFocusLatte: .latte
        case .brewFocusCappuccino: .cappuccino
        case .brewFocusAmericano: .americano
        case .brewFocusEspresso: .espresso
        default: nil
        }
    }

    private static func saveActiveCoffeeSession(_ session: IPhoneFocusSession) throws {
        guard let defaults else {
            throw ScreenTimeSharedError.appGroupUnavailable
        }
        defaults.set(session.coffee.rawValue, forKey: activeCoffeeKey)
        defaults.set(session.startedAt, forKey: activeCoffeeStartedAtKey)
        defaults.set(session.endsAt, forKey: activeCoffeeEndsAtKey)
    }

    private static func removeActiveCoffeeSession() {
        defaults?.removeObject(forKey: activeCoffeeKey)
        defaults?.removeObject(forKey: activeCoffeeStartedAtKey)
        defaults?.removeObject(forKey: activeCoffeeEndsAtKey)
        reloadWidgets()
    }

    private static func archiveCompletedCoffee(_ session: IPhoneFocusSession) {
        guard let defaults else { return }

        let record = CoffeeActivityRecord(
            id: "ios:\(session.coffee.rawValue):\(session.startedAt.timeIntervalSinceReferenceDate)",
            coffee: session.coffee,
            startedAt: session.startedAt,
            completedAt: session.endsAt,
            focusedDuration: max(0, session.endsAt.timeIntervalSince(session.startedAt))
        )
        let updatedHistory = CoffeeActivityHistory.adding(
            record,
            to: loadCoffeeHistory()
        )
        guard let data = try? PropertyListEncoder().encode(updatedHistory) else { return }
        defaults.set(data, forKey: coffeeHistoryKey)
    }

    private static func applyCoffeeShield(
        _ coffee: CoffeeKind,
        using selection: FamilyActivitySelection
    ) {
        let store = coffeeStore(for: coffee)
        store.clearAllSettings()
        switch coffee.restrictionMode {
        case .none:
            break
        case .blockList:
            store.shield.applications = selection.applicationTokens
        case .allowList:
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
        }
    }

    private static func clearCoffeeRestriction(_ coffee: CoffeeKind) {
        coffeeStore(for: coffee).clearAllSettings()
    }

    private static func clearAllCoffeeRestrictions() {
        CoffeeKind.allCases.forEach(clearCoffeeRestriction)
    }

    private static func coffeeStore(for coffee: CoffeeKind) -> ManagedSettingsStore {
        switch coffee {
        case .latte: ManagedSettingsStore(named: .brewFocusLatte)
        case .cappuccino: ManagedSettingsStore(named: .brewFocusCappuccino)
        case .americano: ManagedSettingsStore(named: .brewFocusAmericano)
        case .espresso: ManagedSettingsStore(named: .brewFocusEspresso)
        }
    }

    private static func activeMorningEnd(at date: Date) -> Date? {
        MorningQuarantineSource.allCases
            .compactMap(loadMorningEndsAt(source:))
            .filter { $0 > date }
            .max()
    }

    private static func selectionKey(for coffee: CoffeeKind) -> String {
        coffee == .espresso
            ? legacyEspressoSelectionKey
            : "coffee.\(coffee.rawValue).selection"
    }

    private static func morningStore(for source: MorningQuarantineSource) -> ManagedSettingsStore {
        switch source {
        case .daily:
            ManagedSettingsStore(named: .brewFocusMorningDaily)
        case .shortcut:
            ManagedSettingsStore(named: .brewFocusMorningShortcut)
        }
    }

    private static func morningEndsAtKey(for source: MorningQuarantineSource) -> String {
        switch source {
        case .daily:
            morningDailyEndsAtKey
        case .shortcut:
            morningShortcutEndsAtKey
        }
    }

    private static func dateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension DeviceActivityName {
    static let brewFocusLatte = Self("brewfocus.coffee.latte")
    static let brewFocusCappuccino = Self("brewfocus.coffee.cappuccino")
    static let brewFocusAmericano = Self("brewfocus.coffee.americano")
    static let brewFocusEspresso = Self("brewfocus.espresso.prototype")
    static let brewFocusMorningDaily = Self("brewfocus.morning.daily")
    static let brewFocusMorningShortcut = Self("brewfocus.morning.shortcut")
}

extension ManagedSettingsStore.Name {
    static let brewFocusLatte = Self("brewfocus.coffee.latte")
    static let brewFocusCappuccino = Self("brewfocus.coffee.cappuccino")
    static let brewFocusAmericano = Self("brewfocus.coffee.americano")
    static let brewFocusEspresso = Self("brewfocus.espresso.prototype")
    static let brewFocusMorningDaily = Self("brewfocus.morning.daily")
    static let brewFocusMorningShortcut = Self("brewfocus.morning.shortcut")
}
