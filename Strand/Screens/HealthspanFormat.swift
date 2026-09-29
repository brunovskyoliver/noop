import Foundation
import StrandAnalytics

/// Display formatting for Healthspan v2 factor values and age impacts, shared by the macOS Health section
/// and the Broop Healthspan screen so both print a factor the same way.
enum HealthspanFormat {

    /// The number alone, WHOOP style: durations as h:mm, steps with grouping, percentages whole (lean mass
    /// to one decimal), VO₂max and resting HR whole.
    static func number(_ f: VitalityEngine.Factor, _ v: Double) -> String {
        switch f {
        case .sleepHours: return hmm(minutes: v * 60)
        case .zone13, .zone45, .strength: return hmm(minutes: v)
        case .steps: return Int(v.rounded()).formatted(.number.grouping(.automatic))
        case .sleepConsistency: return "\(Int(v.rounded()))%"
        case .leanMass: return String(format: "%.1f%%", v)
        case .vo2max, .rhr: return "\(Int(v.rounded()))"
        }
    }

    /// The unit printed after `number` (empty for percentages).
    static func unit(_ f: VitalityEngine.Factor) -> String {
        switch f {
        case .sleepHours, .zone13, .zone45, .strength: return "h"
        case .steps: return String(localized: "Steps")
        case .vo2max: return "ml/kg/min"
        case .rhr: return "bpm"
        case .sleepConsistency, .leanMass: return ""
        }
    }

    static func value(_ f: VitalityEngine.Factor, _ v: Double) -> String {
        let u = unit(f)
        return u.isEmpty ? number(f, v) : number(f, v) + " " + u
    }

    /// Signed years to one decimal: "+1.5", "-0.4", "0.0".
    static func years(_ y: Double) -> String {
        let r = (y * 10).rounded() / 10
        if r == 0 { return "0.0" }
        return (r > 0 ? "+" : "-") + String(format: "%.1f", abs(r))
    }

    static func hmm(minutes: Double) -> String {
        let total = Int(max(0, minutes).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
