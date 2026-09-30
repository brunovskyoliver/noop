import Foundation

// SleepPlanner.swift — tonight's bedtime for 100 / 85 / 70 % of your sleep need.
//
// Method (docs/research/2026-09-24-offline-feature-research.md §2):
//   need      = base + min(33 % of sleep debt, 90 min) − today's nap sleep (at most 60 min off)
//               Debt is repaid over several nights, not one: 1 h of debt took about 4 nights of extended
//               sleep to recover (Kitamura 2016). There is no strain term: no study supports one.
//   goal      = need × tier (1.00 / 0.85 / 0.70)
//   inBed     = goal ÷ efficiency + latency. Efficiency is the median of recent nights (0.75–0.97,
//               default 0.88); latency defaults to 15 min.
//   bedtime   = wake − inBed, rounded to 5 min.
//   guard     = no earlier than 90 min before the usual bedtime: sleep is hard to start well before the
//               habitual time (the evening "forbidden zone"), so a bigger gap is spread over later nights
//               and the tier is marked not reachable tonight.
//
// Times are minutes after local midnight (0…1439). Pure and deterministic; the Kotlin twin
// (`SleepPlanner.kt`) must return identical values.
public enum SleepPlanner {

    public struct Inputs: Equatable, Sendable {
        public var baseNeedHours: Double
        public var debtMin: Double
        public var napMin: Double
        public var efficiencies: [Double]        // recent nights, 0–1 (a value > 1 is read as a percent)
        public var latencyMin: Double
        public var wakeMinute: Int
        public var recentBedMinutes: [Int]       // recent main-sleep start times, minutes after midnight
        public init(baseNeedHours: Double, debtMin: Double = 0, napMin: Double = 0, efficiencies: [Double] = [],
                    latencyMin: Double = SleepPlanner.defaultLatencyMin, wakeMinute: Int,
                    recentBedMinutes: [Int] = []) {
            self.baseNeedHours = baseNeedHours; self.debtMin = debtMin; self.napMin = napMin
            self.efficiencies = efficiencies; self.latencyMin = latencyMin; self.wakeMinute = wakeMinute
            self.recentBedMinutes = recentBedMinutes
        }
    }

    public struct Tier: Equatable, Sendable {
        public let fraction: Double
        public let goalSleepMin: Double
        public let inBedMin: Double
        public let bedMinute: Int                // the bedtime to aim for (after the guard)
        public let reachable: Bool               // false when the guard moved the bedtime later
        public let expectedSleepMin: Double      // sleep this bedtime gives at the planned efficiency
    }

    public struct Plan: Equatable, Sendable {
        public let baseNeedMin: Double
        public let debtAddMin: Double
        public let napSubMin: Double
        public let needMin: Double
        public let efficiency: Double
        public let latencyMin: Double
        public let wakeMinute: Int
        public let usualBedMinute: Int?
        public let tiers: [Tier]                 // 1.00, 0.85, 0.70
        /// The full-need tier: the bedtime other features (caffeine cutoff, wind-down) plan around.
        public var target: Tier { tiers[0] }
    }

    public static let tierFractions: [Double] = [1.0, 0.85, 0.70]
    public static let debtRepayShare = 0.33
    public static let maxDebtAddMin = 90.0
    public static let maxNapSubMin = 60.0
    public static let maxNeedMin = 660.0
    public static let defaultEfficiency = 0.88
    public static let minEfficiency = 0.75
    public static let maxEfficiency = 0.97
    public static let minEfficiencyNights = 3
    public static let defaultLatencyMin = 15.0
    public static let maxInBedMin = 720.0
    /// The longest bed-to-wake window a plan can hold: the in-bed cap plus the bedtime's rounding to
    /// `roundToMin` (half a step either way). The wind-down reminder clamps its stored window to this, so a
    /// long plan and its reminder can never name different bedtimes.
    public static let maxWindowMin = Int(maxInBedMin) + roundToMin / 2
    public static let maxEarlierThanUsualMin = 90
    public static let roundToMin = 5

    public static func plan(_ i: Inputs) -> Plan {
        let base = max(0, i.baseNeedHours) * 60
        let debtAdd = min(debtRepayShare * max(0, i.debtMin), maxDebtAddMin)
        let napSub = min(max(0, i.napMin), maxNapSubMin)
        let need = min(max(0, base + debtAdd - napSub), maxNeedMin)
        let eff = efficiency(i.efficiencies)
        let latency = max(0, i.latencyMin)
        let wake = wrap(i.wakeMinute)
        let usual = usualBedMinute(i.recentBedMinutes)
        let tiers = tierFractions.map { f -> Tier in
            let goal = need * f
            let inBed = min(goal / eff + latency, maxInBedMin)
            var bed = wrap(roundTo(Double(wake) - inBed))
            var reachable = true
            if let u = usual {
                let earlier = wrap(u - bed)                 // minutes the plan is earlier than usual
                if earlier > maxEarlierThanUsualMin && earlier < 720 {
                    bed = wrap(u - maxEarlierThanUsualMin)
                    reachable = false
                }
            }
            let window = Double(wrap(wake - bed))
            let expected = max(0, window - latency) * eff
            return Tier(fraction: f, goalSleepMin: goal, inBedMin: inBed, bedMinute: bed,
                        reachable: reachable, expectedSleepMin: expected)
        }
        return Plan(baseNeedMin: base, debtAddMin: debtAdd, napSubMin: napSub, needMin: need, efficiency: eff,
                    latencyMin: latency, wakeMinute: wake, usualBedMinute: usual, tiers: tiers)
    }

    /// Median of recent nights' efficiency (percent values normalised), clamped; default below 3 nights.
    static func efficiency(_ xs: [Double]) -> Double {
        let v = xs.compactMap { e -> Double? in
            guard e.isFinite, e > 0 else { return nil }
            let f = e > 1 ? e / 100 : e
            return f <= 1 ? f : nil
        }
        guard v.count >= minEfficiencyNights else { return defaultEfficiency }
        let s = v.sorted(); let n = s.count
        let m = n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        return min(max(m, minEfficiency), maxEfficiency)
    }

    /// Median bedtime on a clock that runs noon→noon, so 23:30 and 00:30 sit next to each other.
    static func usualBedMinute(_ xs: [Int]) -> Int? {
        guard !xs.isEmpty else { return nil }
        let shifted = xs.map { wrap($0 - 720) }.sorted()
        let n = shifted.count
        let m = n % 2 == 1 ? Double(shifted[n / 2]) : Double(shifted[n / 2 - 1] + shifted[n / 2]) / 2
        return wrap(Int((m + 0.5).rounded(.down)) + 720)
    }

    static func wrap(_ m: Int) -> Int { ((m % 1440) + 1440) % 1440 }

    static func roundTo(_ x: Double) -> Int {
        let step = Double(roundToMin)
        return Int((x / step + 0.5).rounded(.down)) * roundToMin
    }
}
