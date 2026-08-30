import SwiftUI

@main
@MainActor
struct BrewFocusApp: App {
    @StateObject private var manager: SessionManager

    init() {
        let manager = SessionManager.live()
        manager.bootstrap()
        _manager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(manager: manager)
        } label: {
            if manager.currentSession != nil {
                Label(manager.remainingText, systemImage: "cup.and.saucer.fill")
            } else {
                Label("BrewFocus", systemImage: "cup.and.saucer")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
