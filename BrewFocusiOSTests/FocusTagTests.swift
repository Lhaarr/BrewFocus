import CoreNFC
import FamilyControls
import SwiftUI
import UIKit
import XCTest
@testable import BrewFocusiOS

final class FocusTagCompatibilityTests: XCTestCase {
    private let identifier = Data([4, 10, 20, 30, 40, 50, 60])

    func testAcceptsUltralightAndUnspecifiedTypeATags() {
        XCTAssertTrue(FocusTagCompatibility.accepts(.ultralight, identifier: identifier))
        XCTAssertTrue(FocusTagCompatibility.accepts(.unknown, identifier: identifier))
    }

    func testRejectsOtherFamiliesAndEmptyIdentifiers() {
        XCTAssertFalse(FocusTagCompatibility.accepts(.plus, identifier: identifier))
        XCTAssertFalse(FocusTagCompatibility.accepts(.desfire, identifier: identifier))
        XCTAssertFalse(FocusTagCompatibility.accepts(.unknown, identifier: Data()))
        XCTAssertFalse(FocusTagCompatibility.accepts(.ultralight, identifier: Data()))
    }

    func testDiagnosticsDoNotClaimExactChipModel() {
        XCTAssertEqual(FocusTagCompatibility.name(of: .unknown), "ISO14443-A (unspecified family)")
        XCTAssertEqual(FocusTagCompatibility.name(of: .desfire), "MIFARE DESFire")
    }
}

final class FocusTagStateTests: XCTestCase {
    private let tag = Data([4, 10, 20, 30, 40, 50, 60])
    private let otherTag = Data([4, 10, 20, 30, 40, 50, 61])

    func testDurationLabelsUseHoursDaysAndWeeks() {
        XCTAssertEqual(FocusTagDuration.compact(59), "59s")
        XCTAssertEqual(FocusTagDuration.compact(90), "1m 30s")
        XCTAssertEqual(FocusTagDuration.compact(3660), "1h 1m")
        XCTAssertEqual(FocusTagDuration.compact(90060), "1d 1h 1m")
        XCTAssertEqual(FocusTagDuration.compact(604800 + 86400 + 7200), "1w 1d 2h")
        XCTAssertEqual(FocusTagDuration.compact(-10), "0s")
    }

