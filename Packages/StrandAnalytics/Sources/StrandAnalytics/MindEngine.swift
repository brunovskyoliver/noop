import Foundation

// MindEngine.swift — the "Mind" section's long-horizon stress readouts, built from the per-day stress
// summaries the analysis pass stores (`StressDaySummary` keys) plus the nightly Rest and Charge scores.
//
// There is deliberately no "mental age" here. No wearable has a credible one (the WHOOP Healthspan white
// paper leaves mental well-being out of WHOOP Age; the only brain-age products read EEG). What HR and HRV
// can honestly support is a picture of how much stress load a body has been carrying and how well it has
// been recovering from it, which is what these two engines report:
//
//   • Resilience (14 days): the balance of daytime stress load against daytime and overnight recovery,
//     in five levels. Modelled on Oura's Resilience, which Oura documents only as "a 14-day rolling balance
//     of daytime stress, daytime recovery and nighttime recovery" mapped to Limited…Exceptional
//     (support.ouraring.com/hc/en-us/articles/25358829055251). The component scales and weights below are
//     NOOP's own and are documented next to each constant.
//   • Cumulative Stress (31 days): a rolling load index over a month, needing 21 days of data, modelled on
//     Oura's Cumulative Stress (Nov 2025; 31-day window, ≥21 days; validated by Oura against the Perceived
//     Stress Scale and the Copenhagen Burnout Inventory, n=151). Oura's inputs (sleep continuity, HR stress
//     response, micromotion, temperature) are not all available here, so NOOP's version uses the three load
//     signals it does have: waking time in high stress, sleep stress, and the Charge shortfall.
//
// Both are wellness trends, not assessments of mental health, and the UI must say so.
//
// Pure and deterministic: no database, no calendar, no time zone. Days are "yyyy-MM-dd" strings.
// iOS-only fork engine; there is intentionally no Kotlin twin.

/// One local day of Mind inputs. Every field is optional: a day with no strap wear has only the day key.
public struct MindDay: Equatable, Sendable {
    public var day: String
    /// Waking, non-activity scored minutes in the HIGH stress band (≥ 2 on the 0–3 scale).
    public var highStressMin: Double?
    /// Waking, non-activity scored minutes in the LOW stress band (< 1): the "restorative" daytime time.
    public var lowStressMin: Double?
    /// Waking, non-activity scored minutes in total (the coverage the two figures above are shares of).
    public var scoredMin: Double?
    /// Share (0–100) of the main sleep's scored time spent in high stress.
    public var sleepStressPct: Double?
    /// Rest (sleep performance) 0–100.
    public var rest: Double?
    /// Charge (recovery) 0–100.
    public var charge: Double?

    public init(day: String, highStressMin: Double? = nil, lowStressMin: Double? = nil,
                scoredMin: Double? = nil, sleepStressPct: Double? = nil,
                rest: Double? = nil, charge: Double? = nil) {
        self.day = day; self.highStressMin = highStressMin; self.lowStressMin = lowStressMin
        self.scoredMin = scoredMin; self.sleepStressPct = sleepStressPct
        self.rest = rest; self.charge = charge
    }

    /// Enough waking stress coverage to count the day toward a daytime share.
    var hasDaytimeStress: Bool { (scoredMin ?? 0) >= MindEngine.minScoredMinutesPerDay }
}

/// Direction of a rolling Mind score compared with its value a week earlier.
public enum MindTrend: String, Equatable, Sendable {
    case improving, steady, worsening
}

public enum MindEngine {
    /// A day needs at least this many scored waking minutes (2 h) before its high/low shares are trusted.
    /// Below it one tense meeting would read as a stressful day.
    public static let minScoredMinutesPerDay = 120.0
    /// Trends compare the latest value with the value this many days earlier.
    public static let trendLookbackDays = 7

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Days since 1970-01-01 for "yyyy-MM-dd" (shared integer calendar math, see VitalityWindow).
    static func epoch(_ s: String) -> Int? { VitalityEngine.epochDay(s) }

