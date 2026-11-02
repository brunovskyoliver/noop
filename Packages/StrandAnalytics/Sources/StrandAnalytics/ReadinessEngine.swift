import Foundation
import WhoopStore

/// On-device "Readiness" intelligence.
///
/// Synthesizes a handful of established, non-medical sports-science signals from the daily-metrics
/// history into a single readiness read plus the drivers behind it. Everything here is a pure,
/// deterministic function of the rows you pass in — no networking, no strap commands, no state.
///
/// Signals and their references:
/// - **HRV readiness** — the 7-day rolling ln RMSSD against the personal baseline before that week. A
///   single night is too noisy to label; Plews et al. 2013 and Buchheit 2014 read the weekly average.
/// - **Resting-HR drift** — elevated resting HR vs baseline is a classic overtraining / illness
///   signal (Lamberts et al. 2004).
/// - **Respiratory-rate drift** — a rise in sleeping respiratory rate is an early illness signal.
/// - **Training load** — this week's load against the three weeks before it, as a plain comparison.
///   It sets no headline: the evidence does not support the ratio as an injury predictor
///   (Impellizzeri et al. 2020), so it carries no risk band.
/// - **Training monotony** — mean/SD of daily strain over a week; a descriptive note (Foster 1998).
///
/// Not medical advice. These are approximations from a consumer strap; they describe trends in
/// *your own* data, nothing more.
public enum ReadinessEngine {

    // MARK: Output types

    public enum Level: String, Sendable, Equatable {
        case primed       // signals aligned, load supported
        case balanced     // nothing notable either way
        case strained     // one meaningful signal down / load high
        case rundown      // several recovery signals down
        case insufficient // not enough history yet
    }

    public enum Flag: String, Sendable, Equatable {
        case good, neutral, watch, bad
    }

    /// Locale-free numeric evidence. Clients format and localize it at the display boundary.
    public enum Evidence: Sendable, Equatable {
        case metric(value: Double, baseline: Double, unit: String, decimals: Int)
        case trainingLoad(acute: Double, chronic: Double)
        case monotony(Double)
    }

    public struct Signal: Sendable, Equatable {
        public let key: String      // "hrv" | "rhr" | "respRate" | "acwr" | "monotony"
        public let label: String    // short human label
        public let evidence: String?
        public let evidenceData: Evidence?
        public let detail: String   // one-line plain-English read
        public let flag: Flag
        public init(key: String, label: String, evidence: String? = nil,
                    evidenceData: Evidence? = nil, detail: String, flag: Flag) {
            self.key = key; self.label = label; self.evidence = evidence
            self.evidenceData = evidenceData; self.detail = detail; self.flag = flag
        }
    }

    public struct Readiness: Sendable, Equatable {
        public let level: Level
        public let headline: String
        public let summary: String
        public let signals: [Signal]
        /// Acute:chronic workload ratio (nil if not enough strain history).
        public let acwr: Double?
        /// Foster training monotony over the last week (nil if not enough strain history).
        public let monotony: Double?
        /// How much history backs this read (HRV/RHR baseline density) — so the card can show
        /// calibrating / building / solid instead of a confident number off a 7-night baseline.
        public let confidence: ScoreConfidence
        public init(level: Level, headline: String, summary: String,
                    signals: [Signal], acwr: Double?, monotony: Double?,
                    confidence: ScoreConfidence = .calibrating) {
            self.level = level; self.headline = headline; self.summary = summary
            self.signals = signals; self.acwr = acwr; self.monotony = monotony
            self.confidence = confidence
        }
    }

    // MARK: Tunables (named so the thresholds are auditable)

    private static let baselineWindow = 30   // days for HRV / RHR / RR baselines
    /// Calendar days in the rolling HRV reading, and the valid nights it needs (HRVStatus's rule).
    static let rollingHrvDays = 7
    static let minRollingHrvNights = 3
    private static let minBaseline    = 7    // need at least this many baseline nights
    private static let acuteWindow    = 7
    private static let chronicWindow  = 28
    private static let minChronic     = 10   // observed load days needed in the previous three weeks
    private static let minAcute       = 4    // observed load days needed in the 7-day window

