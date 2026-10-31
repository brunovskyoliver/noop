import Foundation
import OuraProtocol
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopProtocol
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum LiveRules {
    static func hrvSnapshotSource(for model: WhoopModel) -> SpotHrvReading.Source {
        switch model {
        case .whoop5mg: return .opticalPPG
        case .whoop4: return .opticalPPG
        }
    }
    /// Whether the low-bandwidth standard-HR fallback note should render. The note explains that live HR
    /// is coming over the standard BLE Heart-Rate profile because the radio couldn't sustain the full
    /// stream (#80). Shown only when LiveState carries a non-empty note string; pure so it's unit-testable
    /// without standing up a SwiftUI view.
    static func shouldShowStandardHRNote(_ note: String?) -> Bool {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }
}

/// One line per ring link phase, shared by the console centrepiece caption, the above-the-fold callout
/// and the controls row so the three never disagree about what the ring is doing.
enum LiveRingCopy {
    static func status(_ phase: OuraLiveSource.LinkPhase, streaming: Bool) -> String {
        switch phase {
        case .disconnected:   return String(localized: "Ring not connected.")
        case .connecting:     return String(localized: "Connecting to the ring…")
        case .authenticating: return String(localized: "Connected, authenticating…")
        case .authenticated:
            return streaming
                ? String(localized: "Live heart rate is flowing from the ring.")
                : String(localized: "Connected, waiting for live heart rate.")
        }
    }
}