    /// The days whose date falls in the `length` days ending at `asOf` (inclusive), oldest first.
    static func window(_ days: [MindDay], asOf: String, length: Int) -> [MindDay] {
        guard let end = epoch(asOf) else { return [] }
        return days.compactMap { d -> (Int, MindDay)? in epoch(d.day).map { ($0, d) } }
            .filter { $0.0 <= end && $0.0 > end - length }
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    /// The "yyyy-MM-dd" string `offset` days after `day` (negative = before). Integer civil-from-days
    /// (Hinnant), so it needs no calendar either.
    static func shift(_ day: String, by offset: Int) -> String? {
        guard let e = epoch(day) else { return nil }
        let z = e + offset + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func trend(now: Double?, before: Double?, threshold: Double, higherIsBetter: Bool) -> MindTrend? {
        guard let now, let before else { return nil }
        let delta = higherIsBetter ? now - before : before - now
        if delta > threshold { return .improving }
        if delta < -threshold { return .worsening }
        return .steady
    }
}

// MARK: - Resilience

public enum ResilienceEngine {

    public enum Level: Int, CaseIterable, Comparable, Sendable {
        case limited = 0, adequate, solid, strong, exceptional
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Result: Equatable, Sendable {
        /// 0–100 balance score (higher = more resilient).
        public let score: Double
        public let level: Level
        /// Share (0–1) of scored waking time spent in high stress over the window.
        public let highShare: Double
        /// Share (0–1) of scored waking time spent in low stress over the window.
        public let lowShare: Double
        /// Mean overnight recovery (0–1): the mean of each night's Rest and Charge, nil without nights.
        public let nightRecovery: Double?
        /// The three component scores (0–1) the balance is built from; nil when a component had no data.
        public let loadComponent: Double
        public let daytimeRecoveryComponent: Double
        public let nightComponent: Double?
        /// Days in the window with enough waking stress coverage, and nights with Rest or Charge.
        public let stressDays: Int
        public let nights: Int
        /// Change against the value `MindEngine.trendLookbackDays` earlier; nil when that value is missing.
        public let trend: MindTrend?
    }

    /// Oura's window.
    public static let windowDays = 14
    /// Cold start: half the window must carry daytime stress before a level is shown.
    public static let minStressDays = 7
    /// Nights are optional (renormalised away when absent), but a handful are needed to count.
    public static let minNights = 4

    /// High-stress share of waking time at which the load component reaches zero. WHOOP's own guidance is
    /// that most waking time should sit in the low and medium bands; a third of the day in high stress is
    /// treated as no remaining headroom.
    public static let highShareCeiling = 0.35
    /// Low-stress share of waking time that earns full daytime-recovery credit (half the waking day calm).
    public static let lowShareTarget = 0.50
    /// Overnight recovery is mapped linearly from 0.30 (a red Charge / poor Rest) to 0.85 (a strong night).
    public static let nightFloor = 0.30, nightCeiling = 0.85

    /// Component weights: load and daytime recovery together are the daytime balance, overnight recovery
    /// the other side. Missing components are renormalised away.
    public static let wLoad = 0.30, wDaytime = 0.30, wNight = 0.40

    /// Level floors on the 0–100 score: Limited < 30 ≤ Adequate < 45 ≤ Solid < 60 ≤ Strong < 75 ≤ Exceptional.
    public static let levelFloors: [(Level, Double)] = [(.exceptional, 75), (.strong, 60), (.solid, 45), (.adequate, 30)]
    /// A score change of more than this many points over a week is a trend.
    public static let trendThreshold = 4.0

    public static func level(for score: Double) -> Level {
        for (level, floor) in levelFloors where score >= floor { return level }
        return .limited
    }

    /// Resilience over the 14 days ending at `asOf`, or nil during the cold start.
    public static func compute(days: [MindDay], asOf: String) -> Result? {
        guard let now = core(days: days, asOf: asOf) else { return nil }
        let before = MindEngine.shift(asOf, by: -MindEngine.trendLookbackDays)
            .flatMap { core(days: days, asOf: $0) }
        let t = MindEngine.trend(now: now.score, before: before?.score, threshold: trendThreshold,
                                 higherIsBetter: true)
        return Result(score: now.score, level: now.level, highShare: now.highShare, lowShare: now.lowShare,
                      nightRecovery: now.nightRecovery, loadComponent: now.loadComponent,
                      daytimeRecoveryComponent: now.daytimeRecoveryComponent,
                      nightComponent: now.nightComponent, stressDays: now.stressDays,
                      nights: now.nights, trend: t)
    }

    /// The rolling score for each of the last `span` days ending at `asOf`, oldest first, skipping days
    /// still in the cold start. Feeds the trend chart.
    public static func history(days: [MindDay], asOf: String, span: Int) -> [(day: String, score: Double)] {
        (0..<max(0, span)).reversed().compactMap { back -> (day: String, score: Double)? in
            guard let d = MindEngine.shift(asOf, by: -back), let r = core(days: days, asOf: d) else { return nil }
            return (d, r.score)
        }
    }

    static func core(days: [MindDay], asOf: String) -> Result? {
        let win = MindEngine.window(days, asOf: asOf, length: windowDays)
        let stress = win.filter { $0.hasDaytimeStress }
        guard stress.count >= minStressDays else { return nil }
        let scored = stress.reduce(0) { $0 + ($1.scoredMin ?? 0) }
        guard scored > 0 else { return nil }
        let high = stress.reduce(0) { $0 + max(0, $1.highStressMin ?? 0) } / scored
        let low = stress.reduce(0) { $0 + max(0, $1.lowStressMin ?? 0) } / scored

        let nightValues = win.compactMap { d -> Double? in
            let parts = [d.rest, d.charge].compactMap { $0 }.map { MindEngine.clamp01($0 / 100) }
            return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
        }
        let nightMean = nightValues.count >= minNights
            ? nightValues.reduce(0, +) / Double(nightValues.count) : nil

        let load = 1 - MindEngine.clamp01(high / highShareCeiling)
        let daytime = MindEngine.clamp01(low / lowShareTarget)
        let night = nightMean.map { MindEngine.clamp01(($0 - nightFloor) / (nightCeiling - nightFloor)) }

        var num = wLoad * load + wDaytime * daytime
        var den = wLoad + wDaytime
        if let night { num += wNight * night; den += wNight }
        let score = 100 * num / den
        return Result(score: score, level: level(for: score), highShare: high, lowShare: low,
                      nightRecovery: nightMean, loadComponent: load, daytimeRecoveryComponent: daytime,
                      nightComponent: night, stressDays: stress.count, nights: nightValues.count, trend: nil)
    }
}

// MARK: - Cumulative Stress

public enum CumulativeStressEngine {

    public enum Level: Int, CaseIterable, Comparable, Sendable {
        case low = 0, moderate, elevated, high
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Result: Equatable, Sendable {
        /// 0–100 load index (higher = more accumulated stress).
        public let score: Double
        public let level: Level
        /// Days in the window that carried a stress-derived load value.
        public let days: Int
        /// Mean of each signal across the window (0–1 load units), nil when that signal never appeared.
        public let daytimeLoad: Double?
        public let sleepLoad: Double?
        public let recoveryLoad: Double?
        /// improving = the load fell over the last week; worsening = it rose.
        public let trend: MindTrend?
    }

    /// Oura's window and minimum.
    public static let windowDays = 31
    public static let minDays = 21

    /// Each signal is mapped to 0–1 "load units" before averaging, so no single one dominates by scale:
    /// • daytime: high-stress share of waking time, full load at 40 %;
    /// • sleep: sleep-stress share of the main sleep, full load at 40 %;
    /// • recovery: Charge shortfall, 0 at Charge ≥ 70 (green), full load at Charge ≤ 20.
    public static let daytimeCeiling = 0.40
    public static let sleepCeiling = 40.0
    public static let chargeNoLoad = 70.0, chargeFullLoad = 20.0
    /// Weights: daytime stress carries half, sleep stress and the Charge shortfall a quarter each.
    public static let wDaytime = 0.50, wSleep = 0.25, wRecovery = 0.25

    /// Level floors on the 0–100 index: Low < 20 ≤ Moderate < 40 ≤ Elevated < 60 ≤ High.
    public static let levelFloors: [(Level, Double)] = [(.high, 60), (.elevated, 40), (.moderate, 20)]
    public static let trendThreshold = 3.0

    public static func level(for score: Double) -> Level {
        for (level, floor) in levelFloors where score >= floor { return level }
        return .low
    }

    /// One day's load (0–1) and its parts, or nil when the day has no stress-derived signal. Charge alone
    /// does not make a stress day: without daytime or sleep stress the day is skipped, not guessed.
    static func dayLoad(_ d: MindDay) -> (load: Double, daytime: Double?, sleep: Double?, recovery: Double?)? {
        let daytime: Double? = d.hasDaytimeStress
            ? MindEngine.clamp01((max(0, d.highStressMin ?? 0) / (d.scoredMin ?? 1)) / daytimeCeiling) : nil
        let sleep = d.sleepStressPct.map { MindEngine.clamp01($0 / sleepCeiling) }
        guard daytime != nil || sleep != nil else { return nil }
        let recovery = d.charge.map { MindEngine.clamp01((chargeNoLoad - $0) / (chargeNoLoad - chargeFullLoad)) }
        var num = 0.0, den = 0.0
        if let daytime { num += wDaytime * daytime; den += wDaytime }
        if let sleep { num += wSleep * sleep; den += wSleep }
        if let recovery { num += wRecovery * recovery; den += wRecovery }
        return (num / den, daytime, sleep, recovery)
    }

    public static func compute(days: [MindDay], asOf: String) -> Result? {
        guard let now = core(days: days, asOf: asOf) else { return nil }
        let before = MindEngine.shift(asOf, by: -MindEngine.trendLookbackDays)
            .flatMap { core(days: days, asOf: $0) }
        let t = MindEngine.trend(now: now.score, before: before?.score, threshold: trendThreshold,
                                 higherIsBetter: false)
        return Result(score: now.score, level: now.level, days: now.days, daytimeLoad: now.daytimeLoad,
                      sleepLoad: now.sleepLoad, recoveryLoad: now.recoveryLoad, trend: t)
    }

    public static func history(days: [MindDay], asOf: String, span: Int) -> [(day: String, score: Double)] {
        (0..<max(0, span)).reversed().compactMap { back -> (day: String, score: Double)? in
            guard let d = MindEngine.shift(asOf, by: -back), let r = core(days: days, asOf: d) else { return nil }
            return (d, r.score)
        }
    }

    static func core(days: [MindDay], asOf: String) -> Result? {
        let loads = MindEngine.window(days, asOf: asOf, length: windowDays).compactMap(dayLoad)
        guard loads.count >= minDays else { return nil }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let score = 100 * (mean(loads.map { $0.load }) ?? 0)
        return Result(score: score, level: level(for: score), days: loads.count,
                      daytimeLoad: mean(loads.compactMap { $0.daytime }),
                      sleepLoad: mean(loads.compactMap { $0.sleep }),
                      recoveryLoad: mean(loads.compactMap { $0.recovery }), trend: nil)
    }
}
