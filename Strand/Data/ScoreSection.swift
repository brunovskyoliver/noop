import StrandDesign
import SwiftUI

/// The three score sections the guide can deep-link to. The raw value is used as the
/// ScrollViewReader anchor id. The Android port mirrors these case names exactly.
enum ScoreSection: String, CaseIterable, Identifiable {
    case charge
    case effort
    case rest

    var id: String { rawValue }

    /// The accent each section uses — the SAME Reset score token its Today hero ring draws with, so a
    /// section reads as that score's colour. No gold / strain / sleep-purple: Charge = chargeColor green,
    /// Effort = effortColor blue accent, Rest = restColor slate (Design Reset, 2026-06-23).
    var accent: Color {
        switch self {
        case .charge: return StrandPalette.chargeColor     // Charge hero ring — green
        case .effort: return StrandPalette.effortColor     // Effort hero ring — blue accent
        case .rest:   return StrandPalette.restColor       // Rest hero ring — slate
        }
    }

    /// A representative sample fraction (0–1) for the section's illustrative gauge — a
    /// "what a strong day looks like" reading, purely decorative in the guide.
    var sampleFraction: Double {
        switch self {
        case .charge: return 0.82
        case .effort: return 0.64
        case .rest:   return 0.88
        }
    }

    /// The number shown inside the sample gauge (the 0–100 score the fraction maps to).
    var sampleNumber: String {
        "\(Int((sampleFraction * 100).rounded()))"
    }

    /// The SF Symbol for the section header (heart/spark · flame · moon).
    var icon: String {
        switch self {
        case .charge: return "heart.circle.fill"
        case .effort: return "flame.fill"
        case .rest:   return "moon.stars.fill"
        }
    }

    /// Localized display name for the section (the raw value stays the stable anchor id).
    var displayName: String {
        switch self {
        case .charge: return String(localized: "Charge")
        case .effort: return String(localized: "Effort")
        case .rest:   return String(localized: "Rest")
        }
    }
}
