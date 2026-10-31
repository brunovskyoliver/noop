import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// "Jun 8" from "2026-06-08", via the engine's own pure parse (no Calendar).
func weeklyDigestShortDate(_ ymd: String) -> String {
    guard let (_, month, day) = WeeklyDigestEngine.parseYMD(ymd) else { return ymd }
    let months = [String(localized: "Jan"), String(localized: "Feb"), String(localized: "Mar"),
                  String(localized: "Apr"), String(localized: "May"), String(localized: "Jun"),
                  String(localized: "Jul"), String(localized: "Aug"), String(localized: "Sep"),
                  String(localized: "Oct"), String(localized: "Nov"), String(localized: "Dec")]
    let name = (1...12).contains(month) ? months[month - 1] : "\(month)"
    return "\(name) \(day)"
}

extension View {
    @ViewBuilder
    func digestScalePopoverAdaptation() -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            presentationCompactAdaptation(.popover)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
