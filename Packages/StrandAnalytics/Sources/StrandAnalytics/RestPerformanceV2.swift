import Foundation
import WhoopStore

// RestPerformanceV2.swift — Rest v2: WHOOP's 2025 Sleep Performance shape.
//
// WHOOP (support, 2025 Sleep update) scores Sleep Performance from four parts: Sufficiency (hours slept vs
// sleep need), Consistency (sleep and wake timing vs the previous 4 days), Efficiency (asleep / in bed)
// and Sleep Stress (time in high stress during sleep). Restorative sleep is shown beside it, not scored.
// Weights are not published. NOOP's choice, keeping sufficiency dominant as the feature-gap notes advise:
//
//     Sufficiency 0.55 · Consistency 0.15 · Efficiency 0.15 · Sleep Stress 0.15
//
// Each part is a 0–1 credit:
//   - sufficiency = min(asleep / need, 1), need = the engine's personalised need (`Rest.personalizedNeedHours`)
//   - consistency = a Sleep Regularity Index over the main-sleep windows (Phillips et al. 2017, Sci Rep 7:3216):
//     for each of the previous 4 nights, the share of a 24 h window whose sleep/wake state matches tonight's
//     at the same clock time (A), mapped SRI-style as 2A − 1 and clamped to [0, 1], then averaged
//   - efficiency = asleep / in bed
//   - sleep stress = 1 − min(pct / 30, 1): a night with 30 % or more of its sleep in HIGH stress earns no
//     credit, a typical 0–5 % night keeps ≥ 83 %
//
// DEGRADATION: sufficiency and efficiency are required (they come from the night's own totals; without
// them there is no score, as before). A missing consistency (fewer than 2 of the previous 4 nights known)
// or sleep stress (no scorable night heart rate) is dropped and the remaining weights are renormalised to
// sum to 1, so a night is scored on what was measured rather than on an invented neutral value.
public extension AnalyticsEngine {

    enum RestV2 {
        public static let wSufficiency = 0.55
        public static let wConsistency = 0.15
        public static let wEfficiency = 0.15
        public static let wSleepStress = 0.15

        /// Sleep-stress share (0–100) at which the sleep-stress credit reaches zero.
        public static let sleepStressZeroCreditPct = 30.0
        /// Previous nights the consistency compares against, and how many must be known.
        public static let consistencyPriorNights = 4
        public static let minConsistencyPriorNights = 2

        /// The four credits, each 0–1; nil = not measured for this night.
        public struct Parts: Equatable, Sendable {
            public let sufficiency: Double
            public let consistency: Double?
            public let efficiency: Double
            public let sleepStress: Double?
            public init(sufficiency: Double, consistency: Double?, efficiency: Double, sleepStress: Double?) {
                self.sufficiency = sufficiency; self.consistency = consistency
                self.efficiency = efficiency; self.sleepStress = sleepStress
            }
        }

        static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

        /// Credit for a night's Sleep Stress share (0–100 %).
        public static func sleepStressCredit(pct: Double) -> Double {
            clamp01(1.0 - pct / sleepStressZeroCreditPct)
        }

        public static func parts(tstSeconds: Double, efficiency: Double, needHours: Double,
                                 consistency: Double?, sleepStressPct: Double?) -> Parts {
            let need = max(needHours, 0.1) * 3600.0
            return Parts(sufficiency: clamp01(tstSeconds / need),
                         consistency: consistency.map(clamp01),
                         efficiency: clamp01(efficiency),
                         sleepStress: sleepStressPct.map(sleepStressCredit(pct:)))
        }

        /// The 0–100 score, renormalised over the parts that are present, rounded to 2 dp like `Rest`.
        public static func composite(_ p: Parts) -> Double {
            var wSum = wSufficiency + wEfficiency
            var sum = wSufficiency * p.sufficiency + wEfficiency * p.efficiency
            if let c = p.consistency { sum += wConsistency * c; wSum += wConsistency }
            if let s = p.sleepStress { sum += wSleepStress * s; wSum += wSleepStress }
            return ((sum / wSum) * 10000.0).rounded() / 100.0
        }

        /// Rest v2 from a persisted day row. nil when the day has no asleep time or no efficiency, the
        /// same gate as `Rest.composite(daily:)`.
        public static func composite(daily d: DailyMetric, needHours: Double = Rest.defaultNeedHours,
                                     consistency: Double? = nil, sleepStressPct: Double? = nil) -> Double? {
            guard let p = parts(daily: d, needHours: needHours, consistency: consistency,
                                sleepStressPct: sleepStressPct) else { return nil }
            return composite(p)
        }

        public static func parts(daily d: DailyMetric, needHours: Double = Rest.defaultNeedHours,
                                 consistency: Double? = nil, sleepStressPct: Double? = nil) -> Parts? {
            guard let tstMin = d.totalSleepMin, tstMin > 0, let eff = d.efficiency else { return nil }
            // Imported rows carry efficiency as a percentage; computed rows as a fraction.
            let e = eff > 1.0 ? eff / 100.0 : eff
            return parts(tstSeconds: tstMin * 60.0, efficiency: e, needHours: needHours,
                         consistency: consistency, sleepStressPct: sleepStressPct)
        }

        /// One main sleep, as a wall-clock interval, plus how many days before the scored night it ended.
        public struct Night: Equatable, Sendable {
            public let start: Int
            public let end: Int
            public let daysBefore: Int
            public init(start: Int, end: Int, daysBefore: Int) {
                self.start = start; self.end = end; self.daysBefore = daysBefore
            }
        }

        /// Sleep Regularity Index–style consistency (0–1) of `tonight` against the previous nights
        /// (`daysBefore` 1…4 are used). Each previous night is shifted forward by `daysBefore` × 24 h and
        /// compared over the 24 h window ending 6 h after tonight's wake: agreement A = 1 − |symmetric
        /// difference| / 24 h, credit = clamp(2A − 1). nil under `minConsistencyPriorNights` usable nights.
        public static func consistency(tonight: Night, previous: [Night]) -> Double? {
            let windowEnd = tonight.end + 6 * 3600
            let windowStart = windowEnd - 86_400
            func clip(_ a: Int, _ b: Int) -> (Int, Int)? {
                let s = max(a, windowStart), e = min(b, windowEnd)
                return e > s ? (s, e) : nil
            }
            guard let t = clip(tonight.start, tonight.end) else { return nil }
            var credits: [Double] = []
            for p in previous where p.daysBefore >= 1 && p.daysBefore <= consistencyPriorNights {
                let shift = p.daysBefore * 86_400
                let shifted = clip(p.start + shift, p.end + shift)
                let lenT = t.1 - t.0
                let lenP = shifted.map { $0.1 - $0.0 } ?? 0
                var inter = 0
                if let s = shifted { inter = max(0, min(t.1, s.1) - max(t.0, s.0)) }
                let symDiff = lenT + lenP - 2 * inter
                let agreement = 1.0 - Double(symDiff) / 86_400.0
                credits.append(clamp01(2.0 * agreement - 1.0))
            }
            guard credits.count >= minConsistencyPriorNights else { return nil }
            return credits.reduce(0, +) / Double(credits.count)
        }
    }
}
