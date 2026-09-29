#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign

// BroopEnergyView.swift — Energy (`EnergyReservoir`): the Home / Health card, the Energy screen and its
// "How it works" sheet. Every number comes from `Repository.energyDayAnalysis` (days) and `EnergyNow`
// (today's live level), so the card and the screen cannot disagree.
//
// iOS-only fork change; Android twin intentionally not updated.

enum BroopEnergyStyle {
    static func color(_ level: Double) -> Color {
        level >= 67 ? BroopPalette.bandHigh : (level >= 34 ? BroopPalette.bandMid : BroopPalette.bandLow)
    }

    static func word(_ level: Double) -> String {
        level >= 67 ? String(localized: "High") : (level >= 34 ? String(localized: "Medium") : String(localized: "Low"))
    }

    static func signed(_ v: Double, plus: Bool) -> String {
        (plus ? "+" : "−") + String(Int(v.rounded()))
    }

    static let calibrating = String(localized: "Energy is calibrating. It needs about 4 days of heart rate to learn your calm and sleeping references.")
}

/// Today's Energy plus the stress wake reference the live sampler needs. Loaded per `refreshSeq`.
private struct BroopEnergyToday {
    var day: EnergyReservoir.DayResult?
    var wake: StressMonitor.WakeReference?
    var heart = Repository.energyHeart(restingHR: nil)
    var loaded = false

    @MainActor
    static func load(repo: Repository, dayKey: String) async -> BroopEnergyToday {
        let stress = await repo.stressDayAnalysis(dayKey: dayKey)
        let day = await repo.energyDayAnalysis(dayKey: dayKey)
        return BroopEnergyToday(day: day, wake: stress?.wake, heart: repo.energyHeart(dayKey: dayKey), loaded: true)
    }
}

/// The live stress level as a number (nil when not connected, moving or no reference).
private func liveStressLevel(_ reading: StressMonitor.LiveReading?) -> Double? {
    if case .level(let l)? = reading { return l }
    return nil
}

// MARK: - Battery gauge

struct BroopEnergyBattery: View {
    let level: Double?
    var width: CGFloat = 46
    var height: CGFloat = 24

    var body: some View {
        let fraction = CGFloat(min(max((level ?? 0) / 100, 0), 1))
        let color = level.map(BroopEnergyStyle.color) ?? BroopPalette.textTertiary
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.22, style: .continuous)
                    .stroke(BroopPalette.textSecondary, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: height * 0.14, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, (width - 6) * fraction))
                    .padding(3)
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1.5).fill(BroopPalette.textSecondary)
                .frame(width: 3, height: height * 0.4)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Card (Home and Health)

/// The Energy card: battery, level and today's charged / drained. A leaf so live stress stays here.
struct BroopEnergyCard: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var liveStress = BroopHealthStressLive.shared
    @State private var today = BroopEnergyToday()

    var body: some View {
        let now = EnergyNow.resolve(day: today.day, liveStress: liveStressLevel(liveStress.reading), heart: today.heart)
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthCardTitle(title: String(localized: "Energy"),
                                 trailing: now?.live == true ? String(localized: "Live") : nil)
            HStack(alignment: .center, spacing: 14) {
                BroopEnergyBattery(level: now?.level)
                Text(verbatim: now.map { String(Int($0.level.rounded())) } ?? "--")
                    .font(BroopType.number(34))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .contentTransition(.numericText())
                if let now {
                    BroopCaps(BroopEnergyStyle.word(now.level), size: 12, color: BroopEnergyStyle.color(now.level))
                }
                Spacer()
                if let s = today.day?.summary {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(verbatim: String(localized: "\(BroopEnergyStyle.signed(s.charged, plus: true)) charged"))
                            .font(BroopType.demi(13)).foregroundStyle(BroopPalette.teal)
                        Text(verbatim: String(localized: "\(BroopEnergyStyle.signed(s.drained, plus: false)) drained"))
                            .font(BroopType.demi(13)).foregroundStyle(BroopPalette.textBody)
                    }
                }
            }
            if today.loaded && today.day == nil {
                Text(verbatim: BroopEnergyStyle.calibrating)
                    .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        .task(id: repo.refreshSeq) {
            today = await BroopEnergyToday.load(repo: repo, dayKey: Repository.localDayKey(Date()))
        }
        .broopHealthStressLive(reference: today.wake, day: today.day?.day)
    }
}

