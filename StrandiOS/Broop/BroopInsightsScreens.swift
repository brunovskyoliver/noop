#if os(iOS)
import SwiftUI
import StrandDesign

/// Insights group: journal, insights, intelligence, fused record, coach and alarms.
struct BroopInsightsScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .journal: InsightsView().broopClassicScreen()
        case .insightsHub: InsightsHubView().broopClassicScreen()
        case .intelligence: IntelligenceView().broopClassicScreen()
        case .fusedRecord: FusedRecordHost().broopClassicScreen()
        case .coach: CoachView().broopClassicScreen()
        case .alarms: SmartAlarmView().broopClassicScreen()
        default: EmptyView()
        }
    }
}
#endif