    /// Daily TRIMP (from stored Effort, Edwards scale) for the calendar days ending on `day`: the last
    /// `acuteWindow` days, and the days before them back to `chronicWindow` (the two never overlap, so the
    /// ratio is not capped by the acute week sitting inside its own baseline). Oldest first, skipping days
    /// with no Effort. Days outside the window never count, however few rows there are.
    static func calendarLoads(_ sorted: [DailyMetric], through day: String,
                              endOffset: Int = 0) -> (acute: [Double], chronic: [Double]) {
        guard let end = VitalityEngine.epochDay(day).map({ $0 - endOffset }) else { return ([], []) }
        var acute: [Double] = [], chronic: [Double] = []
        for d in sorted {
            guard let strain = d.strain, let e = VitalityEngine.epochDay(d.day), e <= end else { continue }
            let load = StrainScorer.strainToTrimp(strain)
            if e > end - acuteWindow { acute.append(load) } else if e > end - chronicWindow { chronic.append(load) }
        }
        return (acute, chronic)
    }

    // MARK: Entry point

    /// Evaluate readiness from daily metrics. `days` may be in any order; the most recent day is
    /// treated as "today" unless `today` (a YYYY-MM-DD string) is given.
    public static func evaluate(days: [DailyMetric], today: String? = nil) -> Readiness {
        // v7.0.2 perf (#707): `evaluate` SORTS the entire daily history and walks trailing windows every
        // call, and it is read from a SwiftUI computed property — so a `body` re-evaluation (the iOS twin of
        // a Compose recompose) re-runs the full-history sort on each ~1 Hz live-HR tick. The Today view also
        // memoizes this at the View layer (its `todayInputKey`); this engine-level cache additionally shields
        // every OTHER caller and the first/uncached read. Key = `today` + a fingerprint over ONLY the row
        // fields the synthesis reads (day + avgHrv/restingHr/respRateBpm/strain), so a new sync re-keys but a
        // cosmetic reorder does not. Result is a small `Readiness`; no row arrays are retained.
        let key = ReadinessKey(today: today, rows: Self.rowsFingerprint(days))
        return evaluateCache.value(key) { evaluateUncached(days: days, today: today) }
    }

    private struct ReadinessKey: Hashable { let today: String?; let rows: StreamFingerprint }
    private static let evaluateCache = AnalyticsMemoCache<ReadinessKey, Readiness>(capacity: 16)

    /// Fingerprint the readiness-relevant columns of the daily rows without re-sorting or copying them.
    /// Order-independent per-row hash (folded into the checksum), so two identical histories in different
    /// order key the same — `evaluate` sorts internally, so order never changes the result.
    private static func rowsFingerprint(_ days: [DailyMetric]) -> StreamFingerprint {
        var sum: UInt64 = 1469598103934665603
        var minDayHash = 0, maxDayHash = 0
        for (i, d) in days.enumerated() {
            // All folds stay in UInt64 — `Double.bitPattern` is already a UInt64 (its sign bit can exceed
            // Int64.max, so an Int64 round-trip would TRAP), and `Int.bitPattern` reinterprets without loss.
            var h: UInt64 = UInt64(bitPattern: Int64(d.day.hashValue))
            h = (h &* 1099511628211) ^ (d.avgHrv ?? -1).bitPattern
            h = (h &* 1099511628211) ^ (d.restingHr.map { UInt64(bitPattern: Int64($0)) } ?? .max)
            h = (h &* 1099511628211) ^ (d.respRateBpm ?? -1).bitPattern
            h = (h &* 1099511628211) ^ (d.strain ?? -1).bitPattern
            sum ^= h                                   // commutative fold → order-independent
            let dh = d.day.hashValue
            if i == 0 { minDayHash = dh; maxDayHash = dh } else { minDayHash = min(minDayHash, dh); maxDayHash = max(maxDayHash, dh) }
        }
        return StreamFingerprint(count: days.count, firstTs: minDayHash, lastTs: maxDayHash, checksum: sum)
    }

