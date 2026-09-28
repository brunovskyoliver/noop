#if os(iOS)
import SwiftUI

/// Insights group: journal, insights, intelligence, fused record, coach and alarms.
struct BroopInsightsScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .journal: BroopInsightsJournalView()
        case .insightsHub: BroopInsightsHubView()
        case .intelligence: BroopInsightsIntelligenceView()
        case .fusedRecord: BroopInsightsFusedView()
        case .coach: BroopInsightsCoachView()
        case .alarms: BroopInsightsAlarmView()
        default: EmptyView()
        }
    }
}
#endif
