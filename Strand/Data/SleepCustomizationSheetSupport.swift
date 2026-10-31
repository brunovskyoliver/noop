import StrandDesign
import SwiftUI

extension SleepSection {
    /// SF Symbol shown beside the card's name in the Arrange sheet.
    var customizationIcon: String {
        switch self {
        case .tonight:         return "moon.zzz"
        case .sleepMarks:      return "bed.double"
        case .stages:          return "chart.bar.xaxis"
        case .bodyClock:       return "clock.badge.checkmark"
        case .nightDetail:     return "square.grid.2x2"
        case .sleepDebt:       return "arrow.down.right.circle"
        case .stagesVsTypical: return "chart.bar"
        case .asleepDuration:  return "clock"
        }
    }

    /// Tint for the card's Arrange-sheet icon. Sleep cards live in the Rest world, so they lean on the
    /// rest palette with the accent for the log/marks entry.
    var customizationTint: Color {
        switch self {
        case .tonight:         return StrandPalette.restColor
        case .sleepMarks:      return StrandPalette.accent
        case .stages:          return StrandPalette.restColor
        case .bodyClock:       return StrandPalette.restColor
        case .nightDetail:     return StrandPalette.restBright
        case .sleepDebt:       return StrandPalette.effortColor
        case .stagesVsTypical: return StrandPalette.restColor
        case .asleepDuration:  return StrandPalette.restBright
        }
    }
}
