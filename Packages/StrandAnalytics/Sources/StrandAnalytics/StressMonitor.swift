import Foundation
import WhoopProtocol

// StressMonitor.swift — Stress Monitor v2: a 0–3 stress read at a 5-minute grain over a whole local
// calendar day, scored against the wearer's own 14-day baselines, plus the per-night Sleep Stress share.
//
// WHAT WHOOP PUBLISHES (support article + 2023 launch release, see the feature-gap notes §3.1):
//   - a 0–3 score "by measuring your heart rate and HRV and comparing that to your baseline",
//   - the baseline is "your personalized baseline from the past 14 days",
//   - "any motion is taken into account to help distinguish known stressors, like exercise",
//   - bands 0–1 low, 1–2 medium, 2–3 high; good sleep usually sits below ~0.5,
//   - Sleep Stress = time in high stress during the sleep period (one of the four 2025 Sleep
//     Performance components).
// The function itself is not published. This file is NOOP's reconstruction, stated in full below so a
// reader can check every number.
//
// ── WAKING EPOCHS (non-sleep, not masked as activity) ─────────────────────────────────────────────
// Reference: the personal calm-awake HR floor, i.e. the MEDIAN over the previous 14 local days of each
// day's `DaytimeStress.dayDaytimeAggregate(...).hr` (the 10th percentile of that day's waking-hour mean
// HRs). That per-day aggregate is the quantity behind `DaytimeStress.baselineRelativeHighMarginBPM`'s
// validation (26 days vs an Oura stress reference, HR-only, r≈0.6), reused verbatim so the reference is
// the validated one. The window is a literal 14 days, not an EWMA: WHOOP says "past 14 days".
// Mapping: level = 3 / (1 + e^−x), x = ln2 · (2·Δ/M − 1), Δ = epoch mean HR − floor, M = 15 bpm.
//   Δ = 0 (at the calm floor)      → 1.0 (top of LOW)          — design anchor, not validated
//   Δ = M/2                        → 1.5
//   Δ = M = 15 bpm                 → 2.0 (bottom of HIGH)      — the validated high margin
// HR only. Daytime RMSSD stays out of the waking score (`DaytimeStress.daytimeRMSSDScoringEnabled` is
// false: wrist RMSSD while awake is artifact-dominated, ~40→430 ms hour to hour). That honesty rule is
// kept as is; nothing here re-validates it.
//
// ── SLEEP EPOCHS ───────────────────────────────────────────────────────────────────────────────────
// Reference: the personal NOCTURNAL baseline. Each main sleep reduces to a `NightAggregate`: the median
// and robust spread (1.4826·MAD) of its 5-minute epoch mean HRs, and the same for ln(epoch RMSSD) when
// the night has R-R. The reference is the median of those over the previous 14 nights (≥ 4 needed).
// Recumbent, still, overnight R-R is the signal the whole app already trusts for HRV, so the sleep score
// DOES use HRV: z_HR = (HR − ref)/spread, z_HRV = (ln ref − ln RMSSD)/spread, s = (z_HR + z_HRV)/√2
// (unit variance under independence), or s = z_HR when either side lacks R-R.
// Mapping: level = 3 / (1 + e^−x), x = −ln 6.5 + (ln 6.5 + ln 2)·s/3, so
//   s = 0 (a typical sleeping epoch) → 0.4  (WHOOP: good sleep sits below ~0.5)
//   s = 3 (three robust SDs above your own sleeping physiology) → 2.0 (HIGH).
// Sleep Stress % = high-band epochs / scored epochs within the main sleep, keyed to the wake day.
//
// ── MOTION ──────────────────────────────────────────────────────────────────────────────────────────
// A waking epoch is masked (state `.activity`, no level) when it overlaps a logged/detected workout, when
// at least `DaytimeStress.activityMaskFraction` of its gravity records are ambulatory
// (`WorkoutDetector.motionThreshold`), or during the post-exercise shadow: up to 15 minutes after an
// active epoch while HR is still `DaytimeStress.postActivityShadowBPM` over the floor. Masked time is
// neither waking stress nor coverage.
//
// ── COLD START ──────────────────────────────────────────────────────────────────────────────────────
// Fewer than `minBaselineDays` prior days (or nights) with an aggregate → the day (night) is scored
// against its OWN aggregate and the reference says `personal == false`. No aggregate at all → unscored.

