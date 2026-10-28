import AppIntents
import DeviceActivity
import FamilyControls
import Foundation

struct StartMorningQuarantineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Morning Quarantine"
    static let description = IntentDescription(
        "Shields distracting apps for one hour using the exceptions saved in BrewFocus."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            return .result(
                dialog: "Open BrewFocus and allow Screen Time access before running this action."
            )
        }

        guard
            ScreenTimeShared.isMorningPrepared,
            ScreenTimeShared.isValidMorningSelection(
                ScreenTimeShared.loadMorningSelection()
            )
        else {
            return .result(
                dialog: "Open BrewFocus and save your Morning Quarantine app exceptions first."
            )
        }

        do {
            _ = try ScreenTimeShared.startOneHourMorningQuarantine()
            return .result(dialog: "Morning Quarantine started for one hour.")
        } catch {
            return .result(
                dialog: "BrewFocus couldn’t start Morning Quarantine. Open the app and try again."
            )
        }
    }
}

struct BrewFocusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleFocusTagIntent(),
            phrases: ["Toggle Focus Tag in \(.applicationName)"],
            shortTitle: "Toggle Focus Tag",
            systemImageName: "power"
        )
        AppShortcut(
            intent: OpenFocusTagIntent(),
            phrases: ["Open Focus Tag in \(.applicationName)"],
            shortTitle: "Focus Tag",
            systemImageName: "wave.3.right"
        )
        AppShortcut(
            intent: StartQuickCoffeeIntent(),
            phrases: [
                "Start Quick Coffee with \(.applicationName)",
                "Order my coffee with \(.applicationName)"
            ],
            shortTitle: "Quick Coffee",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: StartMorningQuarantineIntent(),
            phrases: [
                "Start Morning Quarantine with \(.applicationName)",
                "Start my focus hour with \(.applicationName)"
            ],
            shortTitle: "Morning Quarantine",
            systemImageName: "sunrise.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .orange
    }
}
