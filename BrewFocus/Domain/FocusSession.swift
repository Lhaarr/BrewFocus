import Foundation

enum FocusSessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case aborted
}

struct FocusSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let coffee: CoffeeKind
    let startedAt: Date
    let plannedDuration: TimeInterval
    var scheduledEndAt: Date?
    var pausedRemaining: TimeInterval?
    var finishedAt: Date?
    var status: FocusSessionStatus
    let allowedApplications: [AllowedApplication]
    let blockedApplications: [AllowedApplication]?
    let restrictionMode: ApplicationRestrictionMode?
    var hiddenBundleIdentifiers: Set<String>

    init(
        id: UUID = UUID(),
        coffee: CoffeeKind = .espresso,
        startedAt: Date,
        plannedDuration: TimeInterval,
        scheduledEndAt: Date,
        selectedApplications: [AllowedApplication]
    ) {
        self.id = id
        self.coffee = coffee
        self.startedAt = startedAt
        self.plannedDuration = plannedDuration
        self.scheduledEndAt = scheduledEndAt
        self.pausedRemaining = nil
        self.finishedAt = nil
        self.status = .active
        self.allowedApplications = coffee.restrictionMode == .allowList
            ? selectedApplications
            : []
        self.blockedApplications = coffee.restrictionMode == .blockList
            ? selectedApplications
            : nil
        self.restrictionMode = coffee.restrictionMode
        self.hiddenBundleIdentifiers = []
    }

    var effectiveRestrictionMode: ApplicationRestrictionMode {
        // Snapshots from the Espresso-only prototype predate this field.
        restrictionMode ?? .allowList
    }

    var selectedApplications: [AllowedApplication] {
        switch effectiveRestrictionMode {
        case .none:
            []
        case .blockList:
            blockedApplications ?? []
        case .allowList:
            allowedApplications
        }
    }

    var applicationRestriction: ApplicationRestriction {
        ApplicationRestriction(
            mode: effectiveRestrictionMode,
            bundleIdentifiers: Set(selectedApplications.map(\.bundleIdentifier))
        )
    }

    var focusedDuration: TimeInterval {
        switch status {
        case .completed:
            plannedDuration
        case .aborted:
            max(0, (finishedAt ?? startedAt).timeIntervalSince(startedAt))
        case .active, .paused:
            0
        }
    }
}

struct FocusSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var currentSession: FocusSession?
    var history: [FocusSession]

    init(
        version: Int = FocusSnapshot.currentVersion,
        currentSession: FocusSession? = nil,
        history: [FocusSession] = []
    ) {
        self.version = version
        self.currentSession = currentSession
        self.history = history
    }
}