/// One local day's Stress Monitor summary. THIS IS A STORED CONTRACT (metricSeries under the computed
/// source, read with `repo.exploreSeries(key:source: "my-whoop")`), consumed by the Stress screen, Home,
/// Health and the Mind features (Resilience / Cumulative Stress). All minutes are WAKING minutes: 5-minute
/// epochs that are not sleep, not masked as activity, and had enough heart rate to score.
public struct StressDaySummary: Equatable, Sendable {
    /// Local calendar day, `yyyy-MM-dd`.
    public let day: String
    /// Mean 0–3 level over the scored waking epochs (key `stress_day`). nil when fewer than
    /// `StressMonitor.minWakingScoredMinutes` were scored; the waking keys are then not written at all.
    public let meanLevel: Double?
    /// Waking minutes in each band: high ≥ 2.0, medium [1.0, 2.0), low < 1.0.
    public let highMin: Int
    public let medMin: Int
    public let lowMin: Int
    /// Waking scored minutes (coverage) = high + med + low.
    public let scoredMin: Int
    /// 0–100 share of the MAIN sleep ending on this day that sat in HIGH stress (key `sleep_stress_pct`),
    /// nil when the night had too little scored time.
    public let sleepStressPct: Double?

    public init(day: String, meanLevel: Double?, highMin: Int, medMin: Int, lowMin: Int,
                scoredMin: Int, sleepStressPct: Double?) {
        self.day = day; self.meanLevel = meanLevel
        self.highMin = highMin; self.medMin = medMin; self.lowMin = lowMin
        self.scoredMin = scoredMin; self.sleepStressPct = sleepStressPct
    }

    /// The stored metricSeries keys. Exact strings; other features depend on them.
    public enum Key {
        public static let mean = "stress_day"
        public static let highMin = "stress_high_min"
        public static let medMin = "stress_med_min"
        public static let lowMin = "stress_low_min"
        public static let scoredMin = "stress_scored_min"
        public static let sleepStressPct = "sleep_stress_pct"
        /// Every contract key, in a stable order.
        public static let all = [mean, highMin, medMin, lowMin, scoredMin, sleepStressPct]
    }

    /// True when the waking half carries a value (the five waking keys are written together or not at all).
    public var hasWaking: Bool { meanLevel != nil }

    /// The (key, value) pairs to persist for this day. Waking keys only when `hasWaking`; the sleep key
    /// only when the night was scored.
    public var storedPairs: [(key: String, value: Double)] {
        var out: [(key: String, value: Double)] = []
        if let meanLevel {
            out.append((Key.mean, (meanLevel * 100).rounded() / 100))
            out.append((Key.highMin, Double(highMin)))
            out.append((Key.medMin, Double(medMin)))
            out.append((Key.lowMin, Double(lowMin)))
            out.append((Key.scoredMin, Double(scoredMin)))
        }
        if let sleepStressPct { out.append((Key.sleepStressPct, (sleepStressPct * 10).rounded() / 10)) }
        return out
    }

    /// Rebuild a summary from stored values (the inverse of `storedPairs`), nil when the day has neither
    /// half. A day with only the sleep key reads back with zero waking minutes and a nil mean.
    public static func fromStored(day: String, values: [String: Double]) -> StressDaySummary? {
        let mean = values[Key.mean]
        let sleep = values[Key.sleepStressPct]
        guard mean != nil || sleep != nil else { return nil }
        func minutes(_ k: String) -> Int { mean == nil ? 0 : Int((values[k] ?? 0).rounded()) }
        return StressDaySummary(day: day, meanLevel: mean, highMin: minutes(Key.highMin),
                                medMin: minutes(Key.medMin), lowMin: minutes(Key.lowMin),
                                scoredMin: minutes(Key.scoredMin), sleepStressPct: sleep)
    }
}

public enum StressMonitor {

    // MARK: - Tunables

