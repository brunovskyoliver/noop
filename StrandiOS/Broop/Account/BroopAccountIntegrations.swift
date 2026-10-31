#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import WhoopStore

// MARK: - Range windows

/// W / M / 3M / 6M / 1Y / ALL, windowed relative to each series' latest point with the sparse
/// auto-widen (AppleHealthView / XiaomiBandView): the selected window whenever it holds a point,
/// otherwise the smallest larger one that does.
enum BroopAccountRange: String, CaseIterable, Identifiable {
    case week, month, quarter, half, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return String(localized: "W")
        case .month: return String(localized: "M")
        case .quarter: return String(localized: "3M")
        case .half: return String(localized: "6M")
        case .year: return String(localized: "1Y")
        case .all: return String(localized: "ALL")
        }
    }
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .half: return 180
        case .year: return 365
        case .all: return nil
        }
    }
    var name: String {
        switch self {
        case .week: return String(localized: "week")
        case .month: return String(localized: "month")
        case .quarter: return String(localized: "3 months")
        case .half: return String(localized: "6 months")
        case .year: return String(localized: "year")
        case .all: return String(localized: "all history")
        }
    }
    var widening: [BroopAccountRange] {
        let order = Self.allCases
        guard let i = order.firstIndex(of: self) else { return [.all] }
        return Array(order[i...])
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func slice(_ rows: [(day: String, value: Double)], _ r: BroopAccountRange) -> [(day: String, value: Double)] {
        guard let n = r.days else { return rows }
        guard let lastDay = rows.last?.day, let last = dayParser.date(from: lastDay) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return rows.filter { (dayParser.date(from: $0.day) ?? .distantPast) >= cutoff }
    }

    func resolve(_ rows: [(day: String, value: Double)]) -> BroopAccountResolved {
        guard !rows.isEmpty else { return BroopAccountResolved(effective: self, rows: []) }
        for r in widening {
            let s = Self.slice(rows, r)
            if !s.isEmpty { return BroopAccountResolved(effective: r, rows: s) }
        }
        return BroopAccountResolved(effective: .all, rows: rows)
    }
}

struct BroopAccountResolved {
    var effective: BroopAccountRange
    var rows: [(day: String, value: Double)]
    var values: [Double] { rows.map(\.value) }
    var mean: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
}

/// One metric on a source page: a tile, a chart, or both.
struct BroopAccountMetric: Identifiable {
    enum Aggregate { case latest, mean }
    let key: String
    let title: String
    var tileTitle: String? = nil
    var unit: String = ""
    var aggregate: Aggregate = .latest
    var tint: Color
    var tile = true
    var chart = true
    let format: (Double) -> String
    var id: String { key }
}

// MARK: - Source dashboard

/// Range tabs, a tile grid and a chart card per metric. The resolved windows are computed once per data
/// or range change, never in `body`.
struct BroopAccountSourceDashboard<Extra: View>: View {
    let series: [String: [(day: String, value: Double)]]
    let metrics: [BroopAccountMetric]
    /// Bumped by the owner on every load so the windows are rebuilt for new data.
    var version: Int = 0
    var extraTiles: [(title: String, value: String, caption: String?)] = []
    var sections: [(title: String, keys: [String])]
    @ViewBuilder var extra: (String) -> Extra

