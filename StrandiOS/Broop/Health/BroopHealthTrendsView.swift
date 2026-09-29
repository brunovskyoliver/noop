#if os(iOS)
import Charts
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Trends (`.trends`): WHOOP's My Dashboard as a trends overview. Rebuilt from the classic
/// `TrendsView`: the week-in-review digest with week browsing and a shareable recap, a dashboard row per
/// headline metric (latest vs. the 30 days before it, each opening its Trend View), the long-horizon
/// training load, the Charge calendar and the PDF trends report. The classic Charge hero and HRV / RHR /
/// Effort small multiples live on as those metrics' Trend Views, which carry the same range control.
struct BroopHealthTrendsView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var weekOffset = 0
    @State private var byID: [String: [(day: String, value: Double)]] = [:]
    @State private var loadResult: TrainingLoadEngine.Result?
    @State private var showReport = false
    @State private var yearAll = false

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The dashboard, in WHOOP's pillar order.
    private static let dashboard: [(key: String, source: String)] = [
        ("recovery", "my-whoop"), ("hrv", "my-whoop"), ("rhr", "my-whoop"), ("resp_rate", "my-whoop"),
        ("sleep_performance", "my-whoop"), ("sleep_total_min", "my-whoop"), ("sleep_efficiency", "my-whoop"),
        ("sleep_consistency", "my-whoop"), ("restorative_min", "my-whoop"),
        ("strain", "my-whoop"), ("steps", "my-whoop"), ("steps", "apple-health"), ("steps_est", "my-whoop"),
        ("energy_kcal", "my-whoop"), ("hr_zones13_min", "my-whoop"), ("hr_zones45_min", "my-whoop"),
        ("vo2max_est", "my-whoop"), ("stress", "my-whoop"), ("weight", "apple-health"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if repo.days.isEmpty {
                    BroopHealthEmpty(title: String(localized: "No history yet"),
                                     message: repo.loaded
                                     ? String(localized: "Trends need history to draw. Import your WHOOP export in Data Sources to see weeks, months and years instantly.")
                                     : String(localized: "Loading your history…"))
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("My Dashboard").font(BroopType.demi(26)).foregroundStyle(BroopPalette.textPrimary)
                        Spacer()
                        NavigationLink(value: BroopScreen.metricExplorer) {
                            HStack(spacing: 6) {
                                BroopCaps(String(localized: "All metrics"), size: 11)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(BroopPalette.textPrimary)
                        }
                    }
                    .padding(.top, 8)
                    LazyVStack(spacing: 10) {
                        ForEach(rows, id: \.metric.id) { row in
                            NavigationLink(value: BroopScreen.metric(key: row.metric.key, source: row.metric.source)) {
                                BroopHealthDashboardRow(symbol: row.metric.icon, title: row.metric.title,
                                                        value: row.value, baseline: row.baseline,
                                                        direction: row.direction, good: row.good)
                            }
                            .buttonStyle(BroopPressableStyle())
                        }
                    }
                    .padding(.top, 14)
                    BroopHealthFootnote(text: String(localized: "Latest reading, with the average of the 30 days before it underneath."))
                        .padding(.top, 10)
                    weekReview.padding(.top, BroopMetrics.section)
                    trainingLoad.padding(.top, BroopMetrics.section)
                    yearCalendar.padding(.top, BroopMetrics.section)
                    Button { showReport = true } label: {
                        BroopHealthRow(symbol: "doc.richtext", title: String(localized: "Export trends report"),
                                       detail: String(localized: "A one-page PDF of recovery, sleep, HRV, resting HR and strain over a range, saved on your \(Platform.deviceNoun)."))
                    }
                    .buttonStyle(BroopPressableStyle())
                    .padding(.top, BroopMetrics.section)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Trends")) }
        .broopHealthScreen()
        .task(id: repo.refreshSeq) {
            byID = await repo.exploreAllSeries() ?? [:]
            let days = repo.days
            loadResult = await CancellableAnalysis.run {
                TrainingLoadEngine.evaluate(days: TrainingLoadEngine.dailyTrimp(days))
            }
        }
        .sheet(isPresented: $showReport) { TrendsReportSheet(days: repo.days) }
    }

    // MARK: Dashboard rows

    private struct Row {
        let metric: MetricDescriptor
        let value: String?
        let baseline: String?
        let direction: Int
        let good: Bool?
    }

    private var rows: [Row] {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let temp = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        return Self.dashboard.compactMap { entry -> Row? in
            guard let m = MetricCatalog.metric(key: entry.key, source: entry.source),
                  let s = byID[m.id], let last = s.last else { return nil }
            // The 30 days before the latest reading.
            var base: Double?
            if let d = BroopHealthFormat.date(last.day) {
                let from = BroopHealthFormat.day(d.addingTimeInterval(-30 * 86_400))
                let prior = s.filter { $0.day >= from && $0.day < last.day }.map(\.value)
                if !prior.isEmpty { base = prior.reduce(0, +) / Double(prior.count) }
            }
            let short: (Double) -> String = { v in Self.short(m, v, system: system, temp: temp, effort: effortScale) }
            var dir = 0
            if let base, abs(last.value - base) > max(abs(base) * 0.005, 1e-9) { dir = last.value > base ? 1 : -1 }
            return Row(metric: m, value: short(last.value), baseline: base.map(short), direction: dir,
                       good: m.higherIsBetter.map { (dir > 0) == $0 })
        }
    }

    /// Compact dashboard value: h:mm for minutes, whole % for percentages, the unit dropped otherwise.
    static func short(_ m: MetricDescriptor, _ v: Double, system: UnitSystem, temp: TemperatureUnit,
                      effort: EffortScale) -> String {
        if m.unit == "min" { return BroopFormat.duration(v) }
        if m.unit == "%" { return "\(BroopFormat.whole(v))%" }
        if m.key == "strain" { return UnitFormatter.effortDisplay(v, scale: effort) }
        if m.key.hasPrefix("steps") || m.unit == "kcal" {
            return v.formatted(.number.locale(AppLanguage.activeLocale).precision(.fractionLength(0)))
        }
        let full = m.format(v, system: system, temperature: temp, effortScale: effort)
        let unit = m.displayUnit(system: system, temperature: temp, effortScale: effort)
        if !unit.isEmpty, full.hasSuffix(" " + unit) { return String(full.dropLast(unit.count + 1)) }
        return full
    }

    // MARK: Week in review

    private var minWeekOffset: Int {
        guard let earliest = repo.days.first?.day,
              let earliestMon = WeeklyDigestEngine.mondayOfWeek(containing: earliest),
              let thisMon = WeeklyDigestEngine.mondayOfWeek(containing: Repository.localDayKey(Date())) else { return 0 }
        var off = 0, mon = thisMon
        while mon > earliestMon && off > -520 { mon = WeeklyDigestEngine.addDays(mon, -7); off -= 1 }
        return off
    }
    private var weekAnchor: String { WeeklyDigestEngine.addDays(Repository.localDayKey(Date()), weekOffset * 7) }

    private var weekReview: some View {
        let digest = WeeklyDigestSource.digest(from: repo.days, anchorDay: weekAnchor,
                                               importedSleep: repo.importedSleep,
                                               computedSleep: repo.computedSleepFigures)
        return VStack(alignment: .leading, spacing: 14) {
            BroopHealthDateNav(label: weekOffset == 0 ? String(localized: "This week")
                               : (weekOffset == -1 ? String(localized: "Last week") : weeklyDigestRangeLabel(digest)),
                               canGoBack: weekOffset > minWeekOffset, canGoForward: weekOffset < 0,
                               onBack: { weekOffset = max(minWeekOffset, weekOffset - 1) },
                               onForward: { weekOffset = min(0, weekOffset + 1) })
                .frame(width: 250).frame(maxWidth: .infinity)
            Text(verbatim: "\(weeklyDigestRangeLabel(digest)) · \(String(localized: "\(digest.daysWithData)/7 days"))")
                .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                .frame(maxWidth: .infinity)
            if digest.isEmpty {
                BroopHealthEmpty(symbol: "calendar", title: String(localized: "No readings this week"),
                                 message: String(localized: "Step to another week with the arrows above to see its review."))
            } else {
                HStack(spacing: 10) {
                    ForEach([WeeklyMetric.charge, .effort, .rest], id: \.self) { m in
                        if let s = digest.summary(m) { scoreTile(s) }
                    }
                }
                VStack(spacing: 0) {
                    ForEach([WeeklyMetric.hrv, .rhr], id: \.self) { m in
                        if let s = digest.summary(m) {
                            signalRow(s)
                            if m == .hrv { BroopHairline() }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                if !digest.focalPoints.isEmpty || digest.balance != .insufficient {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(digest.focalPoints.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(verbatim: digest.balance.sentence).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BroopHealthNotchCard())
                    .padding(.top, 6)
                }
                BroopHealthButton(title: String(localized: "Share recap"), symbol: "square.and.arrow.up", kind: .secondary) {
                    let page = WeeklyDigestContent(digest: digest, compact: true, showsHeader: true)
                        .frame(width: 380).padding(24).background(StrandPalette.surfaceBase)
                        .environment(\.colorScheme, colorScheme)
                    TrendsReportRenderer.exportPNG(page: page, suggestedName: "noop-recap-\(weekAnchor).png")
                }
            }
        }
    }

    private func scoreTile(_ s: WeeklyMetricSummary) -> some View {
        let (title, color): (String, Color) = {
            switch s.metric {
            case .charge: return (String(localized: "Charge"), BroopPalette.band(s.thisWeek.mean))
            case .effort: return (String(localized: "Effort"), BroopPalette.effort)
            default: return (String(localized: "Rest"), BroopPalette.rest)
            }
        }()
        let value: String = s.metric == .effort
            ? UnitFormatter.effortDisplay(s.thisWeek.mean, scale: effortScale)
            : "\(Int(s.thisWeek.mean.rounded()))\(s.metric == .effort ? "" : "%")"
        return VStack(spacing: 8) {
            Text(verbatim: value).font(BroopType.number(26)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(26)
            Capsule().fill(color).frame(width: 34, height: 3)
            BroopCaps(title, size: 10.5, color: BroopPalette.textSecondary)
            wow(s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
    }

    private func signalRow(_ s: WeeklyMetricSummary) -> some View {
        HStack {
            BroopCaps(s.metric == .hrv ? String(localized: "HRV") : String(localized: "Resting HR"), size: 11.5)
            Spacer()
            Text(verbatim: "\(Int(s.thisWeek.mean.rounded())) \(s.metric.unit)")
                .font(BroopType.number(19)).foregroundStyle(BroopPalette.textPrimary)
            wow(s).frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 13)
    }

    @ViewBuilder private func wow(_ s: WeeklyMetricSummary) -> some View {
        if s.weekOverWeek.previous.n > 0, s.wowDelta != 0 {
            let up = s.wowDelta > 0
            let color = s.wowGoodness > 0 ? BroopHealthPalette.chipGoodText
                : (s.wowGoodness < 0 ? BroopHealthPalette.chipBadText : BroopPalette.textSecondary)
            HStack(spacing: 3) {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 7))
                Text(verbatim: s.metric == .effort ? UnitFormatter.effortDisplay(abs(s.wowDelta), scale: effortScale)
                     : "\(Int(abs(s.wowDelta).rounded()))")
                    .font(BroopType.number(13))
            }
            .foregroundStyle(color)
        } else {
            Text(verbatim: "–").font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
        }
    }

    // MARK: Training load

    @ViewBuilder private var trainingLoad: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(String(localized: "Training load"), size: 12.5)
                Spacer()
                if let latest = loadResult?.points.last, loadResult?.isAvailable == true {
                    Text(verbatim: String(format: "%+.0f", latest.balance)).font(BroopType.number(20))
                        .foregroundStyle(latest.balance >= 0 ? BroopHealthPalette.mint : BroopHealthPalette.amber)
                    BroopCaps(String(localized: "Form"), size: 10, color: BroopPalette.textSecondary)
                }
            }
            if let r = loadResult, r.isAvailable {
                let pts = r.points.suffix(90)
                Chart {
                    ForEach(Array(pts), id: \.day) { p in
                        if let d = BroopHealthFormat.date(p.day) {
                            LineMark(x: .value("Day", d), y: .value("Load", p.chronicLoad), series: .value("S", "CTL"))
                                .foregroundStyle(BroopHealthPalette.chartBlue)
                            LineMark(x: .value("Day", d), y: .value("Load", p.acuteLoad), series: .value("S", "ATL"))
                                .foregroundStyle(BroopHealthPalette.stressHigh)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(BroopHealthPalette.grid)
                        AxisValueLabel().font(BroopType.number(11)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(BroopType.medium(11)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                .frame(height: 160)
                HStack(spacing: 16) {
                    legend(BroopHealthPalette.chartBlue, String(localized: "Fitness (CTL)"))
                    legend(BroopHealthPalette.stressHigh, String(localized: "Fatigue (ATL)"))
                }
                Text("Chronic (42-day) against acute (7-day) load from each day's Effort. The gap between them is your form. Descriptive only; it never feeds a score.")
                    .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let have = loadResult?.contiguousDays ?? 0
                let need = TrainingLoadEngine.Configuration.standard.minimumDays
                Text("Training load needs \(need) days of Effort in a row. You have \(have) so far.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 3)
            BroopCaps(text, size: 10, color: BroopPalette.textSecondary)
        }
    }

    // MARK: Year calendar

    private var yearCalendar: some View {
        let recent = yearAll ? repo.days[...] : repo.days.suffix(365)
        let days: [RecoveryDay] = recent.compactMap { d in
            BroopHealthFormat.date(d.day).map { RecoveryDay(date: $0, score: d.recovery) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                BroopCaps(yearAll ? String(localized: "Charge · all history") : String(localized: "Charge · past year"), size: 12.5)
                Spacer()
                if repo.days.count > 365 {
                    Button { yearAll.toggle() } label: {
                        BroopCaps(yearAll ? String(localized: "Past year") : String(localized: "All"), size: 10.5,
                                  color: BroopHealthPalette.chartBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                YearHeatStrip(days: days).padding(.vertical, 2)
            }
            HStack(spacing: 8) {
                BroopCaps(String(localized: "Depleted"), size: 9.5, color: BroopPalette.textSecondary)
                LinearGradient(colors: [BroopPalette.bandLow, BroopPalette.bandMid, BroopPalette.bandHigh],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 4).clipShape(Capsule())
                BroopCaps(String(localized: "Peaked"), size: 9.5, color: BroopPalette.textSecondary)
            }
            Text("\(days.filter { $0.score != nil }.count) days with a Charge score")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }
}
#endif
