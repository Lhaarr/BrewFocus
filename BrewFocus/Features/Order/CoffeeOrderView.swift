import AppKit
import SwiftUI

struct CoffeeOrderView: View {
    @ObservedObject var manager: SessionManager
    let coffee: CoffeeKind
    let goBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                if coffee.restrictionMode != .none {
                    Text(selectionCountText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            BrewFocusHeader(
                eyebrow: coffee.name,
                title: orderTitle,
                subtitle: orderSubtitle,
                accent: coffee.accentColor
            )

            if coffee.restrictionMode == .none {
                latteExplanation
            } else if manager.availableApplications.isEmpty {
                emptyApplications
            } else {
                applicationList
            }

            HStack {
                if coffee.restrictionMode != .none {
                    Button {
                        manager.refreshApplications()
                    } label: {
                        Label("Refresh apps", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    DurationFormatting.shortDuration(seconds: coffee.duration),
                    systemImage: "timer"
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                manager.start(coffee)
            } label: {
                Label(actionTitle, systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle(accent: coffee.accentColor))
            .disabled(!manager.canStart(coffee))
            .opacity(manager.canStart(coffee) ? 1 : 0.45)
        }
        .onAppear {
            manager.refreshApplications()
        }
    }

    private var applicationList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(manager.availableApplications) { application in
                    applicationRow(application)
                }
            }
        }
        .frame(height: 230)
    }

    private var latteExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A gentle start", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(coffee.accentColor)
            Text("All apps stay available. BrewFocus simply keeps a calm 25-minute session within reach.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard()
    }

    private var emptyApplications: some View {
        VStack(spacing: 10) {
            Image(systemName: "macwindow.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No running apps found")
                .font(.headline)
            Text("Open the apps you need, then refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func applicationRow(_ application: AllowedApplication) -> some View {
        let isSelected = manager.selectedBundleIdentifiers.contains(application.bundleIdentifier)

        return Button {
            manager.toggleSelection(for: application, coffee: coffee)
        } label: {
            HStack(spacing: 11) {
                ApplicationIconView(application: application)
                Text(application.name)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        isSelected
                            ? coffee.accentColor
                            : Color.secondary.opacity(0.35)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? coffee.accentColor.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectionCountText: String {
        "\(manager.selectedBundleIdentifiers.count)/\(coffee.applicationSelectionRange.upperBound) apps selected"
    }

    private var orderTitle: String {
        switch coffee.restrictionMode {
        case .none: "Ready for a lighter session?"
        case .blockList: "What should stay out?"
        case .allowList: "What do you need for this session?"
        }
    }

    private var orderSubtitle: String {
        switch coffee {
        case .latte:
            "Keep access to everything and build a little momentum."
        case .cappuccino:
            "Choose one to four running apps that tend to pull you away."
        case .americano:
            "Choose up to eight running apps. Everything else steps aside."
        case .espresso:
            "Choose one to four running apps. Everything else steps aside."
        }
    }

    private var actionTitle: String {
        switch coffee {
        case .latte: "Pour the Latte"
        case .cappuccino: "Make the Cappuccino"
        case .americano: "Brew the Americano"
        case .espresso: "Pull the shot"
        }
    }
}

private struct ApplicationIconView: View {
    let application: AllowedApplication

    var body: some View {
        Group {
            if let path = application.bundleURLPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
