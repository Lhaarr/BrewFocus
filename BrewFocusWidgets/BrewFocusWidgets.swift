import AppIntents
import SwiftUI
import WidgetKit

private enum BrewFocusWidgetURL {
    static let quickStart = URL(string: "brewfocus://quick-start")!
    static let app = URL(string: "brewfocus://status")!
}

struct BrewFocusWidgetEntry: TimelineEntry {
    let date: Date
    let state: BrewFocusWidgetState
}

struct BrewFocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrewFocusWidgetEntry {
        let now = Date()
        return BrewFocusWidgetEntry(
            date: now,
            state: BrewFocusWidgetState(
                activeMode: .coffee(.espresso),
                startedAt: now,
                endsAt: now.addingTimeInterval(18 * 60),
                quickCoffee: .espresso,
                isQuickCoffeeReady: true
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (BrewFocusWidgetEntry) -> Void
    ) {
        let now = Date()
        completion(BrewFocusWidgetEntry(date: now, state: ScreenTimeShared.widgetState(at: now)))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<BrewFocusWidgetEntry>) -> Void
    ) {
        let now = Date()
        let state = ScreenTimeShared.widgetState(at: now)
        var entries = [BrewFocusWidgetEntry(date: now, state: state)]

        if let endsAt = state.endsAt, endsAt > now {
            let afterEnd = endsAt.addingTimeInterval(1)
            entries.append(
                BrewFocusWidgetEntry(
                    date: afterEnd,
                    state: ScreenTimeShared.widgetState(at: afterEnd)
                )
            )
            completion(Timeline(entries: entries, policy: .after(afterEnd)))
        } else {
            completion(
                Timeline(
                    entries: entries,
                    policy: .after(now.addingTimeInterval(15 * 60))
                )
            )
        }
    }
}

struct BrewFocusStatusWidget: Widget {
    static let kind = "BrewFocusStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BrewFocusWidgetProvider()) { entry in
            BrewFocusWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Coffee Status")
        .description("See the current coffee or start your saved Quick Coffee.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

private struct BrewFocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BrewFocusWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineContent
            case .accessoryCircular:
                circularContent
            case .accessoryRectangular:
                rectangularContent
            default:
                rectangularContent
            }
        }
        .widgetURL(entry.state.activeMode == nil ? idleURL : BrewFocusWidgetURL.app)
    }

    @ViewBuilder
    private var inlineContent: some View {
        if let title = entry.state.activeTitle, let endsAt = entry.state.endsAt {
            Label {
                Text("\(title) · ") + Text(timerInterval: entry.date...endsAt, countsDown: true)
            } icon: {
                Image(systemName: entry.state.activeSymbolName)
            }
        } else if let coffee = entry.state.quickCoffee, entry.state.isQuickCoffeeReady {
            Label("Start \(coffee.name)", systemImage: "cup.and.saucer.fill")
        } else {
            Label("Set Quick Coffee", systemImage: "cup.and.saucer")
        }
    }

    @ViewBuilder
    private var circularContent: some View {
        if let endsAt = entry.state.endsAt, entry.state.activeMode != nil {
            VStack(alignment: .center, spacing: 1) {
                Image(systemName: entry.state.activeSymbolName)
                    .font(.body.weight(.semibold))
                    .imageScale(.small)
                    .frame(width: 48, alignment: .center)
                Text(timerInterval: entry.date...endsAt, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.center)
                    .frame(width: 48, alignment: .center)
            }
            .frame(width: 48, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(entry.state.activeTitle ?? "BrewFocus")
        } else if entry.state.isQuickCoffeeReady {
            Button(intent: StartQuickCoffeeIntent()) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quickStartLabel)
        } else {
            Image(systemName: "cup.and.saucer")
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("Set Quick Coffee in BrewFocus")
        }
    }

    @ViewBuilder
    private var rectangularContent: some View {
        if let title = entry.state.activeTitle, let endsAt = entry.state.endsAt {
            VStack(spacing: 1) {
                compactCoffeeLabel(title, symbolName: entry.state.activeSymbolName)
                Text(timerInterval: entry.date...endsAt, countsDown: true)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
        } else if let coffee = entry.state.quickCoffee, entry.state.isQuickCoffeeReady {
            Button(intent: StartQuickCoffeeIntent()) {
                VStack(spacing: 1) {
                    compactCoffeeLabel(coffee.name, symbolName: "cup.and.saucer.fill")
                    Text("Start · \(Int(coffee.duration / 60)) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quickStartLabel)
        } else {
            VStack(spacing: 1) {
                compactCoffeeLabel("Quick Coffee", symbolName: "cup.and.saucer")
                Text("Set up in BrewFocus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func compactCoffeeLabel(_ title: String, symbolName: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .imageScale(.small)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var idleURL: URL {
        entry.state.isQuickCoffeeReady ? BrewFocusWidgetURL.quickStart : BrewFocusWidgetURL.app
    }

    private var quickStartLabel: String {
        "Start \(entry.state.quickCoffee?.name ?? "Quick Coffee")"
    }
}

@available(iOS 18.0, *)
struct BrewFocusQuickCoffeeControl: ControlWidget {
    static let kind = "BrewFocusQuickCoffeeControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartQuickCoffeeIntent()) {
                Label("Quick Coffee", systemImage: "cup.and.saucer.fill")
            }
        }
        .displayName("Quick Coffee")
        .description("Start your saved BrewFocus coffee from the Lock Screen or Control Center.")
    }
}

@main
struct BrewFocusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BrewFocusStatusWidget()
        if #available(iOS 18.0, *) {
            BrewFocusQuickCoffeeControl()
        }
    }
}
