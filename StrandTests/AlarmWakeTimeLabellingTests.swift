import XCTest
@testable import Strand

/// A per-day override must win over the base alarm time.
final class AlarmWakeTimeLabellingTests: XCTestCase {

    /// `nextSmartAlarmDate` is the contract the alarm surfaces lean on: an override for a weekday wins
    /// over the base time. Pinned here as behaviour.
    func testAnOverrideDayWinsOverTheBaseAlarmTime() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // Wednesday 2026-09-16, 09:00 UTC. Base alarm 10:00 daily, Saturday overridden to 20:30.
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9)))
        let next = try XCTUnwrap(AppModel.nextSmartAlarmDate(minutes: 10 * 60,
                                                             weekdays: [7],
                                                             overrides: [7: 20 * 60 + 30],
                                                             from: now,
                                                             calendar: cal))
        let parts = cal.dateComponents([.weekday, .hour, .minute], from: next)
        XCTAssertEqual(parts.weekday, 7, "Saturday is the only enabled day")
        XCTAssertEqual(parts.hour, 20)
        XCTAssertEqual(parts.minute, 30, "the override, not the 10:00 base, is what the strap is armed with")
    }
}
