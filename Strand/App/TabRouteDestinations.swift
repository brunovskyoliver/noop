import SwiftUI

extension View {
    /// Maps every `TabRoute` push to its screen. Apply once to the ROOT content of each
    /// `NavigationStack` that hosts a tab-root view (the iOS tab shell's stacks; the macOS
    /// Today detail pane and TrendsView's own macOS wrap).
    func tabRouteDestinations() -> some View {
        navigationDestination(for: TabRoute.self) { route in
            switch route {
            case .fullDayChart: FullDayChartView()
            case .metric(let key):
                // Every caller passes a catalog key, so the fallback is theoretical; Health is the
                // catch-all vitals surface. (Pre-#198 Trends fell back to the Explorer instead —
                // unified here rather than carrying two never-taken branches.)
                if let m = MetricCatalog.all.first(where: { $0.key == key }) {
                    MetricDetailView(metric: m)
                } else {
                    HealthView()
                }
            case .metricSourced(let key, let source):
                // Exact (key, source) resolution, order-independent. Fall back to the bare-key entry,
                // then Health, so a stale route can never dead-end.
                if let m = MetricCatalog.metric(key: key, source: source)
                    ?? MetricCatalog.all.first(where: { $0.key == key }) {
                    MetricDetailView(metric: m)
                } else {
                    HealthView()
                }
            case .metricExplorer: MetricExplorerView()
            case .workouts: WorkoutsView()
            case .dataSources: DataSourcesView()
            case .stress: StressView()
            case .sleep: SleepView()
            case .health: HealthView()
            case .hydration: HydrationView()
            case .coupled: CoupledView()
            }
        }
    }
}
