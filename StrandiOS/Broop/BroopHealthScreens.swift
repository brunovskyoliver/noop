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
        case .labBook: BroopHealthLabBookView()
        case .rhythm: BroopHealthRhythmView()
        case .metricExplorer: BroopHealthExplorerView()
        case .trends: BroopHealthTrendsView()
        case .hydration: BroopHealthHydrationView()
        case .compare: BroopHealthCompareView()
        case .healthspan: BroopHealthspanView()
        case .mind: BroopMindView()
        case .energy: BroopEnergyView()
        case .jetLag: BroopHealthJetLagView()
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
