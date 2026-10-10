import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// Repository+Stress.swift — the ONE funnel for Stress Monitor v2 and for the Rest score.
//
// STRESS. `stressDayAnalysis(dayKey:…)` builds a day's `StressMonitor.DayInput` (raw HR / R-R / gravity,
// sleep windows, the main sleep, workouts) and scores it against the stored 14-day aggregates. The analysis
// pass (IntelligenceEngine) calls it to persist the per-day summary; the Stress screen, Home and Health call
// it (memoised) to draw today. Stored days are read back through `stressDaySummaries(days:)`.
//
// STORED CONTRACT (metricSeries, computed "-noop" source; read with
// `exploreSeries(key:, source: "my-whoop")`, which unions imported and computed). Keys per LOCAL calendar
// day; "waking" = 5-minute epochs that are not sleep and not masked as activity and had enough HR:
//   stress_day          mean 0–3 level over waking scored time
//   stress_high_min     waking minutes with level ≥ 2.0
//   stress_med_min      waking minutes with 1.0 ≤ level < 2.0
//   stress_low_min      waking minutes with level < 1.0
//   stress_scored_min   waking scored minutes (coverage); the four waking-minute keys and stress_day are
//                       written together, only when ≥ 30 minutes were scored
//   sleep_stress_pct    0–100 share of the MAIN sleep ending on that day spent in HIGH stress
// The imported `stress` key (WHOOP export) keeps its meaning and is never written here.
// Internal aggregates stored beside them (not for display): stress_wake_floor_hr, stress_night_hr,
// stress_night_hr_sd, stress_night_lnrmssd, stress_night_lnrmssd_sd.
//
// REST. `restScore(for:)` is the single Rest resolver every screen reads: the imported WHOOP figure, else
// the stored computed `sleep_performance` (which the analysis pass writes with Rest v2 when enabled), else
// a same-formula fallback from the day row for a night the pass has not reached yet.

/// Settings → Scoring switch for Rest v2 (WHOOP's four-part Sleep Performance). Default ON.
enum RestScoringPrefs {
    static let v2Key = "noop.restV2Enabled"
    static var v2Enabled: Bool { UserDefaults.standard.object(forKey: v2Key) as? Bool ?? true }

    /// Rest v2 parts the analysis pass stores beside `sleep_performance`, so the Sleep screen's
    /// contributors show exactly what the score used. Uncapped hours-vs-need % and 0–100 consistency.
    static let hoursVsNeedKey = "rest_hours_vs_need_pct"
    static let consistencyKey = "rest_consistency_pct"
}

/// The computed (on-device) sleep figures for one day, loaded on every `refresh()`.
struct ComputedSleepFigures: Equatable {
    var restPct: Double?
    var hoursVsNeedPct: Double?
    var consistencyPct: Double?
    var sleepStressPct: Double?
}

/// Sleep windows, the main sleep and workouts for one local day, resolved from the same lists by the
/// analysis pass and the screens.
struct StressDayWindows: Equatable {
    let sleepWindows: [StressMonitor.Interval]
    let mainSleep: StressMonitor.Interval?
    let activity: [StressMonitor.Interval]
}

/// Memo of the last few day analyses, keyed by day with an input signature.
@MainActor private var stressDayMemo: [String: (sig: String, result: StressMonitor.DayResult)] = [:]

extension Repository {

    /// A main sleep is the longest sleep ending on the day, and at least this long (shorter is a nap).
    nonisolated static let stressMainSleepMinSeconds = 3 * 3600

    // MARK: - Windows (pure)

