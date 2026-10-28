import FamilyControls
import Foundation

@MainActor
final class FocusTagManager: ObservableObject {
    // The intent is in the main app target; UI and background actions share one owner.
    static let shared = FocusTagManager()
    @Published private(set) var configuration = FocusTagConfiguration()
    @Published private(set) var isAuthorized = false
    @Published private(set) var needsUnlockRetry = false
    @Published var errorMessage: String?
    @Published private(set) var lastCompletedDuration: TimeInterval?

    private let persistence: FocusTagPersisting
    private let shield: FocusTagShielding
    private var hasLoaded = false

    init(persistence: FocusTagPersisting, shield: FocusTagShielding) {
        self.persistence = persistence
        self.shield = shield
    }

    convenience init() {
        self.init(persistence: FocusTagFileStore(), shield: FocusTagShield())
    }

    func refresh(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        if !hasLoaded {
            hasLoaded = true
            do {
                configuration = try persistence.load()
            } catch {
                shield.clear()
                errorMessage = "The saved Focus Tag setup couldn’t be read. Its restrictions were removed. Set it up again."
                return
            }
        }

        if configuration.state.isActive {
            if isAuthorized && configuration.isSelectionValid && configuration.state.isPaired {
                shield.apply(configuration.selection)
                var updated = configuration
                updated.recordBlock(startedAt: updated.state.startedAt, endedAt: Date())
                if updated.longestBlockingDuration > configuration.longestBlockingDuration {
                    do { try save(updated) }
                    catch { errorMessage = "Focus is still on, but your latest personal best couldn’t be saved. Try reopening BrewFocus later." }
                }
            } else {
                emergencyUnlock(recordDuration: false)
            }
        } else {
            shield.clear()
        }
    }

    func saveSelection(_ selection: FamilyActivitySelection) throws {
        guard !configuration.state.isActive else { throw FocusTagError.active }
        var updated = configuration
        updated.selection = selection
        guard updated.isSelectionValid else { throw FocusTagError.invalidSelection }
        try save(updated)
    }

    func pair(_ identifier: Data) throws {
        var updated = configuration
        try updated.state.pair(identifier)
        updated.shortcutControlEnabled = false
        updated.lastShortcutToggleAt = nil
        try save(updated)
    }

    func start(isAuthorized: Bool, now: Date = Date()) throws {
        var updated = configuration
        guard try updated.state.start(isAuthorized: isAuthorized,
                                      isSelectionValid: updated.isSelectionValid, now: now) else { return }
        // Starting in-app is a distinct action; a subsequent tag tap must unlock,
        // even when a Shortcut was used just before it.
        updated.lastShortcutToggleAt = nil
        try save(updated)
        self.isAuthorized = isAuthorized
        lastCompletedDuration = nil
        shield.apply(updated.selection)
    }

    func unlock(scannedIdentifier: Data, now: Date = Date()) throws {
        var updated = configuration
        let startedAt = updated.state.startedAt
        try updated.state.unlock(scannedIdentifier: scannedIdentifier)
        updated.recordBlock(startedAt: startedAt, endedAt: now)
        try save(updated)
        shield.clear()
        recordCompletion(startedAt: startedAt, endedAt: now)
    }

    func clearCompletion() { lastCompletedDuration = nil }

    func setShortcutControlEnabled(_ enabled: Bool) throws {
        var updated = configuration
        if enabled {
            guard updated.state.isPaired else { throw FocusTagError.notPaired }
            guard isAuthorized else { throw FocusTagError.notAuthorized }
            guard updated.isSelectionValid else { throw FocusTagError.invalidSelection }
        }
        updated.shortcutControlEnabled = enabled
        try save(updated)
    }

    /// Reload before acting: never toggle from stale UI state or unreadable storage.
    @discardableResult
    func toggleFromShortcut(isAuthorized: Bool, now: Date = Date()) throws -> Bool {
        var updated = try persistence.load()
        let previousStart = updated.state.startedAt
        let changed = try updated.toggleFromShortcut(isAuthorized: isAuthorized, now: now)
        if changed && !updated.state.isActive {
            updated.recordBlock(startedAt: previousStart, endedAt: now)
        }
        if changed { try save(updated) }
        else { configuration = updated }
        hasLoaded = true
        self.isAuthorized = isAuthorized
        if changed {
            if updated.state.isActive { shield.apply(updated.selection) }
            else { shield.clear() }
            recordCompletion(startedAt: previousStart, endedAt: now)
        }
        return changed
    }

    func toggle(scannedIdentifier: Data, isAuthorized: Bool, now: Date = Date()) throws {
        var updated = configuration
        let previousStart = updated.state.startedAt
        try updated.state.toggle(
            scannedIdentifier: scannedIdentifier,
            isAuthorized: isAuthorized,
            isSelectionValid: updated.isSelectionValid,
            now: now
        )
        if !updated.state.isActive { updated.recordBlock(startedAt: previousStart, endedAt: now) }
        // Commit before applying restrictions, so a failed write can never create a lost lock.
        try save(updated)
        if updated.state.isActive {
            shield.apply(updated.selection)
        } else {
            shield.clear()
        }
        recordCompletion(startedAt: previousStart, endedAt: now)
    }

    func emergencyUnlock(recordDuration: Bool = true, now: Date = Date()) {
        shield.clear()
        if recordDuration { configuration.recordBlock(startedAt: configuration.state.startedAt, endedAt: now) }
        configuration.state.unlock()
        do {
            try persistence.save(configuration)
            needsUnlockRetry = false
            errorMessage = nil
        } catch {
            needsUnlockRetry = true
            errorMessage = "Apps are unlocked now, but the change couldn’t be saved. Keep BrewFocus open and try again before relaunching."
        }
    }

    func forget() throws {
        var updated = configuration
        try updated.state.forget()
        updated.shortcutControlEnabled = false
        updated.lastShortcutToggleAt = nil
        try save(updated)
        shield.clear()
    }

    private func save(_ updated: FocusTagConfiguration) throws {
        try persistence.save(updated)
        configuration = updated
        needsUnlockRetry = false
        errorMessage = nil
    }

    private func recordCompletion(startedAt: Date?, endedAt: Date) {
        if let startedAt, !configuration.state.isActive {
            lastCompletedDuration = max(0, endedAt.timeIntervalSince(startedAt))
        } else if configuration.state.isActive {
            lastCompletedDuration = nil
        }
    }
}
