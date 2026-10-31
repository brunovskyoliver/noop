import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI

/// The on-device consent record for the experimental Rhythm visualization. Mirrors the
/// `Terms` clickwrap pattern: a CURRENT version is stored once the user accepts; bumping
/// the version on a MATERIAL change to the disclaimer re-prompts. Nothing computes or shows
/// until `accepted` is true. Default OFF.
public enum RhythmConsent {
    /// Bump on a material change to the experimental/non-diagnostic wording to re-prompt.
    public static let currentVersion = "1.0"
    /// `@AppStorage` key holding the accepted consent version ("" = never accepted).
    public static let acceptedVersionKey = "noopRhythmConsentVersion"
    /// `@AppStorage` key for the feature on/off flag (the `noopRhythmScreening` flag, default OFF).
    public static let enabledKey = "noopRhythmScreening"

    /// True when the stored accepted version matches the current one.
    public static func isAccepted(_ storedVersion: String) -> Bool {
        !storedVersion.isEmpty && storedVersion == currentVersion
    }

    /// The points the user must read before turning the feature on (spec §9). Each is its
    /// own line (head + body), like `Terms.points`. No condition name, no diagnosis, no
    /// "consider a clinician" verdict — this is a visualization, not a screen.
    public static let points: [(String, String)] = [
        (String(localized: "Experimental, and not a medical device"),
         String(localized: "This is an experimental wellness visualization of your beat-to-beat timing. It is NOT an ECG, and it cannot diagnose, detect, or rule out any heart condition.")),
        (String(localized: "It is a picture, not a verdict"),
         String(localized: "It shows the shape of your heartbeat timing and a plain-language description of how steady it looked. It does not tell you whether anything is right or wrong.")),
        (String(localized: "Variation is normal and often benign"),
         String(localized: "Beat-to-beat timing varies for many ordinary reasons: breathing, movement, an imperfect optical reading, or the occasional extra or skipped beat that most healthy people have.")),
        (String(localized: "It is not a substitute for a professional"),
         String(localized: "If you feel unwell or are worried about your heart, contact a qualified professional; in an emergency, your local emergency service. Do not rely on NOOP.")),
        (String(localized: "Everything stays on your device"),
         String(localized: "All of this is computed on your own device from data you already have. No heartbeat data leaves it.")),
    ]
}