// MARK: - Screen

struct BroopEnergyView: View {
    @EnvironmentObject private var repo: Repository
    @State private var dayOffset = 0
    @State private var today = BroopEnergyToday()
    @State private var history: [EnergyDaySummary] = []
    @State private var showInfo = false

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: BroopMetrics.section) {
                BroopHealthDateNav(label: dayOffset == 0 ? String(localized: "Today") : date.formatted(date: .abbreviated, time: .omitted),
                                   canGoBack: dayOffset < 180, canGoForward: dayOffset > 0,
                                   onBack: { dayOffset += 1 }, onForward: { dayOffset -= 1 })
                BroopEnergyHeadline(today: today, isToday: dayOffset == 0)
                if let day = today.day {
                    BroopEnergyDayChart(points: day.points)
                    breakdown(day.summary)
                } else {
                    Text(verbatim: today.loaded ? BroopEnergyStyle.calibrating : String(localized: "Reading Energy…"))
                        .font(BroopType.medium(15)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !history.isEmpty { trends }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Energy")) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "How it works")) { showInfo = true }
            }
        }
        .broopHealthScreen()
        .task(id: "\(dayOffset)|\(repo.refreshSeq)") {
            today = BroopEnergyToday()
            let loaded = await BroopEnergyToday.load(repo: repo, dayKey: Repository.localDayKey(date))
            guard !Task.isCancelled else { return }
            today = loaded
            let fresh = dayOffset == 0 ? loaded.day : await repo.energyDayAnalysis(dayKey: Repository.localDayKey(Date()))
            let h = await repo.energyDaySummaries(days: 30, today: fresh)
            guard !Task.isCancelled else { return }
            history = h
        }
        .sheet(isPresented: $showInfo) {
            ScrollView { BroopEnergyInfo().padding(BroopMetrics.page) }
                .broopSheetBar(String(localized: "How Energy works")) { showInfo = false }
        }
    }

    private func breakdown(_ s: EnergyDaySummary) -> some View {
        let drains = [(String(localized: "Stress"), s.drainStress), (String(localized: "Activity"), s.drainActivity),
                      (String(localized: "Being awake"), s.drainBaseline)].sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: BroopMetrics.page) {
            HStack {
                stat(String(localized: "Charged"), BroopEnergyStyle.signed(s.charged, plus: true), BroopPalette.teal)
                Spacer()
                stat(String(localized: "Drained"), BroopEnergyStyle.signed(s.drained, plus: false), BroopPalette.textPrimary)
                Spacer()
                stat(String(localized: "At wake"), s.wake.map { String(Int($0.rounded())) } ?? "--", BroopPalette.textPrimary)
            }
            HStack {
                stat(String(localized: "Peak"), String(Int(s.peak.rounded())), BroopPalette.textPrimary)
                Spacer()
                stat(String(localized: "Low"), String(Int(s.low.rounded())), BroopPalette.textPrimary)
                Spacer()
                stat(String(localized: "Day start"), String(Int(s.start.rounded())), BroopPalette.textPrimary)
            }
            BroopCaps(String(localized: "Top drains"), size: 12, color: BroopPalette.textSecondary)
            ForEach(drains, id: \.0) { name, value in
                HStack {
                    Text(verbatim: name).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textBody)
                    Spacer()
                    Text(verbatim: BroopEnergyStyle.signed(value, plus: false)).font(BroopType.number(18))
                        .foregroundStyle(BroopPalette.textPrimary)
                }
            }
            if s.seeded {
                Text("This day started from a neutral 50 because no earlier day was available to carry from.")
                    .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BroopMetrics.page)
        .background(BroopPalette.card, in: RoundedRectangle(cornerRadius: BroopMetrics.cardRadius))
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(title, size: 11, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(24)).foregroundStyle(color)
        }
    }

    private var trends: some View {
        let last7 = Array(history.suffix(7))
        func mean(_ xs: [Double]) -> String {
            xs.isEmpty ? "--" : String(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))
        }
        return VStack(alignment: .leading, spacing: BroopMetrics.page) {
            BroopCaps(String(localized: "Trends"), size: 13)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text(verbatim: "")
                    BroopCaps(String(localized: "7 days"), size: 11, color: BroopPalette.textSecondary)
                    BroopCaps(String(localized: "30 days"), size: 11, color: BroopPalette.textSecondary)
                }
                GridRow {
                    Text("Average at wake").font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                    Text(verbatim: mean(last7.compactMap(\.wake))).font(BroopType.number(20))
                    Text(verbatim: mean(history.compactMap(\.wake))).font(BroopType.number(20))
                }
                GridRow {
                    Text("Average daily low").font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                    Text(verbatim: mean(last7.map(\.low))).font(BroopType.number(20))
                    Text(verbatim: mean(history.map(\.low))).font(BroopType.number(20))
                }
            }
            .foregroundStyle(BroopPalette.textPrimary)
            Chart {
                ForEach(history, id: \.day) { s in
                    if let w = s.wake {
                        BarMark(x: .value("Day", s.day), yStart: .value("Low", s.low), yEnd: .value("Wake", w), width: .ratio(0.55))
                            .foregroundStyle(BroopEnergyStyle.color(w).opacity(0.75))
                    }
                    PointMark(x: .value("Day", s.day), y: .value("Low", s.low))
                        .symbolSize(10).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .frame(height: 120)
            Text("Bars run from the day's low up to its level at wake, over the last 30 days.")
                .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(BroopMetrics.page)
        .background(BroopPalette.card, in: RoundedRectangle(cornerRadius: BroopMetrics.cardRadius))
    }
}

