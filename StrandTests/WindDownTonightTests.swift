import XCTest
@testable import Strand

/// Tonight's wind-down reminder follows the wake tonight's sleep plan uses (`WindDownNudge.tonight`):
/// the armed strap alarm when it rings within 24 h, else the weekday's usual wake time. The scheduler
/// swaps that wake day's repeating trigger for a one-off only when the alarm moves the reminder.
final class WindDownTonightTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func date(_ c: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func hm(_ c: Calendar, _ date: Date) -> [Int] {
        let x = c.dateComponents([.day, .hour, .minute], from: date)
        return [x.day!, x.hour!, x.minute!]
    }

    private let usual7: (Int) -> Int = { _ in 7 * 60 }

    // Monday 5 October 2026, noon. Tuesday is weekday 3.

    func testArmedAlarmSetsTonightsReminderAndReplacesThatWeekday() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 5, 12, 0)
        let alarm = date(c, 2026, 10, 6, 6, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertTrue(t.fromAlarm)
        XCTAssertEqual(t.wakeWeekday, 3)
        XCTAssertEqual(t.offsetMin, 570)
        XCTAssertEqual(hm(c, t.fireDate), [5, 20, 30])
        let plan = WindDownNudge.schedulePlan(now: now, calendar: c, tonight: t, wakeMinuteForWeekday: usual7)
        XCTAssertEqual(plan.repeatingWakeWeekdays, [1, 2, 4, 5, 6, 7])
        XCTAssertEqual(plan.oneOffs.map { hm(c, $0) }, [[5, 20, 30], [12, 21, 30]])
    }

    func testAlarmOffUsesTheWeekdayWakeAndKeepsEveryRepeatingTrigger() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 5, 12, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: nil, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertFalse(t.fromAlarm)
        XCTAssertEqual(hm(c, t.wakeDate), [6, 7, 0])
        XCTAssertEqual(hm(c, t.fireDate), [5, 21, 30])
        let plan = WindDownNudge.schedulePlan(now: now, calendar: c, tonight: t, wakeMinuteForWeekday: usual7)
        XCTAssertEqual(plan, WindDownNudge.SchedulePlan(repeatingWakeWeekdays: Array(1...7), oneOffs: []))
    }

    func testAlarmMoreThanADayAwayDoesNotDriveTonight() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 5, 12, 0)
        let alarm = date(c, 2026, 10, 7, 6, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertFalse(t.fromAlarm)
        XCTAssertEqual(hm(c, t.fireDate), [5, 21, 30])
    }

    func testPerDayOverrideMovesTheWeekdayWake() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 5, 12, 0)
        let wake: (Int) -> Int = { $0 == 3 ? 5 * 60 + 30 : 7 * 60 }
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: nil, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: wake)
        XCTAssertEqual(hm(c, t.fireDate), [5, 20, 0])
        // The alarm on that override day at the override's own time changes nothing in the schedule.
        let alarm = date(c, 2026, 10, 6, 5, 30)
        let armed = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                          wakeMinuteForWeekday: wake)
        XCTAssertTrue(armed.fromAlarm)
        XCTAssertEqual(armed.fireDate, t.fireDate)
        let plan = WindDownNudge.schedulePlan(now: now, calendar: c, tonight: armed, wakeMinuteForWeekday: wake)
        XCTAssertEqual(plan, WindDownNudge.SchedulePlan(repeatingWakeWeekdays: Array(1...7), oneOffs: []))
    }

    func testAlarmJustAfterMidnightPutsTheReminderOnTheEveningBefore() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 5, 12, 0)
        let alarm = date(c, 2026, 10, 6, 0, 30)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 480, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertEqual(t.wakeWeekday, 3)
        XCTAssertEqual(hm(c, t.fireDate), [5, 16, 0])
    }

    func testAfterMidnightTonightsReminderHasPassedAndOnlyTheStandInIsQueued() {
        let c = calendar("Europe/Bratislava")
        let now = date(c, 2026, 10, 6, 0, 10)
        let alarm = date(c, 2026, 10, 6, 6, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertEqual(hm(c, t.fireDate), [5, 20, 30])
        XCTAssertLessThan(t.fireDate, now)
        let plan = WindDownNudge.schedulePlan(now: now, calendar: c, tonight: t, wakeMinuteForWeekday: usual7)
        XCTAssertEqual(plan.repeatingWakeWeekdays, [1, 2, 4, 5, 6, 7])
        XCTAssertEqual(plan.oneOffs.map { hm(c, $0) }, [[12, 21, 30]])
    }

    /// Clocks go back at 03:00 on Sunday 25 October 2026 in Berlin. The reminder stays at the wall-clock
    /// minute the planner prints (21:30), which is 10 h 30 min of real time before a 07:00 alarm.
    func testDSTFallBackKeepsTheWallClockReminder() {
        let c = calendar("Europe/Berlin")
        let now = date(c, 2026, 10, 24, 12, 0)
        let alarm = date(c, 2026, 10, 25, 7, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertEqual(hm(c, t.fireDate), [24, 21, 30])
        XCTAssertEqual(alarm.timeIntervalSince(t.fireDate), 630 * 60)
    }

    /// Clocks go forward at 02:00 on Sunday 29 March 2026 in Berlin: the same 21:30 is 8 h 30 min before.
    func testDSTSpringForwardKeepsTheWallClockReminder() {
        let c = calendar("Europe/Berlin")
        let now = date(c, 2026, 3, 28, 12, 0)
        let alarm = date(c, 2026, 3, 29, 7, 0)
        let t = WindDownNudge.tonight(now: now, calendar: c, alarmFire: alarm, windowMin: 540, leadMin: 30,
                                      wakeMinuteForWeekday: usual7)
        XCTAssertEqual(hm(c, t.fireDate), [28, 21, 30])
        XCTAssertEqual(alarm.timeIntervalSince(t.fireDate), 510 * 60)
    }
}
