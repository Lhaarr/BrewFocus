import AppKit
import SwiftUI

struct CoffeeMenuView: View {
    @ObservedObject var manager: SessionManager
    let orderCoffee: (CoffeeKind) -> Void
    let openCupShelf: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrewFocusHeader(
                eyebrow: "BrewFocus",
                title: "What can I get you?",
                subtitle: "Choose the focus you need right now."
            )

            if let completed = manager.lastCompletedSession {
                completionCard(completed)
            }

            VStack(spacing: 8) {
                ForEach(CoffeeKind.allCases) { coffee in
                    coffeeButton(coffee)
                }
            }

            Text("Each coffee changes the app guard. BrewFocus safely hides apps where requested; it never terminates them or creates an unbreakable lock.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button(action: openCupShelf) {
                    Label(
                        "Cup Shelf (\(manager.completedSessions.count))",
                        systemImage: "square.grid.2x2"
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private func completionCard(_ session: FocusSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.coffee.name) finished.")
                    .font(.headline)
                Text("\(DurationFormatting.shortDuration(seconds: session.focusedDuration)) focused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                manager.clearCompletion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss completion")
        }
        .padding(12)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func coffeeButton(_ coffee: CoffeeKind) -> some View {
        Button {
            orderCoffee(coffee)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(coffee.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(coffee.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(coffee.name)
                        .font(.headline)
                    Text("\(coffee.focusLabel) · \(DurationFormatting.shortDuration(seconds: coffee.duration))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(menuRule(for: coffee))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .warmCard()
        }
        .buttonStyle(.plain)
    }

    private func menuRule(for coffee: CoffeeKind) -> String {
        switch coffee {
        case .latte: "All apps stay available"
        case .cappuccino: "Block up to 4 distractions"
        case .americano: "Keep up to 8 essential apps"
        case .espresso: "Keep no more than 4 apps"
        }
    }
}
