import XCTest
@testable import Strand

/// The question each screen's "Ask Coach about this" hands to Coach, and the date check for its day.
final class CoachAskAboutTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        return c
    }()

    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))! }

    func testTodayAsksWithoutADate() {
        let q = CoachAskAbout.question(.charge, daysAgo: 0, day: day(30), calendar: cal, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(q, "Why is my Charge where it is today, and what should I do with it?")
    }

    /// A past day is named by its date, which the day tool looks up.
    func testPastDaysNameTheDate() {
        let en = Locale(identifier: "en_GB")
        XCTAssertEqual(CoachAskAbout.question(.effort, daysAgo: 2, day: day(28), calendar: cal, locale: en),
                       "How did my Effort on Monday 28 September compare with my usual?")
        XCTAssertEqual(CoachAskAbout.question(.rest, daysAgo: 2, day: day(28), calendar: cal, locale: en),
                       "How did I sleep on the night into Monday 28 September, and what shaped my Rest?")
        XCTAssertEqual(CoachAskAbout.question(.stress, daysAgo: 1, day: day(29), calendar: cal, locale: en),
                       "How was my stress yesterday (Tuesday 29 September)?")
    }

    func testDaysAgo() {
        let today = day(30)
        XCTAssertEqual(CoachFactFormat.daysAgo("2026-09-30", today: today, calendar: cal), 0)
        XCTAssertEqual(CoachFactFormat.daysAgo("2026-09-28", today: today, calendar: cal), 2)
        XCTAssertNil(CoachFactFormat.daysAgo("2026-10-01", today: today, calendar: cal))
        XCTAssertEqual(CoachFactFormat.daysAgo("2026-05-01", today: today, calendar: cal), 152)
        XCTAssertNil(CoachFactFormat.daysAgo("2010-01-01", today: today, calendar: cal))
        XCTAssertNil(CoachFactFormat.daysAgo("28 September", today: today, calendar: cal))
    }
}