    @State private var range: BroopAccountRange = .quarter
    @State private var resolved: [String: BroopAccountResolved] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if metrics.contains(where: { hasData($0.key) }) { rangeTabs }
            tileGrid
            ForEach(sections.filter { $0.keys.contains(where: hasData) }, id: \.title) { section in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        BroopAccountSectionLabel(text: section.title)
                        Spacer()
                        BroopCaps(range.label, size: 10, color: BroopAccountStyle.caption)
                    }
                    extra(section.title)
                    LazyVStack(spacing: 10) {
                        ForEach(section.keys.filter(hasData), id: \.self) { key in
                            if let metric = metrics.first(where: { $0.key == key }), metric.chart {
                                BroopAccountChartCard(metric: metric, resolved: resolved[key], selected: range)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { rebuild() }
        .onChange(of: range) { _, _ in rebuild() }
        .onChange(of: version) { _, _ in rebuild() }
    }

    /// Metrics the source never recorded are left out rather than drawn as empty cards.
    private func hasData(_ key: String) -> Bool { !(series[key] ?? []).isEmpty }

    private func rebuild() {
        var out: [String: BroopAccountResolved] = [:]
        for metric in metrics { out[metric.key] = range.resolve(series[metric.key] ?? []) }
        resolved = out
    }

    private var rangeTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(BroopAccountRange.allCases) { r in
                    let on = r == range
                    Button { withAnimation(.snappy) { range = r } } label: {
                        Text(verbatim: r.label)
                            .font(BroopType.caps(11.5))
                            .tracking(1)
                            .foregroundStyle(on ? BroopPalette.textPrimary : BroopAccountStyle.caption)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(Capsule().fill(on ? BroopPalette.pillInner : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(BroopPalette.pillOuter))
            let widened = metrics.contains { m in
                guard let r = resolved[m.key], !r.rows.isEmpty else { return false }
                return r.effective != range
            }
            Text(verbatim: widened ? String(localized: "\(range.name) · some sparse series widened") : range.name.capitalized)
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopAccountStyle.caption)
        }
    }

    private var tileGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(metrics.filter { $0.tile && hasData($0.key) }) { metric in
                BroopAccountStatTile(metric: metric, resolved: resolved[metric.key])
            }
            ForEach(extraTiles, id: \.title) { tile in
                BroopAccountStatTileBody(title: tile.title, value: tile.value, caption: tile.caption,
                                         spark: [], tint: BroopPalette.effort)
            }
        }
    }
}

private struct BroopAccountStatTile: View {
    let metric: BroopAccountMetric
    let resolved: BroopAccountResolved?

    var body: some View {
        let rows = resolved?.rows ?? []
        let values = rows.map(\.value)
        let value: String
        let caption: String?
        if values.isEmpty {
            value = "—"; caption = nil
        } else if metric.aggregate == .mean, let mean = resolved?.mean {
            value = metric.format(mean); caption = String(localized: "avg · \(values.count)d")
        } else {
            value = metric.format(values.last ?? 0)
            caption = rows.last.flatMap { BroopAccountRange.dayParser.date(from: $0.day) }
                .map { String(localized: "as of \($0.formatted(.dateTime.day().month(.abbreviated)))") }
        }
        return BroopAccountStatTileBody(title: metric.tileTitle ?? metric.title,
                                        value: metric.unit.isEmpty || values.isEmpty ? value : "\(value) \(metric.unit)",
                                        caption: caption, spark: Array(values.suffix(40)), tint: metric.tint)
    }
}

private struct BroopAccountStatTileBody: View {
    let title: String
    let value: String
    let caption: String?
    let spark: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BroopCaps(title, size: 10, color: BroopAccountStyle.caption).lineLimit(1)
            Text(verbatim: value)
                .font(BroopType.number(22))
                .foregroundStyle(value == "—" ? BroopPalette.textTertiary : BroopPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(alignment: .bottom) {
                Text(verbatim: caption ?? " ")
                    .font(BroopType.medium(11.5))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if spark.count > 1 {
                    BroopAccountSparkline(values: spark, tint: tint).frame(width: 54, height: 18)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        .accessibilityElement(children: .combine)
    }
}

struct BroopAccountSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            guard let lo = values.min(), let hi = values.max(), values.count > 1 else { return }
            let span = max(hi - lo, 0.0001)
            var path = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: size.height * (1 - CGFloat((v - lo) / span)))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A metric chart with the average in the corner and an avg / min / max / points footer.
private struct BroopAccountChartCard: View {
    let metric: BroopAccountMetric
    let resolved: BroopAccountResolved?
    let selected: BroopAccountRange

    private struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }

