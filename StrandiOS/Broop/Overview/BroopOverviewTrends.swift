#if os(iOS)
import Charts
import SwiftUI
import StrandDesign
import WhoopStore

/// One metric the deep-dive trend card can show, read through `Repository.exploreSeries` (the same
/// layered read the Explore and metric pages use).
struct BroopOverviewTrendMetric: Hashable, Identifiable {
    enum Kind: Hashable { case percent, duration, whole, one, effort }

    let key: String
    let title: String
    let symbol: String
    let kind: Kind
    /// Colour bars by Charge band (the Charge trend).
    var banded = false
    var color: Color = BroopPalette.rest
    /// Stored as a 0–1 fraction on some paths (efficiency); lift to percent.
    var fractionToPercent = false

    var id: String { key }

    static func == (a: Self, b: Self) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }

    func format(_ v: Double) -> String {
        switch kind {
        case .percent: return BroopFormat.whole(v) + "%"
        case .duration: return BroopFormat.duration(v)
        case .whole: return BroopFormat.whole(v)
        case .one, .effort: return BroopFormat.one(v)
        }
    }

    static let restSet: [BroopOverviewTrendMetric] = [
        .init(key: "sleep_performance", title: String(localized: "Sleep Performance"), symbol: "moon", kind: .percent),
        .init(key: "sleep_total_min", title: String(localized: "Hours of Sleep"), symbol: "clock", kind: .duration),
        .init(key: "sleep_efficiency", title: String(localized: "Sleep Efficiency"), symbol: "bed.double", kind: .percent,
              fractionToPercent: true),
    ]

    static let chargeSet: [BroopOverviewTrendMetric] = [
        .init(key: "recovery", title: String(localized: "Charge"), symbol: "bolt.heart", kind: .percent, banded: true),
        .init(key: "hrv", title: String(localized: "Heart Rate Variability"), symbol: "waveform.path.ecg", kind: .whole,
              color: Color(broopHex: 0x9AA6F5)),
        .init(key: "rhr", title: String(localized: "Resting Heart Rate"), symbol: "heart", kind: .whole,
              color: Color(broopHex: 0x9AA6F5)),
        .init(key: "resp_rate", title: String(localized: "Respiratory Rate"), symbol: "lungs", kind: .one,
              color: Color(broopHex: 0x9AA6F5)),
    ]

    static let effortSet: [BroopOverviewTrendMetric] = [
        .init(key: "strain", title: String(localized: "Day Effort"), symbol: "flame", kind: .effort, color: BroopPalette.effort),
        .init(key: "steps", title: String(localized: "Steps"), symbol: "shoeprints.fill", kind: .whole, color: BroopPalette.effort),
        .init(key: "active_kcal", title: String(localized: "Calories"), symbol: "flame", kind: .whole, color: BroopPalette.effort),
    ]
}

private enum BroopOverviewTrendRange: String, CaseIterable, Hashable {
    case week = "W", month = "M", sixMonths = "6M"
    var days: Int { self == .week ? 7 : (self == .month ? 30 : 182) }
}

/// WHOOP-style trend view inside a deep dive: metric picker, AVERAGE with a delta chip against the
/// previous period, a W | M | 6M control, bars ending on the selected day with a dashed average and an
/// AVG. tag, and press-to-read.
struct BroopOverviewTrendCard: View {
    @EnvironmentObject private var repo: Repository
    let metrics: [BroopOverviewTrendMetric]
    let dayKey: String

    @State private var metric: BroopOverviewTrendMetric
    @State private var range: BroopOverviewTrendRange = .week
    @State private var selection: Date?
    /// Day-keyed history up to and including `dayKey`, ascending. nil while loading.
    @State private var history: [Point]?

    init(metrics: [BroopOverviewTrendMetric], dayKey: String) {
        self.metrics = metrics
        self.dayKey = dayKey
        _metric = State(initialValue: metrics[0])
    }

