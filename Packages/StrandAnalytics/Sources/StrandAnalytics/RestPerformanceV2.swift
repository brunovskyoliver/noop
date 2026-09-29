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
//   - consistency = `SleepRegularity.restConsistency`: tonight's 24 h sleep/wake epochs (naps and wake after
//     onset included) against each of the previous 4 days at the same clock time, agreement A mapped
//     SRI-style as 2A − 1, clamped to [0, 1], then averaged. Same engine as the 7-day SRI.
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
    }
}