    var body: some View {
        let rows = resolved?.rows ?? []
        let values = rows.map(\.value)
        let points = Self.decimate(rows.compactMap { r in
            BroopAccountRange.dayParser.date(from: r.day).map { Point(date: $0, value: r.value) }
        }, max: 160)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: metric.title).font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                    Text(verbatim: note(count: values.count)).font(BroopType.regular(12)).foregroundStyle(BroopAccountStyle.caption)
                }
                Spacer()
                if let mean = resolved?.mean {
                    Text(verbatim: metric.format(mean) + (metric.unit.isEmpty ? "" : " \(metric.unit)"))
                        .font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
                }
            }
            if points.count >= 2 {
                chart(points)
            } else if let only = values.last {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Latest reading"), size: 9.5, color: BroopAccountStyle.caption)
                    Text(verbatim: metric.format(only) + (metric.unit.isEmpty ? "" : " \(metric.unit)"))
                        .font(BroopType.number(30)).foregroundStyle(metric.tint)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                Text("No readings recorded.")
                    .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            footer(values)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private func chart(_ points: [Point]) -> some View {
        let lo = points.map(\.value).min() ?? 0, hi = points.map(\.value).max() ?? 1
        let pad = max((hi - lo) * 0.12, 0.5)
        return Chart(points) { p in
            AreaMark(x: .value("Day", p.date), yStart: .value("Base", lo - pad), yEnd: .value("Value", p.value))
                .foregroundStyle(LinearGradient(colors: [metric.tint.opacity(0.28), metric.tint.opacity(0)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                .foregroundStyle(metric.tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(BroopAccountStyle.caption)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(BroopPalette.hairline)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(verbatim: metric.format(d)).foregroundStyle(BroopAccountStyle.caption) }
                }
            }
        }
        .frame(height: 140)
    }

    private func footer(_ values: [Double]) -> some View {
        let items: [(String, String)] = {
            guard let lo = values.min(), let hi = values.max(), !values.isEmpty else {
                return [(String(localized: "Avg"), "—"), (String(localized: "Min"), "—"), (String(localized: "Max"), "—"), (String(localized: "Points"), "0")]
            }
            let avg = values.reduce(0, +) / Double(values.count)
            return [(String(localized: "Avg"), metric.format(avg)), (String(localized: "Min"), metric.format(lo)),
                    (String(localized: "Max"), metric.format(hi)), (String(localized: "Points"), "\(values.count)")]
        }()
        return HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 3) {
                    BroopCaps(item.0, size: 9, color: BroopAccountStyle.caption)
                    Text(verbatim: item.1).font(BroopType.number(13.5)).foregroundStyle(BroopPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func note(count n: Int) -> String {
        let eff = resolved?.effective ?? selected
        if eff != selected && n > 0 {
            return n == 1 ? String(localized: "1 reading · sparse, widened to \(eff.name)")
                          : String(localized: "\(n) readings · sparse, widened to \(eff.name)")
        }
        return n == 1 ? String(localized: "1 reading · \(selected.name)") : String(localized: "\(n) readings · \(selected.name)")
    }

    /// Min/max bucketing keeps peaks and troughs while capping the vertex count; stats use every point.
    private static func decimate(_ pts: [Point], max: Int) -> [Point] {
        guard pts.count > max, max >= 4 else { return pts }
        let buckets = max / 2
        let size = Double(pts.count) / Double(buckets)
        var out: [Point] = [pts[0]]
        for b in 0..<buckets {
            let lo = Int(Double(b) * size), hi = Swift.min(pts.count, Int(Double(b + 1) * size))
            guard lo < hi else { continue }
            let slice = pts[lo..<hi]
            guard let mn = slice.min(by: { $0.value < $1.value }), let mx = slice.max(by: { $0.value < $1.value }) else { continue }
            if mn.date <= mx.date { out.append(mn); if mx.date != mn.date { out.append(mx) } } else { out.append(mx); out.append(mn) }
        }
        if let last = pts.last, out.last?.date != last.date { out.append(last) }
        return out
    }
}

enum BroopAccountFmt {
    static func int(_ v: Double) -> String { Int(v.rounded()).formatted() }
    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? String(localized: "\(h)h \(m)m") : String(localized: "\(m)m")
    }
}

// MARK: - Integration header

/// Source icon — dot-line-dot — Broop tile, as on WHOOP's Apple Health page.
struct BroopAccountLinkIllustration<Source: View>: View {
    let symbols: [String]
    @ViewBuilder var source: Source

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                source.frame(width: 84, height: 84)
                HStack(spacing: 0) {
                    Circle().fill(BroopAccountStyle.icon).frame(width: 10, height: 10)
                    Rectangle().fill(BroopAccountStyle.icon.opacity(0.7)).frame(width: 60, height: 1.5)
                    Circle().fill(BroopAccountStyle.icon).frame(width: 10, height: 10)
                }
                .padding(.horizontal, 12)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(broopHex: 0x121517))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .overlay(BroopBadge(size: 58))
                    .frame(width: 84, height: 84)
            }
            HStack(spacing: 12) {
                ForEach(symbols, id: \.self) { s in
                    Image(systemName: s)
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopPalette.row))
                }
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BroopAccountStyle.icon.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Apple Health

