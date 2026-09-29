import Foundation

// EnergyReservoir.swift — "Energy": a 0–100 reservoir charged by restful sleep and calm rest and drained by
// being awake, by stress and by exercise, carried from one day into the next (no daily reset).
//
// The idea follows Garmin / Firstbeat Body Battery and Bevel's Energy Bank. Firstbeat's model is
// proprietary and unpublished, so this is NOOP's own estimate with its own constants; it is shown next to
// the scores and feeds nothing (not Charge, Rest, Effort, Healthspan or Mind).
//
// It integrates the Stress Monitor's 5-minute epochs (`StressMonitor.analyzeDay`), so it inherits their
// masks: sleep epochs carry a sleeping stress level built from heart rate and HRV against the personal
// nocturnal reference, waking epochs a level against the personal calm floor, and exercise / movement
// epochs are `.activity` with no stress level. Per epoch (dt = 5 min, E = current level):
//
//   sleep, level L      E += kSleep · q · (100 − E) · dt,  q = clamp((2 − L) / (2 − 0.4), 0, 1)
//                       (0.4 is the typical sleeping level, 2 the high-stress floor: a calm epoch charges
//                       fully, a stressed one not at all; charging slows as the tank fills)
//   waking, level L     E −= (baseline + stressCost · max(0, L − 1)) · dt
//                       and, in a run of ≥ `restRunEpochs` epochs below level 1 (calm and still, since
//                       moving epochs are masked), E += kRest · (100 − E) · dt
//   activity            E −= (baseline + trimpCost · TRIMP_epoch); TRIMP_epoch = Edwards zone weight of
//                       the epoch's mean heart rate × 5 min. Stress is masked here, so nothing is counted
//                       twice.
//   no data / sleep without heart rate: level held, marked as a gap. Nothing is interpolated.
// The level is clamped to 0…100 after every epoch.
//
// Calibration (NOOP's choice, to be checked against real data):
//   kSleep 0.25 /h — 8 h of calm sleep from 40 ends at 100 − 60·e^(−2) ≈ 92 (+52), from 20 at ≈ 89 (+69);
//                    a night at level 1.2 (q = 0.5) from 40 only reaches ≈ 77.
//   baseline 2.0 /h — 16 waking hours cost 32 before any stress or exercise.
//   stressCost 6 /h per level above 1 — an hour at level 2 (the high floor) costs 8 in total, at 3 costs 14.
//   trimpCost 0.10 per Edwards TRIMP — an hour in zone 2 costs 12 + 2 baseline.
//   kRest 0.08 /h — a calm half hour at level 50 adds 2, well under a nap's sleep charge.
// A typical waking day (9 h at level 1.0, 3 h at 1.5, 30 min at 2.3, 1 h of zone-2 exercise, 1.5 h of calm
// rest) drains ≈ 55 and a typical 8 h calm night from 40 recharges ≈ 52, so an average day and night roughly
// balance (`EnergyReservoirTests.testTypicalDayAndNightRoughlyBalance` pins both).
//
// Cold start: the Stress Monitor's personal references (the 14-day window, seeded after
// `Baselines.minNightsSeed` days) must exist for both waking and sleep, otherwise nil ("calibrating").
// The first calibrated day with no carried level starts at `seedLevel` and is flagged `seeded`.
public enum EnergyReservoir {

    public static let epochSeconds = StressMonitor.epochSeconds
    public static let kSleepPerHour = 0.25
    public static let baselinePerHour = 2.0
    public static let stressCostPerHour = 6.0
    public static let trimpCost = 0.10
    public static let kRestPerHour = 0.08
    public static let restRunEpochs = 2
    public static let restLevelCeiling = 1.0
    public static let sleepHighLevel = StressMonitor.highFloor
    public static let sleepTypicalLevel = StressMonitor.sleepTypicalLevel
    public static let seedLevel = 50.0

    public enum Kind: String, Sendable {
        case sleep, rest, awake, stress, activity, gap
    }

    public struct Point: Equatable, Sendable {
        public let ts: Int
        /// Level at the END of the epoch.
        public let level: Double
        public let kind: Kind
    }

