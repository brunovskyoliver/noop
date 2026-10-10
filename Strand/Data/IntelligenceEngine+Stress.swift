import Foundation
import WhoopStore
import StrandAnalytics

// IntelligenceEngine+Stress.swift — the analysis pass's Stress Monitor v2 block and the per-night Rest v2
// inputs (consistency, sleep stress). Runs once per pass, before pass 2, so Charge (which reads Rest) and
// the stored `sleep_performance` both see the same Rest v2 value for a night.
//
// Every day in the pass window is scored through `Repository.stressDayAnalysis` (the same funnel the
// screens use) against running 14-day aggregates, oldest → newest, so a re-scored early day feeds the
// baselines of the days after it. A day whose raw heart rate, sleep windows, workouts and prior
// aggregates are unchanged since the last pass is not re-read; its stored values are carried forward.
//
// Energy (`EnergyReservoir`) is integrated in the same loop from each day's stress analysis, starting at
// the previous day's stored end, so the level carries across midnight. A day whose stress inputs, start
// level and heart profile are unchanged keeps its stored Energy summary.

/// What the stress block hands the rest of the pass.
struct StressRestPassOutput {
    /// Contract keys + internal aggregates for every window day that has them.
    var points: [MetricPoint] = []
    /// Keys the persist step replaces over the window (so a day that lost a value loses the stale row).
    var replaceKeys: [String] = []
    /// Sleep Stress % by wake day, for Rest v2.
    var sleepStressByDay: [String: Double] = [:]
    /// Rest v2 consistency (0–1) by wake day.
    var consistencyByDay: [String: Double] = [:]
    /// Days scored from raw this pass vs carried forward (diagnostic).
    var scored = 0
    var reused = 0
}

extension IntelligenceEngine {

    /// Bump when the stress method changes, so every cached day is re-scored once.
    nonisolated static let stressAlgoVersion = "v2.2"
    nonisolated static let stressPassCacheKey = "intelligence.stressMonitor.dayKeys.v2"

    /// One-shot flag: the first launch with Stress Monitor v2 / Rest v2 re-scores the whole history once,
    /// so existing users get stored stress summaries and Rest v2 for every day that still has raw HR.
    /// ".sri": Rest v2 consistency moved to the Sleep Regularity engine, so history is re-scored once more.
    nonisolated static let stressRestBackfillFlagKey = "intelligence.stressRestV2.sri.backfill.done"

