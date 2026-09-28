import Charts
import SwiftUI

/// One template for every score. The tab strip switches score without leaving the screen.
struct ScoreDetailView: View {
    @EnvironmentObject var store: SampleStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ScoreKind
    @State private var showInfo = false

    init(initial: ScoreKind) { _kind = State(initialValue: initial) }

    var body: some View {
        let day = store.selected
        ScrollView {
            VStack(spacing: 0) {
                header
                UnderlineTabs(options: ScoreKind.allCases, selection: $kind) { $0.title }
                    .padding(.top, 22)
                titleRow.padding(.top, 30)
                hero(day).padding(.top, 18)
                insight(day).padding(.top, 34)
                extras(day)
                statistics.padding(.top, Broop.Space.section)
                TrendCard(kind: kind).padding(.top, Broop.Space.section)
            }
            .padding(.horizontal, Broop.Space.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .statusBarScrim()
        .background(BroopBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showInfo) { HowItWorksSheet(kind: kind) }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            DateNavigator()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Broop.Palette.textPrimary)
                        .frame(width: 40, height: 40, alignment: .leading)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private var titleRow: some View {
        ZStack {
            Caps(kind == .effort ? "Day Effort" : "\(kind.title) Performance", size: 11.5)
                .multilineTextAlignment(.center)
            HStack {
                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Broop.Palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Broop.Palette.textSecondary, lineWidth: 1.3))
                }
                .accessibilityLabel("How \(kind.title) works")
            }
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ day: DayMetrics) -> some View {
        switch kind {
        case .rest:
            RestHero(day: day)
        case .charge:
            ScoreDial(kind: .charge, value: day.charge, diameter: 170, lineWidth: 9)
        case .effort:
            ScoreDial(kind: .effort, value: day.effort, diameter: 170, lineWidth: 9, marker: store.readiness.target.lowerBound)
        }
    }

    // MARK: Insight