    public struct DayResult: Equatable, Sendable {
        public let day: String
        public let points: [Point]
        public let summary: EnergyDaySummary
        public var current: Double? { points.last?.level }
    }

    /// Resting HR and HRmax for the activity TRIMP (the Effort scorer's %HRR).
    public struct HeartProfile: Equatable, Sendable {
        public let restingHR: Double
        public let maxHR: Double
        public init(restingHR: Double, maxHR: Double) { self.restingHR = restingHR; self.maxHR = maxHR }
    }

    /// The Stress Monitor references are personal (the calibration gate).
    public static func isCalibrated(_ stress: StressMonitor.DayResult) -> Bool {
        stress.wake?.personal == true && stress.sleep?.personal == true
    }

    /// One epoch's change. `restRun` = consecutive calm waking epochs including this one.
    public static func step(level e: Double, epoch: StressMonitor.Epoch, restRun: Int, heart: HeartProfile,
                            minutes: Double = Double(epochSeconds) / 60)
        -> (level: Double, kind: Kind, charge: Double, stress: Double, activity: Double, baseline: Double) {
        let h = minutes / 60
        switch epoch.state {
        case .sleep:
            guard let l = epoch.level else { return (e, .gap, 0, 0, 0, 0) }
            let q = min(1, max(0, (sleepHighLevel - l) / (sleepHighLevel - sleepTypicalLevel)))
            let gain = kSleepPerHour * q * (100 - e) * h
            return (min(100, e + gain), .sleep, gain, 0, 0, 0)
        case .waking:
            guard let l = epoch.level else { return (e, .gap, 0, 0, 0, 0) }
            let base = baselinePerHour * h
            let stress = stressCostPerHour * max(0, l - 1) * h
            var gain = 0.0
            if l < restLevelCeiling, restRun >= restRunEpochs { gain = kRestPerHour * (100 - e) * h }
            let next = min(100, max(0, e + gain - base - stress))
            let kind: Kind = gain > 0 ? .rest : (l >= StressMonitor.mediumFloor ? .stress : .awake)
            return (next, kind, gain, stress, 0, base)
        case .activity:
            guard let hr = epoch.meanHR, heart.maxHR > heart.restingHR else { return (e, .gap, 0, 0, 0, 0) }
            let weight = StrainTarget.edwardsTrimpPerMinute(bpm: hr, restingHR: heart.restingHR, maxHR: heart.maxHR)
            let act = trimpCost * weight * minutes
            let base = baselinePerHour * h
            return (min(100, max(0, e - act - base)), .activity, 0, 0, act, base)
        case .noData:
            return (e, .gap, 0, 0, 0, 0)
        }
    }

    /// Integrate one day. `startLevel` is the previous day's end (nil → `seedLevel`, flagged). nil when the
    /// stress references are not personal yet.
    public static func day(_ stress: StressMonitor.DayResult, startLevel: Double?, heart: HeartProfile) -> DayResult? {
        guard isCalibrated(stress) else { return nil }
        let start = min(100, max(0, startLevel ?? seedLevel))
        var e = start
        var points: [Point] = []
        points.reserveCapacity(stress.epochs.count)
        var charged = 0.0, dStress = 0.0, dAct = 0.0, dBase = 0.0
        var peak = start, low = start
        var restRun = 0
        var wake: Double?
        var sawMain = false
        for ep in stress.epochs {
            if ep.state == .waking, let l = ep.level, l < restLevelCeiling { restRun += 1 } else { restRun = 0 }
            let before = e
            let s = step(level: e, epoch: ep, restRun: restRun, heart: heart)
            e = s.level
            // Book the actual change (clamping can cut a drain or a gain short).
            let delta = e - before
            if delta > 0 { charged += delta }
            let spent = s.stress + s.activity + s.baseline
            if delta < 0, spent > 0 {
                let f = -delta / spent
                dStress += s.stress * f; dAct += s.activity * f; dBase += s.baseline * f
            }
            if ep.inMainSleep { sawMain = true } else if sawMain && wake == nil { wake = before }
            peak = max(peak, e); low = min(low, e)
            points.append(Point(ts: ep.startTs + epochSeconds, level: e, kind: s.kind))
        }
        if sawMain && wake == nil { wake = e }
        let summary = EnergyDaySummary(day: stress.day, start: start, end: e, wake: wake, peak: peak, low: low,
                                       charged: charged, drainStress: dStress, drainActivity: dAct,
                                       drainBaseline: dBase, seeded: startLevel == nil)
        return DayResult(day: stress.day, points: points, summary: summary)
    }