    func testLongestBlockKeepsTheMaximumAcrossSerializationAndShorterSessions() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var config = FocusTagConfiguration()
        try config.state.pair(tag)
        config.recordBlock(startedAt: start, endedAt: start.addingTimeInterval(2 * 604800))
        var restored = try PropertyListDecoder().decode(FocusTagConfiguration.self,
                                                        from: PropertyListEncoder().encode(config))
        XCTAssertEqual(restored.longestBlockingDuration, 2 * 604800)
        restored.recordBlock(startedAt: start, endedAt: start.addingTimeInterval(3600))
        restored.recordBlock(startedAt: start, endedAt: start.addingTimeInterval(-100))
        XCTAssertEqual(restored.longestBlockingDuration, 2 * 604800)
        try restored.state.forget()
        XCTAssertEqual(restored.longestBlockingDuration, 2 * 604800)
    }

    func testExplicitUnlockNeverStartsAnAlreadyEndedSession() throws {
        var state = FocusTagState()
        try state.pair(tag)
        try state.start(isAuthorized: true, isSelectionValid: true)
        try state.unlock(scannedIdentifier: tag)
        XCTAssertFalse(state.isActive)
        try state.unlock(scannedIdentifier: tag)
        XCTAssertFalse(state.isActive)
        XCTAssertThrowsError(try state.unlock(scannedIdentifier: otherTag))
        try state.start(isAuthorized: true, isSelectionValid: true)
        XCTAssertThrowsError(try state.unlock(scannedIdentifier: otherTag))
        XCTAssertTrue(state.isActive)
    }

    func testStartInAppNeedsNoScanAndPairedTagStillTogglesBothWays() throws {
        var state = FocusTagState()
        try state.pair(tag)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(try state.start(isAuthorized: true, isSelectionValid: true, now: start))
        XCTAssertEqual(state.startedAt, start)
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: otherTag, isAuthorized: true, isSelectionValid: true))
        XCTAssertTrue(state.isActive)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        XCTAssertFalse(state.isActive)
        let nextStart = start.addingTimeInterval(7200)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true, now: nextStart)
        XCTAssertEqual(state.startedAt, nextStart)
    }

    func testRepeatedStartDoesNotUnlockOrResetTimerAfterReload() throws {
        var state = FocusTagState()
        try state.pair(tag)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try state.start(isAuthorized: true, isSelectionValid: true, now: start)
        var restored = try PropertyListDecoder().decode(FocusTagState.self,
                                                         from: PropertyListEncoder().encode(state))
        XCTAssertFalse(try restored.start(isAuthorized: true, isSelectionValid: true,
                                          now: start.addingTimeInterval(3600)))
        XCTAssertEqual(restored.startedAt, start)
        XCTAssertEqual(restored.elapsedTime(at: start.addingTimeInterval(3600)), 3600)
    }

    func testStartingWithoutScanStillRequiresCompletedSetup() throws {
        var state = FocusTagState()
        XCTAssertThrowsError(try state.start(isAuthorized: true, isSelectionValid: true))
        try state.pair(tag)
        XCTAssertThrowsError(try state.start(isAuthorized: false, isSelectionValid: true))
        XCTAssertThrowsError(try state.start(isAuthorized: true, isSelectionValid: false))
        XCTAssertFalse(state.isActive)
    }

    func testElapsedTimeCountsPastADayAndStopsWhenUnlocked() throws {
        var state = FocusTagState()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(state.elapsedTime(at: start), 0)
        try state.pair(tag)
        try state.start(isAuthorized: true, isSelectionValid: true, now: start)
        XCTAssertEqual(state.elapsedTime(at: start.addingTimeInterval(-10)), 0)
        XCTAssertEqual(state.elapsedTime(at: start.addingTimeInterval(90061)), 90061)
        state.unlock()
        XCTAssertEqual(state.elapsedTime(at: start.addingTimeInterval(90061)), 0)
    }

    func testShortcutRequiresOptInPairingAuthorizationAndSelection() throws {
        var state = FocusTagState()
        XCTAssertThrowsError(try state.toggleFromShortcut(isEnabled: true, isAuthorized: true, isSelectionValid: true))
        try state.pair(tag)
        XCTAssertThrowsError(try state.toggleFromShortcut(isEnabled: false, isAuthorized: true, isSelectionValid: true))
        XCTAssertThrowsError(try state.toggleFromShortcut(isEnabled: true, isAuthorized: false, isSelectionValid: true))
        XCTAssertThrowsError(try state.toggleFromShortcut(isEnabled: true, isAuthorized: true, isSelectionValid: false))
        XCTAssertFalse(state.isActive)
        try state.toggleFromShortcut(isEnabled: true, isAuthorized: true, isSelectionValid: true)
        XCTAssertTrue(state.isActive)
        // Disabling the action cannot be bypassed, even to unlock.
        XCTAssertThrowsError(try state.toggleFromShortcut(isEnabled: false, isAuthorized: true, isSelectionValid: true))
        XCTAssertTrue(state.isActive)
        try state.toggleFromShortcut(isEnabled: true, isAuthorized: false, isSelectionValid: false)
        XCTAssertFalse(state.isActive)
    }

    func testOlderConfigurationKeepsPairingButDoesNotEnableShortcuts() throws {
        var config = FocusTagConfiguration()
        try config.state.pair(tag)
        let data = try PropertyListEncoder().encode(config)
        var legacy = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        legacy.removeValue(forKey: "shortcutControlEnabled")
        legacy.removeValue(forKey: "lastShortcutToggleAt")
        legacy.removeValue(forKey: "longestBlockingDuration")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        let restored = try PropertyListDecoder().decode(FocusTagConfiguration.self, from: legacyData)
        XCTAssertEqual(restored.state.pairedIdentifier, tag)
        XCTAssertFalse(restored.shortcutControlEnabled)
        XCTAssertNil(restored.lastShortcutToggleAt)
        XCTAssertEqual(restored.longestBlockingDuration, 0)
    }

    func testShortcutDuplicateProtectionSurvivesReload() throws {
        var config = FocusTagConfiguration()
        try config.state.pair(tag)
        try config.state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        config.shortcutControlEnabled = true
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(try config.toggleFromShortcut(isAuthorized: true, now: now))
        XCTAssertFalse(config.state.isActive)
        var restored = try PropertyListDecoder().decode(FocusTagConfiguration.self,
                                                        from: PropertyListEncoder().encode(config))
        XCTAssertFalse(try restored.toggleFromShortcut(isAuthorized: true, now: now.addingTimeInterval(1)))
        XCTAssertFalse(restored.state.isActive)
        // After the cooldown the normal selection guard applies again.
        XCTAssertThrowsError(try restored.toggleFromShortcut(isAuthorized: true, now: now.addingTimeInterval(3)))
        XCTAssertEqual(restored.lastShortcutToggleAt, now)
    }

    func testAppSelectionRespectsShieldLimitAndRejectsCategoriesAndWebsites() {
        XCTAssertFalse(FocusTagConfiguration.isValidSelection(applicationCount: 0, categoryCount: 0, websiteCount: 0))
        XCTAssertTrue(FocusTagConfiguration.isValidSelection(applicationCount: 1, categoryCount: 0, websiteCount: 0))
        XCTAssertTrue(FocusTagConfiguration.isValidSelection(applicationCount: 50, categoryCount: 0, websiteCount: 0))
        XCTAssertFalse(FocusTagConfiguration.isValidSelection(applicationCount: 51, categoryCount: 0, websiteCount: 0))
        XCTAssertFalse(FocusTagConfiguration.isValidSelection(applicationCount: 2, categoryCount: 1, websiteCount: 0))
        XCTAssertFalse(FocusTagConfiguration.isValidSelection(applicationCount: 2, categoryCount: 0, websiteCount: 1))
    }

    func testPairingDoesNotStartBlocking() throws {
        var state = FocusTagState()
        try state.pair(tag)
        XCTAssertTrue(state.isPaired)
        XCTAssertFalse(state.isActive)
    }

    func testSameTagStartsThenUnlocksWithoutATimeLimit() throws {
        var state = FocusTagState()
        try state.pair(tag)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true, now: start)
        XCTAssertEqual(state.startedAt, start)
        // Even after a week, only a matching scan changes the state.
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true,
                         now: start.addingTimeInterval(7 * 86400))
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.isPaired)
    }

    func testWrongTagNeverStartsOrUnlocks() throws {
        var state = FocusTagState()
        try state.pair(tag)
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: otherTag, isAuthorized: true, isSelectionValid: true))
        XCTAssertFalse(state.isActive)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        let active = state
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: otherTag, isAuthorized: true, isSelectionValid: true))
        XCTAssertEqual(state, active)
    }

    func testPairingAndForgettingCannotChangeAnActiveSession() throws {
        var state = FocusTagState()
        try state.pair(tag)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        XCTAssertThrowsError(try state.pair(otherTag))
        XCTAssertThrowsError(try state.forget())
        XCTAssertEqual(state.pairedIdentifier, tag)
        XCTAssertTrue(state.isActive)
    }

    func testStartingRequiresAuthorizationPairingAndValidApps() throws {
        var state = FocusTagState()
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true))
        XCTAssertThrowsError(try state.pair(Data()))
        try state.pair(tag)
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: tag, isAuthorized: false, isSelectionValid: true))
        XCTAssertThrowsError(try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: false))
        XCTAssertFalse(state.isActive)
    }

    func testMatchingTagCanUnlockEvenIfSelectionOrAuthorizationIsLost() throws {
        var state = FocusTagState()
        try state.pair(tag)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        try state.toggle(scannedIdentifier: tag, isAuthorized: false, isSelectionValid: false)
        XCTAssertFalse(state.isActive)
    }

    func testActiveStateSurvivesRoundTripAndEmergencyUnlockKeepsPairing() throws {
        var state = FocusTagState()
        try state.pair(tag)
        try state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        let saved = try PropertyListEncoder().encode(state)
        var restored = try PropertyListDecoder().decode(FocusTagState.self, from: saved)
        XCTAssertEqual(restored, state)
        restored.unlock()
        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.pairedIdentifier, tag)
    }
}

