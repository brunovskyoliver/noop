import XCTest
@testable import Strand

/// The evening review's window and its reminder's timing.
final class AppleCoachEveningTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testEveningStartsAtFive() {
        XCTAssertFalse(AppleCoachEveningPolicy.isEvening(date(30, 16, 59), calendar: cal))
        XCTAssertTrue(AppleCoachEveningPolicy.isEvening(date(30, 17), calendar: cal))
        XCTAssertTrue(AppleCoachEveningPolicy.isEvening(date(30, 23, 59), calendar: cal))
        XCTAssertFalse(AppleCoachEveningPolicy.isEvening(date(30, 0, 30), calendar: cal))
    }

    /// An hour before the wind-down reminder, kept between 19:00 and 22:30 of that evening.
    func testReminderIsAnHourBeforeWindDownWithinTheEvening() {
        XCTAssertEqual(EveningReviewTiming.reminderDate(windDownFire: date(30, 22, 10), calendar: cal), date(30, 21, 10))
        XCTAssertEqual(EveningReviewTiming.reminderDate(windDownFire: date(30, 19, 30), calendar: cal), date(30, 19))
        // A wind-down after midnight: the reminder stays on the evening before, at 22:30.
        XCTAssertEqual(EveningReviewTiming.reminderDate(windDownFire: date(30, 0, 40), calendar: cal), date(29, 22, 30))
        XCTAssertEqual(EveningReviewTiming.reminderDate(windDownFire: date(30, 23, 50), calendar: cal), date(30, 22, 30))
    }

    func testReminderDatesSkipPastAndLoggedTonight() {
        let fires = [date(30, 22, 10), date(30, 22, 40)]
        let oct1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 22, minute: 10))!
        let all = EveningReviewTiming.reminderDates(windDownFires: [fires[0], oct1, fires[1]], now: date(30, 18), skipTonight: false, calendar: cal)
        XCTAssertEqual(all, [date(30, 21, 10), oct1.addingTimeInterval(-3600)])
        let skipped = EveningReviewTiming.reminderDates(windDownFires: [fires[0], oct1], now: date(30, 18), skipTonight: true, calendar: cal)
        XCTAssertEqual(skipped, [oct1.addingTimeInterval(-3600)])
        let late = EveningReviewTiming.reminderDates(windDownFires: [fires[0], oct1], now: date(30, 21, 30), skipTonight: false, calendar: cal)
        XCTAssertEqual(late, [oct1.addingTimeInterval(-3600)])
    }

    /// Tonight's habits are logged against tomorrow's morning, as the journal attributes them.
    func testEveningHabitsGoToTomorrowsJournalDay() {
        XCTAssertTrue(cal.isDate(AppleCoachEveningPolicy.journalDay(for: date(30, 21), calendar: cal),
                                 inSameDayAs: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!))
    }

    /// An older stored brief (no evening field) still decodes.
    func testStoredBriefWithoutTonightDecodes() throws {
        let json = #"{"day":"2026-09-30","dataKey":"k","headline":"h","points":[],"offDevice":false,"factsOnly":false}"#
        let b = try JSONDecoder().decode(AppleCoachBrief.self, from: Data(json.utf8))
        XCTAssertNil(b.tonight)
    }
}