    /// The live "now": the day's last level carried forward over the minutes since its last epoch with the
    /// live stress level as a waking epoch. nil live level (no reading, or moving) holds the level.
    public static func projectNow(level: Double, minutesSinceLastEpoch: Double, liveLevel: Double?,
                                  heart: HeartProfile) -> Double {
        guard let liveLevel, minutesSinceLastEpoch > 0 else { return level }
        let ep = StressMonitor.Epoch(startTs: 0, state: .waking, level: liveLevel, meanHR: nil, rmssd: nil,
                                     inMainSleep: false)
        return step(level: level, epoch: ep, restRun: 0, heart: heart,
                    minutes: min(minutesSinceLastEpoch, Double(epochSeconds) / 60 * 6)).level
    }
}

/// The per-day Energy numbers that are stored (they survive raw-data retention, like `StressDaySummary`).
public struct EnergyDaySummary: Equatable, Sendable {
    public let day: String
    public let start: Double
    public let end: Double
    /// Level when the main sleep ended; nil without a main sleep that day.
    public let wake: Double?
    public let peak: Double
    public let low: Double
    public let charged: Double
    public let drainStress: Double
    public let drainActivity: Double
    public let drainBaseline: Double
    /// True when the day started from `EnergyReservoir.seedLevel` rather than a carried level.
    public let seeded: Bool
    public var drained: Double { drainStress + drainActivity + drainBaseline }

    public init(day: String, start: Double, end: Double, wake: Double?, peak: Double, low: Double,
                charged: Double, drainStress: Double, drainActivity: Double, drainBaseline: Double, seeded: Bool) {
        self.day = day; self.start = start; self.end = end; self.wake = wake; self.peak = peak; self.low = low
        self.charged = charged; self.drainStress = drainStress; self.drainActivity = drainActivity
        self.drainBaseline = drainBaseline; self.seeded = seeded
    }

    public enum Key {
        public static let start = "energy_start"
        public static let end = "energy_end"
        public static let wake = "energy_wake"
        public static let peak = "energy_peak"
        public static let low = "energy_low"
        public static let charged = "energy_charged"
        public static let drainStress = "energy_drain_stress"
        public static let drainActivity = "energy_drain_activity"
        public static let drainBaseline = "energy_drain_baseline"
        public static let seeded = "energy_seeded"
        public static let all = [start, end, wake, peak, low, charged, drainStress, drainActivity, drainBaseline, seeded]
    }

    public var storedPairs: [(key: String, value: Double)] {
        func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        var out: [(key: String, value: Double)] = [
            (Key.start, r(start)), (Key.end, r(end)), (Key.peak, r(peak)), (Key.low, r(low)),
            (Key.charged, r(charged)), (Key.drainStress, r(drainStress)), (Key.drainActivity, r(drainActivity)),
            (Key.drainBaseline, r(drainBaseline)), (Key.seeded, seeded ? 1 : 0),
        ]
        if let wake { out.append((Key.wake, r(wake))) }
        return out
    }

    public static func fromStored(day: String, values v: [String: Double]) -> EnergyDaySummary? {
        guard let start = v[Key.start], let end = v[Key.end], let peak = v[Key.peak], let low = v[Key.low],
              let charged = v[Key.charged] else { return nil }
        return EnergyDaySummary(day: day, start: start, end: end, wake: v[Key.wake], peak: peak, low: low,
                                charged: charged, drainStress: v[Key.drainStress] ?? 0,
                                drainActivity: v[Key.drainActivity] ?? 0, drainBaseline: v[Key.drainBaseline] ?? 0,
                                seeded: (v[Key.seeded] ?? 0) > 0)
    }
}
