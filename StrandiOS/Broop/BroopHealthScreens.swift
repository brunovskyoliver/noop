#if os(iOS)
import SwiftUI
import StrandDesign

/// Health group: health monitor details, stress, trends, metric pages, lab book and rhythm.
struct BroopHealthScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .health: BroopHealthMonitorView()
        case .stress: BroopHealthStressView()
        case .labBook: LabBookView().broopClassicScreen()
        case .rhythm: RhythmHost().broopClassicScreen()
        case .metricExplorer: MetricExplorerView().broopClassicScreen()
        case .trends: BroopHealthTrendsView()
        case .hydration: HydrationView().broopClassicScreen()
        case .compare: CompareView().broopClassicScreen()
        case .metric(let key, let source): metric(key: key, source: source)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func metric(key: String, source: String?) -> some View {
        let resolved = source.flatMap { MetricCatalog.metric(key: key, source: $0) }
            ?? MetricCatalog.all.first(where: { $0.key == key })
        if let resolved {
            BroopHealthTrendView(metric: resolved).id(resolved.id)
        } else {
            BroopHealthMonitorView()
        }
    }
}
#endif
