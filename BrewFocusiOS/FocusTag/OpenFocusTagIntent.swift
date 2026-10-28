import AppIntents
import FamilyControls
import Foundation
import UIKit

struct ToggleFocusTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Focus Tag"
    static let description = IntentDescription("Turns Focus Tag blocking on or off using your saved app choices. Enable Allow Shortcut Control in BrewFocus first. This action can unlock without scanning a tag.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = FocusTagManager.shared
        let changed = try manager.toggleFromShortcut(
            isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved
        )
        if !changed {
            return .result(dialog: "Repeated tap ignored. Wait three seconds between taps.")
        }
        if manager.configuration.state.isActive {
            return .result(dialog: "Focus Tag on. Selected apps are blocked.")
        }
        return .result(dialog: "Focus Tag off. Other coffee sessions may still block apps.")
    }
}

struct OpenFocusTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Focus Tag"
    static let description = IntentDescription("Opens BrewFocus’s physical tag scanner. Scan your paired NFC tag in the app to block or unblock selected apps.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "brewfocus://focus-tag")!)
        return .result()
    }
}
