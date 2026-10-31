import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum InsightsRules {
    /// One interrogable outcome metric: how to fetch it and how to read its direction.
    enum Outcome: String, CaseIterable, Identifiable {
        case recovery, hrv, sleep, rhr
        var id: String { rawValue }

        /// Short segment label.
        var label: String {
            switch self {
            case .recovery: return String(localized: "Charge")
            case .hrv:      return "HRV"
            case .sleep:    return String(localized: "Rest")
            case .rhr:      return "RHR"
            }
        }
        /// The metricSeries key (source is always "my-whoop" for these).
        var key: String {
            switch self {
            case .recovery: return "recovery"
            case .hrv:      return "hrv"
            case .sleep:    return "sleep_performance"
            case .rhr:      return "rhr"
            }
        }
        /// The human outcome name used by BehaviorInsights.sentence.
        var outcomeName: String {
            switch self {
            case .recovery: return String(localized: "Charge")
            case .hrv:      return "HRV"
            case .sleep:    return String(localized: "Rest")
            case .rhr:      return String(localized: "Resting HR")
            }
        }
        /// Whether a higher value is the "good" direction (drives tint).
        var higherIsBetter: Bool {
            switch self {
            case .recovery, .hrv, .sleep: return true
            case .rhr:                    return false
            }
        }
        /// The Bevel colour world each outcome belongs to, Charge→green, HRV→Rest
        /// (periwinkle, the HRV world), Rest→indigo, RHR→Stress (teal). Drives the
        /// section's domain accent + the segmented selection's wash.
        var domain: DomainTheme {
            switch self {
            case .recovery: return .charge
            case .hrv:      return .rest
            case .sleep:    return .rest
            case .rhr:      return .stress
            }
        }
    }
    /// The merged DailyMetric column backing an outcome key, for days the imported metricSeries
    /// doesn't cover (strap-only users). sleep_performance has no daily column, so it stays
    /// import-only, never seeded here.
    static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "recovery": return d.recovery
        case "hrv":      return d.avgHrv
        case "rhr":      return d.restingHr.map(Double.init)
        default:         return nil
        }
    }
    // `internal` (not private) so the Workouts post-log note (#439) reuses the exact same input
    // shaping rather than duplicating it, one source of truth for [sport: days] / [day: Charge].
    static func computeActivityCosts(workouts: [WorkoutRow], days: [DailyMetric]) -> [ActivityCost] {
        // Local-day offset so the activity day key lands on the SAME calendar as DailyMetric.day
        // (which IntelligenceEngine/WhoopImporter both bucket by local midnight, #277).
        let tzOffset = TimeZone.current.secondsFromGMT()
        var activityDaysBySport: [String: Set<String>] = [:]
        for w in workouts {
            // displaySport collapses the detector's "detected" token into one "Activity" bucket and
            // de-camelCases WHOOP sport names; manual/imported labels pass through unchanged.
            let sport = WorkoutSource.displaySport(w.sport)
            guard !sport.isEmpty else { continue }
            let day = AnalyticsEngine.dayString(w.startTs, offsetSec: tzOffset)
            activityDaysBySport[sport, default: []].insert(day)
        }
        var recoveryByDay: [String: Double] = [:]
        for d in days {
            if let r = d.recovery { recoveryByDay[d.day] = r }
        }
        return ActivityCostEngine.evaluate(activityDaysBySport: activityDaysBySport,
                                           recoveryByDay: recoveryByDay)
    }
}
