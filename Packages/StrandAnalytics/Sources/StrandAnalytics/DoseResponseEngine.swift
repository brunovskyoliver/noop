import Foundation

// DoseResponseEngine.swift — a personal dose→outcome slope that SHRINKS toward a
// documented population prior until the user has logged enough nights.
//
// Pure, deterministic, DB-free. Journal behaviours can carry an optional integer DOSE
// (alcohol: drinks 0/1/2/3+; caffeine: a time-of-day bucket 0..3). For a dosed behaviour
// we estimate "how much does each extra unit move tomorrow's outcome FOR YOU?":
//
//   1. Pair (dose_d, outcome_{d+1}) for each logged day with a next-day outcome (the same
//      L=1 alignment EffectRanker / ActivityCostEngine use, via CorrelationEngine.shiftDay).
//   2. Fit the PERSONAL slope β_user = OLS slope of outcome on dose via the slope that
//      CorrelationEngine.pearson already returns; n_user = paired days that fed that fit.
//      (pearson needs ≥ 3 pairs AND spread in both axes; if it can't fit, β_user is undefined,
//      n_user = 0 and the result is the prior alone. Logged days that all share one dose say
//      nothing about a slope however many there are, so they cannot raise confidence.)
//   3. SHRINK toward the conservative documented prior β_prior (DoseResponsePriors):
//          β = w · β_user + (1 − w) · β_prior,   w = n_user / (n_user + k)
//      with k = shrinkageK (the pseudo-count of "prior days"). n_user = 0 ⇒ β = β_prior;
//      n_user ≫ k ⇒ β → β_user. β is then clamped to the prior's sane range.
//   4. Report the per-incremental-unit Δ (= β), the personal curve points for the chart, and
//      a ScoreConfidence from n_user / w (mostly-prior → calibrating; blended → building;
//      personal-dominant with enough nights → solid).
//
// HONESTY baked in (the product IS the honesty):
//   - Below the dose gate (n_user < minDoseDays) the result is flagged `priorDominated` so the
//     card can say "population estimate" and show the prior. The priors carry no citation in
//     this repository; treat them as conservative assumptions.
//   - Once the user has enough data, the PERSON overrides the population: if the personal slope
//     contradicts the prior with the prior outside its 95% interval, β follows the user, and
//     `contradictsPrior` flags the "in your data so far, this doesn't move your Charge" copy.
//   - Caffeine "dose" is a TIMING proxy (later = stronger), never mg — the priors table & UI say so.
// Nothing here is a causal/clinical claim; it is association on the user's own logged days.
//
// The Kotlin DoseResponseEngine twin still has the sign-only gate and the n_user that counts
// days with no slope; the iPhone app no longer matches it. (Spec:
// 2026-06-19-v5-insights-correlation-engine-design.md — "Personal dose-response with
// population-prior shrinkage".)

// MARK: - Result

/// A personal, prior-shrunk dose-response estimate for one dosed behaviour on one outcome.
public struct DoseResponse: Equatable, Sendable {
    /// The dosed behaviour this estimate is for.
    public let behavior: DosedBehavior
    /// The outcome label the slope is expressed in (e.g. "Charge", "HRV").
    public let outcome: String
    /// The SHRUNK, clamped effect per ONE extra unit of dose (signed). This is the headline
    /// "each extra drink ≈ Δ for you" number.
    public let perUnit: Double
    /// The user's own OLS slope (signed), or nil when there weren't enough/spread-y pairs to fit.
    public let userSlope: Double?
    /// The documented population prior's per-unit slope this estimate shrank toward.
    public let priorSlope: Double
    /// The shrinkage weight w = n_user / (n_user + k) in [0, 1]; 0 = pure prior, →1 = pure personal.
    public let weight: Double
    /// Number of (dose, next-day-outcome) pairs that backed the personal fit; 0 when there is no fit.
    public let nUser: Int
    /// True while the estimate is mostly the prior (n_user below the dose gate) — show the
    /// "population estimate" banner.
    public let priorDominated: Bool
    /// True when the user has enough data, their slope's SIGN disagrees with the prior, AND the
    /// prior lies outside the slope's 95% interval — show
    /// the "in your data so far, this doesn't move your …" copy (person overrides population).
    public let contradictsPrior: Bool
    /// Per-result certainty tier from n_user / w.
    public let confidence: ScoreConfidence
    /// Curve points (dose, projectedOutcomeDelta-from-baseline) for the chart, dose 0…maxDose,
    /// using the shrunk slope from a 0-dose anchor of 0 (relative deltas, so the UI can offset
    /// them onto any baseline). Always present for dose 0…maxCurveDose.
    public let curve: [DoseCurvePoint]