    /// Scoring grain (seconds). Five minutes: fine enough to find a tense meeting or a restless half hour
    /// of sleep, coarse enough that one epoch of 1 Hz heart rate is a stable mean.
    public static let epochSeconds = 300
    /// Minimum heart-rate samples in an epoch before it is scored (one minute of 1 Hz data).
    public static let minEpochHRSamples = 60
    /// The personal baseline window, in days (WHOOP: "the past 14 days").
    public static let baselineWindowDays = 14
    /// Prior days (or nights) with an aggregate before the baseline counts as personal. The same seed the
    /// nightly baselines use.
    public static let minBaselineDays = Baselines.minNightsSeed
    /// Band floors on the shared 0–3 scale.
    public static let mediumFloor = 1.0
    public static let highFloor = DaytimeStress.highBandFloor
    /// Waking HR elevation over the calm floor that reads as the bottom of HIGH (validated, HR-only).
    public static let wakeHighMarginBPM = DaytimeStress.baselineRelativeHighMarginBPM
    /// Level of a typical sleeping epoch (at the personal nocturnal reference).
    public static let sleepTypicalLevel = 0.4
    /// Combined robust z at which a sleeping epoch reads as the bottom of HIGH.
    public static let sleepHighZ = 3.0
    /// Scored main-sleep epochs needed to build a night aggregate or report Sleep Stress (one hour).
    public static let minNightEpochs = 12
    /// Floors on the robust spreads, so a near-flat night cannot make every wobble read as stress.
    public static let minNightHRSpread = 2.0
    public static let minNightLnRMSSDSpread = 0.10
    /// Waking scored minutes needed before a day's waking summary is written.
    public static let minWakingScoredMinutes = 30
    /// Post-exercise shadow depth, in epochs (15 minutes).
    public static let postActivityShadowEpochs = 3

    // MARK: - Types

