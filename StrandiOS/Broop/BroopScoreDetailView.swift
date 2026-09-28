#if os(iOS)
import Charts
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Score detail for Rest, Charge and Effort. One template for all three; the tab strip switches score in
/// place. Every figure comes from the shared `BroopStore` snapshot (the same one Home draws), so the dial on
/// Home and the hero here always agree for the selected day.
struct BroopScoreDetailView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""

    @State private var score: BroopScore
    @State private var guideSection: ScoreSection?

    init(initial: BroopScore) { _score = State(initialValue: initial) }

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            VStack(spacing: 0) {
                header.padding(.top, 8)
                BroopUnderlineTabs(options: BroopScore.allCases, selection: $score) { $0.title }
                    .padding(.top, 22)
                titleRow.padding(.top, 30)
                hero(snap).padding(.top, 18)
                insight(snap).padding(.top, 34)
                extras(snap)
                statistics(snap)
                if let snap {
                    BroopTrendCard(score: score, dayKey: snap.dayKey, maxValue: snap.maxValue(score))
                        .id("\(score.rawValue)-\(snap.dayKey)-\(repo.refreshSeq)")
                        .padding(.top, BroopMetrics.section)
                }
                detailLinks.padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .broopStatusBarScrim()
        .background(BroopBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)") {
            await store.reload(repo: repo, profile: profile)
        }
        .sheet(item: $guideSection) { section in
            NavigationStack {
                ScoringGuideView(initialSection: section, onClose: { guideSection = nil })
            }
        }
    }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // MARK: Header

    private var header: some View {
        ZStack {
            BroopDateNavigator(
                label: store.dayLabel,
                canGoBack: store.dayOffset < store.maxOffset(repo: repo),
                canGoForward: store.dayOffset > 0,
                onBack: { withAnimation(.snappy) { store.step(1, repo: repo) } },
                onForward: { withAnimation(.snappy) { store.step(-1, repo: repo) } },
                onToday: { withAnimation(.snappy) { store.dayOffset = 0 } }
            )
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 40, height: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                Spacer()
            }
        }
    }

    private var pageTitle: String {
        switch score {
        case .rest: return String(localized: "Rest Performance")
        case .charge: return String(localized: "Charge Performance")
        case .effort: return String(localized: "Day Effort")
        }
    }

    private var titleRow: some View {
        ZStack {
            BroopCaps(pageTitle, size: 11.5)
                .multilineTextAlignment(.center)
            HStack {
                Spacer()
                Button { guideSection = section(for: score) } label: {
                    Image(systemName: "info")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(BroopPalette.textSecondary, lineWidth: 1.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: String(localized: "How scores work") + ": \(score.title)"))
            }
        }
    }

    private func section(for score: BroopScore) -> ScoreSection {
        switch score {
        case .rest: return .rest
        case .charge: return .charge
        case .effort: return .effort
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ snap: BroopSnapshot?) -> some View {
        switch score {
        case .rest:
            BroopRestHero(rest: snap?.rest, asleepMinutes: snap?.asleepMinutes, needMinutes: snap?.needMinutes)
        case .charge:
            let value = snap?.charge
            VStack(spacing: 14) {
                BroopDial(score: .charge, value: value, maxValue: 100, diameter: 170, lineWidth: 9)
                if let value {
                    BroopCaps(bandWord(value), size: 11, color: BroopPalette.band(value))
                }
                if case .carried(_, let caption)? = snap?.chargeDisplay {
                    BroopCaps(caption, size: 9.5, color: BroopPalette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        case .effort:
            BroopDial(score: .effort, value: snap?.effort, maxValue: snap?.effortMax ?? 21, diameter: 170, lineWidth: 9)
                .frame(maxWidth: .infinity)
        }
    }

    private func bandWord(_ charge: Double) -> String {
        if charge >= 67 { return String(localized: "High") }
        if charge >= 34 { return String(localized: "Medium") }
        return String(localized: "Low")
    }

    // MARK: Insight

    private func insight(_ snap: BroopSnapshot?) -> some View {
        let (title, body) = insightText(snap)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BroopBadge(size: 24)
                BroopCaps(title, size: 11.5)
            }
            Text(verbatim: body)
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if score == .charge, let readiness = snap?.readiness, readiness.level != .insufficient,
               !readiness.signals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(readiness.signals.enumerated()), id: \.offset) { _, signal in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(BroopVitals.flagColor(signal.flag))
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                BroopCaps(signal.label, size: 10, color: BroopPalette.textSecondary)
                                Text(verbatim: signal.detail)
                                    .font(BroopType.regular(13))
                                    .foregroundStyle(BroopPalette.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insightText(_ snap: BroopSnapshot?) -> (String, String) {
        switch score {
        case .charge:
            if let r = snap?.readiness, r.level != .insufficient {
                return (r.headline, r.summary)
            }
            return (String(localized: "Readiness"),
                    snap?.chargeDisplay.calibrationDetail
                        ?? String(localized: "Not enough history yet for a readiness read. Keep wearing the strap overnight."))
        case .rest:
            guard let rest = snap?.rest else {
                return (String(localized: "No Rest score"),
                        String(localized: "No Rest score for this day. Wear the strap overnight and sync to see how restorative your sleep was."))
            }
            if rest >= 85 {
                let body: String
                if let pct = snap?.restorativePct {
                    body = String(localized: "You got the sleep your body asked for. Deep and REM made up \(BroopFormat.whole(pct))% of the night.")
                } else {
                    body = String(localized: "You got the sleep your body asked for.")
                }
                return (String(localized: "Optimal Rest"), body)
            }
            if let asleep = snap?.asleepMinutes, let need = snap?.needMinutes, need > asleep {
                return (String(localized: "Short on Rest"),
                        String(localized: "You slept \(BroopFormat.duration(need - asleep)) less than you needed. Going to bed earlier tonight helps pay it back."))
            }
            return (String(localized: "Short on Rest"),
                    String(localized: "Your sleep was less restorative than usual. A regular bedtime tonight helps."))
        case .effort:
            guard let effort = snap?.effort else {
                return (String(localized: "No Effort yet"),
                        String(localized: "No Effort recorded for this day yet."))
            }
            let text = BroopScore.effort.format(effort)
            let baseline = snap?.effortStats.first(where: { $0.name == String(localized: "Effort") })?.baseline
            guard let baseline else {
                return (String(localized: "Day Effort"),
                        String(localized: "Your day's cardiovascular load is \(text). A 30-day average appears once there is more history."))
            }
            let avg = BroopScore.effort.format(baseline)
            let margin = max(baseline * 0.1, 0.5)
            if effort > baseline + margin {
                return (String(localized: "Above your usual"),
                        String(localized: "Effort of \(text) is above your 30-day average of \(avg). Balance it with a good night's Rest."))
            }
            if effort < baseline - margin {
                return (String(localized: "Below your usual"),
                        String(localized: "Effort of \(text) is below your 30-day average of \(avg)."))
            }
            return (String(localized: "In your usual range"),
                    String(localized: "Effort of \(text) is in line with your 30-day average of \(avg)."))
        }
    }

    // MARK: Score-specific

    @ViewBuilder
    private func extras(_ snap: BroopSnapshot?) -> some View {
        switch score {
        case .rest:
            BroopStagesCard(night: snap?.night).padding(.top, BroopMetrics.section)
        case .effort:
            activities(snap).padding(.top, BroopMetrics.section)
            if let zones = snap?.zoneMinutes, zones.count >= 5, zones.contains(where: { $0 > 0 }) {
                BroopZonesCard(minutes: Array(zones.prefix(5))).padding(.top, BroopMetrics.section)
            }
        case .charge:
            EmptyView()
        }
    }

    private func activities(_ snap: BroopSnapshot?) -> some View {
        let workouts = snap?.workouts ?? []
        let scale = effortScale
        return VStack(spacing: 12) {
            BroopListHeader(title: String(localized: "Activities"))
            if workouts.isEmpty {
                BroopCard {
                    Text("No activities logged.")
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopPalette.textBody)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts, id: \.startTs) { w in
                        Button {
                            router.openWorkouts(.detail(startTs: w.startTs, endTs: w.endTs))
                        } label: {
                            BroopActivityRow(
                                symbol: sportSymbol(w.sport),
                                value: w.strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                                color: BroopPalette.effort,
                                name: WorkoutSource.displaySport(w),
                                start: Date(timeIntervalSince1970: TimeInterval(w.startTs)),
                                end: Date(timeIntervalSince1970: TimeInterval(w.endTs))
                            )
                        }
                        .buttonStyle(BroopPressableStyle())
                    }
                }
            }
        }
    }

    // MARK: Statistics

    @ViewBuilder
    private func statistics(_ snap: BroopSnapshot?) -> some View {
        let items: [BroopReading] = {
            guard let snap else { return [] }
            switch score {
            case .charge: return snap.chargeStats
            case .rest: return snap.restStats
            case .effort: return snap.effortStats
            }
        }()
        if !items.isEmpty {
            VStack(spacing: 12) {
                BroopListHeader(title: String(localized: "\(score.title) statistics"),
                                trailing: String(localized: "vs. previous 30 days"))
                BroopCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { BroopHairline() }
                            BroopStatRow(reading: item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, BroopMetrics.section)
        }
    }

    // MARK: Full details

    private var detailLinks: some View {
        let links: [(symbol: String, title: String, route: TabRoute)] = {
            switch score {
            case .rest:
                return [("moon.zzz", String(localized: "Sleep details"), .sleep)]
            case .charge:
                return [("chart.bar.xaxis", String(localized: "Charge history"), .metric("recovery"))]
            case .effort:
                return [("chart.bar.xaxis", String(localized: "Effort history"), .metric("strain")),
                        ("figure.run", String(localized: "All workouts"), .workouts)]
            }
        }()
        return VStack(spacing: 10) {
            ForEach(links, id: \.title) { link in
                NavigationLink(value: link.route) {
                    BroopNavTile(symbol: link.symbol, title: link.title)
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
    }
}

// MARK: - Rest hero

/// Big percentage with dashed brackets down to "hours of sleep" and "sleep needed".
private struct BroopRestHero: View {
    let rest: Double?
    let asleepMinutes: Double?
    let needMinutes: Double?
    @State private var numberWidth: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: rest.map { BroopFormat.whole($0) } ?? "–").font(BroopType.number(74))
                if rest != nil {
                    Text(verbatim: "%").font(BroopType.number(37))
                }
            }
            .foregroundStyle(rest == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
            .broopNumeral(74, color: rest == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
            .contentTransition(.numericText(value: rest ?? 0))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { numberWidth = $0 }
            .frame(height: 84)
            HStack {
                stat(asleepMinutes, String(localized: "Hours of sleep"), BroopPalette.rest)
                Spacer()
                stat(needMinutes, String(localized: "Sleep needed"), BroopPalette.teal)
            }
            .padding(.top, 40)
        }
        .background {
            GeometryReader { geo in
                let w = geo.size.width
                let edge = numberWidth / 2 + 12
                let column: CGFloat = 65
                let y: CGFloat = 44
                let bottom: CGFloat = 116
                let dash = StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                Path { p in
                    p.move(to: CGPoint(x: w / 2 - edge, y: y))
                    p.addLine(to: CGPoint(x: column, y: y))
                    p.addLine(to: CGPoint(x: column, y: bottom))
                }
                .stroke(BroopPalette.rest, style: dash)
                Path { p in
                    p.move(to: CGPoint(x: w / 2 + edge, y: y))
                    p.addLine(to: CGPoint(x: w - column, y: y))
                    p.addLine(to: CGPoint(x: w - column, y: bottom))
                }
                .stroke(BroopPalette.teal, style: dash)
            }
        }
    }

    private func stat(_ minutes: Double?, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            Text(verbatim: minutes.map { BroopFormat.duration($0) } ?? "–")
                .font(BroopType.number(38))
                .foregroundStyle(color)
                .broopNumeral(38, color: color)
            BroopCaps(label, size: 10, color: color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(color, lineWidth: 1.5))
        }
        .frame(width: 130)
    }
}

// MARK: - Sleep stages

private struct BroopStagesCard: View {
    let night: Night?
    private let order: [SleepStage] = [.awake, .rem, .light, .deep]

    private struct Segment: Identifiable {
        let id: String
        let stage: SleepStage
        let start: Date
        let end: Date
    }

    var body: some View {
        VStack(spacing: 12) {
            if let night {
                let wake = Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
                BroopListHeader(title: String(localized: "Sleep stages"),
                                trailing: "\(BroopFormat.time(night.onsetDate)) – \(BroopFormat.time(wake))")
                BroopCard {
                    VStack(spacing: 18) {
                        chart(night).frame(height: 120)
                        totals(night)
                    }
                }
            } else {
                BroopListHeader(title: String(localized: "Sleep stages"))
                BroopCard {
                    Text("No sleep recorded for this day.")
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopPalette.textBody)
                }
            }
        }
    }

    private func chart(_ night: Night) -> some View {
        let onset = night.onsetDate
        let segments = night.intervals.filter { $0.end > $0.start }.map {
            Segment(id: $0.id, stage: $0.stage,
                    start: onset.addingTimeInterval($0.start), end: onset.addingTimeInterval($0.end))
        }
        return Chart(segments) { s in
            RectangleMark(
                xStart: .value("Start", s.start),
                xEnd: .value("End", s.end),
                yStart: .value("Low", Double(lane(s.stage)) + 0.15),
                yEnd: .value("High", Double(lane(s.stage)) + 0.85)
            )
            .cornerRadius(2)
            .foregroundStyle(color(s.stage))
        }
        .chartYScale(domain: 0...4)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                    .font(BroopType.number(10))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }

    private func totals(_ night: Night) -> some View {
        HStack(spacing: 0) {
            ForEach(order, id: \.self) { stage in
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: BroopFormat.duration(minutes(stage, night)))
                        .font(BroopType.number(17))
                        .foregroundStyle(BroopPalette.textPrimary)
                    HStack(spacing: 5) {
                        Rectangle().fill(color(stage)).frame(width: 8, height: 8)
                        BroopCaps(name(stage), size: 9.5, color: BroopPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Awake on top, deep at the bottom.
    private func lane(_ stage: SleepStage) -> Int {
        switch stage {
        case .awake: return 3
        case .rem: return 2
        case .light: return 1
        case .deep: return 0
        }
    }

    private func minutes(_ stage: SleepStage, _ night: Night) -> Double {
        switch stage {
        case .awake: return night.stages.awake
        case .rem: return night.stages.rem
        case .light: return night.stages.light
        case .deep: return night.stages.deep
        }
    }

    private func name(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: return String(localized: "Awake")
        case .rem: return String(localized: "REM")
        case .light: return String(localized: "Light")
        case .deep: return String(localized: "Deep")
        }
    }

    private func color(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return BroopPalette.stageAwake
        case .rem: return BroopPalette.stageREM
        case .light: return BroopPalette.stageLight
        case .deep: return BroopPalette.stageDeep
        }
    }
}

// MARK: - Heart-rate zones

private struct BroopZonesCard: View {
    /// Minutes in zones 1…5.
    let minutes: [Double]

    var body: some View {
        let peak = max(minutes.max() ?? 1, 1)
        VStack(spacing: 12) {
            BroopListHeader(title: String(localized: "Heart rate zones"), trailing: String(localized: "Time in zone"))
            BroopCard {
                VStack(spacing: 14) {
                    ForEach((0..<5).reversed(), id: \.self) { i in
                        HStack(spacing: 12) {
                            Text(verbatim: "\(i + 1)")
                                .font(BroopType.number(15))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .frame(width: 14)
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(BroopPalette.effort.opacity(0.35 + 0.16 * Double(i)))
                                    .frame(width: max(4, geo.size.width * minutes[i] / peak), height: 12)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 18)
                            Text(verbatim: BroopFormat.duration(minutes[i]))
                                .font(BroopType.number(13))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Trends

private enum BroopTrendRange: String, CaseIterable, Hashable {
    case week = "1W", month = "1M", sixMonths = "6M"
}

/// Bars for the score over 1 week / 1 month (daily) or 6 months (weekly averages), ending on the
/// selected day, with a dashed average and press-to-select.
private struct BroopTrendCard: View {
    @EnvironmentObject private var repo: Repository
    let score: BroopScore
    let dayKey: String
    let maxValue: Double

    @State private var range: BroopTrendRange = .month
    @State private var selection: Date?
    /// Day-keyed history up to and including `dayKey`, ascending. nil while loading.
    @State private var history: [Point]?

    struct Point: Identifiable {
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

    private var seriesKey: String {
        switch score {
        case .charge: return "recovery"
        case .rest: return "sleep_performance"
        case .effort: return "strain"
        }
    }

    private func points(_ history: [Point]) -> [Point] {
        switch range {
        case .week: return Array(history.suffix(7))
        case .month: return Array(history.suffix(30))
        case .sixMonths:
            guard let end = Self.dayFormatter.date(from: dayKey) else { return [] }
            let cal = Calendar.current
            var buckets: [Int: [Double]] = [:]
            for p in history {
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: p.date), to: end).day ?? .max
                guard days >= 0 else { continue }
                let week = days / 7
                guard week < 26 else { continue }
                buckets[week, default: []].append(p.value)
            }
            return buckets.keys.sorted(by: >).compactMap { week in
                guard let vals = buckets[week], !vals.isEmpty,
                      let start = cal.date(byAdding: .day, value: -(week * 7 + 6), to: end) else { return nil }
                return Point(date: start, value: vals.reduce(0, +) / Double(vals.count))
            }
        }
    }

    private var unit: Calendar.Component { range == .sixMonths ? .weekOfYear : .day }

    private var axisTicks: [Double] {
        if score == .effort && maxValue > 21 { return [0, 25, 50, 75, 100] }
        return score.axisTicks
    }

    var body: some View {
        VStack(spacing: 12) {
            BroopListHeader(title: String(localized: "Trends"))
            BroopCard {
                VStack(alignment: .leading, spacing: 18) {
                    BroopUnderlineTabs(options: BroopTrendRange.allCases, selection: $range, size: 10.5) { $0.rawValue }
                    if let history {
                        let pts = points(history)
                        if pts.isEmpty {
                            Text("No history for this score yet.")
                                .font(BroopType.regular(14))
                                .foregroundStyle(BroopPalette.textBody)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        } else {
                            chart(pts)
                        }
                    } else {
                        ProgressView()
                            .tint(BroopPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 170)
                    }
                }
            }
        }
        .task(id: "\(score.rawValue)-\(dayKey)") { await load() }
        .onChange(of: range) { _, _ in selection = nil }
    }

    @ViewBuilder
    private func chart(_ pts: [Point]) -> some View {
        let average = pts.reduce(0) { $0 + $1.value } / Double(max(pts.count, 1))
        let picked = selection.flatMap { sel in
            pts.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: score.format(picked?.value ?? average) + score.unit)
                .font(BroopType.number(24))
                .foregroundStyle(BroopPalette.textPrimary)
                .contentTransition(.numericText())
            BroopCaps(picked.map { label(for: $0.date) } ?? String(localized: "Average"),
                      size: 9.5, color: BroopPalette.textSecondary)
        }
        Chart {
            ForEach(pts) { p in
                BarMark(
                    x: .value("Date", p.date, unit: unit),
                    y: .value(score.title, min(p.value, maxValue)),
                    width: .ratio(0.55)
                )
                .cornerRadius(2)
                .foregroundStyle(score.color(for: p.value).opacity(picked == nil || picked?.id == p.id ? 1 : 0.3))
            }
            RuleMark(y: .value("Average", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(BroopPalette.textSecondary)
        }
        .chartYScale(domain: 0...maxValue)
        .chartXSelection(value: $selection)
        .chartYAxis {
            AxisMarks(position: .trailing, values: axisTicks) { _ in
                AxisGridLine().foregroundStyle(BroopPalette.hairline)
                AxisValueLabel().font(BroopType.number(10)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day())
                    .font(BroopType.number(10))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(height: 170)
        .animation(.snappy, value: range)
    }

    private func label(for date: Date) -> String {
        range == .sixMonths
            ? String(localized: "Week of") + " " + date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func load() async {
        let raw = await repo.exploreSeries(key: seriesKey, source: "my-whoop", days: 200)
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        let key = dayKey
        let pts: [Point] = raw.compactMap { row in
            guard row.day <= key, let date = Self.dayFormatter.date(from: row.day) else { return nil }
            let v = score == .effort ? UnitFormatter.effortValue(row.value, scale: scale) : row.value
            return Point(date: date, value: v)
        }
        guard !Task.isCancelled else { return }
        history = pts
    }
}
#endif
