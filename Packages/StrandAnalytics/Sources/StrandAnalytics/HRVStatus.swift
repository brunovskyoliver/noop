import Foundation

// HRVStatus.swift — a 7-night HRV status against your usual range (Garmin-style band).
//
// Method (docs/research/2026-09-24-offline-feature-research.md §1):
//   • ln RMSSD per night (Plews 2013: the 7-day ln-RMSSD average tracks adaptation; a single night does
//     not). Nights outside Baselines.hrvCfg (5–250 ms) are dropped as decode artefacts.
//   • Short window: the last 7 CALENDAR days ending on `asOf`, ≥3 valid nights (Plews 2014).
//   • Usual range: the 60 calendar days BEFORE the short window, so a sustained drop cannot pull its own
//     baseline down. Mean/SD of ln values after one ±3 SD winsorising pass; SD floored at 0.08 ln. Needs
//     ≥21 valid nights (about the three weeks Garmin asks for).
//   • Bands on the 7-night mean m against the usual mean μ and SD σ:
//       balanced  μ − 0.5σ ≤ m ≤ μ + 0.5σ   (the smallest-worthwhile-change band: Vesterinen 2016,
//                                             Javaloyes 2019, Nuuttila 2022)
//       above     m > μ + 0.5σ               (can follow rest OR heavy fatigue: HRV also rises when
//                                             overreached, Bellenger 2016 / Le Meur 2013 — never "good")
//       below     μ − 1.0σ ≤ m < μ − 0.5σ
//       low       m < μ − 1.0σ               (Kiviniemi 2007 used mean − 1 SD as the rest signal)
//   • No recent data: the newest valid night is more than `staleDays` before `asOf` → no status.
//   • Nights in `flaggedDays` (illness heads-up, etc.) are left out of the usual range only; if any sits in
//     the short window the reading says it may reflect that.
//
// NOOP's nightly RMSSD comes from deep-sleep windows only, so published age norms do not apply: there is
// no "poor for your age" tier. Pure and deterministic; the Kotlin twin (`HRVStatus.kt`) must match.
public enum HRVStatus {

    public enum Band: String, Equatable, Sendable { case balanced, above, below, low }

    public struct Night: Equatable, Sendable {
        public let day: String     // yyyy-MM-dd
        public let rmssd: Double?  // ms
        public init(day: String, rmssd: Double?) { self.day = day; self.rmssd = rmssd }
    }

    public struct Reading: Equatable, Sendable {
        public let band: Band
        public let mean7Ms: Double        // exp(mean ln RMSSD) over the short window
        public let usualLowMs: Double     // exp(μ − 0.5σ)
        public let usualHighMs: Double    // exp(μ + 0.5σ)
        public let lowMs: Double          // exp(μ − 1.0σ), the "low" threshold
        public let shortNights: Int       // valid nights in the 7-day window (3…7)
        public let baselineNights: Int    // valid nights in the usual range
        public let mayReflectFlaggedDays: Bool
        /// Fewer than `solidShortNights` in the 7-day window: shown, but marked tentative.
        public var tentative: Bool { shortNights < HRVStatus.solidShortNights }
    }

    public enum Outcome: Equatable, Sendable {
        case calibrating(baselineNights: Int)
        case noRecentData
        case status(Reading)
    }

    public static let shortDays = 7
    public static let baselineDays = 60
    public static let minShortNights = 3
    public static let solidShortNights = 5
    public static let minBaselineNights = 21
    public static let staleDays = 3
    public static let usualK = 0.5
    public static let lowK = 1.0
    public static let sdFloor = 0.08
    public static let winsorK = 3.0

    public static func evaluate(nights: [Night], asOf: String, flaggedDays: Set<String> = []) -> Outcome {
        guard let end = VitalityEngine.epochDay(asOf) else { return .calibrating(baselineNights: 0) }
        let cfg = Baselines.hrvCfg
        var short: [Double] = [], base: [Double] = []
        var newest: Int? = nil
        var flaggedInShort = false
        for n in nights.sorted(by: { $0.day < $1.day }) {
            guard let e = VitalityEngine.epochDay(n.day), e <= end,
                  let v = n.rmssd, v >= cfg.minVal, v <= cfg.maxVal else { continue }
            let l = log(v)
            if e > end - shortDays {
                short.append(l)
                newest = e
                if flaggedDays.contains(n.day) { flaggedInShort = true }
            } else if e > end - shortDays - baselineDays, !flaggedDays.contains(n.day) {
                base.append(l)
            }
        }
        guard base.count >= minBaselineNights else { return .calibrating(baselineNights: base.count) }
        guard let last = newest, end - last <= staleDays, short.count >= minShortNights else {
            return .noRecentData
        }
        let (mu, sigma) = winsorisedMeanSD(base)
        let m = mean(short)
        let band: Band
        if m > mu + usualK * sigma { band = .above }
        else if m >= mu - usualK * sigma { band = .balanced }
        else if m >= mu - lowK * sigma { band = .below }
        else { band = .low }
        return .status(Reading(
            band: band, mean7Ms: exp(m),
            usualLowMs: exp(mu - usualK * sigma), usualHighMs: exp(mu + usualK * sigma),
            lowMs: exp(mu - lowK * sigma), shortNights: short.count, baselineNights: base.count,
            mayReflectFlaggedDays: flaggedInShort))
    }

    /// The status for each of the last `days` days ending on `asOf` (oldest first), for a history strip.
    public static func history(nights: [Night], asOf: String, days: Int,
                               flaggedDays: Set<String> = []) -> [(day: String, outcome: Outcome)] {
        guard let end = VitalityEngine.epochDay(asOf), days > 0 else { return [] }
        return (0..<days).map { i in
            let d = dayString(end - (days - 1) + i)
            return (d, evaluate(nights: nights, asOf: d, flaggedDays: flaggedDays))
        }
    }

    // MARK: helpers (same summation order as the Kotlin twin)

    static func mean(_ xs: [Double]) -> Double {
        var s = 0.0
        for x in xs { s += x }
        return s / Double(xs.count)
    }

    static func sampleSD(_ xs: [Double], mean m: Double) -> Double {
        guard xs.count >= 2 else { return 0 }
        var s = 0.0
        for x in xs { s += (x - m) * (x - m) }
        return (s / Double(xs.count - 1)).squareRoot()
    }

    /// One winsorising pass at ±3 SD, then mean and SD (floored).
    static func winsorisedMeanSD(_ xs: [Double]) -> (Double, Double) {
        let m0 = mean(xs)
        let s0 = sampleSD(xs, mean: m0)
        let lo = m0 - winsorK * s0, hi = m0 + winsorK * s0
        let w = xs.map { min(hi, max(lo, $0)) }
        let m = mean(w)
        return (m, max(sampleSD(w, mean: m), sdFloor))
    }

    /// yyyy-MM-dd for days since 1970-01-01 (Hinnant's civil_from_days), the inverse of epochDay.
    static func dayString(_ z0: Int) -> String {
        let z = z0 + 719_468
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
}