@MainActor
final class FocusTagManagerTests: XCTestCase {
    private let tag = Data([4, 1, 2, 3, 4, 5, 6])

    func testExplicitUnlockReportsDurationAndDoesNotRestartOnRepeatedRead() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        repository.configuration.lastShortcutToggleAt = Date()
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        let start = try XCTUnwrap(manager.configuration.state.startedAt)
        try manager.unlock(scannedIdentifier: tag, now: start.addingTimeInterval(90))
        XCTAssertEqual(manager.lastCompletedDuration, 90)
        XCTAssertEqual(repository.configuration.longestBlockingDuration, 90)
        XCTAssertFalse(repository.configuration.state.isActive)
        try manager.unlock(scannedIdentifier: tag, now: start.addingTimeInterval(120))
        XCTAssertEqual(manager.lastCompletedDuration, 90)
        XCTAssertFalse(repository.configuration.state.isActive)
        XCTAssertEqual(shield.applies, 0)
        manager.clearCompletion()
        XCTAssertNil(manager.lastCompletedDuration)
    }

    func testFailedUnlockDoesNotClearShieldOrShowCompletion() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        repository.configuration.lastShortcutToggleAt = Date()
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        repository.failSave = true
        XCTAssertThrowsError(try manager.unlock(scannedIdentifier: tag))
        XCTAssertTrue(manager.configuration.state.isActive)
        XCTAssertNil(manager.lastCompletedDuration)
        XCTAssertEqual(shield.clears, 0)
        XCTAssertEqual(repository.configuration.longestBlockingDuration, 0)
    }

    func testShortcutCompletionUsesActualInvocationTime() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        let start = try XCTUnwrap(repository.configuration.state.startedAt)
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        XCTAssertTrue(try manager.toggleFromShortcut(isAuthorized: true, now: start.addingTimeInterval(75)))
        XCTAssertEqual(manager.lastCompletedDuration, 75)
        XCTAssertEqual(repository.configuration.longestBlockingDuration, 75)
    }

    func testRecordSurvivesReloadAndExplicitEmergencyUnlock() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        repository.configuration.lastShortcutToggleAt = Date()
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        let start = try XCTUnwrap(manager.configuration.state.startedAt)
        manager.emergencyUnlock(now: start.addingTimeInterval(9 * 86400))
        XCTAssertEqual(repository.configuration.longestBlockingDuration, 9 * 86400)
        let reloaded = FocusTagManager(persistence: repository, shield: TagTestShield())
        reloaded.refresh(isAuthorized: true)
        XCTAssertEqual(reloaded.configuration.longestBlockingDuration, 9 * 86400)
        XCTAssertFalse(reloaded.configuration.state.isActive)
    }

    func testRevokedAuthorizationDoesNotAwardUnverifiedElapsedTime() throws {
        let repository = try activeRepository()
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        manager.refresh(isAuthorized: false)
        XCTAssertEqual(repository.configuration.longestBlockingDuration, 0)
        XCTAssertFalse(repository.configuration.state.isActive)
    }

    func testRepeatedInAppStartPreservesPersistedStartAndDoesNotChangeShields() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        repository.configuration.lastShortcutToggleAt = Date()
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        let start = repository.configuration.state.startedAt
        try manager.start(isAuthorized: true, now: Date().addingTimeInterval(3600))
        XCTAssertEqual(manager.configuration.state.startedAt, start)
        XCTAssertEqual(repository.saves, 0)
        XCTAssertEqual(shield.clears, 0)
        XCTAssertEqual(shield.applies, 0)
    }

    func testInAppStartRejectsMissingAppsWithoutSavingOrBlocking() throws {
        let repository = TagTestStore()
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        try manager.pair(tag)
        let saves = repository.saves
        XCTAssertThrowsError(try manager.start(isAuthorized: true))
        XCTAssertFalse(manager.configuration.state.isActive)
        XCTAssertEqual(repository.saves, saves)
        XCTAssertEqual(shield.applies, 0)
    }

    func testTagUnlockAndEmergencyUnlockClearSessionTimer() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        repository.configuration.lastShortcutToggleAt = Date()
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        XCTAssertNotNil(manager.configuration.state.startedAt)
        try manager.toggle(scannedIdentifier: tag, isAuthorized: true)
        XCTAssertNil(manager.configuration.state.startedAt)
        manager.emergencyUnlock()
        XCTAssertNil(manager.configuration.state.startedAt)
    }

    func testShortcutReloadsSavedStateAndUnlocksWithoutASecondScan() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        XCTAssertTrue(try manager.toggleFromShortcut(isAuthorized: true))
        XCTAssertFalse(manager.configuration.state.isActive)
        XCTAssertFalse(repository.configuration.state.isActive)
        XCTAssertEqual(shield.clears, 1)
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        XCTAssertEqual(repository.saves, 1)
        XCTAssertEqual(shield.clears, 1)
    }

    func testShortcutReadOrWriteFailureCannotApplyOrRemoveShields() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        repository.failLoad = true
        XCTAssertThrowsError(try manager.toggleFromShortcut(isAuthorized: true))
        repository.failLoad = false
        repository.failSave = true
        XCTAssertThrowsError(try manager.toggleFromShortcut(isAuthorized: true))
        XCTAssertTrue(repository.configuration.state.isActive)
        XCTAssertEqual(shield.applies, 0)
        XCTAssertEqual(shield.clears, 0)
    }

    func testDisablingShortcutControlDoesNotUnlockActiveSession() throws {
        let repository = try activeRepository()
        repository.configuration.shortcutControlEnabled = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        // Load via a suppressed duplicate, preserving the active fixture without real tokens.
        repository.configuration.lastShortcutToggleAt = Date()
        XCTAssertFalse(try manager.toggleFromShortcut(isAuthorized: true))
        try manager.setShortcutControlEnabled(false)
        XCTAssertTrue(repository.configuration.state.isActive)
        XCTAssertFalse(repository.configuration.shortcutControlEnabled)
        XCTAssertThrowsError(try manager.toggleFromShortcut(isAuthorized: true))
        XCTAssertEqual(shield.clears, 0)
    }

    func testReplacingTagRevokesShortcutControl() throws {
        let repository = TagTestStore()
        repository.configuration.shortcutControlEnabled = true
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        manager.refresh(isAuthorized: true)
        try manager.pair(tag)
        XCTAssertFalse(repository.configuration.shortcutControlEnabled)
        XCTAssertNil(repository.configuration.lastShortcutToggleAt)
    }

    func testFailedPairingWriteDoesNotChangeConfigurationOrApplyShields() {
        let repository = TagTestStore()
        repository.failSave = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        XCTAssertThrowsError(try manager.pair(tag))
        XCTAssertFalse(manager.configuration.state.isPaired)
        XCTAssertEqual(shield.applies, 0)
    }

    func testCorruptStorageClearsOnlyTheTagShieldAndReportsRecovery() {
        let repository = TagTestStore()
        repository.failLoad = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        manager.refresh(isAuthorized: true)
        XCTAssertEqual(shield.clears, 1)
        XCTAssertEqual(shield.applies, 0)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testRevokedAuthorizationClearsAndPersistsInactiveState() throws {
        let repository = try activeRepository()
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        manager.refresh(isAuthorized: false)
        XCTAssertFalse(manager.configuration.state.isActive)
        XCTAssertFalse(repository.configuration.state.isActive)
        XCTAssertEqual(shield.applies, 0)
        XCTAssertEqual(shield.clears, 1)
    }

    func testEmergencyUnlockClearsShieldEvenWhenSavingFails() throws {
        let repository = try activeRepository()
        repository.failSave = true
        let shield = TagTestShield()
        let manager = FocusTagManager(persistence: repository, shield: shield)
        manager.refresh(isAuthorized: false)
        XCTAssertFalse(manager.configuration.state.isActive)
        XCTAssertEqual(shield.clears, 1)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.needsUnlockRetry)
        manager.errorMessage = nil
        XCTAssertTrue(manager.needsUnlockRetry)
        repository.failSave = false
        manager.emergencyUnlock()
        XCTAssertFalse(manager.needsUnlockRetry)
        XCTAssertFalse(repository.configuration.state.isActive)
    }

    func testEmptySelectionCannotReplaceASavedSetup() {
        let repository = TagTestStore()
        let manager = FocusTagManager(persistence: repository, shield: TagTestShield())
        XCTAssertThrowsError(try manager.saveSelection(FamilyActivitySelection()))
        XCTAssertEqual(repository.saves, 0)
    }

    private func activeRepository() throws -> TagTestStore {
        let repository = TagTestStore()
        try repository.configuration.state.pair(tag)
        try repository.configuration.state.toggle(scannedIdentifier: tag, isAuthorized: true, isSelectionValid: true)
        return repository
    }
}

