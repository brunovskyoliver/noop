import StrandAnalytics
import StrandDesign
import SwiftUI

/// The engines' presentation copy above, for other skins of these cards (the Broop Health tab), so every
/// surface words a result through the same translation.
enum SkinTempCopy {
    static func cycleStatus(_ result: CyclePhaseEngine.Result) -> String { localizedCycleStatus(result) }
    static func bodyClockNote(_ estimate: CircadianEngine.PhaseEstimate) -> String { localizedBodyClockNote(estimate) }
    static func planNote(_ plan: CircadianEngine.JetLagPlan) -> String { localizedPlanNote(plan) }
    static func illness(_ result: IllnessSignalEngine.Result) -> String { localizedIllnessCopy(result) }
    static func bodyClockHeadline(_ estimate: CircadianEngine.PhaseEstimate) -> String { BodyClockCard.offsetTitle(estimate) }
    static func phaseTitle(_ phase: CyclePhaseEngine.Phase) -> String {
        switch phase {
        case .follicular:    return String(localized: "Follicular")
        case .periOvulatory: return String(localized: "Mid-cycle shift")
        case .luteal:        return String(localized: "Luteal")
        case .unknown:       return String(localized: "No clear pattern")
        case .learning:      return String(localized: "Learning your pattern")
        }
    }
    static func confounders(_ result: IllnessSignalEngine.Result) -> [String] {
        result.suppressionReasons.isEmpty
            ? result.suppressedBy.map(localizedConfounder)
            : result.suppressionReasons.map(localizedConfounder)
    }
}
