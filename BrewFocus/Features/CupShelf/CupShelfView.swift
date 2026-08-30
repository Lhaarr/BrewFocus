import SwiftUI

struct CupShelfView: View {
    let sessions: [FocusSession]
    let goBack: () -> Void
    @State private var expandedSessionIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }

            BrewFocusHeader(
                eyebrow: "History",
                title: "Cup Shelf",
                subtitle: "A quiet record of work completed."
            )

            todaySummary

            CoffeeHeatmapView(records: coffeeActivityRecords)
                .warmCard()

            if sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cup.and.saucer")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Your first cup will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var coffeeActivityRecords: [CoffeeActivityRecord] {
        sessions.compactMap { session in
            guard session.status == .completed else { return nil }
            return CoffeeActivityRecord(
                id: "mac:\(session.id.uuidString)",
                coffee: session.coffee,
                startedAt: session.startedAt,
                completedAt: session.finishedAt
                    ?? session.startedAt.addingTimeInterval(session.plannedDuration),
                focusedDuration: session.focusedDuration
            )
        }
    }

    private var todaySessions: [FocusSession] {
        sessions.filter {
            Calendar.current.isDateInToday($0.finishedAt ?? $0.startedAt)
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TODAY")
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            if todaySessions.isEmpty {
                Text("No cups yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    ForEach(todaySessions.prefix(12)) { session in
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(session.coffee.accentColor)
                    }
                    if todaySessions.count > 12 {
                        Text("+\(todaySessions.count - 12)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let seconds = todaySessions.reduce(0) { $0 + $1.focusedDuration }
            Text("\(todaySessions.count) cups · \(DurationFormatting.shortDuration(seconds: seconds)) focused")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard()
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        let isExpanded = expandedSessionIDs.contains(session.id)

        return Button {
            if isExpanded {
                expandedSessionIDs.remove(session.id)
            } else {
                expandedSessionIDs.insert(session.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(session.coffee.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.coffee.name)
                            .font(.subheadline.weight(.medium))
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DurationFormatting.shortDuration(seconds: session.focusedDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.tertiary)
                }

                if isExpanded {
                    Divider()
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(applicationSummary(for: session))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .contentShape(Rectangle())
            .warmCard()
        }
        .buttonStyle(.plain)
    }

    private func applicationSummary(for session: FocusSession) -> String {
        let names = session.selectedApplications.map(\.name).joined(separator: " · ")

        switch session.effectiveRestrictionMode {
        case .none:
            return "No app restrictions"
        case .blockList:
            return "Blocked: \(names)"
        case .allowList:
            return "Allowed: \(names)"
        }
    }
}
