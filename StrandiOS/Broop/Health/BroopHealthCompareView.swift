#if os(iOS)
import Charts
import SwiftUI
import StrandAnalytics
import StrandDesign

/// Broop Compare (`.compare`), rebuilt from the `CompareView`: pick two to four catalog metrics,
/// read them on one min–max normalized overlay (press and drag for each metric's real value on that day),
/// then every pair's Pearson r with the restrained wording. Same loads (`resolvedSeries`), same
/// per-series widening, and the same persisted window and selection keys as the screen.
struct BroopHealthCompareView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage("compare.rangeRaw") private var savedRangeRaw = CompareRange.year.rawValue
    @AppStorage("compare.selectedIds") private var savedSelectedIds = ""

    @State private var selected: [MetricDescriptor] = CompareRules.initialSelection()
    @State private var full: [String: [(day: String, value: Double)]] = [:]
    @State private var loaded = false
    @State private var scrubDate: Date?

    private static let palette: [Color] = [
        Color(broopHex: 0x4FA8F0), Color(broopHex: 0x6FEDA6), Color(broopHex: 0xB07CFF), Color(broopHex: 0xF3AB45),
    ]
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var range: CompareRange { CompareRange(rawValue: savedRangeRaw) ?? .year }

    private struct Series: Identifiable {
        let metric: MetricDescriptor
        let color: Color
        let rows: [(day: String, value: Double)]
        let lo: Double, hi: Double
        var id: String { metric.id }
        func norm(_ v: Double) -> Double { hi > lo ? min(max((v - lo) / (hi - lo), 0), 1) : 0.5 }
    }

    private func slice(_ rows: [(day: String, value: Double)], _ r: CompareRange) -> [(day: String, value: Double)] {
        guard let n = r.days else { return rows }
        guard let last = rows.last.flatMap({ BroopHealthFormat.date($0.day) }) else { return [] }
        let cutoff = BroopHealthFormat.day(last.addingTimeInterval(-Double(n - 1) * 86_400))
        return rows.filter { $0.day >= cutoff }
    }

    private func effective(_ rows: [(day: String, value: Double)]) -> CompareRange {
        guard !rows.isEmpty else { return range }
        for r in range.widening where !slice(rows, r).isEmpty { return r }
        return .all
    }

    private var series: [Series] {
        selected.enumerated().map { i, m in
            let rows = full[m.id] ?? []
            let w = slice(rows, effective(rows))
            let vals = w.map(\.value)
            return Series(metric: m, color: Self.palette[i % Self.palette.count], rows: w,
                          lo: vals.min() ?? 0, hi: vals.max() ?? 0)
        }
    }

    private var widened: Bool {
        selected.contains { m in let r = full[m.id] ?? []; return !r.isEmpty && effective(r) != range }
    }

    var body: some View {
        let s = series
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                picker.padding(.top, 10)
                if selected.count < 2 {
                    BroopHealthEmpty(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "Pick two metrics"),
                                     message: String(localized: "Compare needs at least two metrics with history. Add one above."))
                        .padding(.top, 20)
                } else if s.allSatisfy({ $0.rows.isEmpty }) {
                    BroopHealthEmpty(title: String(localized: "No data"),
                                     message: loaded ? String(localized: "No data for these metrics in \(range.phrase). Widen the range or pick metrics you've logged.")
                                     : String(localized: "Reading your history…"))
                        .padding(.top, 20)
                } else {
                    overlay(s.filter { !$0.rows.isEmpty }).padding(.top, 24)
                    pairsSection(s).padding(.top, BroopMetrics.section)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Compare")) }
        .broopHealthScreen()
        .task(id: "\(selected.map(\.id).sorted().joined(separator: "|"))|\(repo.refreshSeq)") {
            for m in selected { full[m.id] = await repo.resolvedSeries(key: m.key, source: m.source).values }
            loaded = true
        }
    }

    // MARK: Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthSegmented(options: CompareRange.allCases,
                                 selection: Binding(get: { range }, set: { savedRangeRaw = $0.rawValue })) { $0.label }
            VStack(spacing: 8) {
                ForEach(Array(selected.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 12) {
                        Capsule().fill(Self.palette[i % Self.palette.count]).frame(width: 16, height: 4)
                        Image(systemName: m.icon).font(.system(size: 15, weight: .light)).foregroundStyle(BroopPalette.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            BroopCaps(m.title, size: 11)
                            if m.source != "my-whoop" {
                                Text(verbatim: m.sourceLabel).font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textSecondary)
                            }
                        }
                        Spacer()
                        Button { remove(m) } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BroopPalette.textSecondary).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(m.title)"))
                    }
                    .padding(.leading, 16).padding(.trailing, 8)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
                }
                Menu {
                    ForEach(MetricCatalog.categories, id: \.self) { cat in
                        Section(MetricCatalog.categoryDisplayName(cat)) {
                            ForEach(MetricCatalog.inCategory(cat)) { m in
                                let on = selected.contains(m)
                                Button { on ? remove(m) : add(m) } label: {
                                    Label("\(m.title) · \(m.sourceLabel)", systemImage: on ? "checkmark" : m.icon)
                                }
                                .disabled(!on && selected.count >= 4)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        BroopCaps(selected.count >= 4 ? String(localized: "Max 4 metrics") : String(localized: "Add metric"), size: 11.5)
                        Spacer()
                    }
                    .foregroundStyle(selected.count >= 4 ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BroopPalette.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .disabled(selected.count >= 4)
            }
            if selected.count >= 2 {
                let total = series.reduce(0) { $0 + $1.rows.count }
                Text(verbatim: widened
                     ? String(localized: "\(total) readings across \(selected.count) · \(range.phrase) · sparse widened")
                     : String(localized: "\(total) readings across \(selected.count) · \(range.phrase)"))
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(widened ? BroopHealthPalette.amber : BroopPalette.textSecondary)
            }
        }
    }

    private func add(_ m: MetricDescriptor) {
        guard selected.count < 4, !selected.contains(m) else { return }
        withAnimation(.snappy) { selected.append(m) }
        savedSelectedIds = selected.map(\.id).joined(separator: ",")
    }

    private func remove(_ m: MetricDescriptor) {
        withAnimation(.snappy) { selected.removeAll { $0 == m } }
        savedSelectedIds = selected.map(\.id).joined(separator: ",")
    }

    // MARK: Overlay

    private func overlay(_ s: [Series]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(scrubDate.map { BroopHealthFormat.weekday(BroopHealthFormat.day($0)) } ?? String(localized: "Overlay"), size: 12.5)
                Spacer()
                BroopCaps(String(localized: "Normalized"), size: 10, color: BroopPalette.textSecondary)
            }
            Chart {
                ForEach(s) { ser in
                    ForEach(Array(ser.rows.enumerated()), id: \.offset) { _, row in
                        if let d = BroopHealthFormat.date(row.day) {
                            LineMark(x: .value("Day", d), y: .value("Level", ser.norm(row.value)), series: .value("Metric", ser.id))
                                .foregroundStyle(ser.color)
                                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                if let scrubDate {
                    RuleMark(x: .value("Selected", scrubDate)).foregroundStyle(.white.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(BroopHealthPalette.grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(BroopType.medium(11)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .broopHealthScrub(onChange: { loc in
                            guard let plot = proxy.plotFrame else { return }
                            scrubDate = proxy.value(atX: loc.x - geo[plot].origin.x)
                        }, onEnd: { scrubDate = nil })
                }
            }
            .frame(height: 230)
            VStack(spacing: 0) {
                ForEach(Array(s.enumerated()), id: \.element.id) { i, ser in
                    HStack(spacing: 10) {
                        Capsule().fill(ser.color).frame(width: 14, height: 4)
                        BroopCaps(ser.metric.title, size: 10.5, color: BroopPalette.textBody).lineLimit(1)
                        Spacer()
                        Text(verbatim: readout(ser)).font(BroopType.number(15)).foregroundStyle(BroopPalette.textPrimary)
                    }
                    .padding(.vertical, 10)
                    if i < s.count - 1 { BroopHairline() }
                }
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopHealthPalette.innerPanel))
            BroopHealthFootnote(text: widened
                                ? String(localized: "Each line min-max normalized · sparse series widened past \(range.phrase) · press and drag for real values")
                                : String(localized: "Each line min-max normalized within \(range.phrase) · press and drag for real values"))
        }
    }

    /// The real value on the scrubbed day, else the window's min–max.
    private func readout(_ ser: Series) -> String {
        if let scrubDate {
            let key = BroopHealthFormat.day(scrubDate)
            let nearest = ser.rows.min { a, b in
                abs((BroopHealthFormat.date(a.day) ?? .distantPast).timeIntervalSince(scrubDate))
                    < abs((BroopHealthFormat.date(b.day) ?? .distantPast).timeIntervalSince(scrubDate))
            }
            guard let nearest else { return "–" }
            return nearest.day == key ? ser.metric.format(nearest.value, effortScale: effortScale) : "–"
        }
        return "\(ser.metric.format(ser.lo, effortScale: effortScale)) – \(ser.metric.format(ser.hi, effortScale: effortScale))"
    }

    // MARK: Pairs

    private struct Pair: Identifiable {
        let id: String
        let a: Series, b: Series
        let r: Double, n: Int
    }

    private func pairs(_ s: [Series]) -> [Pair] {
        let ne = s.filter { !$0.rows.isEmpty }
        guard ne.count >= 2 else { return [] }
        var out: [Pair] = []
        for i in 0..<(ne.count - 1) {
            for j in (i + 1)..<ne.count {
                let p = CorrelationEngine.alignByDay(ne[i].rows, ne[j].rows)
                guard p.count >= 3, let c = CorrelationEngine.pearson(p) else { continue }
                out.append(Pair(id: "\(ne[i].id)~\(ne[j].id)", a: ne[i], b: ne[j], r: c.r, n: c.n))
            }
        }
        return out.sorted { abs($0.r) > abs($1.r) }
    }

    private func pairsSection(_ s: [Series]) -> some View {
        let list = pairs(s)
        return VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "How they move together"),
                               trailing: list.isEmpty ? nil : (list.count == 1 ? String(localized: "1 pair") : String(localized: "\(list.count) pairs")))
            if list.isEmpty {
                BroopHealthCard {
                    Text("Not enough overlapping days between these metrics in \(range.phrase). Widen the range.")
                        .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                }
            } else {
                ForEach(list) { p in pairCard(p) }
            }
        }
    }

    private func pairCard(_ p: Pair) -> some View {
        let color = p.r >= 0 ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(p.a.color).frame(width: 8, height: 8)
                Circle().fill(p.b.color).frame(width: 8, height: 8)
                BroopCaps("\(p.a.metric.title) ↔ \(p.b.metric.title)", size: 10.5).lineLimit(2)
                Spacer()
                Text(verbatim: "r = \(signedR(p.r))").font(BroopType.number(18)).foregroundStyle(color)
            }
            Text(verbatim: sentence(p)).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(min(abs(p.r), 1)))
                }
            }
            .frame(height: 5)
            Text("\(p.n) overlapping days · \(strength(p.r)) \(direction(p.r)) correlation")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    // the insight language.
    private func sentence(_ p: Pair) -> String {
        let head = String(localized: "\(p.a.metric.title) ↔ \(p.b.metric.title): r = \(signedR(p.r)) (\(strength(p.r)) \(direction(p.r))) over \(p.n) shared days.")
        guard abs(p.r) >= 0.3 else { return String(localized: "\(head) No clear relationship. They move largely independently.") }
        let aT = p.a.metric.title.lowercased(), bT = p.b.metric.title.lowercased()
        return p.r < 0
            ? String(localized: "\(head) When \(aT) rises, \(bT) tends to fall, a \(strength(p.r)) \(direction(p.r)) link.")
            : String(localized: "\(head) When \(aT) rises, \(bT) tends to rise, a \(strength(p.r)) \(direction(p.r)) link.")
    }
    private func signedR(_ r: Double) -> String { (r >= 0 ? "+" : "−") + String(format: "%.2f", abs(r)) }
    private func strength(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.1: return String(localized: "negligible")
        case ..<0.3: return String(localized: "weak")
        case ..<0.5: return String(localized: "moderate")
        case ..<0.7: return String(localized: "strong")
        default: return String(localized: "very strong")
        }
    }
    private func direction(_ r: Double) -> String {
        abs(r) < 0.1 ? "" : (r >= 0 ? String(localized: "positive") : String(localized: "negative"))
    }
}
#endif
