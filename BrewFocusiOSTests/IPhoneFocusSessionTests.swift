import FamilyControls
import XCTest
@testable import BrewFocusiOS

final class IPhoneFocusSessionTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testSessionKeepsCoffeeAndSelectionMetadata() {
        let session = IPhoneFocusSession(
            coffee: .americano,
            startedAt: startDate,
            endsAt: startDate.addingTimeInterval(900),
            selectedApplicationCount: 4
        )

        XCTAssertEqual(session.coffee, .americano)
        XCTAssertEqual(session.selectedApplicationCount, 4)
    }

    func testRemainingSecondsRoundsUpAndNeverBecomesNegative() {
        let session = IPhoneFocusSession(
            coffee: .espresso,
            startedAt: startDate,
            endsAt: startDate.addingTimeInterval(900),
            selectedApplicationCount: 2
        )

        XCTAssertEqual(
            session.remainingSeconds(at: startDate.addingTimeInterval(0.25)),
            900
        )
        XCTAssertEqual(
            session.remainingSeconds(at: startDate.addingTimeInterval(901)),
            0
        )
    }

    func testSessionIsActiveOnlyBeforeEndDate() {
        let endsAt = startDate.addingTimeInterval(900)
        let session = IPhoneFocusSession(
            coffee: .cappuccino,
            startedAt: startDate,
            endsAt: endsAt,
            selectedApplicationCount: 1
        )

        XCTAssertTrue(session.isActive(at: endsAt.addingTimeInterval(-1)))
        XCTAssertFalse(session.isActive(at: endsAt))
    }

    func testMorningScheduleIsExactlyOneHourAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let schedule = try XCTUnwrap(MorningQuarantineSchedule(hour: 23, minute: 30))
        let activeDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 28,
                hour: 23,
                minute: 45
            ))
        )
        let expectedEnd = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 29,
                hour: 0,
                minute: 30
            ))
        )

        XCTAssertEqual(schedule.endHour, 0)
        XCTAssertEqual(
            schedule.activeEndDate(at: activeDate, calendar: calendar),
            expectedEnd
        )
        XCTAssertNil(
            schedule.activeEndDate(
                at: expectedEnd.addingTimeInterval(1),
                calendar: calendar
            )
        )
    }

    func testMorningQuarantineAllowsZeroAppExceptions() {
        XCTAssertTrue(
            ScreenTimeShared.isValidMorningSelection(FamilyActivitySelection())
        )
    }

    func testLatteNeedsNoAppSelection() {
        XCTAssertTrue(
            ScreenTimeShared.isValidCoffeeSelection(
                FamilyActivitySelection(),
                for: .latte
            )
        )
    }

    func testRestrictedCoffeeNeedsAtLeastOneIndividualApp() {
        let emptySelection = FamilyActivitySelection()

        XCTAssertFalse(
            ScreenTimeShared.isValidCoffeeSelection(emptySelection, for: .cappuccino)
        )
        XCTAssertFalse(
            ScreenTimeShared.isValidCoffeeSelection(emptySelection, for: .americano)
        )
        XCTAssertFalse(
            ScreenTimeShared.isValidCoffeeSelection(emptySelection, for: .espresso)
        )
    }

    func testMorningScheduleRejectsInvalidClockValues() {
        XCTAssertNil(MorningQuarantineSchedule(hour: 24, minute: 0))
        XCTAssertNil(MorningQuarantineSchedule(hour: 7, minute: 60))
    }
}
