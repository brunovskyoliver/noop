#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Trend View (`.metric(key:source:)`), the WHOOP trend template for every `MetricCatalog` metric.
/// Rebuilt from the classic `MetricDetailView`: the same loads (explorer series + per-day provenance, the
/// steps calendar projection, the SpO₂ candidate fill, the skin-temperature lead rule, the VO₂max estimator
/// attribution), the same range gating and auto-widen, the same statistics and correlation scan. What is
/// new is presentation only: the metric switcher, the W | M | 6M control with paging back through
/// earlier windows, and a chart with a typical-range band and press-and-drag readout.
struct BroopHealthTrendView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.trendChartStyleKey) private var trendChartStyleRaw = TrendChartStyle.line.rawValue
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""

    @State private var metric: MetricDescriptor
    @State private var range: ExploreRange = .month
    /// Whole windows stepped back from the latest reading (0 = the latest window).
    @State private var page = 0
    @State private var series: [(day: String, value: Double)] = []
    @State private var sourceByDay: [String: String] = [:]
    @State private var loaded = false
    @State private var skinTempNote: String?
    @State private var others: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] = []
    @State private var correlationsLoaded = false
    @State private var correlations: [Corr] = []
    @State private var correlationKey = ""
    @State private var selection: BroopHealthPoint?
    @State private var refreshing = false
    @State private var showAllReadings = false

    init(metric: MetricDescriptor) { _metric = State(initialValue: metric) }

    private struct Corr: Identifiable {
        let id: String
        let metric: MetricDescriptor
        let r: Double
        let n: Int
    }

    // MARK: Units

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit { UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw) }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var skinPref: SkinTempDisplay.Kind { SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute }
    private var isSteps: Bool { MetricDetailSteps.isMetric(metric.key) }

    private func fmt(_ v: Double) -> String {
        if isSteps { return MetricDetailSteps.valueLabel(v, resolution: .daily) }
        return metric.format(v, system: unitSystem, temperature: temperatureUnit, effortScale: effortScale)
    }

    /// The number without its unit (the unit is set small beside it), falling back to the whole string.
    private func number(_ v: Double) -> (String, String) {
        if isSteps {
            return (v.formatted(.number.locale(AppLanguage.activeLocale).precision(.fractionLength(0))),
                    String(localized: "steps"))
        }
        let full = fmt(v)
        let unit = metric.displayUnit(system: unitSystem, temperature: temperatureUnit, effortScale: effortScale)
        if !unit.isEmpty, full.hasSuffix(" " + unit) { return (String(full.dropLast(unit.count + 1)), unit) }
        if let space = full.lastIndex(of: " "), full.firstIndex(of: " ") == space {
            return (String(full[..<space]), String(full[full.index(after: space)...]))
        }
        return (full, "")
    }

    // MARK: Windows

    private var historySpanDays: Int {
        guard let a = series.first.flatMap({ BroopHealthFormat.date($0.day) }),
              let b = series.last.flatMap({ BroopHealthFormat.date($0.day) }) else { return 0 }
        return Int(b.timeIntervalSince(a) / 86_400)
    }

    /// The classic #943 gate: a longer range unlocks once history exceeds the range below it.
    private func isUnlocked(_ r: ExploreRange) -> Bool {
        guard loaded, !series.isEmpty else { return true }
        switch r {
        case .week, .all: return true
        case .twoWeeks: return historySpanDays > ExploreRange.week.rawValue
        case .threeWeeks: return historySpanDays > ExploreRange.twoWeeks.rawValue
        case .month: return historySpanDays > ExploreRange.threeWeeks.rawValue
        case .quarter: return historySpanDays > ExploreRange.month.rawValue
        case .half: return historySpanDays > ExploreRange.quarter.rawValue
        case .year: return historySpanDays > ExploreRange.half.rawValue
        }
    }
    private var coerced: ExploreRange { ExploreRangeGating.coerced(selection: range, isUnlocked: isUnlocked) }

    /// The anchor (last day) of the window `page` windows back from the newest reading.
    private func anchor(_ r: ExploreRange) -> String? {
        guard let last = series.last?.day else { return nil }
        guard page > 0, let days = r.days, let d = BroopHealthFormat.date(last) else { return last }
        return BroopHealthFormat.day(d.addingTimeInterval(-Double(page * days) * 86_400))
    }

    private func rawSlice(_ r: ExploreRange, anchor end: String?) -> [(day: String, value: Double)] {
        guard let days = r.days else { return series }
        guard let end, let d = BroopHealthFormat.date(end) else { return [] }
        let cutoff = BroopHealthFormat.day(d.addingTimeInterval(-Double(days - 1) * 86_400))
        return series.filter { $0.day.utf8.count == 10 && $0.day >= cutoff && $0.day <= end }
    }

    private func presented(_ r: ExploreRange, anchor end: String?) -> [(day: String, value: Double)] {
        guard isSteps else { return rawSlice(r, anchor: end) }
        return MetricDetailSteps.presentation(readings: series, range: r, anchorDay: page == 0 ? nil : end).series
    }

    /// Selected range, widened (on the latest window only) when it holds nothing — the classic rule.
    private var effective: ExploreRange {
        guard !series.isEmpty, page == 0 else { return coerced }
        let candidates = isSteps ? MetricDetailSteps.widening(from: coerced) : coerced.widening
        for r in candidates where !presented(r, anchor: anchor(r)).isEmpty { return r }
        return .all
    }

    private func previous(_ r: ExploreRange, window: [(day: String, value: Double)], end: String?) -> [(day: String, value: Double)] {
        guard r != .all, let end else { return [] }
        if isSteps {
            let a = page == 0 ? (MetricDetailSteps.latestValidDay(readings: series) ?? end) : end
            return MetricDetailSteps.previousPresentation(readings: series, range: r, currentAnchorDay: a).series
        }
        guard let days = r.days, let d = BroopHealthFormat.date(end) else { return [] }
        return rawSlice(r, anchor: BroopHealthFormat.day(d.addingTimeInterval(-Double(days) * 86_400)))
    }

    private var canPageBack: Bool {
        guard let days = effective.days, let first = series.first?.day,
              let end = anchor(effective), let d = BroopHealthFormat.date(end) else { return false }
        return BroopHealthFormat.day(d.addingTimeInterval(-Double(days) * 86_400)) >= first
    }

    /// The trusted personal range for the vitals that band against one (HRV, RHR, respiratory rate): the
    /// same fold and ±2σ rule `VitalBands` uses for the Health Monitor's in-range pill.
    private var typicalRange: ClosedRange<Double>? {
        let cfg: MetricCfg?
        switch metric.key {
        case "hrv": cfg = Baselines.hrvCfg
        case "rhr": cfg = Baselines.restingHRCfg
        case "resp_rate": cfg = Baselines.respCfg
        default: cfg = nil
        }
        guard let cfg, metric.source == "my-whoop" else { return nil }
        let history = VitalBands.calendarSeries(series.map { ($0.day, Optional($0.value)) })
        let state = Baselines.foldHistory(history, cfg: cfg)
        guard state.trusted else { return nil }
        let half = VitalBands.sigmaK * Baselines.sigma(state)
        return (state.baseline - half)...(state.baseline + half)
    }

    private var style: BroopHealthTrendChart.Style {
        if MetricDetailSteps.showsBars(metricKey: metric.key, preferredStyleRaw: trendChartStyleRaw) { return .bars }
        let barKeys: Set<String> = ["energy_kcal", "active_kcal", "hr_zones13_min", "hr_zones45_min", "hr_zones_all_min",
                                    "strength_min", "intensity_min", "calories_in", "protein_g", "carbs_g", "fat_g"]
        return barKeys.contains(metric.key) ? .bars : .line
    }

    // MARK: Body

    var body: some View {
        let eff = effective
        let end = anchor(eff)
        let win = presented(eff, anchor: end)
        let raw = isSteps ? rawSlice(eff, anchor: end) : win
        let prev = previous(eff, window: win, end: end)
        let fellBack = eff != range && page == 0
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                metricSwitcher
                if !loaded {
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 60)
                } else if win.isEmpty {
                    emptyState.padding(.top, 20)
                } else {
                    summary(eff: eff, win: win, prev: prev, end: end).padding(.top, 24)
                    Text(verbatim: insight(eff: eff, win: win, prev: prev))
                        .font(BroopType.medium(16.5))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                    if fellBack {
                        Text(verbatim: String(localized: "Sparse, widened to \(eff.name)"))
                            .font(BroopType.regular(12.5)).foregroundStyle(BroopHealthPalette.amber).padding(.top, 8)
                    }
                    chart(win: win, eff: eff).padding(.top, 20)
                    if metric.key == "vo2max_est", vo2MaxTrendHasBreak(days: win.map(\.day), sourceByDay: sourceByDay) {
                        BroopHealthFootnote(text: String(localized: "The line breaks where the estimation method changed or was not recorded."))
                            .padding(.top, 8)
                    }
                    if let note = skinTempNote {
                        BroopHealthInfoBanner(text: note).padding(.top, 16)
                    }
                    if !ExploreRange.allCases.allSatisfy(isUnlocked) {
                        BroopHealthFootnote(text: String(localized: "Longer ranges unlock as more history builds.")).padding(.top, 10)
                    }
                    statistics(eff: eff, win: win, prev: prev).padding(.top, BroopMetrics.section)
                    readings(raw).padding(.top, BroopMetrics.section)
                    correlationCard(eff: eff).padding(.top, BroopMetrics.section)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Trend View")) }
        .broopHealthScreen()
        .task(id: MetricDetailSteps.loadIdentity(metricID: metric.id, refreshSequence: repo.refreshSeq,
                                                 skinTemperatureStyle: skinTempDisplayRaw, range: range)) { await load() }
        .onChange(of: range) { _, _ in page = 0; selection = nil; recomputeCorrelations() }
        .onChange(of: page) { _, _ in selection = nil; recomputeCorrelations() }
        .onChange(of: metric) { _, _ in
            page = 0; selection = nil; loaded = false; correlationsLoaded = false; correlationKey = ""
        }
    }

    // MARK: Metric switcher

    private var metricSwitcher: some View {
        Menu {
            ForEach(MetricCatalog.categories, id: \.self) { cat in
                Section(MetricCatalog.categoryDisplayName(cat)) {
                    ForEach(MetricCatalog.inCategory(cat)) { m in
                        Button {
                            metric = m
                        } label: {
                            Label("\(m.title) · \(m.sourceLabel)", systemImage: m.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: metric.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    BroopCaps(metric.title, size: 13)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if metric.source != "my-whoop" {
                        Text(verbatim: metric.sourceLabel).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold)).foregroundStyle(BroopPalette.textPrimary)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopHealthPalette.dropdown))
        }
        .padding(.top, 10)
        .accessibilityLabel(Text(verbatim: "\(metric.title). \(String(localized: "Choose metric"))"))
    }

    // MARK: Summary

    private func summary(eff: ExploreRange, win: [(day: String, value: Double)],
                         prev: [(day: String, value: Double)], end: String?) -> some View {
        let values = win.map(\.value)
        let stat = ComparisonEngine.stat(values)
        let cmp = ComparisonEngine.compare(current: values, previous: prev.map(\.value))
        let shown = selection?.value ?? stat.mean
        let (num, unit) = number(shown)
        let label = selection.map { BroopHealthFormat.weekday($0.day) } ?? String(localized: "Average")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    BroopCaps(label, size: 12, color: BroopPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: num)
                            .font(BroopType.number(40))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .broopNumeral(40)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !unit.isEmpty {
                            Text(verbatim: unit).font(BroopType.medium(17)).foregroundStyle(BroopPalette.textPrimary)
                        }
                    }
                    if selection == nil, let pct = cmp.pctChange, cmp.current.n > 0, cmp.previous.n > 0 {
                        BroopHealthDeltaChip(pct: pct,
                                             good: cmp.direction == 0 ? nil : metric.higherIsBetter.map { (cmp.direction > 0) == $0 },
                                             suffix: String(localized: "vs. prior \(eff.name)"))
                    }
                }
                Spacer(minLength: 0)
            }
            BroopHealthRangePicker(selection: Binding(get: { coerced }, set: { range = $0 }), isEnabled: isUnlocked)
            if eff != .all, let end, let first = win.first?.day {
                BroopHealthDateNav(label: BroopHealthFormat.range(first, end),
                                   canGoBack: canPageBack, canGoForward: page > 0,
                                   onBack: { page += 1 }, onForward: { page = max(0, page - 1) })
            }
        }
    }

    private func insight(eff: ExploreRange, win: [(day: String, value: Double)], prev: [(day: String, value: Double)]) -> String {
        let mean = ComparisonEngine.stat(win.map(\.value)).mean
        let name = metric.title
        let period: String = {
            switch eff {
            case .week: return String(localized: "this 7-day period")
            case .all: return String(localized: "all of your history")
            default: return String(localized: "this \(eff.name)")
            }
        }()
        if let t = typicalRange {
            let lo = fmt(t.lowerBound), hi = fmt(t.upperBound)
            if t.contains(mean) {
                return String(localized: "Your average \(name) during \(period) was within its typical range (\(lo) - \(hi)).")
            }
            return mean > t.upperBound
                ? String(localized: "Your average \(name) during \(period) was above its typical range (\(lo) - \(hi)).")
                : String(localized: "Your average \(name) during \(period) was below its typical range (\(lo) - \(hi)).")
        }
        let prevStat = ComparisonEngine.stat(prev.map(\.value))
        guard prevStat.n > 0 else {
            return String(localized: "Your average \(name) during \(period) was \(fmt(mean)).")
        }
        if abs(mean - prevStat.mean) < 1e-9 {
            return String(localized: "Your average \(name) during \(period) matched the previous \(eff.name) (\(fmt(prevStat.mean))).")
        }
        return mean > prevStat.mean
            ? String(localized: "Your average \(name) during \(period) was above the previous \(eff.name)'s average of \(fmt(prevStat.mean)).")
            : String(localized: "Your average \(name) during \(period) was below the previous \(eff.name)'s average of \(fmt(prevStat.mean)).")
    }

    // MARK: Chart

    private func chart(win: [(day: String, value: Double)], eff: ExploreRange) -> some View {
        let segs = metric.key == "vo2max_est"
            ? vo2MaxTrendSegmentIds(days: win.map(\.day), sourceByDay: sourceByDay)
            : Array(repeating: "a", count: win.count)
        let pts: [BroopHealthPoint] = win.enumerated().compactMap { i, row in
            BroopHealthFormat.date(row.day).map { BroopHealthPoint(day: row.day, date: $0, value: row.value, segment: segs[i]) }
        }
        let values = pts.map(\.value) + (typicalRange.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.18, abs(hi) * 0.02, 0.5)
        let domain: ClosedRange<Double> = style == .bars ? 0...(hi + pad) : (lo - pad)...(hi + pad)
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        return VStack(alignment: .trailing, spacing: 12) {
            if typicalRange != nil {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12)
                    BroopCaps(String(localized: "Typical range"), size: 11.5)
                }
            }
            BroopHealthTrendChart(points: pts, style: style, yDomain: domain, typical: typicalRange,
                                  average: style == .bars ? avg : nil,
                                  valueLabel: { number($0).0 },
                                  axisLabel: { axis($0) },
                                  labelsPoints: style == .line && pts.count <= 8,
                                  selection: $selection, height: 260)
        }
    }

    private func axis(_ v: Double) -> String {
        if abs(v) >= 1000 { return v.formatted(.number.locale(AppLanguage.activeLocale).precision(.fractionLength(0))) }
        return metric.decimals > 0 && abs(v) < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }

    // MARK: Statistics

    private func statistics(eff: ExploreRange, win: [(day: String, value: Double)],
                            prev: [(day: String, value: Double)]) -> some View {
        let values = win.map(\.value)
        let s = ComparisonEngine.stat(values)
        let cmp = ComparisonEngine.compare(current: values, previous: prev.map(\.value))
        let hasDelta = cmp.current.n > 0 && cmp.previous.n > 0
        let deltaColor: Color = {
            guard hasDelta, cmp.direction != 0, let better = metric.higherIsBetter else { return BroopPalette.textSecondary }
            return (cmp.direction > 0) == better ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText
        }()
        let latest = isSteps ? win.last : series.last
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopCaps(String(localized: "Key statistics"), size: 12.5)
                Spacer()
                BroopCaps(isSteps ? MetricDetailSteps.countCaption(count: s.n, resolution: MetricDetailSteps.resolution(for: eff), rangeName: eff.name)
                          : (s.n == 1 ? String(localized: "1 day") : String(localized: "\(s.n) days")),
                          size: 10, color: BroopPalette.textSecondary)
            }
            VStack(spacing: 0) {
                statRow(String(localized: "Average"), fmt(s.mean), nil, BroopPalette.textPrimary)
                BroopHairline()
                statRow(String(localized: "Min"), fmt(s.min), nil, BroopPalette.textPrimary)
                BroopHairline()
                statRow(String(localized: "Max"), fmt(s.max), nil, BroopPalette.textPrimary)
                BroopHairline()
                statRow(String(localized: "Latest"), latest.map { fmt($0.value) } ?? "–",
                        latest.map { isSteps ? MetricDetailSteps.periodLabel(day: $0.day, resolution: MetricDetailSteps.resolution(for: eff))
                                     : BroopHealthFormat.weekday($0.day) }, BroopPalette.textPrimary)
                BroopHairline()
                statRow(String(localized: "Δ vs. prior \(eff.name)"),
                        hasDelta ? (cmp.delta >= 0 ? "+" : "−") + metric.formatDelta(abs(cmp.delta), system: unitSystem,
                                                                                     temperature: temperatureUnit, effortScale: effortScale) : "–",
                        cmp.pctChange.map { "\($0 >= 0 ? "+" : "")\(String(format: "%.1f", $0))%" }
                            ?? (eff == .all ? String(localized: "all history") : String(localized: "no prior \(eff.name)")),
                        deltaColor)
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func statRow(_ title: String, _ value: String, _ caption: String?, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            BroopCaps(title, size: 11, color: BroopPalette.textBody)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: value).font(BroopType.number(19)).foregroundStyle(color)
                if let caption {
                    Text(verbatim: caption).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .padding(.vertical, 13)
    }

    // MARK: Readings

    @ViewBuilder
    private func readings(_ raw: [(day: String, value: Double)]) -> some View {
        let rows = vitalReadingRows(readings: raw.map { VitalReading(day: $0.day, value: $0.value,
                                                                     source: sourceByDay[$0.day] ?? metric.source) },
                                    unit: "", strapDeviceId: repo.deviceId, format: fmt)
        if !rows.isEmpty {
            let shown = showAllReadings ? rows : Array(rows.prefix(7))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BroopCaps(String(localized: "Readings"), size: 12.5)
                    Spacer()
                    BroopCaps(String(localized: "Source"), size: 10, color: BroopPalette.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 12) {
                            Text(verbatim: row.time).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: row.value).font(BroopType.number(16)).foregroundStyle(BroopPalette.textPrimary)
                            Text(verbatim: row.source).font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                        if i < shown.count - 1 { BroopHairline() }
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                if rows.count > 7 {
                    Button { withAnimation(.snappy) { showAllReadings.toggle() } } label: {
                        BroopCaps(showAllReadings ? String(localized: "Show fewer")
                                  : String(localized: "Show all \(rows.count) →"), size: 11, color: BroopHealthPalette.chartBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Correlations

    private func correlationCard(eff: ExploreRange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(String(localized: "What moves with it"), size: 12.5)
                Text("Pearson r over the visible window · |r| ≥ 0.30, n ≥ 10")
                    .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
            }
            VStack(spacing: 0) {
                if !correlationsLoaded {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(BroopPalette.textSecondary)
                        Text("Scanning the catalog…").font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else if correlations.isEmpty {
                    Text("Nothing in the catalog moves clearly with \(metric.title.lowercased()) over this window. Widen the range to surface relationships.")
                        .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(correlations.enumerated()), id: \.element.id) { i, row in
                        Button { metric = row.metric } label: { corrRow(row) }
                            .buttonStyle(BroopPressableStyle())
                        if i < correlations.count - 1 { BroopHairline() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func corrRow(_ row: Corr) -> some View {
        let color = row.r >= 0 ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText
        return HStack(spacing: 12) {
            Image(systemName: row.metric.icon).font(.system(size: 15, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(row.metric.title, size: 11)
                Text(verbatim: "\(MetricCatalog.categoryDisplayName(row.metric.category)) · n = \(row.n)")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer(minLength: 8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(min(abs(row.r), 1)))
                }
            }
            .frame(width: 56, height: 5)
            Text(verbatim: "\(row.r >= 0 ? "+" : "−")\(String(format: "%.2f", abs(row.r)))")
                .font(BroopType.number(16)).foregroundStyle(color)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func recomputeCorrelations() {
        let eff = effective
        let key = "\(metric.id)|\(eff.rawValue)|\(page)|\(others.count)"
        guard correlationKey != key else { return }
        correlationKey = key
        let window = rawSlice(eff, anchor: anchor(eff))
        let myDays = Set(window.map(\.day))
        guard !myDays.isEmpty else { correlations = []; return }
        var rows: [Corr] = []
        for entry in others {
            let pairs = CorrelationEngine.alignByDay(window, entry.series.filter { myDays.contains($0.day) })
            guard pairs.count >= 10, let c = CorrelationEngine.pearson(pairs), abs(c.r) >= 0.3 else { continue }
            rows.append(Corr(id: entry.metric.id, metric: entry.metric, r: c.r, n: c.n))
        }
        rows.sort { abs($0.r) > abs($1.r) }
        correlations = Array(rows.prefix(6))
    }

    // MARK: Empty state

    @ViewBuilder private var emptyState: some View {
        if metric.key == "fitness_age" {
            VStack(spacing: 14) {
                BroopHealthEmpty(symbol: "figure.run", title: String(localized: "Fitness Age"),
                                 message: fitnessReadyLeadCopy(rhrDays: repo.days.suffix(7).compactMap { $0.restingHr }.count,
                                                               hasAge: profile.age > 0, hasSex: !profile.sex.isEmpty))
                if refreshing {
                    ProgressView().tint(BroopPalette.textPrimary)
                } else {
                    BroopHealthButton(title: String(localized: "Refresh Fitness Age"), symbol: "arrow.clockwise", kind: .secondary) {
                        refreshing = true
                        Task {
                            _ = await intelligence.recomputeFitnessAgeOnly()
                            await load()
                            refreshing = false
                        }
                    }
                }
            }
        } else {
            BroopHealthEmpty(title: String(localized: "No data"),
                             message: String(localized: "No \(metric.title.lowercased()) readings yet. Import your history in Data Sources, or keep wearing your strap."))
        }
    }

    // MARK: Load (classic MetricDetailView.load, phase 1 then phase 2)

    private func load() async {
        let m = metric
        let requestedRange = range
        let resolution: MetricSeriesResolution
        var loadedSeries: [(day: String, value: Double)]
        if MetricDetailSteps.isMetric(m.key) {
            let full = MetricDetailSteps.requiresFullHistory(metricKey: m.key, range: requestedRange)
            if m.source == MetricCatalog.combinedStepsSource {
                resolution = await repo.resolvedSteps(from: "0000-01-01", to: "9999-12-31")
            } else {
                resolution = await repo.resolvedSeries(key: m.key, source: m.source, fullHistory: full)
            }
            loadedSeries = resolution.values
        } else {
            loadedSeries = await repo.exploreSeries(key: m.key, source: m.source)
            resolution = await repo.resolvedSeries(key: m.key, source: m.source)
        }
        guard !Task.isCancelled, m.id == metric.id else { return }
        var sources: [String: String]
        if m.key == "vo2max_est" {
            var attributed: [String: String] = [:]
            for point in resolution.points {
                let tag = await repo.scoreProvenanceTag(resolvedSource: point.source, day: point.day, metricKey: m.key)
                attributed[point.day] = vo2MaxAttributionSource(tag.flatMap { Vo2MaxEstimator(rawValue: $0) })
            }
            sources = attributed
        } else {
            sources = Dictionary(resolution.points.map { ($0.day, $0.source) }, uniquingKeysWith: { a, _ in a })
        }
        if m.key == "spo2", m.source == "my-whoop", PuffinExperiment.spo2CandidateDisplayEnabled {
            let candidate = await repo.exploreSeries(key: "spo2_candidate", source: m.source)
            if !candidate.isEmpty {
                var byDay = Dictionary(loadedSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
                for p in candidate where byDay[p.day] == nil {
                    byDay[p.day] = p.value
                    sources[p.day] = spo2CandidateAttributionSource
                }
                loadedSeries = byDay.sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
            }
        }
        var note: String?
        if m.key == "skin_temp" {
            let days = repo.days
            let anyAbs = days.contains { $0.skinTempC != nil || $0.skinTempDevC.map(VitalBands.isAbsoluteSkinTemp) == true }
            let anyDev = days.contains { $0.skinTempDevC.map { !VitalBands.isAbsoluteSkinTemp($0) } == true }
            if anyAbs || anyDev {
                let leadsAbs: Bool
                switch skinPref {
                case .absolute: leadsAbs = anyAbs
                case .deviation: leadsAbs = !anyDev && anyAbs
                }
                if leadsAbs {
                    loadedSeries = days.compactMap { row in
                        (row.skinTempC ?? row.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil })
                            .map { (day: row.day, value: $0) }
                    }.sorted { $0.day < $1.day }
                } else {
                    loadedSeries = days.compactMap { row in
                        row.skinTempDevC.flatMap { !VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }.map { (day: row.day, value: $0) }
                    }.sorted { $0.day < $1.day }
                }
                sources = Dictionary(loadedSeries.map { ($0.day, m.source) }, uniquingKeysWith: { a, _ in a })
                let either = days.count { $0.skinTempC != nil || $0.skinTempDevC != nil }
                if shouldExplainSkinTempFallback(prefer: skinPref, leadsAbsolute: leadsAbs, anyAbsoluteInWindow: anyAbs) {
                    note = String(localized: "No measured temperature for these nights — showing the difference from your baseline instead. A re-score refills temperatures for nights that have one.")
                } else if shouldExplainShortenedSkinTempSeries(leadsAbsolute: leadsAbs, shownReadings: loadedSeries.count,
                                                               rowsWithEitherNumber: either) {
                    note = String(localized: "Only nights with a measured temperature are shown — the others only have a baseline difference.")
                }
            }
        }
        series = loadedSeries
        sourceByDay = sources
        skinTempNote = note
        loaded = true

        guard let all = await repo.exploreAllSeries() else { return }
        var loadedOthers: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] = []
        for other in MetricCatalog.all where other.id != m.id {
            guard !Task.isCancelled else { return }
            if let s = all[other.id], !s.isEmpty { loadedOthers.append((other, s)) }
        }
        guard !Task.isCancelled, m.id == metric.id else { return }
        others = loadedOthers
        correlationsLoaded = true
        correlationKey = ""
        recomputeCorrelations()
    }
}
#endif