    private func insight(_ day: DayMetrics) -> some View {
        let (title, body) = insightText(day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandBadge(size: 24)
                Caps(title, size: 11.5)
            }
            Text(body)
                .font(Broop.Typeface.regular(14))
                .foregroundStyle(Broop.Palette.textBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insightText(_ day: DayMetrics) -> (String, String) {
        switch kind {
        case .charge:
            let r = store.readiness
            return (r.title, r.message)
        case .rest:
            let good = day.rest >= 85
            return (
                good ? "Optimal Rest" : "Short on Rest",
                good
                    ? "You got the sleep your body asked for. Deep and REM made up \(Fmt.whole(day.restorativePct))% of the night. Keep the same bedtime tonight."
                    : "You slept \(Fmt.duration(max(day.needMinutes - day.asleepMinutes, 0))) less than you needed. Go to bed earlier tonight to pay it back."
            )
        case .effort:
            let target = store.readiness.target
            let left = target.lowerBound - day.effort
            return left > 0
                ? ("Room to go", "\(Fmt.one(left)) more Effort reaches today's target of \(Int(target.lowerBound))–\(Int(target.upperBound)).")
                : ("Target reached", "You're inside today's target of \(Int(target.lowerBound))–\(Int(target.upperBound)). Anything more is overreaching.")
        }
    }

    // MARK: Score-specific

    @ViewBuilder
    private func extras(_ day: DayMetrics) -> some View {
        switch kind {
        case .rest:
            HypnogramCard(day: day).padding(.top, Broop.Space.section)
        case .effort:
            ActivitiesList(day: day).padding(.top, Broop.Space.section)
            ZonesCard(day: day).padding(.top, Broop.Space.section)
        case .charge:
            EmptyView()
        }
    }

    // MARK: Statistics

    private var statistics: some View {
        let items: [Contributor] = {
            switch kind {
            case .charge: return store.chargeContributors
            case .rest: return store.restContributors
            case .effort: return store.effortContributors
            }
        }()
        return VStack(spacing: 12) {
            ListHeader(title: "\(kind.title) statistics", trailing: "vs. previous 30 days")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline() }
                        StatRow(contributor: item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Rest hero

/// Big percentage with dashed brackets down to "hours of sleep" and "sleep needed".
struct RestHero: View {
    let day: DayMetrics
    @State private var numberWidth: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(Fmt.whole(day.rest)).font(Broop.Typeface.number(74))
                Text("%").font(Broop.Typeface.number(37))
            }
            .foregroundStyle(Broop.Palette.textPrimary)
            .numeral(74)
            .contentTransition(.numericText(value: day.rest))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { numberWidth = $0 }
            .frame(height: 84)
            HStack {
                stat(Fmt.duration(day.asleepMinutes), "Hours of sleep", Broop.Palette.rest)
                Spacer()
                stat(Fmt.duration(day.needMinutes), "Sleep needed", Broop.Palette.teal)
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
                .stroke(Broop.Palette.rest, style: dash)
                Path { p in
                    p.move(to: CGPoint(x: w / 2 + edge, y: y))
                    p.addLine(to: CGPoint(x: w - column, y: y))
                    p.addLine(to: CGPoint(x: w - column, y: bottom))
                }
                .stroke(Broop.Palette.teal, style: dash)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            Text(value).font(Broop.Typeface.number(38)).foregroundStyle(color).numeral(38, color: color)
            Caps(label, size: 10, color: color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(color, lineWidth: 1.5))
        }
        .frame(width: 130)
    }
}

// MARK: - Trend

enum TrendRange: String, CaseIterable, Hashable {
    case week = "1W", month = "1M", sixMonths = "6M"
}

struct TrendCard: View {
    @EnvironmentObject var store: SampleStore
    let kind: ScoreKind
    @State private var range: TrendRange = .month
    @State private var selection: Date?

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var points: [Point] {
        let end = store.selectedIndex
        switch range {
        case .week, .month:
            let n = range == .week ? 7 : 30
            return store.days[max(0, end - n + 1)...end].map { Point(date: $0.date, value: kind.value($0)) }
        case .sixMonths:
            let start = max(0, end - 26 * 7 + 1)
            return stride(from: start, through: end, by: 7).map { s in
                let chunk = store.days[s...min(s + 6, end)]
                let avg = chunk.reduce(0) { $0 + kind.value($1) } / Double(chunk.count)
                return Point(date: chunk.first!.date, value: avg)
            }
        }
    }

    private var unit: Calendar.Component { range == .sixMonths ? .weekOfYear : .day }

    var body: some View {
        let pts = points
        let average = pts.reduce(0) { $0 + $1.value } / Double(max(pts.count, 1))
        let picked = selection.flatMap { sel in pts.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) } }

        VStack(spacing: 12) {
            ListHeader(title: "Trends")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    UnderlineTabs(options: TrendRange.allCases, selection: $range, size: 10.5) { $0.rawValue }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(kind.format(picked?.value ?? average) + kind.unit)
                            .font(Broop.Typeface.number(24))
                            .foregroundStyle(Broop.Palette.textPrimary)
                            .contentTransition(.numericText())
                        Caps(picked.map { label(for: $0.date) } ?? "Average", size: 9.5, color: Broop.Palette.textSecondary)
                    }
                    Chart {
                        ForEach(pts) { p in
                            BarMark(
                                x: .value("Date", p.date, unit: unit),
                                y: .value(kind.title, p.value),
                                width: .ratio(0.55)
                            )
                            .cornerRadius(2)
                            .foregroundStyle(kind.color(for: p.value).opacity(picked == nil || picked?.id == p.id ? 1 : 0.3))
                        }
                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Broop.Palette.textSecondary)
                    }
                    .chartYScale(domain: kind.domain)
                    .chartXSelection(value: $selection)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: kind.axisTicks) { _ in
                            AxisGridLine().foregroundStyle(Broop.Palette.hairline)
                            AxisValueLabel().font(Broop.Typeface.number(10)).foregroundStyle(Broop.Palette.textSecondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(preset: .aligned, values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                            AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day())
                                .font(Broop.Typeface.number(10))
                                .foregroundStyle(Broop.Palette.textSecondary)
                        }
                    }
                    .frame(height: 170)
                    .animation(.snappy, value: range)
                }
            }
        }
    }

    private func label(for date: Date) -> String {
        range == .sixMonths
            ? "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - Rest extras

struct HypnogramCard: View {
    let day: DayMetrics
    private let stages: [SleepSegment.Stage] = [.awake, .rem, .light, .deep]

    var body: some View {
        VStack(spacing: 12) {
            ListHeader(title: "Sleep stages", trailing: "\(Fmt.time(day.bedtime)) – \(Fmt.time(day.wake))")
            Card {
                VStack(spacing: 18) {
                    Chart(day.segments) { s in
                        RectangleMark(
                            xStart: .value("Start", s.start),
                            xEnd: .value("End", s.end),
                            yStart: .value("Low", Double(s.stage.rawValue) + 0.15),
                            yEnd: .value("High", Double(s.stage.rawValue) + 0.85)
                        )
                        .cornerRadius(2)
                        .foregroundStyle(color(s.stage))
                    }
                    .chartYScale(domain: 0...4)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                                .font(Broop.Typeface.number(10))
                                .foregroundStyle(Broop.Palette.textSecondary)
                        }
                    }
                    .frame(height: 120)

                    HStack(spacing: 0) {
                        ForEach(stages, id: \.self) { stage in
                            let minutes = day.minutes(stage)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(Fmt.duration(minutes)).font(Broop.Typeface.number(17)).foregroundStyle(Broop.Palette.textPrimary)
                                HStack(spacing: 5) {
                                    Rectangle().fill(color(stage)).frame(width: 8, height: 8)
                                    Caps(stage.name, size: 9.5, color: Broop.Palette.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func color(_ stage: SleepSegment.Stage) -> Color {
        switch stage {
        case .awake: return Broop.Palette.stageAwake
        case .rem: return Broop.Palette.stageREM
        case .light: return Broop.Palette.stageLight
        case .deep: return Broop.Palette.stageDeep
        }
    }
}

// MARK: - Effort extras

struct ActivitiesList: View {
    let day: DayMetrics

    var body: some View {
        VStack(spacing: 12) {
            ListHeader(title: "Activities")
            if day.activities.isEmpty {
                Card {
                    Text("No activities logged.")
                        .font(Broop.Typeface.regular(14))
                        .foregroundStyle(Broop.Palette.textBody)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(day.activities) { ActivityTile(activity: $0) }
                }
            }
        }
    }
}

struct ZonesCard: View {
    let day: DayMetrics
    private let bounds = ["50–60%", "60–70%", "70–80%", "80–90%", "90–100%"]

    var body: some View {
        let peak = max(day.zoneMinutes.max() ?? 1, 1)
        VStack(spacing: 12) {
            ListHeader(title: "Heart rate zones", trailing: "% of max HR")
            Card {
                VStack(spacing: 14) {
                    ForEach((0..<5).reversed(), id: \.self) { i in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(Broop.Typeface.number(15))
                                .foregroundStyle(Broop.Palette.textPrimary)
                                .frame(width: 14)
                            Text(bounds[i])
                                .font(Broop.Typeface.number(12))
                                .foregroundStyle(Broop.Palette.textSecondary)
                                .frame(width: 56, alignment: .leading)
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Broop.Palette.effort.opacity(0.35 + 0.16 * Double(i)))
                                    .frame(width: max(4, geo.size.width * day.zoneMinutes[i] / peak), height: 12)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 18)
                            Text(Fmt.duration(day.zoneMinutes[i]))
                                .font(Broop.Typeface.number(13))
                                .foregroundStyle(Broop.Palette.textPrimary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Explainer

struct HowItWorksSheet: View {
    let kind: ScoreKind

    private var text: String {
        switch kind {
        case .charge:
            return "Charge is how ready your body is to take on strain today. It weighs last night's HRV, resting heart rate and Rest against your own 30-day range. 67% and up is high, 34–66% medium, below 34% low."
        case .rest:
            return "Rest compares how long you slept with how much sleep you needed. Your need grows with yesterday's Effort and any sleep debt you carry."
        case .effort:
            return "Effort is the cardiovascular load of your whole day on a 0–21 scale. It grows fast at first and slows near the top, so each extra point costs more. Your target comes from today's Charge."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Caps("How \(kind.title) works", size: 12)
            Text(text)
                .font(Broop.Typeface.regular(14))
                .foregroundStyle(Broop.Palette.textBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Broop.Palette.card.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