    /// Run the stress block. `sessions` must already hold this pass's freshly detected nights; `workouts`
    /// the window's workouts. Returns nil when cancelled part-way (the caller then writes nothing for it).
    static func stressRestPass(repo: Repository, windowDays: [String], sessions: [CachedSleepSession],
                               workouts: [WorkoutRow]) async -> StressRestPassOutput? {
        guard let oldest = windowDays.first, let newest = windowDays.last else { return StressRestPassOutput() }
        var out = StressRestPassOutput()
        out.replaceKeys = StressDaySummary.Key.all + Repository.stressAggregateKeys + EnergyDaySummary.Key.all

        // Rest v2 consistency for every window night: tonight vs the previous four days, through the same
        // epoch vector and pairing as the 7-day Sleep Regularity Index (naps and wake after onset included).
        out.consistencyByDay = SleepRegularity.restConsistency(
            days: windowDays,
            sessions: sessions.map { SleepRegularity.Session(start: $0.effectiveStartTs, end: $0.endTs, stagesJSON: $0.stagesJSON) })

        // Stored values over the window plus the 14 days before it.
        let lead = Repository.stressDayKey(offset: -StressMonitor.baselineWindowDays, from: oldest) ?? oldest
        var stored = await repo.stressStoredValues(keys: out.replaceKeys, from: lead, to: newest)
        var cache = (UserDefaults.standard.dictionary(forKey: stressPassCacheKey) as? [String: String]) ?? [:]
        var nextCache: [String: String] = [:]
        let energyCache = (UserDefaults.standard.dictionary(forKey: Repository.energyPassCacheKey) as? [String: String]) ?? [:]
        var nextEnergyCache: [String: String] = [:]
        var paceMark = DispatchTime.now().uptimeNanoseconds

        for day in windowDays {
            await RescoreBackgroundScheduler.paceIfBackgrounded(since: &paceMark)
            guard !Task.isCancelled else { return nil }
            guard let b = Repository.stressDayBounds(day) , b.end > b.start else { continue }
            let priors = Repository.stressPriors(before: day, stored: stored)
            let windows = Repository.stressWindows(dayStart: b.start, nextDayStart: b.next, dayEnd: b.end,
                                                   sessions: sessions, workouts: workouts)
            let readFrom = min(b.start, windows.mainSleep?.start ?? b.start)
            let fp = await repo.hrFingerprintUnion(from: readFrom, to: b.end - 1)
            guard Repository.hrUnionHasRows(fp) else {
                // Raw retention can expire before the derived history. Preserve the last stored
                // summary when its source samples are unavailable; this day cannot be re-scored.
                // Explicit history deletion removes these metric rows in its own transaction.
                var retained = (stored[day] ?? [:]).filter { out.replaceKeys.contains($0.key) }
                // A strap-off day still carries Energy: the empty analysis holds the level flat.
                if retained[EnergyDaySummary.Key.end] == nil,
                   let e = await energyDay(repo: repo, day: day, stored: stored, sessions: sessions,
                                           workouts: workouts, priors: priors, stress: nil) {
                    for p in e.storedPairs { retained[p.key] = p.value }
                    stored[day, default: [:]].merge(retained) { _, new in new }
                }
                for (key, value) in retained {
                    out.points.append(MetricPoint(day: day, key: key, value: value))
                }
                if let value = retained[StressDaySummary.Key.sleepStressPct] {
                    out.sleepStressByDay[day] = value
                }
                if !retained.isEmpty { out.reused += 1 }
                continue
            }
            let revision = await repo.stressInputRevision(from: readFrom, to: b.end - 1)
            let key = [stressAlgoVersion, revision, fp, "\(b.end)",
                       windows.sleepWindows.map { "\($0.start)-\($0.end)" }.joined(separator: ","),
                       windows.mainSleep.map { "\($0.start)-\($0.end)" } ?? "-",
                       windows.activity.map { "\($0.start)-\($0.end)" }.joined(separator: ","),
                       "\(priors.floors)",
                       priors.nights.map { $0.map { "\($0.hr),\($0.hrSpread),\($0.lnRMSSD ?? -1)" } ?? "-" }.joined(separator: ";")]
                .joined(separator: "|")
            var values: [String: Double] = [:]
            var fresh: StressMonitor.DayResult?
            if cache[day] == key, let prior = stored[day],
               prior.keys.contains(where: { StressDaySummary.Key.all.contains($0) || Repository.stressAggregateKeys.contains($0) }) {
                values = prior.filter { out.replaceKeys.contains($0.key) }
                out.reused += 1
            } else {
                guard let r = await repo.stressDayAnalysis(dayKey: day, sessions: sessions, workouts: workouts,
                                                           priors: priors) else { continue }
                for p in r.summary.storedPairs { values[p.key] = p.value }
                if let f = r.wakeFloorAggregate { values[StressMonitor.wakeFloorKey] = f }
                if let n = r.nightAggregate { for p in n.storedPairs { values[p.key] = p.value } }
                out.scored += 1
                fresh = r
            }
            nextCache[day] = key
            // Energy: keep the stored summary only when stress, start level and heart profile are unchanged.
            let prevEnd = Repository.stressDayKey(offset: -1, from: day).flatMap { stored[$0]?[EnergyDaySummary.Key.end] }
            let heart = await repo.energyHeart(dayKey: day)
            let energyKey = "\(key)|\(prevEnd.map { String(format: "%.2f", $0) } ?? "-")|\(heart.restingHR)|\(heart.maxHR)"
            if !(energyCache[day] == energyKey && fresh == nil && values[EnergyDaySummary.Key.end] != nil) {
                values = values.filter { !EnergyDaySummary.Key.all.contains($0.key) }
                if let e = await energyDay(repo: repo, day: day, stored: stored, sessions: sessions,
                                           workouts: workouts, priors: priors, stress: fresh) {
                    for p in e.storedPairs { values[p.key] = p.value }
                }
            }
            nextEnergyCache[day] = energyKey
            // The running aggregates the following days' baselines read.
            var merged = (stored[day] ?? [:]).filter { !out.replaceKeys.contains($0.key) }
            for (k, v) in values { merged[k] = v }
            stored[day] = merged
            for (k, v) in values { out.points.append(MetricPoint(day: day, key: k, value: v)) }
            if let s = values[StressDaySummary.Key.sleepStressPct] { out.sleepStressByDay[day] = s }
        }
        // Keep the cache to the window (it is rebuilt every pass).
        for (k, v) in cache where k < oldest { nextCache[k] = v }
        cache = nextCache.filter { $0.key >= (Repository.stressDayKey(offset: -40, from: newest) ?? oldest) }
        UserDefaults.standard.set(cache, forKey: stressPassCacheKey)
        UserDefaults.standard.set(nextEnergyCache, forKey: Repository.energyPassCacheKey)
        return out
    }

