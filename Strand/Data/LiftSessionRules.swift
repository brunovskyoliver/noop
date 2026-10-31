import Foundation
import StrandDesign
import SwiftUI
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum LiftSessionRules {
    /// The sport every logged session is filed under — the same token the Hevy/Liftosaur importer
    /// uses, so a typed session and an imported one land in one bucket with one icon.
    static let sport = "Strength Training"

    /// Width of the set-number column, shared by the heading and every row so the number sits
    /// directly under its label.
    ///
    /// 34, not 26. `strandOverline` renders ALL-CAPS with +1.4 tracking, and at 26 the heading wrapped
    /// mid-word — a real session photographed it reading "SE / T" over two lines. The headings are
    /// also `lineLimit(1)` with a scale floor: this row is four short labels across a phone width in
    /// ten languages, and a wrapped heading breaks the column alignment for every row beneath it.
    static let setColumnWidth: CGFloat = 34
}