struct BroopAccountAppleHealthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @State private var loaded = false
    @State private var snapshot: AppleHealthLoadCache?
    @State private var loadCount = 0

    private static let seriesKeys = ["steps", "active_kcal", "vo2max", "resting_hr", "hrv", "spo2", "resp_rate",
                                     "asleep_min", "weight", "body_fat", "lean_mass", "bmi"]

    private var mass: (Double) -> String {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return { UnitFormatter.massFromKilograms($0, system: system) }
    }

    private var metrics: [BroopAccountMetric] {
        [
            BroopAccountMetric(key: "steps", title: String(localized: "Steps"), tint: BroopPalette.effort, format: BroopAccountFmt.int),
            BroopAccountMetric(key: "resting_hr", title: String(localized: "Resting heart rate"), tileTitle: String(localized: "Resting HR"),
                               unit: "bpm", tint: BroopPalette.bandLow, format: { "\(Int($0.rounded()))" }),
            BroopAccountMetric(key: "hrv", title: String(localized: "Heart rate variability"), tileTitle: "HRV", unit: "ms",
                               tint: BroopPalette.teal, format: { "\(Int($0.rounded()))" }),
            BroopAccountMetric(key: "vo2max", title: "VO₂ Max", unit: "ml/kg", tint: BroopPalette.teal, chart: false,
                               format: { String(format: "%.1f", $0) }),
            BroopAccountMetric(key: "spo2", title: String(localized: "Blood oxygen"), tint: BroopPalette.rest, tile: false,
                               format: { String(format: "%.1f%%", $0) }),
            BroopAccountMetric(key: "resp_rate", title: String(localized: "Respiratory rate"), tint: BroopPalette.rest, tile: false,
                               format: { String(format: "%.1f rpm", $0) }),
            BroopAccountMetric(key: "active_kcal", title: String(localized: "Active energy"), tint: BroopPalette.warning, tile: false,
                               format: { "\(BroopAccountFmt.int($0)) kcal" }),
            BroopAccountMetric(key: "weight", title: String(localized: "Weight"), tint: BroopPalette.textBody, format: mass),
            BroopAccountMetric(key: "body_fat", title: String(localized: "Body fat"), unit: "%", tint: BroopPalette.warning,
                               format: { String(format: "%.1f", $0) }),
            BroopAccountMetric(key: "lean_mass", title: String(localized: "Lean body mass"), tileTitle: String(localized: "Lean mass"),
                               tint: BroopPalette.textBody, format: mass),
            BroopAccountMetric(key: "bmi", title: "BMI", tint: BroopPalette.rest, tile: false, format: { String(format: "%.1f", $0) }),
            BroopAccountMetric(key: "asleep_min", title: String(localized: "Asleep"), tileTitle: String(localized: "Asleep avg"),
                               aggregate: .mean, tint: BroopPalette.rest, format: BroopAccountFmt.duration),
        ]
    }

    private var hasData: Bool {
        guard let snapshot else { return false }
        return !snapshot.appleRows.isEmpty || snapshot.series.values.contains { !$0.isEmpty }
    }

    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountLinkIllustration(symbols: ["scalemass", "figure.run", "flame", "figure.mind.and.body", "heart.text.square"]) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white)
                    .overlay(Image(systemName: "heart.fill").font(.system(size: 36))
                        .foregroundStyle(LinearGradient(colors: [Color(broopHex: 0xFF5E7E), Color(broopHex: 0xFF2D55)], startPoint: .top, endPoint: .bottom)))
            }
            Text("Connecting Apple Health brings your sleep, heart rate, steps and body measurements into NOOP, and writes your strap's sleep, heart rate, workouts and nightly vitals back. Everything stays on \(Platform.deviceNounPhrase).")
                .font(BroopType.medium(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            BroopAccountAppleHealthLiveCard(reload: { await load(allowCache: false) })
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Reading your Apple Health history…").font(BroopType.medium(14)).foregroundStyle(BroopAccountStyle.caption)
                }
            } else if !hasData {
                BroopAccountNotice(symbol: "tray", text: health.auth == .entitlementMissing
                    ? String(localized: "Nothing here yet. This sideloaded install can't read Apple Health directly. Import a Health export .zip in Data Sources, or turn on Shortcuts Export to bring your strap data into Health.")
                    : String(localized: "Nothing here yet. Tap Enable Apple Health above to read your data live, or import a Health export .zip in Data Sources."),
                    tint: BroopAccountStyle.icon)
            } else if let snapshot {
                BroopAccountSourceDashboard(
                    series: snapshot.series, metrics: metrics, version: loadCount,
                    extraTiles: [(String(localized: "Workouts"), "\(snapshot.workoutCount)",
                                  snapshot.workoutCount > 0 ? String(localized: "Apple-logged") : nil)],
                    sections: [
                        (String(localized: "Heart & vitals"), ["resting_hr", "hrv", "spo2", "resp_rate"]),
                        (String(localized: "Activity & energy"), ["steps", "active_kcal"]),
                        (String(localized: "Body composition"), ["weight", "body_fat", "lean_mass", "bmi"]),
                        (String(localized: "Sleep"), ["asleep_min"]),
                    ]) { _ in EmptyView() }
            }
        }
        .refreshable { await repo.refresh() }
        .broopAccountChrome(String(localized: "Apple Health"))
        .task(id: AppleHealthLoadKey(seq: repo.refreshSeq, dayKey: Repository.localDayKey(Date()))) { await load(allowCache: true) }
    }

    /// The same cached loader the Apple Health screen uses (`performAppleHealthLoad`).
    private func load(allowCache: Bool) async {
        snapshot = await repo.performAppleHealthLoad(seriesKeys: Self.seriesKeys, allowCache: allowCache)
        loaded = true
        loadCount += 1
    }
}

