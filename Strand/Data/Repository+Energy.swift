import Foundation
import StrandAnalytics

// Repository+Energy.swift — the ONE funnel for Energy (`EnergyReservoir`), same shape as Stress.
//
// `energyDayAnalysis(dayKey:)` integrates the day's Stress Monitor analysis (`stressDayAnalysis`) from the
// previous day's stored end level. The analysis pass stores each day's summary under the
// `EnergyDaySummary.Key` keys in the "-noop" computed source, oldest → newest, so the next day starts where
// the last one ended. Screens read days through the same function, so a stored day and a drawn day only
// differ by how recently the pass ran. Energy feeds no score.
//
// iOS-only fork change; Android twin intentionally not updated.

/// Settings → Scoring's "Show Energy". Default ON. Hides the Home card and the Health entry only.
enum EnergyPrefs {
    static let showKey = "noop.showEnergy"
    static var show: Bool { UserDefaults.standard.object(forKey: showKey) as? Bool ?? true }
}

/// The ONE rule for Energy "now": today's last integrated level, carried over the minutes since its last
/// epoch with the live stress reading (`BroopHealthStressNow` source `.live`). Home and the Energy screen
/// both read this.
struct EnergyNow: Equatable {
    let level: Double
    let live: Bool

    static func resolve(day: EnergyReservoir.DayResult?, liveStress: Double?, heart: EnergyReservoir.HeartProfile,
                        now: Date = Date()) -> EnergyNow? {
        guard let day, let last = day.points.last else { return nil }
        let minutes = (now.timeIntervalSince1970 - Double(last.ts)) / 60
        guard let liveStress, minutes > 0 else { return EnergyNow(level: last.level, live: false) }
        return EnergyNow(level: EnergyReservoir.projectNow(level: last.level, minutesSinceLastEpoch: minutes,
                                                           liveLevel: liveStress, heart: heart), live: true)
    }
}

extension Repository {

    nonisolated static let energyPassCacheKey = "intelligence.energy.dayKeys.v1"

    /// Resting HR and HRmax Energy's activity TRIMP uses: the day's resting HR (else the Effort default) and
    /// the Effort HRmax funnel over the stored profile (override, else Tanaka), as `AppModel.effortMaxHR`.
    nonisolated static func energyHeart(restingHR: Double?) -> EnergyReservoir.HeartProfile {
        let d = UserDefaults.standard
        let override = d.integer(forKey: "profile.hrMaxOverride")
        let age = d.object(forKey: "profile.age") as? Int ?? StrainScorer.defaultAge
        let maxHR = StrainScorer.effortMaxHR(override: override > 0 ? Double(override) : nil, age: Double(age))
            ?? Double(StrainScorer.defaultMaxHR())
        return .init(restingHR: restingHR ?? StrainScorer.defaultRestingHR, maxHR: maxHR)
    }

    func energyHeart(dayKey: String) -> EnergyReservoir.HeartProfile {
        Self.energyHeart(restingHR: days.first { $0.day == dayKey }?.restingHr.map(Double.init))
    }

    /// The previous day's stored end level (nil → the engine seeds and flags the day).
    func energyStartLevel(dayKey: String) async -> Double? {
        guard let prev = Self.stressDayKey(offset: -1, from: dayKey) else { return nil }
        return await stressStoredValues(keys: [EnergyDaySummary.Key.end], from: prev, to: prev)[prev]?[EnergyDaySummary.Key.end]
    }

    /// THE Energy day: nil while the stress references are calibrating or without a stress analysis.
    func energyDayAnalysis(dayKey: String, now: Date = Date()) async -> EnergyReservoir.DayResult? {
        guard let stress = await stressDayAnalysis(dayKey: dayKey, now: now) else { return nil }
        let start = await energyStartLevel(dayKey: dayKey)
        return EnergyReservoir.day(stress, startLevel: start, heart: energyHeart(dayKey: dayKey))
    }

    /// Stored per-day summaries for the last `days` days, oldest → newest, with today's replaced by the
    /// fresh `energyDayAnalysis` (the function the pass stores with).
    func energyDaySummaries(days: Int, today: EnergyReservoir.DayResult?) async -> [EnergyDaySummary] {
        var byDay: [String: [String: Double]] = [:]
        for key in EnergyDaySummary.Key.all {
            for p in await exploreSeries(key: key, source: Self.whoopSource, days: days) {
                byDay[p.day, default: [:]][key] = p.value
            }
        }
        var out = byDay.compactMap { EnergyDaySummary.fromStored(day: $0.key, values: $0.value) }
        if let today {
            out.removeAll { $0.day == today.day }
            out.append(today.summary)
        }
        return out.sorted { $0.day < $1.day }
    }
}
