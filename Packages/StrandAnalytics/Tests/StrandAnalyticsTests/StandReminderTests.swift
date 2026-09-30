import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class StandReminderTests: XCTestCase {
    typealias SR = StandReminder

    /// Local day 20_000 (2024-10-04) is a Friday. UTC keeps the arithmetic readable.
    private let day = 20_000
    private let tz = 0
    private func t(_ hour: Int, _ minute: Int = 0, day d: Int? = nil) -> Int {
        (d ?? day) * 86_400 + hour * 3600 + minute * 60
    }
    /// Minutes from `from` up to (not including) `to`, all desk-like except the listed up minutes.
    private func mins(_ from: Int, _ to: Int, up: Set<Int> = [], still: Bool = false) -> [SR.Minute] {
        stride(from: from, to: to, by: 60).map { SR.Minute(start: $0, up: up.contains($0), still: still) }
    }
    private let on = SR.Config(enabled: true, learnWindow: false,
                               manualWindow: SR.Window(startHour: 9, endHour: 18))

    // MARK: Minutes

    func testWalkingMinuteIsUpAndDeskMinuteIsNot() {
        var g: [GravitySample] = [], s: [StepSample] = []
        for i in 0..<60 {   // desk: tiny wobble
            g.append(GravitySample(ts: 600 + i, x: i % 2 == 0 ? 0 : 0.03, y: 0, z: 1))
        }
        for i in 0..<60 {   // walking by gravity delta alone (a WHOOP 4.0 has no activity class)
            g.append(GravitySample(ts: 660 + i, x: i % 2 == 0 ? 0 : 0.4, y: 0, z: 1))
        }
        for i in 0..<60 {   // desk motion, but the strap tagged 20 s as walking
            g.append(GravitySample(ts: 720 + i, x: 0, y: 0, z: 1))
            s.append(StepSample(ts: 720 + i, counter: i, activityClass: i < 20 ? 1 : 0))
        }
        let m = SR.minutes(gravity: g, steps: s)
        XCTAssertEqual(m.map(\.start), [600, 660, 720])
        XCTAssertEqual(m.map(\.up), [false, true, true])
        XCTAssertEqual(m.map(\.still), [false, false, true])
    }

    func testSparseMinuteIsNotObserved() {
        let g = (0..<4).map { GravitySample(ts: 60 + $0 * 10, x: 0, y: 0, z: 1) }
        XCTAssertTrue(SR.minutes(gravity: g, steps: []).isEmpty)
    }

    // MARK: Decision

    func testSchedulesAtTheReminderMinuteWhenBehind() {
        let d = SR.evaluate(nowSec: t(10, 30), tzOffsetSec: tz, minutes: mins(t(9), t(10, 30)),
                            worn: true, config: on, state: SR.State())
        XCTAssertEqual(d.action, .schedule(fireAt: t(10, 50)))
        XCTAssertEqual(d.nextState.scheduledFireAt, t(10, 50))
    }

    func testGoalMetClearsTheReminder() {
        let up = Set((0..<5).map { t(10, 10 + $0) })
        var st = SR.State(); st.scheduledFireAt = t(10, 50)
        let d = SR.evaluate(nowSec: t(10, 30), tzOffsetSec: tz, minutes: mins(t(9), t(10, 30), up: up),
                            worn: true, config: on, state: st)
        XCTAssertEqual(d.action, .clear)
        XCTAssertEqual(d.upThisHour, 5)
        XCTAssertEqual(d.nextState.scheduledFireAt, 0)
    }

    func testPastTheReminderMinuteRemindsNowOncePerHour() {
        let d = SR.evaluate(nowSec: t(10, 52), tzOffsetSec: tz, minutes: mins(t(9), t(10, 52)),
                            worn: true, config: on, state: SR.State())
        XCTAssertEqual(d.action, .remindNow)
        XCTAssertEqual(d.nextState.countToday, 1)
        let again = SR.evaluate(nowSec: t(10, 57), tzOffsetSec: tz, minutes: mins(t(9), t(10, 57)),
                                worn: true, config: on, state: d.nextState)
        XCTAssertEqual(again.action, .keep)
    }

    func testAScheduledReminderThatPassedCountsAsFired() {
        var st = SR.State(); st.scheduledFireAt = t(10, 50)
        let d = SR.evaluate(nowSec: t(10, 55), tzOffsetSec: tz, minutes: mins(t(9), t(10, 55)),
                            worn: true, config: on, state: st)
        XCTAssertEqual(d.action, .keep)
        XCTAssertEqual(d.nextState.lastReminderTs, t(10, 50))
        XCTAssertEqual(d.nextState.countToday, 1)
    }

    func testGuards() {
        let desk = mins(t(9), t(10, 30))
        func action(_ m: [SR.Minute], worn: Bool = true, config: SR.Config? = nil, state: SR.State = SR.State(),
                    now: Int? = nil) -> SR.Action {
            SR.evaluate(nowSec: now ?? t(10, 30), tzOffsetSec: tz, minutes: m, worn: worn,
                        config: config ?? on, state: state).action
        }
        XCTAssertEqual(action(desk, worn: false), .clear, "strap off")
        XCTAssertEqual(action(mins(t(9), t(10, 0))), .clear, "data 30 min old")
        XCTAssertEqual(action(mins(t(9), t(10, 30), still: true)), .clear, "asleep / off wrist")
        XCTAssertEqual(action(mins(t(9), t(10, 30), up: [t(10, 27), t(10, 29)])), .clear, "walking right now")
        XCTAssertEqual(action(mins(t(18), t(18, 30)), now: t(18, 30)), .clear, "outside window")
        var paused = SR.State(); paused.pausedUntil = t(24)
        XCTAssertEqual(action(desk, state: paused), .clear, "paused")
        var capped = SR.State(); capped.countDay = day; capped.countToday = 8
        XCTAssertEqual(action(desk, state: capped), .clear, "daily cap")
        var off = on; off.enabled = false
        XCTAssertEqual(action(desk, config: off), .clear, "disabled")
    }

    // MARK: Outcomes and muting

    func testReminderOutcomeIsResolvedFromTheFollowingMinutes() {
        var st = SR.State(); st.lastReminderTs = t(10, 50); st.lastReminderResolved = false
        let walked = SR.evaluate(nowSec: t(11, 10), tzOffsetSec: tz,
                                 minutes: mins(t(10), t(11, 10), up: [t(10, 53), t(10, 54)]),
                                 worn: true, config: on, state: st)
        XCTAssertEqual(walked.nextState.outcomes, [SR.Outcome(ts: t(10, 50), hour: 10, weekend: false, responded: true)])
        let sat = SR.evaluate(nowSec: t(11, 10), tzOffsetSec: tz, minutes: mins(t(10), t(11, 10)),
                              worn: true, config: on, state: st)
        XCTAssertEqual(sat.nextState.outcomes.map(\.responded), [false])
    }

    func testThreeIgnoredRemindersMuteTheSlotForAWeekThenProbe() {
        // Ignored at 14:50 on three weekdays (Mon-Wed of the week after `day`).
        let ignored = [3, 4, 5].map { SR.Outcome(ts: t(14, 50, day: day + $0), hour: 14, weekend: false, responded: false) }
        let now = t(14, 20, day: day + 6)
        XCTAssertTrue(SR.isMuted(hour: 14, weekend: false, outcomes: ignored, nowSec: now))
        XCTAssertFalse(SR.isMuted(hour: 15, weekend: false, outcomes: ignored, nowSec: now))
        XCTAssertFalse(SR.isMuted(hour: 14, weekend: true, outcomes: ignored, nowSec: now))
        XCTAssertFalse(SR.isMuted(hour: 14, weekend: false, outcomes: ignored, nowSec: now + 7 * 86_400), "probe after a week")
        let answered = ignored + [SR.Outcome(ts: t(14, 50, day: day + 6), hour: 14, weekend: false, responded: true)]
        XCTAssertFalse(SR.isMuted(hour: 14, weekend: false, outcomes: answered, nowSec: now + 3600))

        var st = SR.State(); st.outcomes = ignored
        let d = SR.evaluate(nowSec: now, tzOffsetSec: tz, minutes: mins(t(13, day: day + 6), now),
                            worn: true, config: on, state: st)
        XCTAssertEqual(d.action, .clear)
        var noLearn = on; noLearn.learnMuting = false
        XCTAssertEqual(SR.evaluate(nowSec: now, tzOffsetSec: tz, minutes: mins(t(13, day: day + 6), now),
                                   worn: true, config: noLearn, state: st).action,
                       .schedule(fireAt: t(14, 50, day: day + 6)))
    }

    // MARK: Learned window

    /// Weekdays awake 07:00-23:00, weekends 09:00-24:00, as hour records.
    private func history(days: Range<Int>) -> [SR.HourRecord] {
        days.flatMap { d -> [SR.HourRecord] in
            let (wake, bed) = SR.isWeekend(day: d) ? (9, 24) : (7, 23)
            return (0..<24).map { h in
                let awake = h >= wake && h < bed
                return SR.HourRecord(day: d, hour: h, covered: 60, up: awake ? 8 : 0, still: awake ? 3 : 55)
            }
        }
    }

    func testLearnsSeparateWeekdayAndWeekendWindowsAndLeavesTheLastHourFree() {
        let h = history(days: day - 21..<day)
        XCTAssertEqual(SR.learnedWindow(h, weekend: false), SR.Window(startHour: 7, endHour: 22))
        // 23:00 on weekends: 6 of 6 awake, but the weekday prior (2 pseudo-days, 0% awake) holds it at
        // 0.75, so three weeks are not yet enough to learn the late weekend hour.
        XCTAssertEqual(SR.learnedWindow(h, weekend: true), SR.Window(startHour: 9, endHour: 22))
        XCTAssertEqual(SR.learnedWindow(history(days: day - 70..<day), weekend: true),
                       SR.Window(startHour: 9, endHour: 23), "ten weekends outweigh the prior")
    }

    func testAnHourWithTooFewObservationsBridgesTheWindow() {
        var h = history(days: day - 14..<day)
        h.removeAll { $0.hour == 13 }   // strap off every lunch
        XCTAssertEqual(SR.learnedWindow(h, weekend: false), SR.Window(startHour: 7, endHour: 22))
    }

    func testTooLittleHistoryFallsBackToTheDefaultWindow() {
        let h = history(days: day - 3..<day)
        XCTAssertNil(SR.learnedWindow(h, weekend: false))
        XCTAssertEqual(SR.window(for: day, config: SR.Config(enabled: true), history: h), SR.defaultWindow)
    }

    func testFinishedHoursAreFoldedIntoHistory() {
        let d = SR.evaluate(nowSec: t(10, 30), tzOffsetSec: tz, minutes: mins(t(9), t(10, 30), up: [t(9, 5)]),
                            worn: true, config: on, state: SR.State())
        XCTAssertEqual(d.nextState.history, [SR.HourRecord(day: day, hour: 9, covered: 60, up: 1, still: 0)])
    }

    func testAPartialViewOfAFinishedHourDoesNotReplaceTheFullRecord() {
        // A later sync's 3 h lookback starts at 09:57, so it only sees the last three minutes of hour 9.
        let first = SR.evaluate(nowSec: t(10, 30), tzOffsetSec: tz, minutes: mins(t(9), t(10, 30), up: [t(9, 5)]),
                                worn: true, config: on, state: SR.State())
        let later = SR.evaluate(nowSec: t(12, 57), tzOffsetSec: tz, minutes: mins(t(9, 57), t(12, 57)),
                                worn: true, config: on, state: first.nextState)
        XCTAssertEqual(later.nextState.history.first, SR.HourRecord(day: day, hour: 9, covered: 60, up: 1, still: 0))
    }

    func testLocalClockHonoursTheOffset() {
        // 23:30 UTC is 01:30 the next day at UTC+2.
        let ts = t(23, 30)
        XCTAssertEqual(SR.localHour(ts, tzOffsetSec: 7200), 1)
        XCTAssertEqual(SR.localDay(ts, tzOffsetSec: 7200), day + 1)
        XCTAssertFalse(SR.isWeekend(day: day))
        XCTAssertTrue(SR.isWeekend(day: day + 1))
    }
}
