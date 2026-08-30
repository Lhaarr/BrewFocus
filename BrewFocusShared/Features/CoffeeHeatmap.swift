import Foundation
import SwiftUI

struct CoffeeActivityRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let coffee: CoffeeKind
    let startedAt: Date
    let completedAt: Date
    let focusedDuration: TimeInterval
}

enum CoffeeActivityHistory {
    static let maximumRecordCount = 2_000

    static func adding(
        _ record: CoffeeActivityRecord,
        to records: [CoffeeActivityRecord]
    ) -> [CoffeeActivityRecord] {
        var recordsByID: [String: CoffeeActivityRecord] = [:]
        for existingRecord in records {
            if let savedRecord = recordsByID[existingRecord.id],
               savedRecord.completedAt >= existingRecord.completedAt {
                continue
            }
            recordsByID[existingRecord.id] = existingRecord
        }
        recordsByID[record.id] = record
        return recordsByID.values
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(maximumRecordCount)
            .map { $0 }
    }
}

extension CoffeeKind {
    var focusWeight: Int {
        switch self {
        case .latte: 1
        case .cappuccino: 2
        case .americano: 3
        case .espresso: 4
        }
    }
}

struct CoffeeHeatmapDay: Identifiable, Equatable {
    let date: Date
    let sessionCount: Int
    let focusScore: Int
    let focusedDuration: TimeInterval
    let isFuture: Bool

    var id: Date { date }

    var intensity: Int {
        switch focusScore {
        case 0: 0
        case 1: 1
        case 2...3: 2
        case 4...6: 3
        default: 4
        }
    }
}

struct CoffeeHeatmapWeek: Identifiable, Equatable {
    let startDate: Date
    let monthLabel: String?
    let days: [CoffeeHeatmapDay]

    var id: Date { startDate }
}

struct CoffeeHeatmap: Equatable {
    let weeks: [CoffeeHeatmapWeek]
    let sessionCount: Int
    let focusedDuration: TimeInterval

    init(
        records: [CoffeeActivityRecord],
        referenceDate: Date = Date(),
        weekCount: Int = 16,
        calendar sourceCalendar: Calendar = .current
    ) {
        let calendar = sourceCalendar

        let safeWeekCount = max(1, weekCount)
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -daysSinceWeekStart,
            to: today
        ) ?? today
        let firstWeekStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(safeWeekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart

        let recordsByDay = Dictionary(grouping: records) {
            calendar.startOfDay(for: $0.completedAt)
        }

        var generatedWeeks: [CoffeeHeatmapWeek] = []
        for weekIndex in 0..<safeWeekCount {
            let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekIndex,
                to: firstWeekStart
            ) ?? firstWeekStart

            let days = (0..<7).map { dayIndex in
                let date = calendar.date(
                    byAdding: .day,
                    value: dayIndex,
                    to: weekStart
                ) ?? weekStart
                let dayRecords = recordsByDay[date] ?? []
                return CoffeeHeatmapDay(
                    date: date,
                    sessionCount: dayRecords.count,
                    focusScore: dayRecords.reduce(0) { $0 + $1.coffee.focusWeight },
                    focusedDuration: dayRecords.reduce(0) { $0 + $1.focusedDuration },
                    isFuture: date > today
                )
            }

            let monthStart = days.first { calendar.component(.day, from: $0.date) == 1 }
            let monthDate = weekIndex == 0 ? days.first?.date : monthStart?.date
            generatedWeeks.append(
                CoffeeHeatmapWeek(
                    startDate: weekStart,
                    monthLabel: monthDate.map {
                        $0.formatted(
                            Date.FormatStyle()
                                .month(.abbreviated)
                                .locale(calendar.locale ?? .current)
                        )
                    },
                    days: days
                )
            )
        }

        let visibleStart = firstWeekStart
        let visibleRecords = records.filter {
            let completedDay = calendar.startOfDay(for: $0.completedAt)
            return completedDay >= visibleStart && completedDay <= today
        }
        weeks = generatedWeeks
        sessionCount = visibleRecords.count
        focusedDuration = visibleRecords.reduce(0) { $0 + $1.focusedDuration }
    }
}

struct CoffeeHeatmapView: View {
    @Environment(\.colorScheme) private var colorScheme

    let records: [CoffeeActivityRecord]
    let referenceDate: Date
    let calendar: Calendar
    let weekCount: Int

    init(
        records: [CoffeeActivityRecord],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        weekCount: Int = 16
    ) {
        self.records = records
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.weekCount = weekCount
    }

    private var heatmap: CoffeeHeatmap {
        CoffeeHeatmap(
            records: records,
            referenceDate: referenceDate,
            weekCount: weekCount,
            calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COFFEE RHYTHM")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(weekCount) WEEKS")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { proxy in
                let spacing: CGFloat = 4
                let availableWidth = max(1, proxy.size.width - spacing * CGFloat(weekCount - 1))
                let cellSize = min(14, floor(availableWidth / CGFloat(weekCount)))

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(heatmap.weeks) { week in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(week.monthLabel ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(width: cellSize, height: 14, alignment: .leading)

                            VStack(spacing: spacing) {
                                ForEach(week.days) { day in
                                    dayCell(day, size: cellSize)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 14 + 5 + (14 * 7) + (4 * 6))

            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(1...4, id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: intensity))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(.primary.opacity(0.18), lineWidth: 0.75)
                        }
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("Darker = stronger coffee and more completed sessions.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var summaryText: String {
        "\(heatmap.sessionCount) cups · \(shortDuration(heatmap.focusedDuration)) focused"
    }

    private func dayCell(_ day: CoffeeHeatmapDay, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: day.intensity))
            .overlay {
                if day.intensity > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(.primary.opacity(0.18), lineWidth: 0.75)
                }
                if calendar.isDate(day.date, inSameDayAs: referenceDate) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(.primary.opacity(0.45), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .opacity(day.isFuture ? 0 : 1)
            .accessibilityElement()
            .accessibilityHidden(day.isFuture || day.sessionCount == 0)
            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(
                "\(day.sessionCount) completed coffees, intensity \(day.intensity) of 4"
            )
    }

    private func color(for intensity: Int) -> Color {
        guard intensity > 0 else {
            return .primary.opacity(0.07)
        }

        let lightPalette = [
            Color(red: 0.80, green: 0.66, blue: 0.52),
            Color(red: 0.63, green: 0.45, blue: 0.31),
            Color(red: 0.46, green: 0.29, blue: 0.20),
            Color(red: 0.28, green: 0.16, blue: 0.11)
        ]
        let darkPalette = [
            Color(red: 0.80, green: 0.63, blue: 0.47),
            Color(red: 0.63, green: 0.44, blue: 0.30),
            Color(red: 0.47, green: 0.29, blue: 0.20),
            Color(red: 0.33, green: 0.19, blue: 0.13)
        ]
        let palette = colorScheme == .dark ? darkPalette : lightPalette
        return palette[min(intensity, 4) - 1]
    }

    private func shortDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded()) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}
