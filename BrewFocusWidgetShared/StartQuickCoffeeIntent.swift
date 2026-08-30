import AppIntents
import DeviceActivity
import FamilyControls
import Foundation

struct StartQuickCoffeeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Quick Coffee"
    static let description = IntentDescription(
        "Starts the coffee recipe saved as Quick Coffee in BrewFocus."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            return .result(
                dialog: "Open BrewFocus and allow Screen Time access before starting Quick Coffee."
            )
        }

        do {
            let session = try ScreenTimeShared.startQuickCoffee()
            return .result(
                dialog: "\(session.coffee.name) started for \(Int(session.coffee.duration / 60)) minutes."
            )
        } catch ScreenTimeSharedError.coffeeAlreadyActive {
            return .result(dialog: "Your coffee is already running.")
        } catch {
            return .result(dialog: "\(error.localizedDescription)")
        }
    }
}
