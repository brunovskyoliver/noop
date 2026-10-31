import Charts
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// The symbol a stored Fitness Age needs when it is sitting on a reporting bound (#2173).
///
/// `FitnessAgeEngine` clamps to [minAge, maxAge], so every model output below 20 is stored as
/// exactly 20.0 and every output above 80 as exactly 80.0. A reader cannot tell either from a
/// genuine 20 or 80, and the number looks as exact as every other number on the screen, which is
/// what makes a floored reading read like a sync or scoring fault rather than the end of the scale.
///
/// Decided from the value rather than carried out of the engine, matching the Kotlin twin. The
/// clamp returns the bound constant itself, so equality is exact and needs no tolerance, and
/// deciding here covers the weekly rows already banked, which no flag added today could reach.
/// A reading that is genuinely 20.0 is therefore also called "20 or younger", which is true of it.
/// Saying "<20" would need the unclamped value, and that is gone before anything is stored.
func fitnessAgeBoundSymbol(_ value: Double) -> String {
    if value <= FitnessAgeEngine.minAge { return "≤" }
    if value >= FitnessAgeEngine.maxAge { return "≥" }
    return ""
}

/// The Fitness Age not-ready lead: a concrete countdown of nights-of-wear still needed (from the shared
/// `nightsUntilReady`), noting the profile basics only when they're actually missing. File-scope (not a
/// view method) so BOTH the Health hub's `FitnessAgeCard` and the Today card's `MetricDetailView`
/// tap-through render the SAME copy from one source. Kept WORD-FOR-WORD identical to the Android
/// `fitnessReadyLead` so the two platforms match.
func fitnessReadyLeadCopy(rhrDays: Int, hasAge: Bool, hasSex: Bool) -> String {
    let remaining = FitnessAgeEngine.nightsUntilReady(rhrDays: rhrDays)
    let needsBasics = !hasAge || !hasSex
    switch (remaining, needsBasics) {
    case (0, false): return String(localized: "A few more days and we can show your Fitness Age.")
    case (0, true):  return String(localized: "Add your age and sex below and we can show your Fitness Age.")
    case (1, false): return String(localized: "1 more night of wear and we can show your Fitness Age.")
    case (1, true):  return String(localized: "1 more night of wear, plus your age and sex below, and we can show your Fitness Age.")
    case (let n, false): return String(localized: "\(n) more nights of wear and we can show your Fitness Age.")
    case (let n, true):  return String(localized: "\(n) more nights of wear, plus your age and sex below, and we can show your Fitness Age.")
    }
}
