import Foundation
import WhoopStore
import StrandAnalytics

// AppModel+TonightPlan.swift — builds tonight's sleep plan (SleepPlanner) once and publishes it, so the
// Sleep tab's Tonight card, the caffeine cutoff and the wind-down reminder read ONE bedtime. Before this
// each kept its own (a caffeine bedtime setting, the wind-down's fixed 8 h need), and they disagreed.
extension AppModel {

    /// The armed strap alarm tonight's plan wakes to: on, will actually arm (same gate and resolver as
    /// the Alarms screen) and ringing within 24 h. Nil otherwise.
    func tonightAlarmFire(now: Date = Date()) -> Date? {
        guard behavior.smartAlarmEnabled, strapAlarmWillArm,
              let fire = AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes,
                                                     weekdays: behavior.smartAlarmWeekdays,
                                                     overrides: WindDownNudge.perDayWakeOverrides, from: now),
              fire.timeIntervalSince(now) < 24 * 3600 else { return nil }
        return fire
    }

    /// Tomorrow morning's wake, minutes after midnight: the strap alarm when it is on and will actually
    /// ring, else the usual wake time for that weekday. Resolved by `WindDownNudge.tonightWake`, the same
    /// function tonight's wind-down reminder fires from, so the plan and the reminder share one wake.
    func tonightWakeMinute(now: Date = Date()) -> Int {
        let cal = Calendar.current
        let wake = WindDownNudge.tonightWake(now: now, calendar: cal, alarmFire: tonightAlarmFire(now: now),
                                             wakeMinuteForWeekday: { WindDownNudge.wakeMinutes(forWeekday: $0) })
        let c = cal.dateComponents([.hour, .minute], from: wake.date)
        return (c.hour ?? 7) * 60 + (c.minute ?? 0)
    }

    /// Tonight's wind-down reminder, from the plan's wake (see `WindDownNudge.Tonight`). The Alarms
    /// screens print this; the scheduler fires the same value.
    func windDownTonight(now: Date = Date()) -> WindDownNudge.Tonight {
        WindDownNudge.tonight(now: now, alarmFire: tonightAlarmFire(now: now))
    }

    /// Rebuild `tonightPlan` from the stored nights and push its bed-to-wake window to the wind-down
    /// reminder. Cheap (a month of sessions); called when the data refreshes.
    func refreshTonightPlan() async {
        let sessions = await repo.allSleepSessions(days: 30)
        // Main night vs nap per wake-day with the Sleep tab's own selector and the learned habitual
        // mid-sleep, so a nap beside a short night is credited as a nap (and its start is never read as a
        // bedtime). Same inputs Android's `tonightPlanInputs` groups by.
        let habitual = await repo.habitualMidsleepSec()
        let navDays = SleepModel.navDays(navSessions: sessions)
        let naps = SleepModel.napSleepMinutesByDay(navDays: navDays, habitualMidsleepSec: habitual)
        let mainStarts = Self.mainNightStarts(navDays: navDays, habitualMidsleepSec: habitual)
        let inputs = Self.tonightPlanInputs(days: repo.days, mainSleeps: mainStarts,
                                            napSleepMinByDay: naps, today: Repository.dayString(Date()),
                                            wakeMinute: tonightWakeMinute(), timeZone: .current,
                                            age: profile.age)
        let plan = SleepPlanner.plan(inputs)
        tonightPlan = plan
        if StrainTargetContext.shared.sleepDebtMin != inputs.debtMin {
            StrainTargetContext.shared.sleepDebtMin = inputs.debtMin
            evaluateStrainTarget()
        }
        WindDownNudge.syncPlan(windowMinutes: ((plan.wakeMinute - plan.target.bedMinute) % 1440 + 1440) % 1440,
                               alarmFire: tonightAlarmFire())
    }

    /// The first block of each wake-day's main sleep (the Sleep tab's `mainNightGroup` selector), one per
    /// day: the session whose start is that night's bedtime.
    nonisolated static func mainNightStarts(navDays: [[CachedSleepSession]],
                                            habitualMidsleepSec: Int?) -> [CachedSleepSession] {
        navDays.compactMap { blocks in
            SleepView.mainNightGroup(blocks, habitualMidsleepSec: habitualMidsleepSec)
                .min { $0.effectiveStartTs < $1.effectiveStartTs }
        }
    }

    /// The planner inputs from stored data. Base need and debt are the Sleep tab's own
    /// (`SleepModel.debtLedger`), so the plan and the Sleep Debt card measure against one need, floored by
    /// the profile age the engine scores Rest with.
    /// Efficiency and usual bedtime come from the last 14 nights.
    nonisolated static func tonightPlanInputs(days: [DailyMetric], mainSleeps: [CachedSleepSession],
                                              napSleepMinByDay: [String: Double], today: String,
                                              wakeMinute: Int, timeZone: TimeZone, age: Int?) -> SleepPlanner.Inputs {
        let ledger = SleepModel.debtLedger(days: days, napSleepMinByDay: napSleepMinByDay, age: age)
        let recent = days.sorted { $0.day < $1.day }.suffix(14)
        let beds = mainSleeps.sorted { $0.effectiveStartTs < $1.effectiveStartTs }.suffix(14).map { s -> Int in
            let ts = s.effectiveStartTs
            let local = ts + timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
            return ((local % 86_400 + 86_400) % 86_400) / 60
        }
        return SleepPlanner.Inputs(
            baseNeedHours: ledger.needMin / 60,
            debtMin: ledger.isDebt ? ledger.magnitudeMin : 0,
            napMin: napSleepMinByDay[today] ?? 0,
            efficiencies: recent.compactMap(\.efficiency),
            wakeMinute: wakeMinute,
            recentBedMinutes: Array(beds))
    }
}
