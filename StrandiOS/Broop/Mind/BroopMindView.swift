#if os(iOS)
import Charts
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Labels

/// Names, colours and copy for the Mind levels, shared by the screen and the Health-tab card.
enum BroopMindCopy {
    static func name(_ level: ResilienceEngine.Level) -> String {
        switch level {
        case .limited: return String(localized: "Limited")
        case .adequate: return String(localized: "Adequate")
        case .solid: return String(localized: "Solid")
        case .strong: return String(localized: "Strong")
        case .exceptional: return String(localized: "Exceptional")
        }
    }

    static func name(_ level: CumulativeStressEngine.Level) -> String {
        switch level {
        case .low: return String(localized: "Low")
        case .moderate: return String(localized: "Moderate")
        case .elevated: return String(localized: "Elevated")
        case .high: return String(localized: "High")
        }
    }

    /// Resilience runs from amber (limited) to mint (exceptional); neutral, never red.
    static func color(_ level: ResilienceEngine.Level) -> Color {
        switch level {
        case .limited: return BroopHealthPalette.amber
        case .adequate: return BroopHealthPalette.stressHigh.opacity(0.8)
        case .solid: return BroopHealthPalette.stressLow
        case .strong: return BroopHealthPalette.stressMedium
        case .exceptional: return BroopHealthPalette.mint
        }
    }

    static func color(_ level: CumulativeStressEngine.Level) -> Color {
        switch level {
        case .low: return BroopHealthPalette.stressLow
        case .moderate: return BroopHealthPalette.stressMedium
        case .elevated, .high: return BroopHealthPalette.amber
        }
    }

    static func trendLine(_ trend: MindTrend?, resilience: Bool) -> String? {
        switch trend {
        case .improving?: return resilience ? String(localized: "Building over the last week") : String(localized: "Easing over the last week")
        case .worsening?: return resilience ? String(localized: "Slipping over the last week") : String(localized: "Building over the last week")
        case .steady?: return String(localized: "Steady over the last week")
        case nil: return nil
        }
    }

    static func cumulativeDescription(_ level: CumulativeStressEngine.Level) -> String {
        switch level {
        case .low:
            return String(localized: "The available stress signals produce a low rolling load. This describes recorded physiological signals, not how the month felt.")
        case .moderate:
            return String(localized: "The available stress signals produce a moderate rolling load. Compare the trend with your own previous weeks.")
        case .elevated:
            return String(localized: "The available stress signals produce an elevated rolling load. The component values below show which recorded signals contributed.")
        case .high:
            return String(localized: "The available stress signals produce a high rolling load. Physiological stress can reflect many causes; the score cannot identify them.")
        }
    }

    /// The summary card: one sentence pair from the two levels together.
    static func summary(resilience: ResilienceEngine.Result?, cumulative: CumulativeStressEngine.Result?) -> (String, String)? {
        guard let r = resilience else { return nil }
        let heavy = (cumulative?.level ?? .low) >= .elevated
        switch (r.level >= .solid, heavy) {
        case (true, false):
            return (String(localized: "Well Balanced"),
                    String(localized: "Your recorded recovery and low-stress time balance the recent stress load in this estimate."))
        case (true, true):
            return (String(localized: "Holding Up Under Load"),
                    String(localized: "The 14-day balance is solid or higher, while the 31-day load is elevated. The two windows describe different periods."))
        case (false, true):
            return (String(localized: "Running Low"),
                    String(localized: "The recent balance is below Solid and the monthly load is elevated. Check the recorded components and compare them with how you feel."))
        case (false, false):
            return (String(localized: "Room to Recover"),
                    String(localized: "The recent balance is below Solid. The components below show the stress and recovery data available for this period."))
        }
    }
}

// MARK: - Screen

