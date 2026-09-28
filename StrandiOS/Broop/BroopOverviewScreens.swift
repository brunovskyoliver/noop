#if os(iOS)
import SwiftUI
import StrandDesign

/// Overview group: sleep, the whole-day heart-rate timeline and the coupled one-glance day read.
struct BroopOverviewScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .sleep: BroopOverviewSleepScreen()
        case .fullDayChart: BroopOverviewDayChartScreen()
        case .coupled: BroopOverviewCoupledScreen()
        default: EmptyView()
        }
    }
}
#endif
