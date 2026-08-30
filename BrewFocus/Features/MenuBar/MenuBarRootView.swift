import AppKit
import SwiftUI

struct MenuBarRootView: View {
    private enum Route {
        case coffeeMenu
        case order
        case cupShelf
    }

    @ObservedObject var manager: SessionManager
    @State private var route: Route = .coffeeMenu
    @State private var orderedCoffee: CoffeeKind = .espresso
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if manager.currentSession != nil {
                    FocusSessionView(manager: manager)
                } else if !hasCompletedOnboarding {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                } else {
                    switch route {
                    case .coffeeMenu:
                        CoffeeMenuView(
                            manager: manager,
                            orderCoffee: { coffee in
                                orderedCoffee = coffee
                                manager.prepareOrder(for: coffee)
                                route = .order
                            },
                            openCupShelf: { route = .cupShelf }
                        )
                    case .order:
                        CoffeeOrderView(
                            manager: manager,
                            coffee: orderedCoffee,
                            goBack: { route = .coffeeMenu }
                        )
                    case .cupShelf:
                        CupShelfView(
                            sessions: manager.completedSessions,
                            goBack: { route = .coffeeMenu }
                        )
                    }
                }
            }
            .padding(18)

            if let error = manager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button {
                        manager.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.1))
            }
        }
        .frame(width: 390)
        .onChange(of: manager.currentSession?.id) { _, sessionID in
            if sessionID == nil {
                route = .coffeeMenu
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didLaunchApplicationNotification
            )
        ) { _ in
            if manager.currentSession == nil {
                manager.refreshApplications()
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didTerminateApplicationNotification
            )
        ) { _ in
            if manager.currentSession == nil {
                manager.refreshApplications()
            }
        }
    }
}
