#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Everything the Broop screens show for one selected day, resolved in one pass by `BroopStore.reload`.
///
/// The reads mirror `LiquidTodayView.load()` call for call (same repository queries, same carry rules,
/// same helpers), so Broop and the classic Today can never disagree about a number. Where Liquid keeps a
/// resolution private, the static helper it delegates to is called instead.
struct BroopSnapshot {
    var dayKey: String
    var date: Date
    var isToday: Bool

    /// Charge 0–100 (nil = nothing honest to show) and how it was resolved (scored / carried / calibrating).
    var charge: Double?
    var chargeDisplay: LiquidTodayView.ChargeDisplay
    /// Rest 0–100.
    var rest: Double?
    /// Effort on the wearer's chosen display scale (0–21 or 0–100).
    var effort: Double?
    var effortMax: Double

    var readiness: ReadinessEngine.Readiness?

    /// The main night that ended on the selected day.
    var night: Night?
    var asleepMinutes: Double?
    var needMinutes: Double?
    var efficiency: Double?
    var restorativePct: Double?

    var workouts: [WorkoutRow]
    var zoneMinutes: [Double]?
    var steps: Double?
    var activeKcal: Double?

    var stress: StressModel?

    /// Statistics against the previous 30 days, per score.
    var chargeStats: [BroopReading]
    var restStats: [BroopReading]
    var effortStats: [BroopReading]
    /// Dashboard rows, each with the score screen that owns it (the row links there).
    var dashboard: [(reading: BroopReading, home: BroopScore)]

    var streak: Int

    static func empty(dayKey: String, date: Date, isToday: Bool) -> BroopSnapshot {
        BroopSnapshot(dayKey: dayKey, date: date, isToday: isToday,
                      charge: nil, chargeDisplay: .noData, rest: nil, effort: nil, effortMax: 21,
                      readiness: nil, night: nil, asleepMinutes: nil, needMinutes: nil,
                      efficiency: nil, restorativePct: nil, workouts: [], zoneMinutes: nil,
                      steps: nil, activeKcal: nil, stress: nil,
                      chargeStats: [], restStats: [], effortStats: [], dashboard: [], streak: 0)
    }

    func value(_ score: BroopScore) -> Double? {
        switch score {
        case .rest: return rest
        case .charge: return charge
        case .effort: return effort
        }
    }

    func maxValue(_ score: BroopScore) -> Double { score == .effort ? effortMax : 100 }
}

/// Shared selected-day state for every Broop screen, so the day chosen on Home is the day the detail
/// screens show (and going back keeps it, rather than resetting to today).
@MainActor
final class BroopStore: ObservableObject {
    /// 0 = today's logical day, 1 = yesterday, …
    @Published var dayOffset = 0
    @Published private(set) var snapshot: BroopSnapshot?