    private static func evaluateUncached(days: [DailyMetric], today: String?) -> Readiness {
        let sorted = days.sorted { $0.day < $1.day }
        // When an explicit `today` is given (the dashboard passes the device's real local day key), use
        // the row for THAT day and nothing else: a stale historical import has no row for today, so the
        // readiness card reads "insufficient" rather than synthesizing off the newest stored — possibly
        // months-old — row (issue #23/#24). With no `today` (live-strap default callers) fall back to the
        // most recent row exactly as before, so nothing wearing the strap nightly changes.
        let latestRow: DailyMetric?
        if let today { latestRow = sorted.first { $0.day == today } } else { latestRow = sorted.last }
        guard let latest = latestRow else {
            return Readiness(level: .insufficient,
                             headline: "Readiness",
                             summary: "Wear the strap for a few nights and your readiness read will appear here.",
                             signals: [], acwr: nil, monotony: nil)
        }
        let history = sorted.filter { $0.day < latest.day }   // everything before today
        // Calendar windows, so a gap cannot pass rows from months ago off as the recent baseline.
        let latestEpochDay = VitalityEngine.epochDay(latest.day) ?? 0
        func rows(daysBack range: ClosedRange<Int>) -> [DailyMetric] {
            sorted.filter { d in
                VitalityEngine.epochDay(d.day).map { range.contains(latestEpochDay - $0) } ?? false
            }
        }
        // Same HRV bounds as the Charge baseline.
        let hrvWeek = rows(daysBack: 0...(rollingHrvDays - 1)).compactMap { $0.avgHrv }
            .filter { Baselines.hrvCfg.minVal <= $0 && $0 <= Baselines.hrvCfg.maxVal }
        let hrvBaseline = rows(daysBack: rollingHrvDays...(rollingHrvDays + baselineWindow - 1))
            .compactMap { $0.avgHrv }
        let recent = rows(daysBack: 1...baselineWindow)

        var signals: [Signal] = []

        // HRV readiness ------------------------------------------------------
        let hrvSignal = zSignal(
            // Today must have a reading; the label then describes the week it ends, as HRVStatus does.
            value: latest.avgHrv.flatMap { _ in
                hrvWeek.count >= minRollingHrvNights
                    ? exp(hrvWeek.map { log(max($0, 1.0)) }.reduce(0, +) / Double(hrvWeek.count)) : nil
            },
            baseline: hrvBaseline,
            key: "hrv", label: "HRV",
            unit: "ms",
            decimals: 0,
            higherIsBetter: true,
            logDomain: true,   // RD1: lnRMSSD — HRV is right-skewed
            cfg: Baselines.readinessHRVLnCfg,   // RD2: ln-space spine, reject off
            goodText: "above your baseline - well recovered",
            neutralText: "in your normal range",
            watchText: "a touch below baseline",
            badText: "suppressed - a sign of autonomic fatigue")
        if let s = hrvSignal { signals.append(s) }

        // Resting-HR drift ---------------------------------------------------
        let rhrSignal = zSignal(
            value: latest.restingHr.map(Double.init),
            baseline: recent.compactMap { $0.restingHr.map(Double.init) },
            key: "rhr", label: "Resting HR",
            unit: "bpm",
            decimals: 0,
            higherIsBetter: false,
            cfg: Baselines.restingHRCfg,   // RD2: raw-bpm spine, reject off
            goodText: "at or below baseline",
            neutralText: "in your normal range",
            watchText: "running a little high",
            badText: "elevated - overtraining or illness can do this")
        if let s = rhrSignal { signals.append(s) }

        // Respiratory-rate drift (illness early signal) ----------------------
        // respRateBpm may be a clean cloud value OR a higher-variance on-device RSA estimate, so gate
        // BOTH the latest value and the baseline mean to the plausible sleeping-RR band (8–25 bpm) and
        // use wider resp-only z thresholds (WATCH 1.5 / BAD 2.0) than HRV/RHR so a single noisy night
        // can't flip RUNDOWN. Mirrors the Kotlin reference (#78) for cross-platform parity.
        if let rr = latest.respRateBpm, SleepStager.respPlausibleRangeBpm.contains(rr) {
            let base = recent.compactMap { $0.respRateBpm }
            if base.count >= minBaseline, let m = mean(base),
               SleepStager.respPlausibleRangeBpm.contains(m), let sd = sampleSD(base) {
                // σ floor: a very narrow history must not turn a small rise into a huge z.
                let z = (rr - m) / max(sd, Baselines.respCfg.floorSpread)
                if z >= 2.0 {
                    signals.append(Signal(key: "respRate", label: "Respiratory rate",
                        evidence: evidence(value: rr, baseline: m, unit: "rpm", decimals: 1),
                        evidenceData: .metric(value: rr, baseline: m, unit: "rpm", decimals: 1),
                        detail: "up vs baseline - sometimes an early sign of getting sick", flag: .bad))
                } else if z >= 1.5 {
                    signals.append(Signal(key: "respRate", label: "Respiratory rate",
                        evidence: evidence(value: rr, baseline: m, unit: "rpm", decimals: 1),
                        evidenceData: .metric(value: rr, baseline: m, unit: "rpm", decimals: 1),
                        detail: "slightly raised vs baseline", flag: .watch))
                }
            }
        }

        // Training Stress Balance (ACWR) + monotony --------------------------
        // Both run on TRIMP recovered from the stored Effort (`StrainScorer.strainToTrimp`), not on the
        // log-compressed Effort itself, and over CALENDAR windows ending the day BEFORE the target: the
        // target's Effort is still accruing, and a morning's near-zero must not read as a light full day.
        // A week off the strap leaves the acute window short instead of reaching back past the gap.
        let (acuteLoads, chronicLoads) = calendarLoads(sorted, through: latest.day, endOffset: 1)
        var acwr: Double? = nil
        var monotony: Double? = nil
        if chronicLoads.count >= minChronic, acuteLoads.count >= minAcute {
            let acute = mean(acuteLoads)!
            let chronic = mean(chronicLoads)!
            if chronic > 0 {
                let ratio = acute / chronic
                acwr = ratio
                signals.append(acwrSignal(ratio, acute: acute, chronic: chronic))
            }
            // Foster monotony over the last week of load.
            let week = acuteLoads
            // A relative floor on SD: identical Efforts map to identical TRIMP, but their mean can sit one
            // rounding step off, leaving an SD of ~1e-16 and a meaningless monotony in the quadrillions.
            if week.count >= 4, let sd = sampleSD(week), let m = mean(week), sd > 1e-9 * max(1, abs(m)) {
                let mono = m / sd
                monotony = mono
                if mono >= 2.0 {
                    signals.append(Signal(key: "monotony", label: "Training variety",
                        evidence: "monotony \(String(format: "%.1f", mono))",
                        evidenceData: .monotony(mono),
                        detail: "low - similar strain every day this week", flag: .neutral))
                }
            }
        }

        let (level, headline, summary) = synthesize(signals: signals,
                                                    hasHistory: !history.isEmpty || acwr != nil)
        // RD-confidence: surface how much history backs the read (HRV baseline density, the primary
        // readiness driver). A read off a 7-night baseline must not look as certain as one off the full
        // 30-night window. Insufficient reads carry .calibrating.
        let hrvBaselineNights = hrvBaseline.count
        let confidence = ScoreConfidence.readiness(hasRead: level != .insufficient,
                                                   baselineNights: hrvBaselineNights,
                                                   fullWindow: baselineWindow)
        return Readiness(level: level, headline: headline, summary: summary,
                         signals: signals, acwr: acwr, monotony: monotony,
                         confidence: confidence)
    }

