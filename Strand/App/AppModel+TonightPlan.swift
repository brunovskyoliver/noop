import Foundation
import WhoopStore
import StrandAnalytics

// AppModel+TonightPlan.swift — builds tonight's sleep plan (SleepPlanner) once and publishes it, so the
// Sleep tab's Tonight card, the caffeine cutoff and the wind-down reminder read ONE bedtime. Before this
// each kept its own (a caffeine bedtime setting, the wind-down's fixed 8 h need), and they disagreed.
extension AppModel {

    /// Tomorrow morning's wake, minutes after midnight: the strap alarm when it is on and will actually
    /// ring (same gate and resolver as the Alarms screen), else the usual wake time for that weekday.
    func tonightWakeMinute(now: Date = Date()) -> Int {
        let cal = Calendar.current
        if behavior.smartAlarmEnabled, strapAlarmWillArm,
           let fire = AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes,
                                                  weekdays: behavior.smartAlarmWeekdays,
                                                  overrides: WindDownNudge.perDayWakeOverrides, from: now),
           fire.timeIntervalSince(now) < 24 * 3600 {
            let c = cal.dateComponents([.hour, .minute], from: fire)
            return (c.hour ?? 7) * 60 + (c.minute ?? 0)
        }
        let start = cal.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let minute = WindDownNudge.wakeMinutes(forWeekday: cal.component(.weekday, from: day))
            if let fire = cal.date(byAdding: .minute, value: minute, to: day), fire > now { return minute }
        }
        return WindDownNudge.wakeMinutes
    }

    /// Rebuild `tonightPlan` from the stored nights and push its bed-to-wake window to the wind-down
    /// reminder. Cheap (a month of sessions); called when the data refreshes.
    func refreshTonightPlan() async {
        let sessions = await repo.allSleepSessions(days: 30)
        let naps = SleepModel.napSleepMinutesByDay(navDays: SleepModel.navDays(navSessions: sessions),
                                                   habitualMidsleepSec: nil)
        let inputs = Self.tonightPlanInputs(days: repo.days, mainSleeps: repo.sleeps,
                                            napSleepMinByDay: naps, today: Repository.dayString(Date()),
                                            wakeMinute: tonightWakeMinute(), timeZone: .current)
        let plan = SleepPlanner.plan(inputs)
        tonightPlan = plan
        WindDownNudge.syncPlannedWindow(((plan.wakeMinute - plan.target.bedMinute) % 1440 + 1440) % 1440)
    }

    /// The planner inputs from stored data. Base need and debt are the Sleep tab's own
    /// (`SleepModel.debtLedger`), so the plan and the Sleep Debt card measure against one need.
    /// Efficiency and usual bedtime come from the last 14 nights.
    nonisolated static func tonightPlanInputs(days: [DailyMetric], mainSleeps: [CachedSleepSession],
                                              napSleepMinByDay: [String: Double], today: String,
                                              wakeMinute: Int, timeZone: TimeZone) -> SleepPlanner.Inputs {
        let ledger = SleepModel.debtLedger(days: days, napSleepMinByDay: napSleepMinByDay)
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