    public init(behavior: DosedBehavior, outcome: String, perUnit: Double,
                userSlope: Double?, priorSlope: Double, weight: Double, nUser: Int,
                priorDominated: Bool, contradictsPrior: Bool,
                confidence: ScoreConfidence, curve: [DoseCurvePoint]) {
        self.behavior = behavior
        self.outcome = outcome
        self.perUnit = perUnit
        self.userSlope = userSlope
        self.priorSlope = priorSlope
        self.weight = weight
        self.nUser = nUser
        self.priorDominated = priorDominated
        self.contradictsPrior = contradictsPrior
        self.confidence = confidence
        self.curve = curve
    }

    /// The signed Δ on the outcome for going from `fromDose` to `toDose` units. Used by the
    /// evening Damage Forecast: each incremental unit contributes `perUnit`.
    public func delta(fromDose: Int, toDose: Int) -> Double {
        Double(toDose - fromDose) * perUnit
    }

    /// Plain-English read. Honest about whether it's still the prior or now the user's own.
    public func sentence() -> String {
        let mag = DoseResponseEngine.round1(abs(perUnit))
        let dir = perUnit <= 0 ? "lower" : "higher"
        if priorDominated {
            return "Each extra unit typically lines up with about \(mag) \(outcome) \(dir) "
                + "- population estimate, not your data (n=\(nUser))."
        }
        if contradictsPrior {
            return "In your data so far, this doesn't move your \(outcome) the way it typically "
                + "does (n=\(nUser))."
        }
        return "Each extra unit tends to line up with about \(mag) \(outcome) \(dir) for you "
            + "(n=\(nUser))."
    }
}

/// One point on the personal dose-response curve: a dose level and the modelled outcome
/// DELTA from the 0-dose anchor at that dose (so the UI can offset onto any baseline).
public struct DoseCurvePoint: Equatable, Sendable {
    public let dose: Int
    public let outcomeDelta: Double
    public init(dose: Int, outcomeDelta: Double) {
        self.dose = dose
        self.outcomeDelta = outcomeDelta
    }
}

// MARK: - Engine

public enum DoseResponseEngine {

    // MARK: Tunables (documented, deterministic — NOT learned). Mirror Kotlin exactly.

    /// Pseudo-count of "prior days": the shrinkage constant k in w = n/(n+k). With n_user = k
    /// the estimate is a 50/50 blend; larger k leans harder on the prior for longer.
    public static let shrinkageK: Double = 8.0
    /// Paired (dose, next-day) days below which the estimate is `priorDominated` (show the
    /// "population estimate" banner).
    public static let minDoseDays: Int = 5
    /// n_user at/above which confidence can reach `.solid` (the personal slope is trusted).
    public static let solidDoseDays: Int = 12
    /// The highest dose level the curve enumerates (0…maxCurveDose), matching the 0/1/2/3+ axis.
    public static let maxCurveDose: Int = 3

    // MARK: - Doses

    /// One day's dose from the journal: a Yes with no explicit amount reads 1, a No reads 0, and an
    /// explicit dose row wins. Without the No days every dose would be 1 and no slope could exist.
    public static func mergedDoses(yesDays: Set<String>, noDays: Set<String>,
                                   explicit: [String: Int]) -> [String: Int] {
        var doses: [String: Int] = [:]
        for day in noDays { doses[day] = 0 }
        for day in yesDays { doses[day] = 1 }
        doses.merge(explicit) { _, new in new }
        return doses
    }

    // MARK: - Estimate

    /// Estimate the prior-shrunk dose-response for a behaviour against its DEFAULT outcome.
    ///
    /// - Parameters:
    ///   - behavior: the dosed behaviour (must have a documented prior or this returns nil).
    ///   - doseByDay: dose integer per "yyyy-MM-dd" the behaviour was logged with a dose ≥ 0.
    ///   - outcomeByDay: the daily outcome series keyed "yyyy-MM-dd".
    /// - Returns: a `DoseResponse`, or nil when no prior is documented for the behaviour.
    public static func estimate(behavior: DosedBehavior,
                                doseByDay: [String: Int],
                                outcomeByDay: [String: Double]) -> DoseResponse? {
        let outcome = DoseResponsePriors.defaultOutcome(for: behavior)
        return estimate(behavior: behavior, outcome: outcome,
                        doseByDay: doseByDay, outcomeByDay: outcomeByDay)
    }