/// The big level. Only this child observes the live stress reading.
private struct BroopEnergyHeadline: View {
    let today: BroopEnergyToday
    let isToday: Bool
    @ObservedObject private var liveStress = BroopHealthStressLive.shared

    var body: some View {
        let now = isToday
            ? EnergyNow.resolve(day: today.day, liveStress: liveStressLevel(liveStress.reading), heart: today.heart)
            : today.day.map { EnergyNow(level: $0.summary.end, live: false) }
        VStack(spacing: 10) {
            BroopEnergyBattery(level: now?.level, width: 120, height: 56)
            Text(verbatim: now.map { String(Int($0.level.rounded())) } ?? "--")
                .font(BroopType.number(60)).foregroundStyle(BroopPalette.textPrimary)
                .contentTransition(.numericText())
            BroopCaps(now.map { BroopEnergyStyle.word($0.level) } ?? String(localized: "No reading"), size: 13,
                      color: now.map { BroopEnergyStyle.color($0.level) } ?? BroopPalette.textSecondary)
            Text(verbatim: isToday ? (now?.live == true ? String(localized: "Live") : String(localized: "Latest measured"))
                                   : String(localized: "End of day"))
                .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .broopHealthStressLive(reference: isToday ? today.wake : nil, day: isToday ? today.day?.day : nil)
    }
}

/// The day's level with sleep, rest and activity shaded; gaps break the line.
private struct BroopEnergyDayChart: View {
    let points: [EnergyReservoir.Point]

    private struct Run: Identifiable {
        let id: Int
        let kind: EnergyReservoir.Kind
        let start: Int
        let end: Int
    }