/// Live HealthKit connection: the card's four states and its Enable / Sync now calls.
private struct BroopAccountAppleHealthLiveCard: View {
    let reload: () async -> Void
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BroopCaps(String(localized: "Apple Health (live)"), size: 12)
                Spacer()
                if health.auth == .authorized {
                    BroopAccountChip(text: health.syncing ? String(localized: "Syncing") : String(localized: "Connected"),
                                     tint: BroopAccountStyle.connected)
                }
            }
            switch health.auth {
            case .unavailable:
                note(String(localized: "Apple Health isn't available on \(Platform.deviceNounPhrase)."))
            case .entitlementMissing:
                note(String(localized: "This install can't connect to Apple Health directly. It was signed with a profile that doesn't include Apple's Health permission, so there's nothing to enable, and NOOP won't appear under Settings › Health."))
                note(String(localized: "To get your Apple Health data in anyway: import a Health export .zip in Data Sources, or turn on Shortcuts Export to feed your strap data into Health without the entitlement. (A build installed from the App Store or signed with a paid Apple Developer account connects directly.)"))
            case .unknown, .denied:
                note(String(localized: "Read your heart rate, HRV, blood oxygen, respiratory rate, sleep, steps and energy straight from Apple Health, and write NOOP's strap data back: sleep with full stages, continuous heart rate, workouts, and nightly vitals. Everything stays on \(Platform.deviceNounPhrase)."))
                BroopAccountButton(title: String(localized: "Enable Apple Health")) {
                    Task {
                        await health.requestAuthorization()
                        await syncAndRefresh()
                    }
                }
                if health.auth == .denied {
                    note(String(localized: "If you don't see the prompt, enable NOOP under Settings › Health › Data Access & Devices."))
                }
            case .authorized:
                note(health.lastSync.map { String(localized: "Last synced \(relativeAgo($0.timeIntervalSince1970)).") }
                     ?? String(localized: "Connected. New strap data is written automatically, with periodic background refresh when iOS allows it."))
                BroopAccountButton(title: String(localized: "Sync now"), kind: .secondary, busy: health.syncing) {
                    Task { await syncAndRefresh() }
                }
            }
            if let err = health.lastError {
                Text(verbatim: err).font(BroopType.regular(12.5)).foregroundStyle(BroopAccountStyle.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private func syncAndRefresh() async {
        await HealthSyncRefreshCoordinator.run(
            sync: { await health.sync() },
            refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
        await reload()
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Mi Band

struct BroopAccountMiBandView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @State private var loaded = false
    @State private var series: [String: [(day: String, value: Double)]] = [:]
    @State private var loadCount = 0
    @State private var lastNight: (session: CachedSleepSession, intervals: [SleepInterval], stages: [SleepStage: Double])?

    private static let source = "xiaomi-band"
    private static let seriesKeys = ["steps", "distance_m", "energy_kcal", "intensity_min", "rhr", "avg_hr", "max_hr", "spo2",
                                     "sleep_total_min", "sleep_deep_min", "sleep_rem_min", "sleep_light_min", "sleep_score",
                                     "stress", "vitality"]

    private var metrics: [BroopAccountMetric] {
        let distanceSystem = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
        let bpm: (Double) -> String = { "\(Int($0.rounded()))" }
        return [
            BroopAccountMetric(key: "steps", title: String(localized: "Steps"), tint: BroopPalette.effort, format: BroopAccountFmt.int),
            BroopAccountMetric(key: "rhr", title: String(localized: "Resting heart rate"), tileTitle: String(localized: "Resting HR"),
                               unit: "bpm", tint: BroopPalette.bandLow, format: bpm),
            BroopAccountMetric(key: "sleep_total_min", title: String(localized: "Time asleep"), tileTitle: String(localized: "Sleep avg"),
                               aggregate: .mean, tint: BroopPalette.rest, format: BroopAccountFmt.duration),
            BroopAccountMetric(key: "sleep_score", title: String(localized: "Sleep score"), tint: BroopPalette.rest, format: bpm),
            BroopAccountMetric(key: "spo2", title: String(localized: "Blood oxygen"), unit: "%", tint: BroopPalette.rest,
                               format: { String(format: "%.0f", $0) }),
            BroopAccountMetric(key: "stress", title: String(localized: "Stress"), tileTitle: String(localized: "Stress avg"),
                               aggregate: .mean, tint: BroopPalette.warning, format: bpm),
            BroopAccountMetric(key: "avg_hr", title: String(localized: "Average heart rate"), tileTitle: String(localized: "Avg HR"),
                               unit: "bpm", aggregate: .mean, tint: BroopPalette.bandLow, format: bpm),
            BroopAccountMetric(key: "vitality", title: String(localized: "Vitality"), tint: BroopPalette.teal, format: bpm),
            BroopAccountMetric(key: "max_hr", title: String(localized: "Peak heart rate"), unit: "bpm", tint: BroopPalette.bandLow,
                               tile: false, format: bpm),
            BroopAccountMetric(key: "sleep_deep_min", title: String(localized: "Deep sleep"), tint: BroopPalette.stageDeep, tile: false,
                               format: BroopAccountFmt.duration),
            BroopAccountMetric(key: "sleep_rem_min", title: String(localized: "REM sleep"), tint: BroopPalette.stageREM, tile: false,
                               format: BroopAccountFmt.duration),
            BroopAccountMetric(key: "distance_m", title: String(localized: "Distance"), tint: BroopPalette.effort, tile: false,
                               format: { UnitFormatter.distanceFromMeters($0, system: distanceSystem) }),
            BroopAccountMetric(key: "energy_kcal", title: String(localized: "Active energy"), tint: BroopPalette.warning, tile: false,
                               format: { "\(BroopAccountFmt.int($0)) kcal" }),
            BroopAccountMetric(key: "intensity_min", title: String(localized: "Intensity minutes"), unit: "min", tint: BroopPalette.warning,
                               tile: false, format: bpm),
        ]
    }

    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountLinkIllustration(symbols: ["figure.walk", "heart", "bed.double", "lungs", "brain.head.profile"]) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(broopHex: 0xFF6900))
                    .overlay(Image(systemName: "figure.walk.motion").font(.system(size: 34, weight: .medium)).foregroundStyle(.white))
            }
            Text("Your Mi Band history, imported from the Mi Fitness app: steps, heart rate, sleep stages, SpO₂ and stress, read locally on \(Platform.deviceNounPhrase).")
                .font(BroopType.medium(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Reading your Mi Band history…").font(BroopType.medium(14)).foregroundStyle(BroopAccountStyle.caption)
                }
            } else if !series.values.contains(where: { !$0.isEmpty }) {
                BroopAccountNotice(symbol: "tray",
                                   text: String(localized: "Nothing imported yet. In Data Sources, choose your Mi Fitness export (a .zip of the Mi Fitness app folder from the Files app) to bring in your steps, heart rate, sleep stages, SpO₂ and stress."),
                                   tint: BroopAccountStyle.icon)
                BroopAccountLink(value: BroopScreen.dataSources, symbol: "square.and.arrow.down", title: String(localized: "Data Sources"))
            } else {
                BroopAccountSourceDashboard(
                    series: series, metrics: metrics, version: loadCount,
                    sections: [
                        (String(localized: "Heart & vitals"), ["rhr", "avg_hr", "max_hr", "spo2"]),
                        (String(localized: "Sleep"), ["sleep_total_min", "sleep_deep_min", "sleep_rem_min", "sleep_score"]),
                        (String(localized: "Activity & energy"), ["steps", "distance_m", "energy_kcal", "intensity_min"]),
                        (String(localized: "Wellbeing"), ["stress", "vitality"]),
                    ]) { title in
                        if title == String(localized: "Sleep"), let lastNight {
                            BroopAccountHypnogramCard(session: lastNight.session, intervals: lastNight.intervals, stages: lastNight.stages)
                        }
                    }
            }
        }
        .refreshable { await repo.refresh() }
        .broopAccountChrome(String(localized: "Mi Band"))
        .task(id: repo.refreshSeq) { await load() }
    }

    private func load() async {
        var fetched: [String: [(day: String, value: Double)]] = [:]
        for key in Self.seriesKeys { fetched[key] = await repo.series(key: key, source: Self.source) }
        var sleeps: [CachedSleepSession] = []
        if let store = await repo.storeHandle() {
            let far = Int(Date.distantFuture.timeIntervalSince1970)
            sleeps = (try? await store.sleepSessions(deviceId: Self.source, from: 0, to: far, limit: 4000)) ?? []
        }
        var night: (CachedSleepSession, [SleepInterval], [SleepStage: Double])?
        if let s = sleeps.last(where: { ($0.stagesJSON?.count ?? 0) > 2 }),
           let decoded = Self.decodeStages(s.stagesJSON, sessionStart: s.startTs), decoded.intervals.count >= 2 {
            night = (s, decoded.intervals, decoded.stages)
        }
        series = fetched
        lastNight = night.map { (session: $0.0, intervals: $0.1, stages: $0.2) }
        loaded = true
        loadCount += 1
    }

    /// The importer's verbatim `[{start,end,stage}]` hypnogram, decoded as XiaomiBandView does.
    private static func decodeStages(_ json: String?, sessionStart: Int) -> (stages: [SleepStage: Double], intervals: [SleepInterval])? {
        guard let json, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !arr.isEmpty else { return nil }
        var stages: [SleepStage: Double] = [:]
        var intervals: [SleepInterval] = []
        for seg in arr {
            guard let start = (seg["start"] as? NSNumber)?.intValue, let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                  let name = seg["stage"] as? String else { continue }
            let stage: SleepStage
            switch name {
            case "wake", "awake": stage = .awake
            case "light": stage = .light
            case "deep": stage = .deep
            case "rem": stage = .rem
            default: continue
            }
            stages[stage, default: 0] += Double(end - start) / 60
            intervals.append(SleepInterval(stage: stage, start: TimeInterval(start - sessionStart), end: TimeInterval(end - sessionStart)))
        }
        let asleep = (stages[.light] ?? 0) + (stages[.deep] ?? 0) + (stages[.rem] ?? 0)
        return asleep > 0 ? (stages, intervals) : nil
    }
}