    // MARK: Signal builders

    /// Build a z-score signal for a metric where the baseline is the trailing window.
    private static func zSignal(value: Double?, baseline: [Double],
                                key: String, label: String, unit: String, decimals: Int,
                                higherIsBetter: Bool, logDomain: Bool = false,
                                cfg: MetricCfg,
                                goodText: String, neutralText: String,
                                watchText: String, badText: String) -> Signal? {
        guard let v = value, baseline.count >= minBaseline else { return nil }
        // RD1: right-skewed metrics (HRV/RMSSD) are z-scored in the LOG domain — lnRMSSD is closer to
        // normal, so a symmetric z is statistically valid, whereas a raw-ms z over-weights the long
        // upper tail and misstates tail rarity (Plews/Altini; the app's own HRVReadiness works this
        // way). RHR/resp are ~normal and stay linear. Evidence stays in the metric's own units, but the
        // baseline shown is then the GEOMETRIC mean (exp of the log-mean) — a typical night, not an
        // outlier-inflated arithmetic mean.
        let tv = logDomain ? log(max(v, 1.0)) : v
        let tb = logDomain ? baseline.map { log(max($0, 1.0)) } : baseline
        // RD2: the same equally weighted, σ-floored window fold Charge uses, so a recent sustained shift
        // is absorbed instead of rejected. `cfg` is in the SAME space as `tb` (ln for HRV, linear for RHR).
        let state = Baselines.rollingMeanSD(tb, cfg: cfg, window: .max)
        guard state.usable else { return nil }
        let sigma = Baselines.sigma(state)
        guard sigma > 0 else { return nil }
        let m = state.baseline
        // Orient z so positive always means "better".
        let z = (higherIsBetter ? (tv - m) : (m - tv)) / sigma
        let flag: Flag
        let text: String
        switch z {
        case 0.5...:        flag = .good;    text = goodText
        case -0.5..<0.5:    flag = .neutral; text = neutralText
        case -1.0 ..< -0.5: flag = .watch;   text = watchText
        default:            flag = .bad;     text = badText
        }
        return Signal(key: key, label: label,
                      evidence: evidence(value: v, baseline: logDomain ? exp(m) : m,
                                         unit: unit, decimals: decimals),
                      evidenceData: .metric(value: v, baseline: logDomain ? exp(m) : m,
                                            unit: unit, decimals: decimals),
                      detail: text, flag: flag)
    }

