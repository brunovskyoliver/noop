import Foundation
import SwiftUI

// MARK: - "Your cards" customisable dashboard (WHOOP "My Dashboard")
//
// The Today screen's "Your cards" section was a fixed trio (Stress / Fitness age / Vitality). This turns
// it into a user-customisable dashboard faithful to WHOOP's "My Dashboard": the user chooses WHICH metric
// cards show and in WHAT order from a registry of the values Today already loads. Persistence is
// DISPLAY-ONLY, no metric is computed or stored differently; this just decides which already-loaded
// values render as WHOOP metric rows and in what sequence.
//
// Stored as a JSON-encoded [String] of card ids in @AppStorage (UserDefaults). Unknown ids are dropped on
// read; a known id missing from the saved list is offered (disabled) in the editor so a future card can't
// be lost. Mirrors the existing KeyMetric layout mechanism but as its own list so the two sections stay
// independent (Key Metrics grid vs. the Your-cards dashboard).

/// One available card in the "Your cards" dashboard. The `rawValue` is the stable persisted identifier,
/// keep it byte-identical to the Android `DashboardCard` ids so a backup/restore reads the same dashboard
/// on either OS.
enum DashboardCard: String, CaseIterable, Identifiable {
    case hrv
    case restingHr
    case respiratory
    case steps
    case stepsAverage30
    case stress
    case fitnessAge
    case vo2max
    case vitality
    case bloodOxygen
    case skinTemp
    case sleep
    case calories
    case hydration
    /// Optional, default-OFF (task #43): a tap-through to the Coupled view (the WHOOP-style day read). Unlike
    /// every other card this carries NO metric value of its own, it is a navigation row that opens the full
    /// CoupledView screen. It is NOT in `defaultSelection`, so a fresh install never shows it until the user
    /// adds it via CUSTOMISE, matching the manual-first / default-OFF posture.
    case coupled

    /// Optional, default-OFF (#1862): a tap-through that opens the Coach launcher SHEET rather than pushing
    /// a screen — the one card that does. Coach is otherwise buried in More, and entering it means leaving
    /// Today. Like `coupled` it carries no metric value of its own and is absent from `defaultSelection`, so
    /// a fresh install never shows it: someone who does not use a provider should not gain a fixed dashboard
    /// row for one. Opening the sheet makes NO provider request — see `CoachLauncherSheet`.
    case coach

    var id: String { rawValue }

    /// The card's display label (the UPPERCASE WHOOP metric-row label is derived from this). Localized via
    /// the String Catalog so the dashboard rows read in the user's language (the `.uppercased()` the row
    /// applies then uppercases the LOCALIZED word, with the current locale's casing rules).
    var title: String {
        switch self {
        case .hrv:         return String(localized: "HRV")
        case .restingHr:   return String(localized: "Resting HR")
        case .respiratory: return String(localized: "Respiratory")
        case .steps:       return String(localized: "Steps")
        case .stepsAverage30: return String(localized: "30-day step average")
        case .stress:      return String(localized: "Stress")
        case .fitnessAge:  return String(localized: "Fitness Age")
        case .vo2max:      return String(localized: "VO₂ Max")
        case .vitality:    return String(localized: "Vitality")
        case .bloodOxygen: return String(localized: "Blood Oxygen")
        case .skinTemp:    return String(localized: "Skin Temp")
        case .sleep:       return String(localized: "Sleep")
        case .calories:    return String(localized: "Calories")
        case .hydration:   return String(localized: "Hydration")
        case .coupled:     return String(localized: "Coupled view")
        case .coach:       return String(localized: "Coach")
        }
    }

    /// A short grey baseline/caption shown under the row's value (the WHOOP "30-day baseline" line).
    /// Static descriptive text only, never invented data. Localized via the String Catalog.
    var subtitle: String {
        switch self {
        case .hrv:         return String(localized: "Heart-rate variability")
        case .restingHr:   return String(localized: "Resting heart rate")
        case .respiratory: return String(localized: "Breaths per minute")
        case .steps:       return String(localized: "Today")
        case .stepsAverage30: return String(localized: "Rolling average over the last 30 days")
        case .stress:      return String(localized: "Autonomic load")
        case .fitnessAge:  return String(localized: "Updated weekly")
        case .vo2max:      return String(localized: "Estimated, updated weekly")
        case .vitality:    return String(localized: "Wellness score")
        case .bloodOxygen: return String(localized: "Blood oxygen")
        case .skinTemp:    return String(localized: "Skin temperature")
        case .sleep:       return String(localized: "Last night")
        case .calories:    return String(localized: "Active energy")
        case .hydration:   return String(localized: "Today's fluid")
        case .coupled:     return String(localized: "Recovery, strain and sleep in one glance")
        // Reuses the Coach screen's own subtitle, so the card and the screen describe the feature
        // identically and no new copy needs translating into ten locales.
        case .coach:       return String(localized: "Ask about your charge, effort, rest and workouts, grounded in your own numbers.")
        }
    }

    /// The thin-line SF Symbol shown in the leading icon tile.
    var icon: String {
        switch self {
        case .hrv:         return "waveform.path.ecg"
        case .restingHr:   return "heart.fill"
        case .respiratory: return "lungs.fill"
        case .steps, .stepsAverage30: return "figure.walk"
        case .stress:      return "bolt.heart"
        case .fitnessAge:  return "figure.run"
        case .vo2max:      return "lungs"
        case .vitality:    return "sparkles"
        case .bloodOxygen: return "drop.fill"
        case .skinTemp:    return "thermometer.medium"
        case .sleep:       return "bed.double.fill"
        case .calories:    return "flame.fill"
        case .hydration:   return "waterbottle.fill"
        case .coupled:     return "circle.hexagongrid.fill"
        case .coach:       return "bubble.left.and.text.bubble.right.fill"
        }
    }

    /// The unit suffix shown after the value (smaller weight). Empty when the value is already complete.
    var unit: String {
        switch self {
        case .hrv:         return "ms"
        case .restingHr:   return "bpm"
        case .respiratory: return "rpm"
        case .steps, .stepsAverage30: return ""
        case .stress:      return ""
        case .fitnessAge:  return "yrs"
        case .vo2max:      return ""    // the estimated VO₂max number alone; ml/kg/min is too long for a tile
        case .vitality:    return ""
        case .bloodOxygen: return ""    // value carries the % itself
        case .skinTemp:    return ""    // value carries the ° itself
        case .sleep:       return ""    // value carries the h/m itself
        case .calories:    return "kcal"
        case .hydration:   return ""    // value bakes in "<total> / <goal> L" itself
        case .coupled:     return ""    // a tap-through row, no value, so no unit
        case .coach:       return ""    // likewise: a launcher row, no metric of its own
        }
    }

    /// The default set when the user hasn't customised the dashboard: the original Stress / Fitness age /
    /// Vitality trio plus HRV + Resting HR (per the task's "sensible default"). Cards with no value yet
    /// simply render "—", so the default set is safe on a fresh install.
    static let defaultSelection: [DashboardCard] = [
        .stress, .fitnessAge, .vitality, .hrv, .restingHr,
    ]

    /// Canonical order used to list the disabled remainder in the editor.
    static let canonicalOrder: [DashboardCard] = allCases
}