    /// One day's Energy summary from its stress analysis (read through the funnel when not passed) and the
    /// previous day's stored end in the pass's running `stored`. nil while calibrating.
    private static func energyDay(repo: Repository, day: String, stored: [String: [String: Double]],
                                  sessions: [CachedSleepSession], workouts: [WorkoutRow],
                                  priors: (floors: [Double?], nights: [StressMonitor.NightAggregate?]),
                                  stress: StressMonitor.DayResult?) async -> EnergyDaySummary? {
        let prevEnd = Repository.stressDayKey(offset: -1, from: day).flatMap { stored[$0]?[EnergyDaySummary.Key.end] }
        var r = stress
        if r == nil {
            r = await repo.stressDayAnalysis(dayKey: day, sessions: sessions, workouts: workouts, priors: priors)
        }
        guard let r else { return nil }
        return EnergyReservoir.day(r, startLevel: prevEnd, heart: await repo.energyHeart(dayKey: day))?.summary
    }

    /// The Rest (0–100) a night scores in this pass: Rest v2 with the pass's personalised need, the
    /// night's consistency and Sleep Stress when Rest v2 is on, else the legacy composite. Charge's sleep
    /// term and the stored `sleep_performance` both read this.
    nonisolated static func passRest(_ d: DailyMetric, v2: Bool, needHours: Double,
                                     consistency: Double?, sleepStressPct: Double?) -> Double? {
        guard v2 else { return AnalyticsEngine.Rest.composite(daily: d) }
        return AnalyticsEngine.RestV2.composite(daily: d, needHours: needHours, consistency: consistency,
                                                sleepStressPct: sleepStressPct)
    }

    /// The stored Rest v2 parts for a night (only written when Rest v2 is on).
    nonisolated static func restPartPoints(_ d: DailyMetric, needHours: Double, consistency: Double?) -> [MetricPoint] {
        var pts: [MetricPoint] = []
        if let tst = d.totalSleepMin, tst > 0, needHours > 0 {
            pts.append(MetricPoint(day: d.day, key: RestScoringPrefs.hoursVsNeedKey,
                                   value: ((tst / (needHours * 60)) * 1000).rounded() / 10))
        }
        if let c = consistency {
            pts.append(MetricPoint(day: d.day, key: RestScoringPrefs.consistencyKey, value: (c * 1000).rounded() / 10))
        }
        return pts
    }

    /// One-shot history backfill for Stress Monitor v2 and Rest v2 (runs `analyzeRecent` over the full
    /// history once). Mirrors `runEffortRescoreIfNeeded`.
    func runStressRestBackfillIfNeeded(historyDays: Int = 4000) async {
        guard !UserDefaults.standard.bool(forKey: Self.stressRestBackfillFlagKey) else { return }
        await analyzeRecent(maxDays: historyDays)
        // Completion is recorded only at the successful end of the full-history pass.
    }

    /// Settings → Scoring toggled Rest v2: re-score the whole history so every stored `sleep_performance`
    /// and every Charge that reads it move together.
    /// Re-arms the one-shot backfill flag first, so a pass that could not run now (another pass holding
    /// the lock) is completed on the next launch instead of leaving history in the old mode.
    func rescoreForRestModeChange(historyDays: Int = 4000) async {
        UserDefaults.standard.set(false, forKey: Self.stressRestBackfillFlagKey)
        await runStressRestBackfillIfNeeded(historyDays: historyDays)
    }
}