    /// The main sleep that ends in `[dayStart, nextDayStart)`: the longest such session ≥ 3 h.
    nonisolated static func mainSleep(dayStart: Int, nextDayStart: Int,
                                      sessions: [CachedSleepSession]) -> StressMonitor.Interval? {
        sessions
            .filter { $0.endTs >= dayStart && $0.endTs < nextDayStart
                && $0.endTs - $0.effectiveStartTs >= stressMainSleepMinSeconds }
            .max { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) }
            .map { StressMonitor.Interval(start: $0.effectiveStartTs, end: $0.endTs) }
    }

    nonisolated static func stressWindows(dayStart: Int, nextDayStart: Int, dayEnd: Int,
                                          sessions: [CachedSleepSession],
                                          workouts: [WorkoutRow]) -> StressDayWindows {
        let main = mainSleep(dayStart: dayStart, nextDayStart: nextDayStart, sessions: sessions)
        let lo = min(dayStart, main?.start ?? dayStart)
        let sleeps = sessions
            .filter { $0.endTs > lo && $0.effectiveStartTs < dayEnd && $0.endTs > $0.effectiveStartTs }
            .map { StressMonitor.Interval(start: $0.effectiveStartTs, end: $0.endTs) }
            .sorted { $0.start < $1.start }
        let acts = workouts
            .filter { $0.endTs > dayStart && $0.startTs < dayEnd && $0.endTs > $0.startTs }
            .map { StressMonitor.Interval(start: $0.startTs, end: $0.endTs) }
            .sorted { $0.start < $1.start }
        return StressDayWindows(sleepWindows: sleeps, mainSleep: main, activity: acts)
    }

    // MARK: - Day bounds

    /// Local midnight of `dayKey`, the next local midnight, and the exclusive end (capped at `now`).
    nonisolated static func stressDayBounds(_ dayKey: String, now: Date = Date())
        -> (start: Int, next: Int, end: Int)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dayKey) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: d)
        guard let next = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let s = Int(start.timeIntervalSince1970), n = Int(next.timeIntervalSince1970)
        return (s, n, min(n, Int(now.timeIntervalSince1970)))
    }

    nonisolated static func stressDayKey(offset: Int, from dayKey: String) -> String? {
        guard let b = stressDayBounds(dayKey, now: .distantFuture) else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(b.start + 12 * 3600))
        guard let shifted = Calendar.current.date(byAdding: .day, value: offset, to: d) else { return nil }
        return localDayKey(shifted)
    }

    // MARK: - Stored aggregates

    /// Stored values for `keys` over `[from, to]`, computed source first (it wins), then imported. Day →
    /// key → value.
    func stressStoredValues(keys: [String], from: String, to: String) async -> [String: [String: Double]] {
        guard let store = await storeHandle() else { return [:] }
        var out: [String: [String: Double]] = [:]
        for key in keys {
            for id in importedReadIds.reversed() + computedReadIds.reversed() {
                for p in (try? await store.metricSeries(deviceId: id, key: key, from: from, to: to)) ?? [] {
                    out[p.day, default: [:]][key] = p.value
                }
            }
        }
        return out
    }

    nonisolated static let stressAggregateKeys: [String] = [
        StressMonitor.wakeFloorKey,
        StressMonitor.NightAggregate.Key.hr, StressMonitor.NightAggregate.Key.hrSpread,
        StressMonitor.NightAggregate.Key.lnRMSSD, StressMonitor.NightAggregate.Key.lnRMSSDSpread,
    ]

    /// The 14 prior days' aggregates (oldest → newest) from the stored values.
    nonisolated static func stressPriors(before dayKey: String,
                                         stored: [String: [String: Double]])
        -> (floors: [Double?], nights: [StressMonitor.NightAggregate?]) {
        var floors: [Double?] = [], nights: [StressMonitor.NightAggregate?] = []
        for back in stride(from: StressMonitor.baselineWindowDays, through: 1, by: -1) {
            guard let k = stressDayKey(offset: -back, from: dayKey) else { continue }
            let v = stored[k] ?? [:]
            floors.append(v[StressMonitor.wakeFloorKey])
            nights.append(StressMonitor.NightAggregate.fromStored(v))
        }
        return (floors, nights)
    }

    /// Includes HR, R-R and motion writes, including corrected records with unchanged timestamps.
    func stressInputRevision(from: Int, to: Int) async -> String {
        guard let store = await storeHandle() else { return UUID().uuidString }
        var revisions: [String] = []
        let devices = (try? DeviceRegistryStore(dbQueue: store.registryWriter).all()) ?? []
        let ids = Self.rawWhoopSourceIds(activeDeviceId: deviceId, registeredWhoopIds: devices.filter {
            $0.brand.caseInsensitiveCompare("WHOOP") == .orderedSame
        }.map(\.id))
        for id in ids {
            revisions.append((try? await store.analysisWindowRevision(deviceId: id, from: from, to: to)) ?? UUID().uuidString)
        }
        return revisions.joined(separator: "|")
    }

    // MARK: - Day analysis (the funnel)

    /// Score one local day. The analysis pass passes its own session / workout lists and running priors;
    /// a screen passes nothing and the same lists are read from the store. Memoised on the inputs.
    func stressDayAnalysis(dayKey: String,
                           sessions: [CachedSleepSession]? = nil,
                           workouts: [WorkoutRow]? = nil,
                           priors: (floors: [Double?], nights: [StressMonitor.NightAggregate?])? = nil,
                           now: Date = Date()) async -> StressMonitor.DayResult? {
        guard let b = Self.stressDayBounds(dayKey, now: now), b.end > b.start else { return nil }
        let memoKey = "\(deviceId)|\(dayKey)"
        #if DEBUG
        if AppleDemoSeeder.requested, let demo = await runUnescalated({ AppleDemoSeeder.stressDemoDay(dayKey: dayKey, now: now) }) {
            stressDayMemo[memoKey] = ("demo", demo)
            return demo
        }
        #endif
        let daysAgo = max(0, Int((now.timeIntervalSince1970 - Double(b.start)) / 86_400))
        let sess: [CachedSleepSession]
        if let sessions { sess = sessions } else { sess = await allSleepSessions(days: daysAgo + 3) }
        let wos: [WorkoutRow]
        if let workouts { wos = workouts } else { wos = await workoutRowsUnreconciled(days: daysAgo + 3) }
        let windows = Self.stressWindows(dayStart: b.start, nextDayStart: b.next, dayEnd: b.end,
                                         sessions: sess, workouts: wos)
        let pri: (floors: [Double?], nights: [StressMonitor.NightAggregate?])
        if let priors { pri = priors } else {
            let from = Self.stressDayKey(offset: -StressMonitor.baselineWindowDays, from: dayKey) ?? dayKey
            let to = Self.stressDayKey(offset: -1, from: dayKey) ?? dayKey
            pri = Self.stressPriors(before: dayKey,
                                    stored: await stressStoredValues(keys: Self.stressAggregateKeys, from: from, to: to))
        }
        let readFrom = min(b.start, windows.mainSleep?.start ?? b.start)
        // The per-id union witness (`hrFingerprintUnion`), not a summed count: a window whose composition
        // changes without its totals changing must still invalidate the memo.
        let fp = await hrFingerprintUnion(from: readFrom, to: b.end - 1)
        guard !fp.isEmpty else { return nil }
        let revision = await stressInputRevision(from: readFrom, to: b.end - 1)
        let sig = "\(revision)|\(refreshSeq)|\(deviceId)|\(fp)|\(b.end)|\(windows.sleepWindows.map { "\($0.start)-\($0.end)" })"
            + "|\(windows.mainSleep.map { "\($0.start)-\($0.end)" } ?? "-")"
            + "|\(windows.activity.map { "\($0.start)-\($0.end)" })|\(pri.floors)|\(pri.nights.map { $0.map { "\($0.hr),\($0.hrSpread),\($0.lnRMSSD ?? -1)" } ?? "-" })"
        if let m = stressDayMemo[memoKey], m.sig == sig { return m.result }
        guard Self.hrUnionHasRows(fp) else {
            let empty = StressMonitor.analyzeDay(
                StressMonitor.DayInput(day: dayKey, dayStart: b.start, dayEnd: b.end,
                                       tzOffsetSeconds: TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(b.start))),
                                       hr: [], rr: [], gravity: [], sleepWindows: windows.sleepWindows,
                                       mainSleep: windows.mainSleep, activityWindows: windows.activity),
                priorFloors: pri.floors, priorNights: pri.nights)
            stressDayMemo[memoKey] = (sig, empty)
            return empty
        }
        let hr = await hrSamples(from: readFrom, to: b.end - 1, limit: 250_000)
        let rr = await rrIntervals(from: readFrom, to: b.end - 1, limit: 250_000)
        let gravity = await gravitySamplesUnion(from: b.start, to: b.end - 1, limit: 250_000)
        let tz = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(b.start + 12 * 3600)))
        let input = StressMonitor.DayInput(day: dayKey, dayStart: b.start, dayEnd: b.end, tzOffsetSeconds: tz,
                                           hr: hr, rr: rr, gravity: gravity,
                                           sleepWindows: windows.sleepWindows, mainSleep: windows.mainSleep,
                                           activityWindows: windows.activity)
        let result = await runUnescalated {
            StressMonitor.analyzeDay(input, priorFloors: pri.floors, priorNights: pri.nights)
        }
        if stressDayMemo.count > 12 { stressDayMemo.removeAll() }
        stressDayMemo[memoKey] = (sig, result)
        return result
    }

    /// Whether a `hrFingerprintUnion` witness ("id:count:maxTs|…") saw any heart rate under any id.
    nonisolated static func hrUnionHasRows(_ witness: String) -> Bool {
        witness.split(separator: "|").contains { part in
            part.split(separator: ":").dropLast().last.map { $0 != "0" } ?? false
        }
    }

    /// Today's analysis (the Stress screen, the Home tile and the Health card all read this one).
    func stressToday(now: Date = Date()) async -> StressMonitor.DayResult? {
        await stressDayAnalysis(dayKey: Self.localDayKey(now), now: now)
    }

    // MARK: - Summaries (the resolver other features read)

    /// Per-day Stress Monitor summaries for the last `days` days, oldest → newest: the stored contract
    /// keys, with today's summary replaced by the fresh one when today has already been analysed this
    /// session (the same function the pass stores with, so the two only differ by how recently it ran).
    func stressDaySummaries(days: Int) async -> [StressDaySummary] {
        var byDay: [String: [String: Double]] = [:]
        for key in StressDaySummary.Key.all {
            for p in await exploreSeries(key: key, source: Self.whoopSource, days: days) {
                byDay[p.day, default: [:]][key] = p.value
            }
        }
        var out = byDay.compactMap { StressDaySummary.fromStored(day: $0.key, values: $0.value) }
        let todayKey = Self.localDayKey(Date())
        if let fresh = stressDayMemo["\(deviceId)|\(todayKey)"]?.result.summary {
            out.removeAll { $0.day == todayKey }
            if fresh.hasWaking || fresh.sleepStressPct != nil { out.append(fresh) }
        }
        return out.sorted { $0.day < $1.day }
    }

    // MARK: - Rest resolver

    /// Load the computed sleep figures for `[from, to]` (called by `refresh()`).
    func loadComputedSleepFigures(store: WhoopStore, from: String, to: String) async -> [String: ComputedSleepFigures] {
        var out: [String: ComputedSleepFigures] = [:]
        let keys = ["sleep_performance", RestScoringPrefs.hoursVsNeedKey, RestScoringPrefs.consistencyKey,
                    StressDaySummary.Key.sleepStressPct]
        for key in keys {
            for id in computedReadIds.reversed() {
                for p in (try? await store.metricSeries(deviceId: id, key: key, from: from, to: to)) ?? [] {
                    var f = out[p.day] ?? ComputedSleepFigures()
                    switch key {
                    case "sleep_performance": f.restPct = p.value
                    case RestScoringPrefs.hoursVsNeedKey: f.hoursVsNeedPct = p.value
                    case RestScoringPrefs.consistencyKey: f.consistencyPct = p.value
                    default: f.sleepStressPct = p.value
                    }
                    out[p.day] = f
                }
            }
        }
        return out
    }

    /// Rest (0–100) for a day row when nothing is stored for it yet: Rest v2 from the row's own totals
    /// (default need, consistency and sleep stress not known, so renormalised away), or the legacy
    /// composite when Rest v2 is off.
    nonisolated static func restFallback(daily d: DailyMetric, v2: Bool = RestScoringPrefs.v2Enabled) -> Double? {
        v2 ? AnalyticsEngine.RestV2.composite(daily: d) : AnalyticsEngine.Rest.composite(daily: d)
    }

    /// THE Rest resolver: imported WHOOP figure → stored computed `sleep_performance` → fallback.
    nonisolated static func resolveRest(daily d: DailyMetric, imported: ImportedSleepFigures?,
                                        computed: ComputedSleepFigures?,
                                        v2: Bool = RestScoringPrefs.v2Enabled) -> Double? {
        if let p = imported?.performancePct { return p }
        if let c = computed?.restPct { return c }
        return restFallback(daily: d, v2: v2)
    }

    /// Rest for a day row, as every screen shows it.
    func restScore(for d: DailyMetric) -> Double? {
        Self.resolveRest(daily: d, imported: importedSleep[d.day], computed: computedSleepFigures[d.day])
    }

    /// The Rest v2 parts for a day as stored by the pass (nil fields = not stored / not measured). Only
    /// meaningful while Rest v2 is on.
    func restParts(dayKey: String) -> ComputedSleepFigures? {
        RestScoringPrefs.v2Enabled ? computedSleepFigures[dayKey] : nil
    }
}