    var body: some View {
        let step = EnergyReservoir.epochSeconds
        var runs: [Run] = []
        for p in points where [.sleep, .rest, .activity].contains(p.kind) {
            if let last = runs.last, last.kind == p.kind, last.end == p.ts - step {
                runs[runs.count - 1] = Run(id: last.id, kind: last.kind, start: last.start, end: p.ts)
            } else {
                runs.append(Run(id: runs.count, kind: p.kind, start: p.ts - step, end: p.ts))
            }
        }
        var segment = 0
        var segmented: [(seg: Int, p: EnergyReservoir.Point)] = []
        for p in points {
            if p.kind == .gap { segment += 1; continue }
            segmented.append((segment, p))
        }
        return VStack(alignment: .leading, spacing: BroopMetrics.page) {
            BroopCaps(String(localized: "Day timeline"), size: 13)
            Chart {
                ForEach(runs) { r in
                    RectangleMark(xStart: .value("Start", Date(timeIntervalSince1970: Double(r.start))),
                                  xEnd: .value("End", Date(timeIntervalSince1970: Double(r.end))),
                                  yStart: .value("Low", 0), yEnd: .value("High", 100))
                        .foregroundStyle(shade(r.kind).opacity(0.18))
                }
                ForEach(segmented, id: \.p.ts) { item in
                    LineMark(x: .value("Time", Date(timeIntervalSince1970: Double(item.p.ts))),
                             y: .value("Energy", item.p.level), series: .value("Segment", item.seg))
                        .foregroundStyle(BroopPalette.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
            .frame(height: 180)
            HStack {
                Label("Sleep", systemImage: "bed.double.fill").foregroundStyle(BroopPalette.rest)
                Spacer()
                Label("Rest", systemImage: "leaf.fill").foregroundStyle(BroopPalette.teal)
                Spacer()
                Label("Activity", systemImage: "figure.run").foregroundStyle(BroopPalette.effort)
            }.font(BroopType.regular(12))
        }
    }

    private func shade(_ k: EnergyReservoir.Kind) -> Color {
        switch k {
        case .sleep: return BroopPalette.rest
        case .activity: return BroopPalette.effort
        default: return BroopPalette.teal
        }
    }
}

/// "How it works".
struct BroopEnergyInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            para("Energy is a 0–100 estimate of your reserves. Restful sleep and calm, still rest charge it; being awake, stress and exercise drain it. It carries over from one day to the next instead of resetting at midnight.")
            head("Charging")
            para("During sleep it charges toward 100, faster when it is low. Each 5 minutes counts in full when your sleeping stress is at its typical calm level and not at all when it reaches the high band. Eight calm hours from 40 end near 92. Awake, 10 or more minutes of low stress while still add a small amount.")
            head("Draining")
            para("Being awake costs 2 per hour. Stress costs 6 per hour for each point above the calm level of 1, so an hour at level 2 costs 8 in total. Exercise costs 0.1 per point of Edwards heart-rate load, which is about 12 per hour in zone 2. Stress is not scored during exercise, so nothing is counted twice.")
            head("Gaps and calibration")
            para("When the strap is off the level holds flat; nothing is guessed. Energy stays in calibration until the Stress Monitor has learned your personal calm and sleeping references, which takes about 4 days.")
            head("What it is not")
            para("Garmin's Body Battery comes from Firstbeat, whose model is proprietary and unpublished. This is NOOP's own estimate with its own constants, computed on your phone. It does not change Charge, Rest, Effort, Healthspan or Mind.")
        }
        .foregroundStyle(BroopPalette.textBody)
    }

    private func head(_ s: LocalizedStringKey) -> some View {
        Text(s).font(BroopType.demi(17)).foregroundStyle(BroopPalette.textPrimary)
    }

    private func para(_ s: LocalizedStringKey) -> some View {
        Text(s).font(BroopType.regular(15)).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