    public struct Interval: Equatable, Sendable, Codable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
        public func contains(_ ts: Int) -> Bool { ts >= start && ts < end }
        public var duration: Int { max(0, end - start) }
    }

    public enum EpochState: String, Sendable, Equatable {
        /// Awake, not moving: scored against the waking reference.
        case waking
        /// Inside a sleep period: scored against the nocturnal reference.
        case sleep
        /// Awake but moving or exercising: masked, no level.
        case activity
        /// Too little heart rate to say anything.
        case noData
    }

    public struct Epoch: Equatable, Sendable {
        /// Wall-clock start (unix seconds).
        public let startTs: Int
        public let state: EpochState
        /// 0–3, nil for `.activity` / `.noData` (and for a sleep or waking epoch with no reference).
        public let level: Double?
        public let meanHR: Double?
        /// Only computed for sleep epochs (daytime RMSSD is not used).
        public let rmssd: Double?
        /// True when the epoch lies in the MAIN sleep that ends on this day.
        public let inMainSleep: Bool

        public init(startTs: Int, state: EpochState, level: Double?, meanHR: Double?, rmssd: Double?,
                    inMainSleep: Bool) {
            self.startTs = startTs; self.state = state; self.level = level
            self.meanHR = meanHR; self.rmssd = rmssd; self.inMainSleep = inMainSleep
        }
    }

    /// Where a waking epoch's calm floor came from.
    public struct WakeReference: Equatable, Sendable {
        public let floorHR: Double
        /// true = median of ≥ `minBaselineDays` prior days in the 14-day window; false = the day's own.
        public let personal: Bool
        /// Prior days that fed the median (0 when not personal).
        public let days: Int
        public init(floorHR: Double, personal: Bool, days: Int) {
            self.floorHR = floorHR; self.personal = personal; self.days = days
        }
    }

    /// One main sleep reduced to what the nocturnal baseline needs.
    public struct NightAggregate: Equatable, Sendable {
        public let hr: Double
        public let hrSpread: Double
        public let lnRMSSD: Double?
        public let lnRMSSDSpread: Double?
        public init(hr: Double, hrSpread: Double, lnRMSSD: Double?, lnRMSSDSpread: Double?) {
            self.hr = hr; self.hrSpread = hrSpread; self.lnRMSSD = lnRMSSD; self.lnRMSSDSpread = lnRMSSDSpread
        }

        /// Stored keys for the per-night aggregate (internal, not for display). Written beside the contract
        /// keys so a later day's baseline is read, not recomputed from raw.
        public enum Key {
            public static let hr = "stress_night_hr"
            public static let hrSpread = "stress_night_hr_sd"
            public static let lnRMSSD = "stress_night_lnrmssd"
            public static let lnRMSSDSpread = "stress_night_lnrmssd_sd"
        }
        public var storedPairs: [(key: String, value: Double)] {
            var out: [(key: String, value: Double)] = [(Key.hr, hr), (Key.hrSpread, hrSpread)]
            if let lnRMSSD, let lnRMSSDSpread {
                out.append((Key.lnRMSSD, lnRMSSD)); out.append((Key.lnRMSSDSpread, lnRMSSDSpread))
            }
            return out
        }
        public static func fromStored(_ v: [String: Double]) -> NightAggregate? {
            guard let hr = v[Key.hr], let sd = v[Key.hrSpread] else { return nil }
            return NightAggregate(hr: hr, hrSpread: sd, lnRMSSD: v[Key.lnRMSSD], lnRMSSDSpread: v[Key.lnRMSSDSpread])
        }
    }

    /// Stored key for the per-day waking calm floor (internal, not for display).
    public static let wakeFloorKey = "stress_wake_floor_hr"

    public struct SleepReference: Equatable, Sendable {
        public let night: NightAggregate
        public let personal: Bool
        public let nights: Int
        public init(night: NightAggregate, personal: Bool, nights: Int) {
            self.night = night; self.personal = personal; self.nights = nights
        }
    }

    /// Everything one local day needs. `hr` / `rr` must cover `[min(dayStart, mainSleep.start), dayEnd)`.
    public struct DayInput {
        public let day: String
        /// Local midnight as a wall-clock unix timestamp.
        public let dayStart: Int
        /// Exclusive end: the next local midnight, or "now" for today.
        public let dayEnd: Int
        public let tzOffsetSeconds: Int
        public let hr: [HRSample]
        public let rr: [RRInterval]
        public let gravity: [GravitySample]
        /// Every sleep period touching the day (main nights and naps).
        public let sleepWindows: [Interval]
        /// The main sleep that ENDS on this day (Sleep Stress is keyed to it), nil when none.
        public let mainSleep: Interval?
        /// Logged or detected workouts touching the day.
        public let activityWindows: [Interval]

        public init(day: String, dayStart: Int, dayEnd: Int, tzOffsetSeconds: Int,
                    hr: [HRSample], rr: [RRInterval], gravity: [GravitySample],
                    sleepWindows: [Interval], mainSleep: Interval?, activityWindows: [Interval]) {
            self.day = day; self.dayStart = dayStart; self.dayEnd = dayEnd
            self.tzOffsetSeconds = tzOffsetSeconds; self.hr = hr; self.rr = rr; self.gravity = gravity
            self.sleepWindows = sleepWindows; self.mainSleep = mainSleep; self.activityWindows = activityWindows
        }
    }

    public struct DayResult: Equatable, Sendable {
        public let day: String
        /// The calendar-day grid, `dayStart` → `dayEnd`, one entry per 5 minutes.
        public let epochs: [Epoch]
        public let wake: WakeReference?
        public let sleep: SleepReference?
        public let summary: StressDaySummary
        /// This day's own aggregates, persisted so later days' baselines can read them.
        public let wakeFloorAggregate: Double?
        public let nightAggregate: NightAggregate?

        /// The newest epoch with a level (the "current" reading for today).
        public var latest: Epoch? { epochs.last { $0.level != nil } }
    }

    // MARK: - Level mappings

    /// Waking level from the epoch mean HR and the calm floor (see the header for the anchors).
    public static func wakeLevel(meanHR: Double, floorHR: Double) -> Double {
        let delta = meanHR - floorHR
        let x = log(2.0) * (2.0 * delta / wakeHighMarginBPM - 1.0)
        return clamp03(3.0 / (1.0 + exp(-x)))
    }

    /// Combined robust z for a sleeping epoch (HR up and HRV down both push it positive).
    public static func sleepZ(meanHR: Double, rmssd: Double?, ref: NightAggregate) -> Double {
        let zHR = (meanHR - ref.hr) / max(ref.hrSpread, minNightHRSpread)
        guard let rmssd, rmssd > 0, let lnRef = ref.lnRMSSD, let lnSd = ref.lnRMSSDSpread else { return zHR }
        let zHRV = (lnRef - log(rmssd)) / max(lnSd, minNightLnRMSSDSpread)
        return (zHR + zHRV) / 2.0.squareRoot()
    }

    /// Sleeping level from the combined z (see the header for the anchors).
    public static func sleepLevel(z: Double) -> Double {
        let lo = log(3.0 / sleepTypicalLevel - 1.0)          // ln 6.5
        let hi = log(3.0 / (3.0 - highFloor) - 1.0)          // ln 2  (level 2.0)
        let x = -lo + (lo + hi) * z / sleepHighZ
        return clamp03(3.0 / (1.0 + exp(-x)))
    }

    static func clamp03(_ v: Double) -> Double { min(max(v, 0), 3) }

    // MARK: - References

    /// The waking reference for a day: the median of the non-nil floors among the LAST `baselineWindowDays`
    /// entries of `priorFloors` (oldest → newest, the scored day excluded), when at least `minBaselineDays`
    /// exist; otherwise the day's own floor (cold start); otherwise nil.
    public static func wakeReference(priorFloors: [Double?], todayFloor: Double?) -> WakeReference? {
        let window = priorFloors.suffix(baselineWindowDays).compactMap { $0 }
        if window.count >= minBaselineDays {
            return WakeReference(floorHR: median(window), personal: true, days: window.count)
        }
        return todayFloor.map { WakeReference(floorHR: $0, personal: false, days: 0) }
    }

    /// The nocturnal reference: per-field medians over the last `baselineWindowDays` prior nights (≥
    /// `minBaselineDays` needed), else tonight's own aggregate, else nil. The HRV half is only present when
    /// at least `minBaselineDays` of those nights carried R-R.
    public static func sleepReference(priorNights: [NightAggregate?], tonight: NightAggregate?) -> SleepReference? {
        let window = priorNights.suffix(baselineWindowDays).compactMap { $0 }
        if window.count >= minBaselineDays {
            let withHRV = window.filter { $0.lnRMSSD != nil && $0.lnRMSSDSpread != nil }
            let hrv = withHRV.count >= minBaselineDays
            let agg = NightAggregate(
                hr: median(window.map(\.hr)), hrSpread: median(window.map(\.hrSpread)),
                lnRMSSD: hrv ? median(withHRV.compactMap(\.lnRMSSD)) : nil,
                lnRMSSDSpread: hrv ? median(withHRV.compactMap(\.lnRMSSDSpread)) : nil)
            return SleepReference(night: agg, personal: true, nights: window.count)
        }
        return tonight.map { SleepReference(night: $0, personal: false, nights: 0) }
    }

    // MARK: - Aggregates

    struct EpochAgg { var hrSum = 0.0; var hrN = 0; var rr: [Double] = [] }

    /// Bucket samples onto the absolute 5-minute grid anchored at `anchor` (index may be negative).
    static func bucket(hr: [HRSample], rr: [RRInterval], anchor: Int, range: Interval,
                       withRR: Bool) -> [Int: EpochAgg] {
        var out: [Int: EpochAgg] = [:]
        for s in hr where range.contains(s.ts) {
            let k = DaytimeStress.floorDiv(s.ts - anchor, epochSeconds)
            out[k, default: EpochAgg()].hrSum += Double(s.bpm)
            out[k, default: EpochAgg()].hrN += 1
        }
        if withRR {
            for r in rr where range.contains(r.ts) {
                let k = DaytimeStress.floorDiv(r.ts - anchor, epochSeconds)
                out[k, default: EpochAgg()].rr.append(Double(r.rrMs))
            }
        }
        return out
    }

    /// Reduce one main sleep to its aggregate (nil under `minNightEpochs` scored epochs).
    public static func nightAggregate(hr: [HRSample], rr: [RRInterval], mainSleep: Interval,
                                      anchor: Int? = nil) -> NightAggregate? {
        let a = anchor ?? mainSleep.start
        let buckets = bucket(hr: hr, rr: rr, anchor: a, range: mainSleep, withRR: true)
        var hrs: [Double] = []
        var lnR: [Double] = []
        for (_, b) in buckets where b.hrN >= minEpochHRSamples {
            hrs.append(b.hrSum / Double(b.hrN))
            if let r = HRVAnalyzer.analyze(rawRR: b.rr).rmssd, r > 0 { lnR.append(log(r)) }
        }
        guard hrs.count >= minNightEpochs else { return nil }
        let hrMed = median(hrs)
        let hrSd = max(1.4826 * median(hrs.map { abs($0 - hrMed) }), minNightHRSpread)
        var lnMed: Double? = nil, lnSd: Double? = nil
        if lnR.count >= minNightEpochs {
            let m = median(lnR)
            lnMed = m
            lnSd = max(1.4826 * median(lnR.map { abs($0 - m) }), minNightLnRMSSDSpread)
        }
        return NightAggregate(hr: hrMed, hrSpread: hrSd, lnRMSSD: lnMed, lnRMSSDSpread: lnSd)
    }

    // MARK: - Day analysis

    /// Score one local day. `priorFloors` / `priorNights` are the stored aggregates of the preceding days,
    /// oldest → newest, the scored day excluded (only the last 14 are read).
    public static func analyzeDay(_ input: DayInput, priorFloors: [Double?],
                                  priorNights: [NightAggregate?]) -> DayResult {
        let dayRange = Interval(start: input.dayStart, end: max(input.dayStart, input.dayEnd))
        let dayHR = input.hr.filter { dayRange.contains($0.ts) }
        let dayRR = input.rr.filter { dayRange.contains($0.ts) }

        // 1) This day's own aggregates.
        let floorAgg = DaytimeStress.dayDaytimeAggregate(hr: dayHR, rr: dayRR,
                                                         tzOffsetSeconds: input.tzOffsetSeconds).hr
        let night = input.mainSleep.flatMap {
            nightAggregate(hr: input.hr, rr: input.rr, mainSleep: $0, anchor: input.dayStart)
        }
        let wakeRef = wakeReference(priorFloors: priorFloors, todayFloor: floorAgg)
        let sleepRef = sleepReference(priorNights: priorNights, tonight: night)

        // 2) Motion: per-epoch ambulatory fraction from gravity, on the day grid.
        var activeFrac: [Int: Double] = [:]
        if !input.gravity.isEmpty {
            var counts: [Int: (Int, Int)] = [:]
            for p in WorkoutDetector.activitySeries(input.gravity) where dayRange.contains(p.ts) {
                let k = DaytimeStress.floorDiv(p.ts - input.dayStart, epochSeconds)
                var c = counts[k] ?? (0, 0)
                c.1 += 1
                if p.intensity > WorkoutDetector.motionThreshold { c.0 += 1 }
                counts[k] = c
            }
            for (k, c) in counts where c.1 > 0 { activeFrac[k] = Double(c.0) / Double(c.1) }
        }

        // 3) The day grid.
        let n = dayRange.duration / epochSeconds + (dayRange.duration % epochSeconds > 0 ? 1 : 0)
        let buckets = bucket(hr: input.hr, rr: input.rr, anchor: input.dayStart, range: dayRange, withRR: true)
        var epochs: [Epoch] = []
        epochs.reserveCapacity(n)
        var lastActive = Int.min
        for k in 0..<n {
            let start = input.dayStart + k * epochSeconds
            let mid = start + epochSeconds / 2
            let b = buckets[k]
            let meanHR: Double? = (b?.hrN ?? 0) >= minEpochHRSamples ? b!.hrSum / Double(b!.hrN) : nil
            let inSleep = input.sleepWindows.contains { $0.contains(mid) }
            let inMain = input.mainSleep?.contains(mid) ?? false
            if inSleep || inMain {
                var rmssd: Double? = nil
                var level: Double? = nil
                if let meanHR, let ref = sleepRef {
                    rmssd = HRVAnalyzer.analyze(rawRR: b?.rr ?? []).rmssd
                    level = sleepLevel(z: sleepZ(meanHR: meanHR, rmssd: rmssd, ref: ref.night))
                }
                epochs.append(Epoch(startTs: start, state: meanHR == nil ? .noData : .sleep, level: level,
                                    meanHR: meanHR, rmssd: rmssd, inMainSleep: inMain))
                continue
            }
            let workout = input.activityWindows.contains { $0.start < start + epochSeconds && $0.end > start }
            let ambulatory = (activeFrac[k] ?? 0) >= DaytimeStress.activityMaskFraction
            if workout || ambulatory { lastActive = k }
            let shadow = !workout && !ambulatory && lastActive != Int.min
                && k - lastActive <= postActivityShadowEpochs
                && meanHR != nil && wakeRef != nil
                && meanHR! > wakeRef!.floorHR + DaytimeStress.postActivityShadowBPM
            guard let meanHR else {
                epochs.append(Epoch(startTs: start, state: .noData, level: nil, meanHR: nil, rmssd: nil,
                                    inMainSleep: false))
                continue
            }
            if workout || ambulatory || shadow {
                epochs.append(Epoch(startTs: start, state: .activity, level: nil, meanHR: meanHR, rmssd: nil,
                                    inMainSleep: false))
                continue
            }
            let level = wakeRef.map { wakeLevel(meanHR: meanHR, floorHR: $0.floorHR) }
            epochs.append(Epoch(startTs: start, state: .waking, level: level, meanHR: meanHR, rmssd: nil,
                                inMainSleep: false))
        }

        // 4) Sleep Stress over the WHOLE main sleep (it may start before this day's midnight), on the same
        //    absolute grid so the epochs inside the day are exactly the chart's.
        var sleepStressPct: Double? = nil
        if let main = input.mainSleep, let ref = sleepRef {
            let nb = bucket(hr: input.hr, rr: input.rr, anchor: input.dayStart, range: main, withRR: true)
            var scored = 0, high = 0
            for (_, b) in nb where b.hrN >= minEpochHRSamples {
                let r = HRVAnalyzer.analyze(rawRR: b.rr).rmssd
                let lvl = sleepLevel(z: sleepZ(meanHR: b.hrSum / Double(b.hrN), rmssd: r, ref: ref.night))
                scored += 1
                if lvl >= highFloor { high += 1 }
            }
            if scored >= minNightEpochs { sleepStressPct = 100.0 * Double(high) / Double(scored) }
        }

        let summary = summarize(day: input.day, epochs: epochs, sleepStressPct: sleepStressPct)
        return DayResult(day: input.day, epochs: epochs, wake: wakeRef, sleep: sleepRef, summary: summary,
                         wakeFloorAggregate: floorAgg, nightAggregate: night)
    }

    /// Build the day summary from the waking epochs (one definition, used by the engine and the screen).
    public static func summarize(day: String, epochs: [Epoch], sleepStressPct: Double?) -> StressDaySummary {
        let minutesPerEpoch = epochSeconds / 60
        var low = 0, med = 0, high = 0, sum = 0.0
        for e in epochs where e.state == .waking {
            guard let l = e.level else { continue }
            sum += l
            if l >= highFloor { high += 1 } else if l >= mediumFloor { med += 1 } else { low += 1 }
        }
        let count = low + med + high
        let scoredMin = count * minutesPerEpoch
        let hasWaking = scoredMin >= minWakingScoredMinutes
        return StressDaySummary(day: day, meanLevel: hasWaking ? sum / Double(count) : nil,
                                highMin: hasWaking ? high * minutesPerEpoch : 0,
                                medMin: hasWaking ? med * minutesPerEpoch : 0,
                                lowMin: hasWaking ? low * minutesPerEpoch : 0,
                                scoredMin: hasWaking ? scoredMin : 0,
                                sleepStressPct: sleepStressPct)
    }

    // MARK: - Live

    /// Live window length (seconds of 1 Hz heart rate) and the minimum samples to report a level.
    public static let liveWindowSeconds = 300
    public static let liveMinSamples = 60
    /// A live window this far above the calm floor is read as movement, not stress. There is no motion
    /// channel on the live path, and psychological stress at rest rarely lifts HR this much; above it the
    /// readout says "active" instead of claiming a stress level. Heuristic, stated as such.
    public static let liveActivityMarginBPM = 35.0

    public enum LiveReading: Equatable, Sendable {
        case level(Double)
        case active
    }

    /// Score the most recent live heart-rate window (bpm values, oldest → newest) against the waking
    /// reference. nil when there are fewer than `liveMinSamples` plausible samples.
    public static func liveReading(hrWindow: [Double], wake: WakeReference) -> LiveReading? {
        let xs = hrWindow.suffix(liveWindowSeconds).filter { $0 >= 30 && $0 <= 220 }
        guard xs.count >= liveMinSamples else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        if mean - wake.floorHR >= liveActivityMarginBPM { return .active }
        return .level(wakeLevel(meanHR: mean, floorHR: wake.floorHR))
    }

    // MARK: - Helpers

    /// Median of a non-empty array (mean of the two middles for an even count).
    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