/// Broop Mind: Resilience (14 days), Cumulative Stress (31 days), the optional monthly check-in and the
/// daily mood, laid out like WHOOP's Healthspan screen. Every number comes from `BroopMindData`.
struct BroopMindView: View {
    @EnvironmentObject private var repo: Repository
    @State private var data = BroopMindData()
    @State private var showInfo = false
    @State private var showCheckIn = false
    @State private var reload = 0
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showInfo {
                    BroopHealthInfoBanner(symbol: "lightbulb", text: String(localized: "Mind is built on-device from your stress data. Resilience balances the last 14 days of daytime stress against calm waking time and overnight recovery (Rest and Charge). Cumulative Stress averages a month of stress load by day and by night. Neither is a mental-health assessment."))
                        .padding(.top, 12)
                        .transition(.opacity)
                }
                hero.padding(.top, 8)
                if let summary = BroopMindCopy.summary(resilience: data.resilience, cumulative: data.cumulative) {
                    summaryCard(summary).padding(.top, 22)
                }
                resilienceSection.padding(.top, BroopMetrics.section)
                cumulativeSection.padding(.top, BroopMetrics.section)
                checkInSection.padding(.top, BroopMetrics.section)
                moodSection.padding(.top, BroopMetrics.section)
                methodSection.padding(.top, BroopMetrics.section)
                BroopHealthFootnote(text: String(localized: "Mind shows estimates from recorded stress, sleep and recovery. It is not a medical device and cannot diagnose anxiety, depression or any other condition."))
                    .padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Mind"), subtitle: String(localized: "Last 14 days"), fill: BroopPalette.bgBottom) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "About Mind")) {
                    withAnimation(.snappy) { showInfo.toggle() }
                }
            }
        }
        .background(BroopBackground())
        .broopBarChrome()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCheckIn, onDismiss: { reload += 1 }) {
            BroopMindCheckInSheet()
        }
        .confirmationDialog("Delete last check-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete check-in", role: .destructive) {
                guard let last = data.latestCheckIn else { return }
                deleting = true
                Task {
                    defer { deleting = false }
                    do { try await repo.deleteMindCheckIn(day: last.day); reload += 1 }
                    catch { deleteFailed = true }
                }
            }
        }
        .alert("Check-in was not deleted", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) { }
        } message: { Text("Please try again.") }
        .task(id: "\(repo.refreshSeq)|\(repo.mindCheckInRevision)|\(reload)") { data = await BroopMindData.load(repo: repo) }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                BroopMindLevelRing(level: data.resilience?.level)
                    .frame(width: 260, height: 260)
                VStack(spacing: 8) {
                    if let r = data.resilience {
                        Text(verbatim: BroopMindCopy.name(r.level))
                            .font(BroopType.demi(38))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        BroopCaps(String(localized: "Resilience"), size: 15, color: BroopPalette.textSecondary)
                        if let line = BroopMindCopy.trendLine(r.trend, resilience: true) {
                            Text(verbatim: line)
                                .font(BroopType.demi(15))
                                .foregroundStyle(BroopMindCopy.color(r.level))
                        }
                    } else {
                        Text(verbatim: "--").font(BroopType.number(56)).foregroundStyle(BroopPalette.textPrimary)
                        BroopCaps(String(localized: "Resilience"), size: 15, color: BroopPalette.textSecondary)
                        Text(data.loaded
                             ? "Calibrating · \(data.resilienceStressDays) of \(ResilienceEngine.minStressDays) days"
                             : "Loading")
                            .font(BroopType.demi(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryCard(_ s: (String, String)) -> some View {
        BroopHealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: s.0).font(BroopType.demi(18)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: s.1).font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Resilience

    private var resilienceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Resilience"), trailing: String(localized: "14 days"))
            if let r = data.resilience {
                BroopHealthCard(padding: 0) {
                    VStack(spacing: 0) {
                        componentRow(symbol: "bolt.heart", title: String(localized: "Daytime stress"),
                                     value: percent(r.highShare), detail: String(localized: "of scored waking time in high stress"),
                                     score: r.loadComponent)
                        BroopHairline().padding(.leading, 60)
                        componentRow(symbol: "leaf", title: String(localized: "Daytime recovery"),
                                     value: percent(r.lowShare), detail: String(localized: "of scored waking time calm"),
                                     score: r.daytimeRecoveryComponent)
                        BroopHairline().padding(.leading, 60)
                        componentRow(symbol: "moon.zzz", title: String(localized: "Overnight recovery"),
                                     value: r.nightRecovery.map(percent) ?? "--",
                                     detail: r.nightRecovery == nil ? String(localized: "needs a few scored nights")
                                                                   : String(localized: "average of Rest and Charge"),
                                     score: r.nightComponent)
                    }
                }
                if data.resilienceHistory.count >= 2 {
                    BroopHealthCard {
                        VStack(alignment: .leading, spacing: 12) {
                            BroopCaps(String(localized: "Last 90 days"), size: 11, color: BroopPalette.textSecondary)
                            BroopMindHistoryChart(points: data.resilienceHistory, domain: 0...100,
                                                  bands: ResilienceEngine.levelFloors.map { $0.1 },
                                                  color: BroopMindCopy.color(r.level))
                                .frame(height: 150)
                        }
                    }
                }
            } else {
                BroopHealthCard {
                    BroopHealthEmpty(symbol: "brain.head.profile", title: String(localized: "Calibrating"),
                                     message: String(localized: "Resilience needs 7 days of daytime stress data in the last 14. Keep wearing your strap during the day."))
                }
            }
        }
    }

    private func componentRow(symbol: String, title: String, value: String, detail: String, score: Double?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(title, size: 11.5)
                Text(verbatim: detail).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(verbatim: value).font(BroopType.number(22)).foregroundStyle(BroopPalette.textPrimary)
                BroopMindMiniBar(fraction: score)
                    .frame(width: 64, height: 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Cumulative stress

    private var cumulativeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Cumulative Stress"), trailing: String(localized: "31 days"))
            BroopHealthCard {
                VStack(alignment: .leading, spacing: 14) {
                    if let c = data.cumulative {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: BroopMindCopy.name(c.level))
                                .font(BroopType.demi(28))
                                .foregroundStyle(BroopMindCopy.color(c.level))
                            Spacer()
                            Text(verbatim: BroopFormat.whole(c.score))
                                .font(BroopType.number(24))
                                .foregroundStyle(BroopPalette.textPrimary)
                            Text("/ 100").font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                        }
                        BroopMindRuler(value: c.score, labels: CumulativeStressEngine.Level.allCases.map(BroopMindCopy.name))
                            .frame(height: 52)
                        if let line = BroopMindCopy.trendLine(c.trend, resilience: false) {
                            BroopCaps(line, size: 10.5, color: BroopPalette.textSecondary)
                        }
                        Text(verbatim: BroopMindCopy.cumulativeDescription(c.level))
                            .font(BroopType.regular(15))
                            .foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                        loadBreakdown(c)
                        if data.cumulativeHistory.count >= 2 {
                            BroopMindHistoryChart(points: data.cumulativeHistory, domain: 0...100,
                                                  bands: CumulativeStressEngine.levelFloors.map { $0.1 },
                                                  color: BroopMindCopy.color(c.level))
                                .frame(height: 140)
                                .padding(.top, 4)
                        }
                    } else {
                        BroopHealthEmpty(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "Calibrating"),
                                         message: String(localized: "Cumulative Stress needs 21 days of stress data in the last 31. \(data.cumulativeStressDays) so far."))
                    }
                }
            }
        }
    }

    private func loadBreakdown(_ c: CumulativeStressEngine.Result) -> some View {
        HStack(spacing: 0) {
            loadCell(String(localized: "Day"), c.daytimeLoad)
            loadCell(String(localized: "Sleep"), c.sleepLoad)
            loadCell(String(localized: "Charge"), c.recoveryLoad)
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.innerRadius).fill(BroopHealthPalette.innerPanel))
    }

    private func loadCell(_ title: String, _ load: Double?) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: load.map { BroopFormat.whole($0 * 100) } ?? "--")
                .font(BroopType.number(20)).foregroundStyle(BroopPalette.textPrimary)
            BroopCaps(title + " " + String(localized: "load"), size: 9.5, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Check-in

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Monthly Check-in"), trailing: String(localized: "Optional"))
            BroopHealthCard {
                VStack(alignment: .leading, spacing: 14) {
                    if let last = data.latestCheckIn {
                        HStack(spacing: 0) {
                            checkInCell("PSS-4", String(localized: "Stress"), last.pss4, MindCheckIn.Form.pss4.maxScore)
                            checkInCell("GAD-2", String(localized: "Worry"), last.gad2, MindCheckIn.Form.gad2.maxScore)
                            checkInCell("PHQ-2", String(localized: "Mood"), last.phq2, MindCheckIn.Form.phq2.maxScore)
                        }
                        BroopCaps(String(localized: "Last check-in") + " · " + BroopHealthFormat.shortDay(last.day),
                                  size: 10, color: BroopPalette.textSecondary)
                        if atOrAboveCutoff(last) {
                            BroopHealthInfoBanner(symbol: "person.2", text: String(localized: "Some of your answers were in the range where talking things through with a doctor or counsellor can help. That's a common step, and this check-in can't tell you more than that."))
                        }
                        if data.checkIns.count >= 2 { BroopMindCheckInChart(checkIns: data.checkIns).frame(height: 120) }
                        linksBlock
                    } else {
                        Text("Once a month, answer eight short questions about stress, worry and mood. Broop stores the scores locally and, after a few months, shows how they move with your Charge and HRV.")
                            .font(BroopType.regular(15))
                            .foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    BroopHealthButton(title: data.checkInDue ? String(localized: "Start check-in") : String(localized: "Check in again"),
                                      symbol: "checklist", kind: data.checkInDue ? .primary : .secondary) {
                        showCheckIn = true
                    }
                }
            }
            if data.latestCheckIn != nil {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    BroopCaps(String(localized: "Delete last check-in"), size: 10, color: BroopPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(deleting)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func atOrAboveCutoff(_ c: BroopMindData.CheckIn) -> Bool {
        (c.gad2.map { MindCheckIn.atOrAboveCutoff(.gad2, score: $0) } ?? false)
            || (c.phq2.map { MindCheckIn.atOrAboveCutoff(.phq2, score: $0) } ?? false)
    }

    private func checkInCell(_ form: String, _ title: String, _ score: Int?, _ max: Int) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: score.map(String.init) ?? "--").font(BroopType.number(26)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: "/\(max)").font(BroopType.medium(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            BroopCaps(title, size: 10.5)
            Text(verbatim: form).font(BroopType.regular(11)).foregroundStyle(BroopPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var linksBlock: some View {
        let clear = data.links.filter { abs($0.r) >= MindCheckIn.minAbsR }
        if data.checkIns.count < MindCheckIn.minPairs {
            BroopFootnote(text: String(localized: "After \(MindCheckIn.minPairs) check-ins, Broop looks for links with your Charge and HRV. \(data.checkIns.count) of \(MindCheckIn.minPairs) so far."))
        } else if clear.isEmpty {
            BroopFootnote(text: String(localized: "No clear link yet between your answers and your Charge or HRV."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(clear.prefix(3))) { link in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: link.r < 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BroopHealthPalette.infoText)
                        Text(verbatim: linkSentence(link))
                            .font(BroopType.regular(14))
                            .foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func linkSentence(_ l: BroopMindData.Link) -> String {
        let topic: String
        switch l.form {
        case .pss4: topic = String(localized: "perceived stress")
        case .gad2: topic = String(localized: "worry")
        case .phq2: topic = String(localized: "low mood")
        }
        let r = String(format: "%.2f", l.r)
        return l.r < 0
            ? String(localized: "Months with higher \(l.signal) came with lower \(topic) scores (r \(r), \(l.n) check-ins).")
            : String(localized: "Months with higher \(l.signal) came with higher \(topic) scores (r \(r), \(l.n) check-ins).")
    }

    // MARK: Mood and method

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Daily Mood"))
            NavigationLink { BroopFinalAMoodPage() } label: {
                BroopHealthRow(symbol: "face.smiling", title: String(localized: "Mood check-in"),
                               detail: String(localized: "One tap a day, alongside your body's signals"))
            }
            .buttonStyle(BroopPressableStyle())
            NavigationLink(value: BroopScreen.stress) {
                BroopHealthRow(symbol: "gauge.with.dots.needle.50percent", title: String(localized: "Stress Monitor"),
                               detail: String(localized: "Today's stress, live and by the hour"))
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "How Mind Works"))
            BroopHealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    methodItem(String(localized: "Resilience"), String(localized: "The last 14 days of scored waking time in high stress, set against calm waking time and your average Rest and Charge. Five levels, from Limited to Exceptional. It needs 7 days with at least two scored waking hours."))
                    methodItem(String(localized: "Cumulative Stress"), String(localized: "A 31-day average of daily stress load: waking time in high stress (half the weight), stress during sleep and a low Charge (a quarter each). It needs 21 days of data and moves slowly on purpose."))
                    methodItem(String(localized: "Check-in"), String(localized: "PSS-4 (perceived stress, last month), GAD-2 and PHQ-2 (worry and mood, last two weeks) are short, widely used questionnaires. Scores are compared only with your own Charge and HRV. A higher score is not a diagnosis."))
                    methodItem(String(localized: "About these estimates"), String(localized: "Broop uses its own weights and thresholds, inspired by published descriptions of Oura’s rolling windows. These scores have not been clinically validated and are not Oura scores. Missing inputs are omitted and remaining weights are renormalised."))
                    methodItem(String(localized: "Why no mental age"), String(localized: "No wearable can measure a brain or mental age from heart data. Broop shows rolling estimates from the recorded stress and recovery signals."))
                }
            }
        }
    }

    private func methodItem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(title, size: 11)
            Text(verbatim: text).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}

// MARK: - Pieces

/// Five arc segments, one per Resilience level, filled up to the current level.
struct BroopMindLevelRing: View {
    let level: ResilienceEngine.Level?

    var body: some View {
        GeometryReader { geo in
            let count = ResilienceEngine.Level.allCases.count
            let gap = 0.018
            let span = (0.8 - gap * Double(count - 1)) / Double(count)
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let start = 0.1 + Double(i) * (span + gap)
                    let active = level.map { i <= $0.rawValue } ?? false
                    Circle()
                        .trim(from: start, to: start + span)
                        .stroke(active ? BroopMindCopy.color(level ?? .limited) : BroopPalette.track,
                                style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                        .rotationEffect(.degrees(90))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// Thin progress bar for a 0–1 component score (nil = empty track).
struct BroopMindMiniBar: View {
    let fraction: Double?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track)
                Capsule().fill(BroopHealthPalette.stressLow)
                    .frame(width: geo.size.width * min(max(fraction ?? 0, 0), 1))
            }
        }
    }
}

/// A Pace-of-Aging-style tick ruler over 0–100 with the value's tick highlighted and level labels below.
struct BroopMindRuler: View {
    let value: Double
    let labels: [String]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let ticks = 50
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach(0...ticks, id: \.self) { i in
                        Rectangle()
                            .fill(BroopPalette.textTertiary)
                            .frame(width: 1.5, height: i % 10 == 0 ? 22 : 16)
                            .position(x: w * Double(i) / Double(ticks), y: geo.size.height / 2)
                    }
                    Capsule()
                        .fill(BroopPalette.textPrimary)
                        .frame(width: 3, height: 30)
                        .position(x: w * min(max(value, 0), 100) / 100, y: geo.size.height / 2)
                }
            }
            .frame(height: 30)
            GeometryReader { geo in
                let centers = [0.10, 0.30, 0.50, 0.80]
                ForEach(Array(labels.enumerated()), id: \.element) { i, label in
                    Text(verbatim: label).font(BroopType.medium(11)).foregroundStyle(BroopPalette.textSecondary)
                        .position(x: geo.size.width * centers[i], y: geo.size.height / 2)
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(Int(value.rounded())) of 100"))
    }
}

/// A light line chart of a rolling Mind score with dashed level floors.
struct BroopMindHistoryChart: View {
    let points: [(day: String, score: Double)]
    let domain: ClosedRange<Double>
    let bands: [Double]
    let color: Color

    private var dated: [(Date, Double)] {
        points.compactMap { p in BroopHealthFormat.dayParser.date(from: p.day).map { ($0, p.score) } }
    }

    var body: some View {
        Chart {
            ForEach(bands, id: \.self) { b in
                RuleMark(y: .value("Level", b))
                    .foregroundStyle(BroopHealthPalette.grid)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(dated, id: \.0) { p in
                LineMark(x: .value("Day", p.0, unit: .day), y: .value("Score", p.1))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                AxisValueLabel { Text(verbatim: "\(v.as(Int.self) ?? 0)").font(BroopType.medium(10)).foregroundStyle(BroopPalette.textSecondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { v in
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(BroopType.medium(10)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }
}

/// Check-in totals over time, each as a share of its form's maximum so the three share one axis.
struct BroopMindCheckInChart: View {
    let checkIns: [BroopMindData.CheckIn]

    private struct Mark: Identifiable {
        let date: Date; let form: String; let share: Double
        var id: String { "\(form)\(date.timeIntervalSince1970)" }
    }

    private var marks: [Mark] {
        checkIns.flatMap { c -> [Mark] in
            guard let date = BroopHealthFormat.dayParser.date(from: c.day) else { return [] }
            return [("PSS-4", c.pss4, 16.0), ("GAD-2", c.gad2, 6.0), ("PHQ-2", c.phq2, 6.0)].compactMap { name, v, max in
                v.map { Mark(date: date, form: name, share: Double($0) / max) }
            }
        }
    }

    var body: some View {
        Chart(marks) { m in
            LineMark(x: .value("Day", m.date, unit: .day), y: .value("Share", m.share), series: .value("Form", m.form))
                .foregroundStyle(by: .value("Form", m.form))
            PointMark(x: .value("Day", m.date, unit: .day), y: .value("Share", m.share))
                .foregroundStyle(by: .value("Form", m.form))
                .symbolSize(24)
        }
        .chartForegroundStyleScale(["PSS-4": BroopHealthPalette.stressLow, "GAD-2": BroopHealthPalette.stressMedium,
                                    "PHQ-2": BroopHealthPalette.amber])
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, spacing: 8)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(BroopType.medium(10)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }
}
#endif