    var selectedLogicalDay: Date {
        let base = Repository.logicalDay(Date())
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: base) ?? base
    }

    func selectedDayKey(repo: Repository) -> String {
        if dayOffset == 0, let k = repo.today?.day { return k }
        return Repository.localDayKey(selectedLogicalDay)
    }

    func maxOffset(repo: Repository) -> Int {
        LiquidTodayView.maxDayOffset(earliestDayKey: repo.freshness.earliestDay,
                                     todayKey: Repository.logicalDayKey(Date()))
    }

    /// +1 = one day older, -1 = one day newer.
    func step(_ delta: Int, repo: Repository) {
        let next = LiquidTodayView.clampedDayOffset(current: dayOffset, delta: delta, maxOffset: maxOffset(repo: repo))
        guard next != dayOffset else { return }
        dayOffset = next
    }

    var dayLabel: String {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default:
            return selectedLogicalDay.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.activeLocale))
        }
    }

    /// Resolve everything for the selected day. Called from a `.task(id:)` keyed on the repository's
    /// refresh sequence and the day offset, like Liquid's `load()`.
    func reload(repo: Repository, profile: ProfileStore) async {
        let offset = dayOffset
        let isToday = offset == 0
        let key = selectedDayKey(repo: repo)
        let logicalDay = selectedLogicalDay
        var s = BroopSnapshot.empty(dayKey: key, date: logicalDay, isToday: isToday)

        let days = repo.days
        let day: DailyMetric? = isToday
            ? (repo.today ?? days.last(where: { $0.day == key }))
            : days.last(where: { $0.day == key })
        let tkey = day?.day ?? key

        // Charge, with Liquid's carry and calibration rules.
        let calNights = isToday
            ? RecoveryScorer.calibrationNights(nightlyHrv: days.map(\.avgHrv), dayKeys: days.map(\.day),
                                               hasRecovery: day?.recovery != nil)
            : nil
        let prior = TodayView.lastScoredRecoveryDay(days: days, selectedDayKey: tkey, isToday: isToday,
                                                    todayScored: day?.recovery != nil,
                                                    isCalibrating: calNights != nil)
        s.chargeDisplay = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: day?.recovery, priorScored: prior,
                                                                calibrationNights: calNights, todayKey: tkey)
        s.charge = s.chargeDisplay.pct
        s.readiness = ReadinessEngine.evaluate(days: days, today: day?.day)

        // Day window, honouring the day-cycle (sleep-onset) mode exactly as Liquid does.
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: logicalDay)
        let calendarFrom = Int(dayStart.timeIntervalSince1970)
        let calendarTo: Int = isToday
            ? Int(Date().timeIntervalSince1970)
            : Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)
        let nextDayKey = Repository.localDayKey(cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart)
        let cycleMode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey)
                                               ?? DayCycleMode.sleepOnset.rawValue)
        let markers = cycleMode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        let from = markers.last(where: { $0.day == key }).map { Int($0.value) } ?? calendarFrom
        let toExclusive = markers.last(where: { $0.day == nextDayKey }).map { Int($0.value) } ?? calendarTo
        let to = max(from, toExclusive - 1)

        // Effort: live for today (same scorer and params as Liquid), else the stored row.
        var liveStrain: Double?
        if isToday {
            let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
            let maxHR = profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil
            let restHR = day?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
            let method = PuffinExperiment.effortMethod
            let sex = profile.sex
            liveStrain = await CancellableAnalysis.run {
                StrainScorer.strain(hr, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
            }
        }
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        s.effortMax = scale == .whoop ? 21 : 100
        if let stored = StrainScorer.effectiveEffort(live: isToday ? liveStrain : nil, stored: day?.strain) {
            s.effort = UnitFormatter.effortValue(stored, scale: scale)
        }

        async let restSeriesA = repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        async let stressA = repo.series(key: "stress", source: "my-whoop")
        async let stepsA = repo.exploreSeries(key: "steps_est", source: "my-whoop")
        async let appleA = repo.appleDailyRows()
        async let workoutsA = repo.workoutRows(from: from, to: toExclusive)
        async let zonesA = repo.workoutZoneMinutes(from: from, to: to, zoneSet: profile.hrZoneSet)
        async let sessionsA = repo.allSleepSessions()
        async let habitualA = repo.habitualMidsleepSec()

        let restSeries = await restSeriesA
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        s.rest = TodayView.freshRestScore(todayValue: restByDay[key], lastDay: restSeries.last?.day,
                                          lastValue: restSeries.last?.value, isTodaySelected: isToday, todayKey: key)

        s.stress = StressModel(days: days, stored: await stressA)
        s.workouts = await workoutsA
        s.zoneMinutes = await zonesA

        let apple = await appleA
        let stepsEst = await stepsA
        s.steps = day?.steps.map(Double.init)
            ?? apple.filter { $0.day == key }.compactMap { $0.steps }.max().map(Double.init)
            ?? stepsEst.last(where: { $0.day == key })?.value
        s.activeKcal = apple.filter { $0.day == key }.compactMap { $0.activeKcal }.max()
            ?? day?.activeKcalEst

        // Sleep: the main night that ended on the selected day (SleepView's resolution).
        let sessions = await sessionsA
        let habitual = await habitualA
        let groups = SleepModel.navDays(navSessions: sessions.isEmpty ? repo.sleeps : sessions)
        if let group = groups.first(where: { g in
            guard let last = g.last else { return false }
            return Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(last.endTs))) == key
        }) {
            let motion = await repo.sessionMotions(sessions: group)
            s.night = SleepModel.mergeDay(group, habitualMidsleepSec: habitual, motionByStart: motion)
        }
        let asleep = day?.totalSleepMin ?? s.night?.stages.asleep
        s.asleepMinutes = asleep
        s.needMinutes = repo.importedSleep[key]?.needMin ?? SleepModel.sleepNeedMin(days: days)
        if let e = day?.efficiency {
            s.efficiency = e <= 1 ? e * 100 : e
        } else if let n = s.night, n.timeInBed > 0 {
            s.efficiency = n.stages.asleep / n.timeInBed * 100
        }
        if let asleep, asleep > 0 {
            let deep = day?.deepMin ?? s.night?.stages.deep
            let rem = day?.remMin ?? s.night?.stages.rem
            if let deep, let rem { s.restorativePct = (deep + rem) / asleep * 100 }
        }

        // 30-day statistics (the "vs. previous 30 days" rows).
        let index = days.lastIndex(where: { $0.day <= key }) ?? (days.count - 1)
        let window = index >= 0 ? Array(days[max(0, index - 30)..<max(0, index)]) : []
        func stat(_ name: String, unit: String, better: BroopReading.Better,
                  value: Double?, format: @escaping (Double) -> String,
                  _ metric: (DailyMetric) -> Double?) -> BroopReading? {
            guard let value else { return nil }
            let hist = window.compactMap(metric)
            guard !hist.isEmpty else { return nil }
            let mean = hist.reduce(0, +) / Double(hist.count)
            let variance = hist.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(hist.count)
            let sd = max(variance.squareRoot(), abs(mean) * 0.02, 0.05)
            return BroopReading(name: name, value: value, unit: unit, typical: (mean - sd)...(mean + sd),
                                baseline: mean, better: better, format: format)
        }
        let whole: (Double) -> String = { BroopFormat.whole($0) }
        let one: (Double) -> String = { BroopFormat.one($0) }
        let hrvNow = day?.avgHrv ?? (isToday ? Repository.lastHrvDay(days: days, todayKey: tkey)?.avgHrv : nil)
        let rhrNow = (day?.restingHr ?? (isToday ? Repository.lastRestingHrDay(days: days, todayKey: tkey)?.restingHr : nil)).map(Double.init)
        let respNow = day?.respRateBpm ?? (isToday ? (Repository.lastVitalsDay(days: days, todayKey: tkey)?.respRateBpm
                                                      ?? Repository.lastRespDay(days: days, todayKey: tkey)?.respRateBpm) : nil)
        let hrv = stat(String(localized: "HRV"), unit: "ms", better: .higher, value: hrvNow, format: whole) { $0.avgHrv }
        let rhr = stat(String(localized: "Resting heart rate"), unit: "bpm", better: .lower, value: rhrNow, format: whole) { $0.restingHr.map(Double.init) }
        let resp = stat(String(localized: "Respiratory rate"), unit: "rpm", better: .neutral, value: respNow, format: one) { $0.respRateBpm }
        let spo2 = stat(String(localized: "Blood oxygen"), unit: "%", better: .higher, value: day?.spo2Pct, format: whole) { $0.spo2Pct }
        s.chargeStats = [hrv, rhr, resp, spo2].compactMap { $0 }

        let asleepStat = stat(String(localized: "Hours of sleep"), unit: "", better: .higher, value: asleep, format: { BroopFormat.duration($0) }) { $0.totalSleepMin }
        let effStat = stat(String(localized: "Sleep efficiency"), unit: "%", better: .higher, value: s.efficiency, format: whole) { d in
            d.efficiency.map { $0 <= 1 ? $0 * 100 : $0 }
        }
        let restorativeStat = stat(String(localized: "Restorative sleep"), unit: "%", better: .higher, value: s.restorativePct, format: whole) { d in
            guard let a = d.totalSleepMin, a > 0, let deep = d.deepMin, let rem = d.remMin else { return nil }
            return (deep + rem) / a * 100
        }
        let deepStat = stat(String(localized: "Deep sleep"), unit: "", better: .higher, value: day?.deepMin ?? s.night?.stages.deep, format: { BroopFormat.duration($0) }) { $0.deepMin }
        let remStat = stat(String(localized: "REM sleep"), unit: "", better: .higher, value: day?.remMin ?? s.night?.stages.rem, format: { BroopFormat.duration($0) }) { $0.remMin }
        s.restStats = [asleepStat, effStat, restorativeStat, deepStat, remStat].compactMap { $0 }

        let stepsStat = stat(String(localized: "Steps"), unit: "", better: .neutral, value: s.steps, format: whole) { $0.steps.map(Double.init) }
        let kcalStat = stat(String(localized: "Active calories"), unit: "kcal", better: .neutral, value: s.activeKcal, format: whole) { $0.activeKcalEst }
        let effortStat = stat(String(localized: "Effort"), unit: "", better: .neutral,
                              value: s.effort, format: one) { d in d.strain.map { UnitFormatter.effortValue($0, scale: scale) } }
        s.effortStats = [effortStat, stepsStat, kcalStat].compactMap { $0 }

        let rows: [(BroopReading?, BroopScore)] = [(hrv, .charge), (rhr, .charge), (restorativeStat, .rest),
                                                   (resp, .charge), (stepsStat, .effort), (kcalStat, .effort)]
        s.dashboard = rows.compactMap { r in r.0.map { (reading: $0, home: r.1) } }

        s.streak = StreakCalculator.streaks(
            dayKeys: days.map(\.day),
            qualified: days.map { $0.recovery != nil },
            today: AnalyticsEngine.dayString(Int(Date().timeIntervalSince1970),
                                             offsetSec: TimeZone.current.secondsFromGMT())
        ).current

        // Drop a stale result if the day changed while this pass was running.
        guard offset == dayOffset, !Task.isCancelled else { return }
        snapshot = s
    }
}

/// Routes pushed inside the Broop tabs.
enum BroopRoute: Hashable {
    case score(BroopScore)
}
#endif

enum BroopPrefs {
    /// On by default in this fork; More → "Classic NOOP interface" turns it off.
    static let enabledKey = "broop.uiEnabled"
}
