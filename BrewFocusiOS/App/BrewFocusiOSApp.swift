import SwiftUI

@main
struct BrewFocusiOSApp: App {
    @StateObject private var manager = IPhoneFocusManager()

    init() {
        BrewFocusAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            IPhoneRootView(manager: manager)
        }
    }
}