    struct Point: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Trends"))
            metricPicker
            BroopOverviewCard {
                if let history {
                    content(history)
                } else {
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .task(id: "\(metric.key)-\(dayKey)-\(repo.refreshSeq)") { await load() }
        .onChange(of: range) { _, _ in selection = nil }
    }

    private var metricPicker: some View {
        Menu {
            ForEach(metrics) { m in
                Button { metric = m; selection = nil } label: { Label(m.title, systemImage: m.symbol) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
                BroopCaps(metric.title, size: 11.5)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(broopHex: 0x353B42)))
        }
    }

    @ViewBuilder
    private func content(_ history: [Point]) -> some View {
        let pts = points(history, range)
        let previous = previousPoints(history)
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        let prevAvg = previous.isEmpty ? nil : previous.map(\.value).reduce(0, +) / Double(previous.count)
        let picked = selection.flatMap { sel in pts.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) } }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    BroopCaps(picked.map { label(for: $0.date) } ?? String(localized: "Average"), size: 10.5,
                              color: BroopPalette.textSecondary)
                    Text(verbatim: (picked?.value ?? avg).map(metric.format) ?? "---")
                        .font(BroopType.number(30))
                        .broopNumeral(30)
                        .foregroundStyle(BroopPalette.textPrimary)
                    if picked == nil, let avg, let prevAvg, prevAvg != 0 {
                        deltaChip(pct: (avg - prevAvg) / abs(prevAvg) * 100)
                    }
                }
                Spacer()
                segmented
            }
            if pts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar").font(.system(size: 22, weight: .light))
                    BroopCaps(String(localized: "No data"), size: 11, color: BroopPalette.textSecondary)
                }
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                chart(pts, average: avg ?? 0, picked: picked)
            }
        }
    }

    private func deltaChip(pct: Double) -> some View {
        let up = pct >= 0
        let color = abs(pct) < 0.5 ? BroopPalette.textSecondary : (up ? BroopOverviewPalette.optimal : BroopOverviewPalette.poor)
        let period = range == .week ? String(localized: "vs. prior week")
            : (range == .month ? String(localized: "vs. prior month") : String(localized: "vs. prior 6 months"))
        return HStack(spacing: 4) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 7))
            Text(verbatim: "\(BroopFormat.whole(abs(pct)))% \(period)").font(BroopType.demi(12))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(BroopOverviewTrendRange.allCases, id: \.self) { r in
                Button { withAnimation(.snappy) { range = r } } label: {
                    Text(verbatim: r.rawValue)
                        .font(BroopType.caps(11))
                        .foregroundStyle(range == r ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                        .frame(width: 38, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(range == r ? Color(broopHex: 0x3A4046) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(broopHex: 0x1A1E22)))
    }

    private func barColor(_ v: Double) -> Color {
        guard metric.banded else { return metric.color }
        return v >= 67 ? Color(broopHex: 0x6FE948) : (v >= 34 ? Color(broopHex: 0xFADF4A) : Color(broopHex: 0xEB3335))
    }

    private func chart(_ pts: [Point], average: Double, picked: Point?) -> some View {
        let unit: Calendar.Component = range == .sixMonths ? .weekOfYear : .day
        let top = max(pts.map(\.value).max() ?? 1, metric.kind == .percent ? 100 : 0) * (range == .week ? 1.15 : 1.05)
        return Chart {
            ForEach(pts) { p in
                BarMark(x: .value("Date", p.date, unit: unit), y: .value(metric.title, p.value), width: .ratio(0.55))
                    .cornerRadius(2)
                    .foregroundStyle(barColor(p.value).opacity(picked == nil || picked?.id == p.id ? 1 : 0.3))
                    .annotation(position: .top, spacing: 4) {
                        if range == .week {
                            Text(verbatim: metric.format(p.value))
                                .font(BroopType.number(10.5))
                                .foregroundStyle(barColor(p.value))
                        }
                    }
            }
            RuleMark(y: .value("Average", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(BroopPalette.textPrimary.opacity(0.8))
                .annotation(position: .overlay, alignment: .leading) {
                    Text("AVG.")
                        .font(BroopType.caps(8.5))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white))
                }
        }
        .chartYScale(domain: 0...max(top, 0.1))
        .chartXSelection(value: $selection)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Color(broopHex: 0x2A3036))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(verbatim: metric.kind == .duration ? "\(Int(d / 60))" : BroopFormat.whole(d))
                            .font(BroopType.number(10))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                    .font(BroopType.number(10))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(height: 210)
        .animation(.snappy, value: range)
    }

    private func label(for date: Date) -> String {
        range == .sixMonths
            ? String(localized: "Week of") + " " + date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// The window's points: daily for W and M, weekly means for 6M.
    private func points(_ history: [Point], _ range: BroopOverviewTrendRange, endOffset: Int = 0) -> [Point] {
        guard let end0 = Self.dayFormatter.date(from: dayKey),
              let end = Calendar.current.date(byAdding: .day, value: -endOffset, to: end0) else { return [] }
        let cal = Calendar.current
        let inWindow = history.filter { p in
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: p.date), to: end).day ?? .max
            return d >= 0 && d < range.days
        }
        guard range == .sixMonths else { return inWindow }
        var buckets: [Int: [Double]] = [:]
        for p in inWindow {
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: p.date), to: end).day ?? 0
            buckets[d / 7, default: []].append(p.value)
        }
        return buckets.keys.sorted(by: >).compactMap { week in
            guard let vals = buckets[week], !vals.isEmpty,
                  let start = cal.date(byAdding: .day, value: -(week * 7 + 6), to: end) else { return nil }
            return Point(date: start, value: vals.reduce(0, +) / Double(vals.count))
        }
    }

    private func previousPoints(_ history: [Point]) -> [Point] {
        points(history, range, endOffset: range.days)
    }

    private func load() async {
        let back = Self.dayFormatter.date(from: dayKey)
            .flatMap { Calendar.current.dateComponents([.day], from: $0, to: Date()).day } ?? 0
        let m = metric
        let raw = await repo.exploreSeries(key: m.key, source: "my-whoop", days: 400 + max(0, back))
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        let key = dayKey
        let pts: [Point] = raw.compactMap { row in
            guard row.day <= key, let date = Self.dayFormatter.date(from: row.day) else { return nil }
            var v = row.value
            if m.kind == .effort { v = UnitFormatter.effortValue(v, scale: scale) }
            if m.fractionToPercent, v <= 1 { v *= 100 }
            return Point(date: date, value: v)
        }
        guard !Task.isCancelled else { return }
        history = pts
    }
}
#endif
