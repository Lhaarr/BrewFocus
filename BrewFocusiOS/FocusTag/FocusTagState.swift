import Foundation

enum FocusTagDuration {
    static func compact(_ duration: TimeInterval) -> String {
        let seconds = duration.isFinite ? Int(max(0, min(duration, 1_000_000_000_000))) : 0
        let weeks = seconds / 604800
        let days = seconds / 86400 % 7
        let hours = seconds / 3600 % 24
        let minutes = seconds / 60 % 60
        if weeks > 0 { return "\(weeks)w \(days)d \(hours)h" }
        if seconds >= 86400 { return "\(seconds / 86400)d \(hours)h \(minutes)m" }
        if seconds >= 3600 { return "\(seconds / 3600)h \(minutes)m" }
        if seconds >= 60 { return "\(minutes)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}

enum FocusTagError: LocalizedError {
    case notPaired, wrongTag, active, invalidSelection, notAuthorized, invalidIdentifier
    case shortcutsDisabled

    var errorDescription: String? {
        switch self {
        case .notPaired: "Pair your Focus Tag first."
        case .wrongTag: "This is not your Focus Tag. Scan the tag you paired."
        case .active: "Unlock your Focus Tag session before changing its setup."
        case .invalidSelection: "Choose 1–50 individual apps. Remove categories and websites."
        case .notAuthorized: "Allow Screen Time access in BrewFocus first."
        case .invalidIdentifier: "The tag could not be identified. Try scanning it again."
        case .shortcutsDisabled: "Enable Allow Shortcut Control in BrewFocus → Focus Tag first."
        }
    }
}

/// A tag is a physical focus cue, not a cryptographic key: its UID can be copied.
struct FocusTagState: Codable, Equatable {
    private(set) var pairedIdentifier: Data?
    private(set) var startedAt: Date?

    var isActive: Bool { startedAt != nil }
    var isPaired: Bool { pairedIdentifier != nil }

    mutating func pair(_ identifier: Data) throws {
        guard !isActive else { throw FocusTagError.active }
        guard !identifier.isEmpty else { throw FocusTagError.invalidIdentifier }
        pairedIdentifier = identifier
    }

    mutating func toggle(
        scannedIdentifier: Data,
        isAuthorized: Bool,
        isSelectionValid: Bool,
        now: Date = Date()
    ) throws {
        guard let pairedIdentifier else { throw FocusTagError.notPaired }
        guard pairedIdentifier == scannedIdentifier else { throw FocusTagError.wrongTag }
        try changeBlocking(isAuthorized: isAuthorized, isSelectionValid: isSelectionValid, now: now)
    }

    /// Starting in the app never acts as a toggle or resets an existing session.
    @discardableResult
    mutating func start(isAuthorized: Bool, isSelectionValid: Bool, now: Date = Date()) throws -> Bool {
        guard !isActive else { return false }
        guard isPaired else { throw FocusTagError.notPaired }
        guard isAuthorized else { throw FocusTagError.notAuthorized }
        guard isSelectionValid else { throw FocusTagError.invalidSelection }
        startedAt = now
        return true
    }

    func elapsedTime(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    mutating func unlock(scannedIdentifier: Data) throws {
        guard let pairedIdentifier else { throw FocusTagError.notPaired }
        guard pairedIdentifier == scannedIdentifier else { throw FocusTagError.wrongTag }
        // An explicit unlock scan must never restart a session ended by Shortcuts.
        startedAt = nil
    }

    mutating func toggleFromShortcut(
        isEnabled: Bool,
        isAuthorized: Bool,
        isSelectionValid: Bool,
        now: Date = Date()
    ) throws {
        guard isEnabled else { throw FocusTagError.shortcutsDisabled }
        guard isPaired else { throw FocusTagError.notPaired }
        // Shortcuts does not supply a verified tag UID. Never pretend this is a scan.
        try changeBlocking(isAuthorized: isAuthorized, isSelectionValid: isSelectionValid, now: now)
    }

    private mutating func changeBlocking(isAuthorized: Bool, isSelectionValid: Bool, now: Date) throws {
        if isActive {
            startedAt = nil
        } else {
            try start(isAuthorized: isAuthorized, isSelectionValid: isSelectionValid, now: now)
        }
    }

    mutating func unlock() { startedAt = nil }

    mutating func forget() throws {
        guard !isActive else { throw FocusTagError.active }
        pairedIdentifier = nil
    }
}
