#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Broop Metric Explorer (`.metricExplorer`): every catalog metric grouped by pillar, each opening its
/// Trend View, with the Deep Timeline on top. Rebuilt from the classic `MetricExplorerView`, including its
/// cheap non-empty probe that marks metrics with no data.
struct BroopHealthExplorerView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var nonEmpty: Set<String>?
    @State private var hideEmpty = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: BroopScreen.fullDayChart) {
                    BroopHealthRow(symbol: "waveform.path.ecg", title: String(localized: "Deep Timeline"),
                                   detail: String(localized: "Every second of your day, zoomable."))
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 10)
                HStack {
                    if nonEmpty == nil {
                        ProgressView().controlSize(.small).tint(BroopPalette.textSecondary)
                        Text("Scanning your data…").font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    Spacer()
                    Toggle(isOn: $hideEmpty) {
                        BroopCaps(String(localized: "Only with data"), size: 10.5, color: BroopPalette.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .tint(BroopHealthPalette.mint)
                    .fixedSize()
                }
                .padding(.top, 18)
                ForEach(MetricCatalog.categories, id: \.self) { category in
                    let metrics = MetricCatalog.inCategory(category).filter { !hideEmpty || isNonEmpty($0) != false }
                    if !metrics.isEmpty {
                        BroopHealthHeading(text: MetricCatalog.categoryDisplayName(category), trailing: "\(metrics.count)")
                            .padding(.top, 26)
                        VStack(spacing: 0) {
                            ForEach(Array(metrics.enumerated()), id: \.element.id) { i, m in
                                NavigationLink(value: BroopScreen.metric(key: m.key, source: m.source)) { row(m) }
                                    .buttonStyle(BroopPressableStyle())
                                if i < metrics.count - 1 { BroopHairline().padding(.leading, 50) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                        .padding(.top, 12)
                    }
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Metric Explorer")) }
        .broopHealthScreen()
        .task(id: repo.refreshSeq) {
            let ids = await repo.nonEmptyMetricIDs(MetricCatalog.all)
            guard !Task.isCancelled else { return }
            nonEmpty = ids
        }
    }

    private func isNonEmpty(_ m: MetricDescriptor) -> Bool? { nonEmpty.map { $0.contains(m.id) } }

    private func row(_ m: MetricDescriptor) -> some View {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let unit = m.displayUnit(system: system, temperature: UnitPrefs.resolveTemperature(system: system, override: temperatureRaw),
                                 effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
        let empty = isNonEmpty(m) == false
        return HStack(spacing: 14) {
            Image(systemName: m.icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(m.title, size: 11.5, color: empty ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                Text(verbatim: m.sourceLabel).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer(minLength: 8)
            if empty {
                BroopCaps(String(localized: "No data"), size: 9.5, color: BroopPalette.textTertiary)
            } else if !unit.isEmpty {
                Text(verbatim: unit).font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
