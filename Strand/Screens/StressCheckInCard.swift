import StrandAnalytics
import Foundation
import SwiftUI
import Combine
import StrandDesign

// StressCheckInCard.swift — the L3 closed-loop JITAI surface (the "passive" layer). When the shipped,
// unit-tested `StressOnsetDetector` fires (a fresh, non-metabolic HRV dip while the user is still), the
// central hook (Wave 3, in BLEManager's existing offload/evaluateStress call-site) posts a pending nudge
// on `StressNudgeCenter`; this dismissible card surfaces it. NEVER an alarm, NEVER a push (unless the
// user separately opted into notifications), NEVER a diagnosis — "HRV dipped at a resting heart rate", with
// Breathe now / Not now / Turn off, matching DaytimeStress's "passive suggestion" stance.
//
// See docs/superpowers/specs/2026-06-19-v5-haptic-biofeedback-design.md (L3 / UX → "Auto-nudge (passive)").

/// The single observable the L3 hook posts to and the card observes. Self-contained — the central wiring
/// (Wave 3) holds one instance and calls `present()` when `StressOnsetDetector.evaluate` returns
/// `shouldNudge`; the card binds to `pending`. Keeping it here (not in AppModel) means the UI lane owns
/// the whole surface; Wave 3 only needs to inject the instance + call `present`.
@MainActor
final class StressNudgeCenter: ObservableObject {
    /// A live nudge awaiting the user, or nil. Carries the engine's honest numbers for the card copy.
    @Published var pending: Nudge? = nil

    struct Nudge: Equatable {
        /// The fast short-window RMSSD at the moment of the dip (ms), for the honest sub-line.
        let fastRMSSD: Double?
        /// The slow baseline RMSSD (ms) it dipped below.
        let baselineRMSSD: Double?
        /// When it fired.
        let firedAt: Date
    }

    /// Post a nudge (the central L3 hook calls this on a fire). Idempotent-ish: a newer fire replaces an
    /// un-acted one.
    func present(fastRMSSD: Double?, baselineRMSSD: Double?) {
        pending = Nudge(fastRMSSD: fastRMSSD, baselineRMSSD: baselineRMSSD, firedAt: Date())
    }

    func dismiss() { pending = nil }
}

struct StressNudgeCenterKey: EnvironmentKey {
    static let defaultValue: StressNudgeCenter? = nil
}

extension EnvironmentValues {
    /// The shared L3 nudge center. Wave 3 sets this (`.environment(\.stressNudgeCenter, model.stressNudge)`)
    /// from the same instance its BLEManager hook posts to; nil → BreathingView uses a local fallback.
    var stressNudgeCenter: StressNudgeCenter? {
        get { self[StressNudgeCenterKey.self] }
        set { self[StressNudgeCenterKey.self] = newValue }
    }
}
