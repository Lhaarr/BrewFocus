import FamilyControls
import Foundation
import ManagedSettings

struct FocusTagConfiguration: Codable {
    var state = FocusTagState()
    var selection = FamilyActivitySelection()
    var shortcutControlEnabled = false
    var lastShortcutToggleAt: Date?
    private(set) var longestBlockingDuration: TimeInterval = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case state, selection, shortcutControlEnabled, lastShortcutToggleAt, longestBlockingDuration
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        state = try values.decode(FocusTagState.self, forKey: .state)
        selection = try values.decode(FamilyActivitySelection.self, forKey: .selection)
        shortcutControlEnabled = try values.decodeIfPresent(Bool.self, forKey: .shortcutControlEnabled) ?? false
        lastShortcutToggleAt = try values.decodeIfPresent(Date.self, forKey: .lastShortcutToggleAt)
        let savedRecord = try values.decodeIfPresent(TimeInterval.self, forKey: .longestBlockingDuration) ?? 0
        longestBlockingDuration = savedRecord.isFinite ? max(0, savedRecord) : 0
    }

    mutating func recordBlock(startedAt: Date?, endedAt: Date) {
        guard let startedAt else { return }
        let duration = endedAt.timeIntervalSince(startedAt)
        guard duration.isFinite else { return }
        longestBlockingDuration = max(longestBlockingDuration, duration)
    }

    /// Returns false for a repeated invocation, including after an app relaunch.
    mutating func toggleFromShortcut(isAuthorized: Bool, now: Date = Date()) throws -> Bool {
        guard shortcutControlEnabled else { throw FocusTagError.shortcutsDisabled }
        if let lastShortcutToggleAt, abs(now.timeIntervalSince(lastShortcutToggleAt)) < 3 {
            return false
        }
        try state.toggleFromShortcut(isEnabled: shortcutControlEnabled,
                                     isAuthorized: isAuthorized,
                                     isSelectionValid: isSelectionValid, now: now)
        lastShortcutToggleAt = now
        return true
    }

    var isSelectionValid: Bool {
        Self.isValidSelection(applicationCount: selection.applicationTokens.count,
                              categoryCount: selection.categoryTokens.count,
                              websiteCount: selection.webDomainTokens.count)
    }

    static func isValidSelection(applicationCount: Int, categoryCount: Int, websiteCount: Int) -> Bool {
        (1...50).contains(applicationCount) && categoryCount == 0 && websiteCount == 0
    }
}

@MainActor
protocol FocusTagPersisting {
    func load() throws -> FocusTagConfiguration
    func save(_ configuration: FocusTagConfiguration) throws
}

@MainActor
final class FocusTagFileStore: FocusTagPersisting {
    private func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("focus-tag.plist")
    }

    func load() throws -> FocusTagConfiguration {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return FocusTagConfiguration()
        }
        return try PropertyListDecoder().decode(
            FocusTagConfiguration.self, from: Data(contentsOf: url)
        )
    }

    func save(_ configuration: FocusTagConfiguration) throws {
        try PropertyListEncoder().encode(configuration).write(
            to: fileURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

@MainActor
protocol FocusTagShielding {
    func apply(_ selection: FamilyActivitySelection)
    func clear()
}

@MainActor
final class FocusTagShield: FocusTagShielding {
    // Independent of coffee and Morning Quarantine; ending either cannot unlock the tag.
    private let store = ManagedSettingsStore(named: .init("brewfocus.focus-tag"))

    func apply(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens
    }

    func clear() { store.clearAllSettings() }
}
