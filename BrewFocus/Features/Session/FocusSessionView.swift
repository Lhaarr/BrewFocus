import SwiftUI

struct FocusSessionView: View {
    @ObservedObject var manager: SessionManager

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(coffee.accentColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)

            VStack(spacing: 5) {
                Text(manager.remainingText)
                    .font(.system(size: 45, weight: .medium, design: .rounded).monospacedDigit())
                Text(isPaused ? "\(coffee.name) paused" : coffee.name)
                    .font(.headline)
                Text(applicationNames)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let blockedName = manager.lastBlockedApplicationName, isActive {
                Label("Not with this coffee: \(blockedName)", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(coffee.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        coffee.accentColor.opacity(0.09),
                        in: Capsule()
                    )
            }

            if let failure = manager.lastRestrictionFailure, isActive {
                Label(
                    "Couldn’t hide \(failure.name). Return to an allowed app manually.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            Text(sessionNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    if isPaused {
                        manager.resume()
                    } else {
                        manager.pause()
                    }
                } label: {
                    Label(
                        isPaused ? "Resume" : "Pause",
                        systemImage: isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button(role: .destructive) {
                    manager.abort()
                } label: {
                    Text("Abort")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(.vertical, 12)
    }

    private var session: FocusSession? {
        manager.currentSession
    }

    private var coffee: CoffeeKind {
        session?.coffee ?? .espresso
    }

    private var isPaused: Bool {
        session?.status == .paused
    }

    private var isActive: Bool {
        session?.status == .active
    }

    private var applicationNames: String {
        guard let session else { return "" }

        switch session.effectiveRestrictionMode {
        case .none:
            return "All apps stay available"
        case .blockList:
            return "Blocked: " + session.selectedApplications.map(\.name).joined(separator: " · ")
        case .allowList:
            return "Allowed: " + session.selectedApplications.map(\.name).joined(separator: " · ")
        }
    }

    private var sessionNote: String {
        guard let session else { return "" }

        if isPaused {
            return session.effectiveRestrictionMode == .none
                ? "Your timer is paused."
                : "App restrictions are lifted while this coffee is paused."
        }

        switch session.effectiveRestrictionMode {
        case .none:
            return "No apps are hidden during a Latte."
        case .blockList:
            return "Selected distractions are safely hidden, never terminated."
        case .allowList:
            return "Apps outside your selection are safely hidden, never terminated."
        }
    }
}
