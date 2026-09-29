import Foundation
import StrandAnalytics

// AppModel+StrainTarget.swift — THE resolver for a day's Effort target band. Home, the score detail, the
// Coupled reads, the live workout coach and the notifier all call `StrainTargetContext.band`, so no two
// of them can show a different band for the same day. The mapping itself is the pure `StrainTarget`.
//
// iOS-only fork change; Android twin intentionally not updated.

/// Settings → Scoring's strain goal.
enum StrainTargetPrefs {
    static let goalKey = "noop.strainTargetGoal"
    static var goal: StrainTarget.Goal {
        StrainTarget.Goal(rawValue: UserDefaults.standard.string(forKey: goalKey) ?? "") ?? .maintain
    }
}

/// The band's inputs other than Charge. Small and rarely changing, so a view can observe it without
/// subscribing to `AppModel`'s live publishes. `AppModel` feeds it: the sleep-debt ledger from tonight's
/// plan, the illness heads-up from `healthAlert`, the goal from Settings.
@MainActor
final class StrainTargetContext: ObservableObject {
    static let shared = StrainTargetContext()

    /// Current sleep debt in minutes (0 when none), from the ledger `tonightPlan` and the Sleep Debt card
    /// use. nil until the first plan build.
    @Published var sleepDebtMin: Double?
    /// An illness heads-up is showing (`AppModel.healthAlert`).
    @Published var illness = false
    @Published var goal: StrainTarget.Goal = StrainTargetPrefs.goal

    /// The Effort target band (0–100 axis) for a day with this Charge. Sleep debt and the illness heads-up
    /// describe NOW, so they only adjust today's band; a past day gets its Charge and the goal. nil without
    /// a Charge (never a guessed target).
    func band(charge: Double?, isToday: Bool) -> StrainTarget.Band? {
        StrainTarget.band(.init(charge: charge, sleepDebtMin: isToday ? sleepDebtMin : nil,
                                illness: isToday && illness, goal: goal))
    }
}

extension AppModel {

    func strainTarget(charge: Double?, isToday: Bool) -> StrainTarget.Band? {
        StrainTargetContext.shared.band(charge: charge, isToday: isToday)
    }

    /// The once-a-day nudges (#593): the band's low end reached, and optionally its top passed. Reads the
    /// resolved today-row; the notifier's per-day gates make this safe on every days republish.
    func evaluateStrainTarget() {
        guard let row = repo.today else { return }
        StrainTargetNotifier.onDayUpdate(day: row.day, effort: row.strain,
                                         band: strainTarget(charge: row.recovery, isToday: true),
                                         lowerEnabled: behavior.strainTargetNudge,
                                         upperEnabled: behavior.strainTargetUpperNudge)
    }
}
