#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The whole-day timeline in WHOOP's day heart-rate style: the selected day's sleep, Charge and Effort
/// across the top, then the metric line over the full day with the night banded, a Charge marker at wake
/// and an Effort marker at the latest reading. Pinch to zoom, drag to pan (up to two days back), hold to
/// read. Reads come from `Repository.timelineSeries`, as the classic Deep Timeline's do.
struct BroopOverviewDayChartScreen: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var store: BroopStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    @State private var metric: Repository.TimelineMetric = .hr
    @State private var ownedOnly = true
    @State private var sourceName: String?
    @State private var metricUnsupported = false
    @State private var series: Repository.TimelineSeries = .empty
    @State private var sleepSpan: OverviewHRChart.SleepSpan?
    @State private var workoutSpans: [OverviewHRChart.WorkoutSpan] = []
    @State private var zoomDomain: ClosedRange<Date>?
    @State private var loading = true

    private var dayStart: Date { Calendar.current.startOfDay(for: store.selectedLogicalDay) }
    private var dayBounds: ClosedRange<Date> { dayStart...dayStart.addingTimeInterval(86_400) }
    private var panBounds: ClosedRange<Date> { dayStart.addingTimeInterval(-2 * 86_400)...dayBounds.upperBound }
    private var visibleWindow: ClosedRange<Date> { zoomDomain ?? dayBounds }

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            VStack(spacing: 0) {
                BroopOverviewNavBar(
                    title: BroopOverviewFormat.dayTitle(store),
                    canGoBack: store.dayOffset < store.maxOffset(repo: repo),
                    canGoForward: store.dayOffset > 0,
                    onBack: { zoomDomain = nil; withAnimation(.snappy) { store.step(1, repo: repo) } },
                    onForward: { zoomDomain = nil; withAnimation(.snappy) { store.step(-1, repo: repo) } })
                .padding(.horizontal, -BroopMetrics.page)

                HStack {
                    BroopCaps(metric.title, size: 13)
                    Spacer()
                    BroopOverviewSyncedLabel()
                }
                .padding(.top, 6)

                summary(snap).padding(.top, 18)
                chartArea(snap).padding(.top, 14)
                zoomRow.padding(.top, 10)
                if !series.points.isEmpty { stats.padding(.top, 18) }
                metricPicker.padding(.top, 26)
                sourceRow.padding(.top, 14)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .broopStatusBarScrim()
        .background(BroopBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)") { await store.reload(repo: repo, profile: profile) }
        .task(id: taskKey) { await reload() }
        .task(id: "\(Int(dayStart.timeIntervalSince1970))|\(repo.refreshSeq)") { await reloadAnnotations() }
        .task(id: metric) { await resolveUnsupported() }
        .task(id: repo.deviceId) { sourceName = repo.activeDeviceDisplayName() }
    }

    private var taskKey: String {
        let lo = Int(visibleWindow.lowerBound.timeIntervalSince1970)
        let hi = Int(visibleWindow.upperBound.timeIntervalSince1970)
        return "\(metric.rawValue)|\(ownedOnly)|\(lo)|\(hi)|\(repo.refreshSeq)"
    }

    // MARK: Header strip

    /// Sleep, Charge and Effort for the day, as WHOOP heads its day chart.
    private func summary(_ snap: BroopSnapshot?) -> some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 4) {
                Image(systemName: "moon.fill").font(.system(size: 15)).foregroundStyle(BroopPalette.textSecondary)
                Text(verbatim: snap?.asleepMinutes.map(BroopFormat.duration) ?? "--")
                    .font(BroopType.number(20)).foregroundStyle(BroopPalette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                BroopCaps(String(localized: "Charge"), size: 10.5, color: snap?.charge.map(BroopPalette.band) ?? BroopPalette.textSecondary)
                Text(verbatim: snap?.charge.map { BroopFormat.whole($0) + "%" } ?? "--")
                    .font(BroopType.number(20))
                    .foregroundStyle(snap?.charge.map(BroopPalette.band) ?? BroopPalette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                BroopCaps(String(localized: "Effort"), size: 10.5, color: BroopPalette.effort)
                Text(verbatim: snap?.effort.map(BroopScore.effort.format) ?? "--")
                    .font(BroopType.number(20)).foregroundStyle(BroopPalette.effort)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.bgBottom.opacity(0.6)))
    }

    // MARK: Chart

    private var displayPoints: [TrendPoint] {
        guard metric == .skinTemp, temperatureUnit == .fahrenheit else { return series.points }
        return series.points.map { TrendPoint(date: $0.date, value: UnitFormatter.celsiusToFahrenheit($0.value)) }
    }

    @ViewBuilder
    private func chartArea(_ snap: BroopSnapshot?) -> some View {
        ZStack {
            if loading && series.points.isEmpty {
                ProgressView().tint(BroopPalette.textSecondary)
            } else if series.points.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.slash").font(.system(size: 26, weight: .light))
                    BroopCaps(String(localized: "No data"), size: 11, color: BroopPalette.textSecondary)
                    Text(verbatim: emptyReason)
                        .font(BroopType.medium(13))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(BroopPalette.textSecondary)
                .padding(.horizontal, 24)
            } else {
                OverviewHRChart(
                    points: displayPoints,
                    sleep: sleepSpan,
                    workouts: workoutSpans,
                    recovery: recoveryMarker(snap),
                    effort: effortMarker(snap),
                    gradient: Gradient(colors: [lineColor.opacity(0.55), lineColor]),
                    valueRange: valueRange(displayPoints),
                    xRange: dayBounds,
                    height: 340,
                    touchScrub: true,
                    workoutTint: BroopPalette.effort,
                    zoomDomain: $zoomDomain,
                    zoomBounds: panBounds,
                    valueFormat: { format($0) },
                    dateFormat: { BroopFormat.time($0) })
            }
        }
        .frame(height: 340)
    }

    private var lineColor: Color {
        switch metric {
        case .hr, .bandSleepState: return BroopPalette.rest
        case .hrv, .spo2: return Color(broopHex: 0x9AA6F5)
        case .skinTemp: return BroopPalette.warning
        default: return BroopPalette.textSecondary
        }
    }

    private func recoveryMarker(_ snap: BroopSnapshot?) -> OverviewHRChart.EdgeMarker? {
        guard let charge = snap?.charge, let wake = snap?.night?.session.endTs else { return nil }
        return .init(date: Date(timeIntervalSince1970: TimeInterval(wake)),
                     label: String(localized: "Charge") + " \(BroopFormat.whole(charge))%", color: BroopPalette.band(charge))
    }

    private func effortMarker(_ snap: BroopSnapshot?) -> OverviewHRChart.EdgeMarker? {
        guard let effort = snap?.effort, let last = series.points.last?.date else { return nil }
        return .init(date: last, label: String(localized: "Effort") + " " + BroopScore.effort.format(effort),
                     color: BroopPalette.effort, alignment: .trailing)
    }

    private var zoomRow: some View {
        HStack(spacing: 8) {
            Image(systemName: zoomDomain == nil ? "plus.magnifyingglass" : "minus.magnifyingglass")
                .font(.system(size: 14))
            Text(zoomDomain == nil ? "Pinch to zoom · drag to pan · hold to read" : "Zoomed in. Drag to pan · hold to read")
                .font(BroopType.medium(12.5))
            Spacer()
            if zoomDomain != nil {
                Button { withAnimation(.snappy) { zoomDomain = nil } } label: {
                    BroopCaps(String(localized: "Reset"), size: 10.5)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().stroke(BroopPalette.textPrimary, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(BroopPalette.textSecondary)
    }

    private var stats: some View {
        let v = displayPoints.map(\.value)
        return HStack(spacing: 0) {
            stat(String(localized: "Min"), format(v.min() ?? 0))
            stat(String(localized: "Avg"), format(v.reduce(0, +) / Double(max(1, v.count))))
            stat(String(localized: "Max"), format(v.max() ?? 0))
            stat(String(localized: "Resolution"), resolution)
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var resolution: String {
        if series.isRaw { return String(localized: "1 s") }
        let m = series.bucketSeconds / 60
        return m >= 1 ? String(localized: "\(m) min") : String(localized: "\(series.bucketSeconds) s")
    }

    // MARK: Controls

    private var metricPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "Metric"), size: 10.5, color: BroopPalette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Repository.TimelineMetric.allCases, id: \.self) { m in
                        Button { metric = m } label: {
                            BroopCaps(m.title, size: 10.5, color: metric == m ? Color.black : BroopPalette.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Capsule().fill(metric == m ? Color.white : BroopOverviewPalette.button))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The owned source and the #574 scope: the active device, or every source with the honest note that
    /// others don't offload raw per-second data on-device.
    private var sourceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 13)).foregroundStyle(BroopPalette.textSecondary)
            Text(verbatim: sourceName ?? String(localized: "My WHOOP"))
                .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
            Spacer()
            HStack(spacing: 2) {
                ForEach([true, false], id: \.self) { owned in
                    Button { ownedOnly = owned } label: {
                        Text(verbatim: owned ? String(localized: "Owned") : String(localized: "All"))
                            .font(BroopType.caps(10.5))
                            .foregroundStyle(ownedOnly == owned ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                            .frame(width: 58, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ownedOnly == owned ? Color(broopHex: 0x3A4046) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(broopHex: 0x1A1E22)))
        }
    }

    // MARK: Formatting

    private var emptyReason: String {
        if ownedOnly, metricUnsupported, metric == .spo2 {
            return String(localized: "This strap doesn’t send SpO₂ over Bluetooth. Import a WHOOP export or Health Connect to see it.")
        }
        if ownedOnly, metricUnsupported, metric == .respiration {
            return String(localized: "This strap sends no raw respiration stream. Your estimated respiratory rate appears on the Health screen.")
        }
        return ownedOnly ? String(localized: "Nothing offloaded for this window yet.")
            : String(localized: "Other sources don’t offload raw per-second data on-device.")
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case .hr, .respiration, .hrv, .ouraMovement: return String(Int(v.rounded()))
        case .skinTemp: return String(format: "%.1f", v)
        case .spo2, .motion: return String(format: "%.2f", v)
        case .bandSleepState: return FullDayChartView.bandStateLabel(v)
        }
    }

    private func valueRange(_ pts: [TrendPoint]) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return metric == .hr ? 40...120 : 0...1 }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    // MARK: Reads

    private func resolveUnsupported() async {
        guard repo.activeStrapIsWhoop5(), metric == .spo2 || metric == .respiration else { metricUnsupported = false; return }
        metricUnsupported = !(await repo.strapHasEverProduced(metric))
    }

    private func reload() async {
        loading = true
        let w = visibleWindow
        let result = await repo.timelineSeries(metric: metric, from: Int(w.lowerBound.timeIntervalSince1970),
                                               to: Int(w.upperBound.timeIntervalSince1970), targetPoints: 600)
        guard !Task.isCancelled else { return }
        series = result
        loading = false
    }

    /// The main night's band and each workout's glyph, scoped exactly as the classic timeline scopes them.
    private func reloadAnnotations() async {
        let daysBack = max(0, Int(Date().timeIntervalSince(dayStart) / 86_400)) + 2
        let sleeps: [OverviewHRChart.SleepSpan] = await repo.allSleepSessions(days: daysBack).map { s in
            .init(start: Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs)),
                  end: Date(timeIntervalSince1970: TimeInterval(s.endTs)),
                  label: BroopFormat.duration(Double(s.endTs - s.effectiveStartTs) / 60))
        }
        let workouts: [OverviewHRChart.WorkoutSpan] = await repo.workoutRows(days: daysBack).map { w in
            .init(start: Date(timeIntervalSince1970: TimeInterval(w.startTs)),
                  end: Date(timeIntervalSince1970: TimeInterval(w.endTs)), symbol: sportSymbol(w.sport))
        }
        guard !Task.isCancelled else { return }
        sleepSpan = OverviewHRChart.mainSleep(sleeps, overlapping: dayBounds)
        workoutSpans = OverviewHRChart.workouts(workouts, overlapping: dayBounds)
    }
}

/// "Data synced to 12:44 PM", isolated so live ticks refresh only this label.
private struct BroopOverviewSyncedLabel: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        if let ts = live.lastSyncedAt {
            Text(verbatim: String(localized: "Data synced to") + " " + BroopFormat.time(Date(timeIntervalSince1970: ts)))
                .font(BroopType.medium(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
        }
    }
}
#endif