@MainActor
private final class TagTestStore: FocusTagPersisting {
    var configuration = FocusTagConfiguration()
    var failLoad = false
    var failSave = false
    var saves = 0
    func load() throws -> FocusTagConfiguration {
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        return configuration
    }
    func save(_ configuration: FocusTagConfiguration) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        self.configuration = configuration
        saves += 1
    }
}

@MainActor
final class FocusTagHomeCardLayoutTests: XCTestCase {
    func testReadyAndActiveCardsFitANarrowIPhone() async throws {
        for active in [false, true] {
            for dark in [false, true] {
                try await renderCard(active: active, dark: dark, largeText: false)
            }
        }
    }

    func testLargeTextCanReflowWithoutClippingControls() async throws {
        try await renderCard(active: true, dark: true, largeText: true)
    }

    func testMultiweekClockFitsANarrowIPhone() async throws {
        try await renderCard(active: true, dark: true, largeText: false, duration: 16 * 86400 + 3661)
    }

    private func renderCard(active: Bool, dark: Bool, largeText: Bool, duration: TimeInterval = 23 * 60 + 14) async throws {
        let card = FocusTagHomeCard(
            startedAt: active ? Date().addingTimeInterval(-duration) : nil,
            applicationCount: 4, isReady: true, isScanning: false,
            shortcutControlEnabled: false, onStart: {}, onScan: {}, onSetup: {},
            isScanAvailable: true
        )
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
        let host = UIHostingController(rootView: card)
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let size = host.sizeThatFits(in: CGSize(width: 375, height: 2000))
        XCTAssertTrue(size.height.isFinite)
        // At default text size the complete primary task fits on a small screen.
        // At accessibility sizes it grows vertically inside the app's ScrollView.
        XCTAssertLessThan(size.height, largeText ? 1500 : 600)
        let previousWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKey() }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let name = "focus-\(active ? "active" : "ready")-\(dark ? "dark" : "light")\(largeText ? "-large-text" : "")\(duration >= 604800 ? "-weeks" : "")"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("png")
        try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)
        print("Focus layout capture: \(url.path)")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class TagTestShield: FocusTagShielding {
    var applies = 0
    var clears = 0
    func apply(_ selection: FamilyActivitySelection) { applies += 1 }
    func clear() { clears += 1 }
}