/// Last imported night as a stepped four-lane hypnogram in the Rest stage colours.
private struct BroopAccountHypnogramCard: View {
    let session: CachedSleepSession
    let intervals: [SleepInterval]
    let stages: [SleepStage: Double]

    var body: some View {
        let asleep = (stages[.light] ?? 0) + (stages[.deep] ?? 0) + (stages[.rem] ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last sleep").font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                    Text(verbatim: subtitle).font(BroopType.regular(12)).foregroundStyle(BroopAccountStyle.caption)
                }
                Spacer()
                Text(verbatim: BroopAccountFmt.duration(asleep)).font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
            }
            Canvas { ctx, size in
                let total = max(intervals.map(\.end).max() ?? 1, 1)
                let lane = size.height / 4
                for i in intervals {
                    let row: CGFloat
                    let color: Color
                    switch i.stage {
                    case .awake: row = 0; color = BroopPalette.stageAwake
                    case .rem: row = 1; color = BroopPalette.stageREM
                    case .light: row = 2; color = BroopPalette.stageLight
                    default: row = 3; color = BroopPalette.stageDeep
                    }
                    let x = size.width * CGFloat(i.start / total)
                    let w = max(1, size.width * CGFloat((i.end - i.start) / total))
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: row * lane + 3, width: w, height: lane - 6), cornerRadius: 2),
                             with: .color(color))
                }
            }
            .frame(height: 110)
            HStack(spacing: 0) {
                stat(String(localized: "REM"), stages[.rem] ?? 0, BroopPalette.stageREM)
                stat(String(localized: "Deep"), stages[.deep] ?? 0, BroopPalette.stageDeep)
                stat(String(localized: "Light"), stages[.light] ?? 0, BroopPalette.stageLight)
                stat(String(localized: "Awake"), stages[.awake] ?? 0, BroopPalette.stageAwake)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private var subtitle: String {
        let inBed = BroopAccountFmt.duration(Double(session.endTs - session.startTs) / 60)
        let date = Date(timeIntervalSince1970: TimeInterval(session.startTs)).formatted(.dateTime.day().month(.abbreviated))
        if let eff = session.efficiency {
            return String(localized: "\(date) · \(inBed) in bed · \(Int(eff.rounded()))% efficiency")
        }
        return String(localized: "\(date) · \(inBed) in bed")
    }

    private func stat(_ label: String, _ minutes: Double, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            BroopCaps(label, size: 9, color: tint)
            Text(verbatim: BroopAccountFmt.duration(minutes)).font(BroopType.number(13.5)).foregroundStyle(BroopPalette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