    /// Estimate the prior-shrunk dose-response for a behaviour against a NAMED outcome.
    /// Returns nil when `(behaviour, outcome)` has no documented prior to shrink toward.
    public static func estimate(behavior: DosedBehavior,
                                outcome: String,
                                doseByDay: [String: Int],
                                outcomeByDay: [String: Double]) -> DoseResponse? {
        guard let prior = DoseResponsePriors.prior(for: behavior, outcome: outcome) else { return nil }

        // Pair each logged dose day D with the NEXT-day outcome (D+1) — the L=1 alignment.
        var pairs: [(Double, Double)] = []
        // Sort the day keys so the pair order (and thus any float reduction) is deterministic.
        for day in doseByDay.keys.sorted() {
            let dose = doseByDay[day]!
            guard let d1 = CorrelationEngine.shiftDay(day, by: 1),
                  let outVal = outcomeByDay[d1] else { continue }
            pairs.append((Double(dose), outVal))
        }
        // Personal OLS slope of outcome on dose (nil if < 3 pairs or no spread in either axis).
        let userSlope = CorrelationEngine.pearson(pairs)?.slope
        let nUser = userSlope == nil ? 0 : pairs.count

        // Shrinkage weight: 0 with no data, → 1 as data accumulates past k.
        let w = Double(nUser) / (Double(nUser) + shrinkageK)

        // Blend, then clamp to the prior's sane range. With no usable personal slope the blend
        // falls back to the prior alone (w applied to nothing), which is the honest cold-start.
        let blended: Double
        if let us = userSlope {
            blended = w * us + (1.0 - w) * prior.slopePerUnit
        } else {
            blended = prior.slopePerUnit
        }
        let perUnit = clamp(blended, prior.clampLow, prior.clampHigh)

        let priorDominated = nUser < minDoseDays
        // Person overrides population only once they have enough data, the signs disagree (e.g.
        // prior says drinking lowers Charge but your slope is ≥ 0), and the data can tell the two
        // apart. Sign alone flips by chance on about a quarter of people at n=5.
        let contradicts: Bool
        if let us = userSlope, nUser >= minDoseDays {
            contradicts = !sameSign(us, prior.slopePerUnit)
                && abs(us - prior.slopePerUnit) > slopeHalfInterval(pairs, slope: us)
        } else {
            contradicts = false
        }

        let confidence = confidenceFor(nUser: nUser)

        // Curve: relative outcome delta from a 0-dose anchor, dose 0…maxCurveDose, using perUnit.
        var curve: [DoseCurvePoint] = []
        for dose in 0...maxCurveDose {
            curve.append(DoseCurvePoint(dose: dose, outcomeDelta: Double(dose) * perUnit + 0.0)) // +0.0 normalises -0.0 → 0.0
        }

        return DoseResponse(behavior: behavior, outcome: outcome, perUnit: perUnit,
                            userSlope: userSlope, priorSlope: prior.slopePerUnit,
                            weight: w, nUser: nUser, priorDominated: priorDominated,
                            contradictsPrior: contradicts, confidence: confidence, curve: curve)
    }

    // MARK: - Confidence

    /// Calibrating while mostly prior (n_user < minDoseDays); building while blended; solid
    /// once the personal fit dominates (n_user ≥ solidDoseDays).
    static func confidenceFor(nUser: Int) -> ScoreConfidence {
        if nUser < minDoseDays { return .calibrating }
        return nUser >= solidDoseDays ? .solid : .building
    }

    // MARK: - Helpers

    /// Half-width of the OLS slope's 95% interval on n−2 degrees of freedom.
    static func slopeHalfInterval(_ pairs: [(Double, Double)], slope: Double) -> Double {
        let n = Double(pairs.count)
        let meanX = pairs.reduce(0) { $0 + $1.0 } / n, meanY = pairs.reduce(0) { $0 + $1.1 } / n
        let sxx = pairs.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        let residual = pairs.reduce(0) { sum, p in
            let e = p.1 - meanY - slope * (p.0 - meanX)
            return sum + e * e
        }
        return CorrelationEngine.studentTQuantile(twoSidedP: 0.05, df: n - 2)
            * (residual / (n - 2) / sxx).squareRoot()
    }

    /// True when a and b share a sign. Zero is treated as "not the same sign" as a non-zero
    /// value (a flat personal slope DOES contradict a non-zero prior — that's the honest read).
    static func sameSign(_ a: Double, _ b: Double) -> Bool {
        if a > 0 && b > 0 { return true }
        if a < 0 && b < 0 { return true }
        if a == 0 && b == 0 { return true }
        return false
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(x, lo), hi)
    }

    /// Round to one decimal place (half away from zero via Foundation's rounded()).
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
