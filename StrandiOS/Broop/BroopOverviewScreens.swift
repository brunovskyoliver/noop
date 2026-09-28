#if os(iOS)
import SwiftUI
import StrandDesign

/// Overview group: sleep and the score deep dives' raw detail screens.
struct BroopOverviewScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .sleep: SleepView().broopClassicScreen()
        case .fullDayChart: FullDayChartView().broopClassicScreen()
        case .coupled: CoupledView().broopClassicScreen()
        default: EmptyView()
        }
    }
}
#endif
