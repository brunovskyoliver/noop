import Foundation

// StrainTarget.swift — today's Effort target band (WHOOP's "Strain Coach" idea), NOOP's own mapping.
//
// WHOOP describes a recommended day strain from the day's Recovery that "maintains fitness and still
// recovers", adjustable to restorative / optimal / overreaching, but does not publish the curve. NOOP's
// previous display mapping was three fixed bands on the 0–21 axis (Charge ≥ 67 → 14–18, 34–66 → 10–14,
// < 34 → 4–10). This replaces them with two straight lines fitted through those bands at their Charge
// midpoints (17, 50, 83), so the old bands are reproduced where they were centred and the band moves
// smoothly between them:
//
//     lower21 = 1.75 + 0.15 · Charge        (17 → 4.3, 50 → 9.3, 83 → 14.2; old 4, 10, 14)
//     upper21 = 8.00 + 0.12 · Charge        (17 → 10.0, 50 → 14.0, 83 → 18.0; old 10, 14, 18)
//
// Both rise with Charge (monotone) and the band narrows from 6.25 to 3.25 as Charge rises, like the old
// red band being the widest. Adjustments, applied on the 0–21 axis in this order:
//   • Sleep debt: past `debtFreeMinutes` (60 min) of debt, both bounds drop `debtPerHour` (0.5) per extra
//     hour, at most `maxDebtShift` (2.0). A short night argues for less load (SleepDebt ledger).
//   • Illness heads-up: both bounds are capped at the old red band (4–10), whatever the Charge.
//   • Goal (Settings → Scoring): Restore −3, Maintain 0, Build +2 on both bounds.
// Then clamped to 0…21 with at least `minWidth21` (1.0) between the bounds, and returned on NOOP's
// internal 0–100 Effort axis (× 100/21). nil when Charge is unknown: never guess a target.
public enum StrainTarget {

    public enum Goal: String, CaseIterable, Sendable {
        case restore, maintain, build
        /// Shift of both bounds on the 0–21 axis.
        public var shift21: Double {
            switch self {
            case .restore: return -3
            case .maintain: return 0
            case .build: return 2
            }
        }
    }

    public enum Zone: String, Sendable {
        /// Below the band: a lighter day than today's Charge supports.
        case restoring
        /// Inside the band.
        case optimal
        /// Above the band.
        case overreaching
    }

    public static let lowerIntercept21 = 1.75, lowerSlope21 = 0.15
    public static let upperIntercept21 = 8.0, upperSlope21 = 0.12
    public static let debtFreeMinutes = 60.0
    public static let debtPerHour21 = 0.5
    public static let maxDebtShift21 = 2.0
    public static let illnessCap21: ClosedRange<Double> = 4...10
    public static let minWidth21 = 1.0
    static let per21 = StrainScorer.maxStrain / 21

    public struct Inputs: Equatable, Sendable {
        public var charge: Double?
        public var sleepDebtMin: Double?
        public var illness: Bool
        public var goal: Goal
        public init(charge: Double?, sleepDebtMin: Double? = nil, illness: Bool = false, goal: Goal = .maintain) {
            self.charge = charge; self.sleepDebtMin = sleepDebtMin; self.illness = illness; self.goal = goal
        }
    }

    /// The target band on the internal 0–100 Effort axis.
    public struct Band: Equatable, Sendable {
        public let lower: Double
        public let upper: Double
        public init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }

        public func zone(effort: Double) -> Zone {
            effort < lower ? .restoring : (effort > upper ? .overreaching : .optimal)
        }
    }

    public static func band(_ i: Inputs) -> Band? {
        guard let c = i.charge, c.isFinite else { return nil }
        let charge = min(100, max(0, c))
        var lo = lowerIntercept21 + lowerSlope21 * charge
        var hi = upperIntercept21 + upperSlope21 * charge
        if let debt = i.sleepDebtMin, debt > debtFreeMinutes {
            let shift = min(maxDebtShift21, (debt - debtFreeMinutes) / 60 * debtPerHour21)
            lo -= shift; hi -= shift
        }
        if i.illness {
            lo = min(lo, illnessCap21.lowerBound); hi = min(hi, illnessCap21.upperBound)
        }
        lo += i.goal.shift21; hi += i.goal.shift21
        lo = min(max(0, lo), 21 - minWidth21)
        hi = min(21, max(hi, lo + minWidth21))
        return Band(lower: lo * per21, upper: hi * per21)
    }

    // MARK: - Minutes to target (the scorer inverted)

    /// Minutes of work at `trimpPerMinute` (Edwards: the zone weight 1–5 of the current heart rate) that
    /// take the day from `currentEffort` to `targetEffort`, both on the 0–100 axis. The scorer is
    /// Effort = 100·ln(TRIMP + 1)/ln(D), so the TRIMP still needed is D^(target/100) − D^(current/100).
    /// 0 when already there; nil when the rate is zero (below zone 1 nothing accrues) or not finite.
    public static func minutesToReach(targetEffort: Double, currentEffort: Double, trimpPerMinute: Double,
                                      denominator: Double = StrainScorer.strainDenominator) -> Double? {
        let needed = StrainScorer.strainToTrimp(targetEffort, denominator: denominator)
            - StrainScorer.strainToTrimp(currentEffort, denominator: denominator)
        if needed <= 0 { return 0 }
        guard trimpPerMinute > 0, trimpPerMinute.isFinite else { return nil }
        return needed / trimpPerMinute
    }

    /// The Edwards TRIMP a minute at `bpm` adds (its zone weight, 0–5), on the same %HRR the scorer uses.
    public static func edwardsTrimpPerMinute(bpm: Double, restingHR: Double, maxHR: Double) -> Double {
        guard maxHR > restingHR else { return 0 }
        return Double(StrainScorer.zoneWeight(bpm, restingHR: restingHR, hrReserve: maxHR - restingHR))
    }
}
