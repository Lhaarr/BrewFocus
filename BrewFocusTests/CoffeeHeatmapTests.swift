import XCTest
@testable import BrewFocus

final class CoffeeHeatmapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 28,
            hour: 12
        ))!
    }

    func testIntensityCombinesCoffeeStrengthAndSessionCount() {
        let records = [
            record(.latte, daysAgo: 0, index: 1),
            record(.latte, daysAgo: 1, index: 2),
            record(.cappuccino, daysAgo: 1, index: 3),
            record(.espresso, daysAgo: 2, index: 4),
            record(.cappuccino, daysAgo: 2, index: 5),
            record(.espresso, daysAgo: 3, index: 6),
            record(.espresso, daysAgo: 3, index: 7),
            record(.espresso, daysAgo: 3, index: 8),
            record(.espresso, daysAgo: 4, index: 9)
        ]

        let heatmap = CoffeeHeatmap(
            records: records,
            referenceDate: referenceDate,
            weekCount: 2,
            calendar: calendar
        )

        XCTAssertEqual(day(daysAgo: 0, in: heatmap)?.intensity, 1)
        XCTAssertEqual(day(daysAgo: 1, in: heatmap)?.intensity, 2)
        XCTAssertEqual(day(daysAgo: 2, in: heatmap)?.intensity, 3)
        XCTAssertEqual(day(daysAgo: 3, in: heatmap)?.intensity, 4)
        XCTAssertEqual(day(daysAgo: 4, in: heatmap)?.intensity, 3)
        XCTAssertEqual(heatmap.sessionCount, records.count)
    }

    func testHistoryKeepsOneRecordPerCompletedSession() {
        let first = record(.espresso, daysAgo: 0, index: 1)
        let replacement = CoffeeActivityRecord(
            id: first.id,
            coffee: .americano,
            startedAt: first.startedAt,
            completedAt: first.completedAt.addingTimeInterval(10),
            focusedDuration: 45 * 60
        )

        let history = CoffeeActivityHistory.adding(
            replacement,
            to: [first, first]
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.coffee, .americano)
    }

    func testFutureSessionsAreNotIncluded() {
        let future = record(.espresso, daysAgo: -1, index: 1)
        let heatmap = CoffeeHeatmap(
            records: [future],
            referenceDate: referenceDate,
            weekCount: 2,
            calendar: calendar
        )

        XCTAssertEqual(heatmap.sessionCount, 0)
        XCTAssertTrue(day(daysAgo: -1, in: heatmap)?.isFuture == true)
        XCTAssertEqual(day(daysAgo: -1, in: heatmap)?.sessionCount, 1)
    }

    private func record(
        _ coffee: CoffeeKind,
        daysAgo: Int,
        index: Int
    ) -> CoffeeActivityRecord {
        let completedAt = calendar.date(
            byAdding: .day,
            value: -daysAgo,
            to: referenceDate
        )!
        return CoffeeActivityRecord(
            id: "record-\(index)",
            coffee: coffee,
            startedAt: completedAt.addingTimeInterval(-coffee.duration),
            completedAt: completedAt,
            focusedDuration: coffee.duration
        )
    }

    private func day(daysAgo: Int, in heatmap: CoffeeHeatmap) -> CoffeeHeatmapDay? {
        let expectedDate = calendar.startOfDay(for: calendar.date(
            byAdding: .day,
            value: -daysAgo,
            to: referenceDate
        )!)
        return heatmap.weeks
            .flatMap(\.days)
            .first { calendar.isDate($0.date, inSameDayAs: expectedDate) }
    }
}