    private static func acwrSignal(_ ratio: Double, acute: Double, chronic: Double) -> Signal {
        let evidence = "7d \(String(format: "%.1f", acute)) / prior 21d \(String(format: "%.1f", chronic))"
        let pct = Int((abs(ratio - 1) * 100).rounded())
        let detail = pct < 5 ? "about the same as your previous 3 weeks"
            : "\(pct)% \(ratio > 1 ? "above" : "below") your previous 3 weeks"
        return Signal(key: "acwr", label: "Training load", evidence: evidence,
                      evidenceData: .trainingLoad(acute: acute, chronic: chronic),
                      detail: detail, flag: .neutral)
    }

    private static func evidence(value: Double, baseline: Double, unit: String, decimals: Int) -> String {
        "\(format(value, decimals: decimals)) vs \(format(baseline, decimals: decimals)) \(unit)"
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        decimals == 0
            ? String(Int(value.rounded()))
            : String(format: "%.\(decimals)f", value)
    }

    // MARK: Synthesis

    private static func synthesize(signals: [Signal], hasHistory: Bool) -> (Level, String, String) {
        guard hasHistory, !signals.isEmpty else {
            return (.insufficient, "Readiness",
                    "A few more nights of data and your readiness read will sharpen.")
        }
        let bad = signals.filter { $0.flag == .bad }
        let watch = signals.filter { $0.flag == .watch }
        let good = signals.filter { $0.flag == .good }
        let recoveryDown = signals.contains { ["hrv", "rhr", "respRate"].contains($0.key) && ($0.flag == .bad) }

        if bad.count >= 2 {
            return (.rundown, "Run down",
                    "Several signals are down at once. Treat today as recovery - easy movement, real sleep tonight.")
        }
        if recoveryDown || bad.count >= 1 {
            return (.strained, "Strained",
                    "One of your signals is flagging. You can train, but keep it controlled and bank the recovery.")
        }
        if good.count >= 2 && watch.isEmpty {
            return (.primed, "Primed",
                    "Your signals are aligned. A harder session is well backed today.")
        }
        return (.balanced, "Balanced",
                "Nothing's flagging. Train to feel - your body's holding steady.")
    }

    // MARK: Stats helpers

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n-1). nil for fewer than 2 points.
    static func sampleSD(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let ss = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(xs.count - 1)).squareRoot()
    }
}
