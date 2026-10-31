#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - Data

/// The Healthspan figures (Broop Age, Pace of Aging, the nine age impacts, the weekly trend) from
/// `Repository.healthspanSnapshot`, the one resolver the weekly store pass and the macOS Health section
/// also use, plus the Fitness Age / VO₂max pair read as the `FitnessAgeSection` reads it.
struct BroopHealthspanData {
    var snap = HealthspanSnapshot.empty
    var fitnessAge: Double?
    var vo2max: Double?
    var vo2Estimator: Vo2MaxEstimator?
    var loaded = false

    var bodyAge: Double? { snap.bodyAge }
    var pace: Double? { snap.pace }

    @MainActor
    static func load(repo: Repository, profile: ProfileStore) async -> BroopHealthspanData {
        var d = BroopHealthspanData()
        d.snap = await repo.healthspanSnapshot(profileAge: profile.age, sex: profile.sex)
        d.fitnessAge = (await repo.exploreSeries(key: "fitness_age", source: "my-whoop")).last?.value
        let vo2 = await repo.resolvedSeries(key: "vo2max_est", source: "my-whoop")
        if let latest = vo2.points.last {
            d.vo2max = latest.value
            let tag = await repo.scoreProvenanceTag(resolvedSource: latest.source, day: latest.day,
                                                    metricKey: "vo2max_est")
            d.vo2Estimator = tag.flatMap { Vo2MaxEstimator(rawValue: $0) }
        }
        d.loaded = true
        return d
    }

    /// Positive = younger than the calendar age (the sign the Health-tab card colours by).
    func bodyAgeDelta(age: Int) -> Double? { snap.delta.map { -$0 } }

    static func yearsLine(_ delta: Double) -> String {
        let yrs = abs(delta)
        if yrs < 0.05 { return String(localized: "About your age") }
        let n = BroopFormat.one(yrs)
        return delta > 0 ? String(localized: "\(n) years younger") : String(localized: "\(n) years older")
    }

    static func paceBandLabel(_ pace: Double) -> String {
        switch VitalityEngine.paceBand(pace) {
        case .reversing: return String(localized: "Reversing")
        case .slowing: return String(localized: "Slowing")
        case .steady: return String(localized: "Steady")
        case .accelerated: return String(localized: "Accelerating")
        }
    }

    /// Days until the next Sunday update (1…7).
    @MainActor var daysToNextUpdate: Int? {
        guard let u = VitalityEngine.epochDay(snap.updateDay),
              let t = VitalityEngine.epochDay(Repository.dayString(Date())) else { return nil }
        return max(1, u + 7 - t)
    }
}

/// Segment and marker colours of the Healthspan contributor bars (WHOOP's orange → brown → teal → mint
/// scale, grey for "no effect").
private enum BroopHealthspanPalette {
    static let bad = BroopPalette.warning
    static let badDim = BroopPalette.warning.opacity(0.55)
    static let neutral = BroopPalette.textSecondary
    static let goodDim = BroopPalette.teal.opacity(0.45)
    static let good = BroopPalette.teal
    static let delta = BroopPalette.stageREM
    static let chrono = BroopPalette.stageAwake

    /// Colour for an age impact in years (negative = younger = good).
    static func forYears(_ y: Double) -> Color {
        if y <= -0.5 { return good }
        if y < -0.05 { return goodDim }
        if y <= 0.05 { return neutral }
        if y < 0.5 { return badDim }
        return bad
    }

    static func text(_ y: Double) -> Color {
        abs(y) < 0.05 ? BroopPalette.textPrimary : (y < 0 ? good : bad)
    }
}

// MARK: - Screen

/// Broop Healthspan, laid out like WHOOP's Healthspan: Broop Age hero against the calendar age, Pace of
/// Aging ruler with its tooltip, the nine contributors grouped Sleep / Strain / Fitness (6-month value,
/// 30-day marker, recommendation colours and age impact, each linking to its trend), the Broop Age trend,
/// then Fitness Age / VO₂max.
struct BroopHealthspanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @State private var data = BroopHealthspanData()
    @State private var showInfo = false
    @State private var showReadiness = false
    @State private var refreshing = false
    @State private var calibrationDismissed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let day = data.snap.shownDay {
                    BroopCaps(Self.weekLabel(day), size: 12, color: BroopPalette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, BroopMetrics.gap / 2)
                }
                hero.padding(.top, BroopMetrics.page)
                if showInfo {
                    BroopHealthInfoBanner(symbol: "lightbulb",
                                          text: String(localized: "Broop Age estimates age impacts from nine habits and fitness markers over six months using published research. WHOOP does not publish its fitted curves or overlap weights, so this independent approximation will differ from WHOOP Age. Pace of Aging projects your last 30 days six months ahead. Updates on Sunday with 21 recoveries in 31 days. A wellness estimate, not a clinical biological age."))
                        .padding(.top, BroopMetrics.page)
                        .transition(.opacity)
                }
                if calibrating && !calibrationDismissed {
                    calibrationBanner.padding(.top, BroopMetrics.page)
                }
                if data.snap.bodyAge != nil {
                    paceSection.padding(.top, BroopMetrics.section)
                    insightCard.padding(.top, BroopMetrics.section)
                }
                if let r = data.snap.result {
                    ForEach(VitalityEngine.Pillar.allCases, id: \.self) { pillar in
                        pillarSection(pillar, r).padding(.top, BroopMetrics.section).id(pillar.rawValue)
                    }
                } else if data.snap.isStale {
                    BroopHealthInfoBanner(text: String(localized: "Not updated this week. Broop Age needs 21 recoveries in the last 31 days (\(data.snap.recoveriesLast31) so far)."))
                        .padding(.top, BroopMetrics.section)
                }
                if data.snap.trend.count >= 2 {
                    trendSection.padding(.top, BroopMetrics.section).id("trend")
                }
                fitnessSection.padding(.top, BroopMetrics.section).id("fitnessAge")
                BroopHealthFootnote(text: String(localized: "A wellness estimate from your habits, not a clinical biological age."))
                    .padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Healthspan"),
                              subtitle: data.daysToNextUpdate.map { n in
                                  n == 1 ? String(localized: "Next update in 1 day")
                                         : String(localized: "Next update in \(n) days") }
                                  ?? String(localized: "Updated weekly"),
                              fill: BroopPalette.bgBottom) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "About Healthspan")) {
                    withAnimation(.snappy) { showInfo.toggle() }
                }
            }
        }
        .background(
            LinearGradient(stops: [.init(color: BroopPalette.bgBottom, location: 0), .init(color: BroopPalette.bgBottom, location: 0.35),
                                   .init(color: BroopPalette.bgBottom, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .broopBarChrome()
        .preferredColorScheme(.dark)
        .task(id: repo.refreshSeq) { data = await BroopHealthspanData.load(repo: repo, profile: profile) }
    }

    /// "SEP 21 - SEP 27": the week ending on the update Sunday… WHOOP labels the week the value covers; the
    /// value here is as of that Sunday, so the label is the seven days ending on it.
    static func weekLabel(_ sunday: String) -> String {
        guard let e = VitalityEngine.epochDay(sunday) else { return sunday }
        let f = DateFormatter()
        f.locale = Locale.current; f.timeZone = TimeZone(identifier: "UTC"); f.setLocalizedDateFormatFromTemplate("MMM d")
        func d(_ x: Int) -> String { f.string(from: Date(timeIntervalSince1970: TimeInterval(x) * 86_400)).uppercased() }
        return "\(d(e - 6)) - \(d(e))"
    }

    private var calibrating: Bool {
        guard let r = data.snap.result else { return false }
        return r.coveredDays < 90
    }

    private var hue: Color {
        guard let delta = data.snap.delta else { return BroopPalette.textSecondary }
        if delta <= -1 { return BroopHealthspanPalette.good }
        if delta < 1 { return BroopHealthPalette.chartBlue }
        return BroopHealthPalette.amber
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                BroopHealthspanRing(color: hue)
                    .frame(width: 270, height: 270)
                VStack(spacing: BroopMetrics.gap / 2) {
                    Text(verbatim: data.snap.bodyAge.map(BroopFormat.one) ?? "--")
                        .font(BroopType.number(68))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .broopNumeral(68)
                    BroopCaps(String(localized: "Broop Age"), size: 15, color: BroopPalette.textSecondary)
                    if let delta = data.snap.delta {
                        Text(verbatim: BroopHealthspanData.yearsLine(-delta))
                            .font(BroopType.demi(19))
                            .foregroundStyle(BroopHealthspanPalette.delta)
                        Text("Calendar age \(BroopFormat.one(data.snap.chronoAge))")
                            .font(BroopType.regular(13))
                            .foregroundStyle(BroopPalette.textSecondary)
                    } else {
                        Text(data.loaded ? lockedCopy : String(localized: "Reading your Healthspan…"))
                            .font(BroopType.regular(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 200)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private var lockedCopy: String {
        if profile.age <= 0 { return String(localized: "Add your age in Settings to see your Broop Age.") }
        let left = max(0, VitalityEngine.gateMinRecoveries - data.snap.recoveriesLast31)
        return String(localized: "\(left) more recoveries this month to unlock Broop Age.")
    }

    private var calibrationBanner: some View {
        HStack(alignment: .top, spacing: BroopMetrics.gap) {
            Image(systemName: "lightbulb").font(BroopType.demi(16))
                .foregroundStyle(BroopHealthPalette.infoText)
            VStack(alignment: .leading, spacing: BroopMetrics.gap / 2) {
                Text("Broop Age Is Calibrating").font(BroopType.demi(15)).foregroundStyle(BroopHealthPalette.infoText)
                Text("Your Healthspan is calibrating, so fluctuations in your Broop Age are normal. It settles after about three months of wear.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { calibrationDismissed = true } } label: {
                Image(systemName: "xmark").font(BroopType.demi(13))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(BroopMetrics.page)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.innerRadius, style: .continuous)
            .fill(BroopHealthPalette.infoBanner))
    }

    // MARK: Pace of Aging

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
            BroopCaps(String(localized: "Pace of Aging"), size: 14)
            HStack(alignment: .lastTextBaseline) {
                HStack(spacing: BroopMetrics.gap / 2) {
                    Circle().fill(BroopPalette.textSecondary).frame(width: 12, height: 12)
                    Text("Slow").font(BroopType.medium(16)).foregroundStyle(BroopPalette.textSecondary)
                }
                Spacer()
                Text(verbatim: data.snap.pace.map { BroopFormat.one($0) + "x" } ?? "--")
                    .font(BroopType.number(30))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                HStack(spacing: BroopMetrics.gap / 2) {
                    Text("Fast").font(BroopType.medium(16)).foregroundStyle(BroopPalette.textSecondary)
                    Image(systemName: "hare").font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            BroopHealthPaceRuler(pace: data.snap.pace)
                .frame(height: 30)
            HStack {
                Text(verbatim: "-1.0x")
                Spacer()
                Text(verbatim: "1.0x")
                Spacer()
                Text(verbatim: "3.0x")
            }
            .font(BroopType.number(15))
            .foregroundStyle(BroopPalette.textSecondary)
        }
    }

    // MARK: Insight (tooltip card)

    /// Derived only from the resolver's own numbers: the pace band, then the factor with the largest
    /// impact each way.
    @ViewBuilder private var insightCard: some View {
        if let r = data.snap.result {
            let present = r.current.impacts.filter { !$0.isMissing }
            let worst = present.max { $0.years < $1.years }.flatMap { $0.years > 0.05 ? $0 : nil }
            let best = present.min { $0.years < $1.years }.flatMap { $0.years < -0.05 ? $0 : nil }
            VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                Text(verbatim: insightTitle(r.paceOfAging))
                    .font(BroopType.demi(17)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: insightBody(r, best: best, worst: worst))
                    .font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BroopMetrics.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BroopHealthNotchCard())
        }
    }

    private func insightTitle(_ pace: Double) -> String {
        switch VitalityEngine.paceBand(pace) {
        case .reversing: return String(localized: "Turning Back the Clock")
        case .slowing: return String(localized: "Aging Slowly")
        case .steady: return String(localized: "Right on Pace")
        case .accelerated: return String(localized: "Faster Pace")
        }
    }

    private func insightBody(_ r: VitalityEngine.Healthspan, best: VitalityEngine.Impact?,
                             worst: VitalityEngine.Impact?) -> String {
        let pace = BroopFormat.one(r.paceOfAging)
        var parts = [String(localized: "If your last 30 days hold for six months, your estimated Broop Age changes at \(pace) years per year.")]
        if let worst {
            parts.append(String(localized: "\(worst.factor.label) adds the most: \(HealthspanFormat.years(worst.years)) years."))
        }
        if let best {
            parts.append(String(localized: "\(best.factor.label) helps the most: \(HealthspanFormat.years(best.years)) years."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: Contributors

    private func pillarTitle(_ p: VitalityEngine.Pillar) -> String {
        switch p {
        case .sleep: return String(localized: "Sleep")
        case .strain: return String(localized: "Strain")
        case .fitness: return String(localized: "Fitness")
        }
    }

    private func pillarSection(_ pillar: VitalityEngine.Pillar, _ r: VitalityEngine.Healthspan) -> some View {
        let impacts = r.current.impacts.filter { $0.factor.pillar == pillar }
        return VStack(alignment: .leading, spacing: BroopMetrics.page) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: pillarTitle(pillar)).font(BroopType.demi(26)).foregroundStyle(BroopPalette.textPrimary)
                Spacer(minLength: BroopMetrics.gap)
                HStack(spacing: BroopMetrics.gap) {
                    Image(systemName: "arrowtriangle.down.fill").font(BroopType.regular(10))
                    Text("6 Month avg.")
                    Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 16)
                    Image(systemName: "arrowtriangle.up.fill").font(BroopType.regular(10))
                        .foregroundStyle(BroopPalette.textSecondary)
                    Text("30 Day avg.")
                }
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            VStack(spacing: 0) {
                ForEach(Array(impacts.enumerated()), id: \.element.factor) { i, impact in
                    contributor(impact, recent: r.recentInputs.value(impact.factor))
                    if i < impacts.count - 1 { BroopHairline() }
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        }
    }

    /// Where a row links: its metric trend, or the screen where the input comes from.
    private func link(_ f: VitalityEngine.Factor) -> BroopScreen {
        switch f {
        case .sleepHours: return .metric(key: "sleep_total_min", source: "my-whoop")
        case .sleepConsistency: return .sleep   // the 7-day regularity lives on the Sleep screen
        case .zone13, .zone45: return .workouts
        case .strength: return .liftLog
        case .steps: return .metric(key: "steps", source: MetricCatalog.combinedStepsSource)
        case .vo2max: return .metric(key: "vo2max_est", source: "my-whoop")
        case .rhr: return .metric(key: "rhr", source: "my-whoop")
        case .leanMass: return .metric(key: "body_fat", source: "apple-health")
        }
    }

    @ViewBuilder
    private func contributor(_ impact: VitalityEngine.Impact, recent: Double?) -> some View {
        let f = impact.factor
        if impact.isMissing {
            NavigationLink(value: f == .leanMass ? BroopScreen.labBook : link(f)) {
                missingRow(impact)
            }
            .buttonStyle(BroopPressableStyle())
        } else {
            VStack(spacing: 0) {
                NavigationLink {
                    BroopHealthspanFactorTrend(factor: f)
                } label: {
                    BroopHealthspanContributorRow(impact: impact, recent: recent,
                                                  age: data.snap.chronoAge, sex: profile.sex)
                }
                .buttonStyle(BroopPressableStyle())
                if f == .strength, (impact.value ?? 0) < 1 {
                    NavigationLink(value: BroopScreen.liftLog) {
                        hintLine(String(localized: "Log strength in Strength Trainer"))
                    }
                    .buttonStyle(BroopPressableStyle())
                    .padding(.bottom, BroopMetrics.page)
                }
            }
        }
    }

    private func missingRow(_ impact: VitalityEngine.Impact) -> some View {
        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
            HStack {
                BroopCaps(impact.factor.label, size: 13)
                Spacer()
                Text(verbatim: "0.0").font(BroopType.number(20)).foregroundStyle(BroopPalette.textSecondary)
            }
            hintLine(missingHint(impact.factor))
        }
        .padding(.vertical, BroopMetrics.page)
        .contentShape(Rectangle())
    }

    private func missingHint(_ f: VitalityEngine.Factor) -> String {
        switch f {
        case .leanMass: return String(localized: "Add lean mass in Lab Book or Apple Health. No effect until then.")
        case .vo2max: return String(localized: "Import VO₂ max from Apple Health, or keep wearing your strap for an estimate.")
        case .strength: return String(localized: "Log strength in Strength Trainer. No effect until there is a week of data.")
        default: return String(localized: "Not enough data yet. No effect until there is.")
        }
    }

    private func hintLine(_ text: String) -> some View {
        HStack(spacing: BroopMetrics.gap) {
            Image(systemName: "plus.circle").font(BroopType.demi(13))
            Text(verbatim: text).font(BroopType.regular(13.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(BroopType.demi(11))
        }
        .foregroundStyle(BroopHealthPalette.chartBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            Text("Trend View").font(BroopType.demi(26)).foregroundStyle(BroopPalette.textPrimary)
            NavigationLink(value: BroopScreen.metric(key: "body_age", source: "my-whoop")) {
                BroopHealthspanTrendCard(points: data.snap.trend.map { p in
                    (day: p.day, age: p.value,
                     chrono: Repository.healthspanAge(profileAge: profile.age, asOf: p.day,
                                                      currentUpdateDay: data.snap.updateDay))
                })
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    // MARK: Fitness

    private var readiness: FitnessAgeReadiness {
        let last7 = repo.days.suffix(7)
        return FitnessAgeEngine.assessReadiness(
            hasAge: profile.age > 0, hasSex: !profile.sex.isEmpty,
            rhrDays: last7.compactMap { $0.restingHr }.count,
            activityDays: last7.compactMap { $0.strain }.count,
            hasHeightWeight: profile.heightCm > 0 && profile.weightKg > 0,
            hasWaist: profile.waistCm > 0)
    }

    private var fitnessSection: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
            BroopHealthHeading(text: String(localized: "Fitness"), trailing: String(localized: "Weekly"))
            if let age = data.fitnessAge {
                fitnessCard(age: age)
                if profile.waistCm <= 0 {
                    NavigationLink(value: BroopScreen.settings) {
                        BroopHealthRow(symbol: "lungs", title: String(localized: "Add your waist for a more accurate VO₂max"))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                Button {
                    withAnimation(.snappy) { showReadiness.toggle() }
                } label: {
                    BroopHealthRow(symbol: "info.circle", title: String(localized: "How accurate is this?"),
                                   trailingSymbol: showReadiness ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(BroopPressableStyle())
                if showReadiness {
                    BroopHealthReadinessCard(readiness: readiness, lead: nil, onRefresh: nil, refreshing: false)
                }
            } else if data.loaded {
                BroopHealthReadinessCard(
                    readiness: readiness,
                    lead: fitnessReadyLeadCopy(rhrDays: repo.days.suffix(7).compactMap { $0.restingHr }.count,
                                               hasAge: profile.age > 0, hasSex: !profile.sex.isEmpty),
                    onRefresh: {
                        guard !refreshing else { return }
                        refreshing = true
                        Task {
                            _ = await intelligence.recomputeFitnessAgeOnly()
                            data = await BroopHealthspanData.load(repo: repo, profile: profile)
                            refreshing = false
                        }
                    },
                    refreshing: refreshing)
            }
            NavigationLink(value: BroopScreen.metric(key: "vo2max_est", source: "my-whoop")) {
                BroopHealthRow(symbol: "chart.xyaxis.line", title: String(localized: "VO₂ Max trend"))
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    private func fitnessCard(age: Double) -> some View {
        let shown = Int(age.rounded())
        let bound = fitnessAgeBoundSymbol(age)
        let delta = Double(profile.age) - age
        let years = Int(abs(delta).rounded())
        let younger = delta >= 0
        return NavigationLink(value: BroopScreen.metric(key: "fitness_age", source: "my-whoop")) {
            VStack(alignment: .leading, spacing: BroopMetrics.page) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: BroopMetrics.gap / 2) {
                        BroopCaps(String(localized: "Fitness Age"), size: 11, color: BroopPalette.textSecondary)
                        Text(verbatim: "\(bound)\(shown)")
                            .font(BroopType.number(44))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .broopNumeral(44)
                        Text(verbatim: fitnessDeltaLine(years: years, younger: younger, bound: bound))
                            .font(BroopType.demi(14))
                            .foregroundStyle(younger ? BroopHealthPalette.mint : BroopHealthPalette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let vo2 = data.vo2max {
                        VStack(alignment: .trailing, spacing: BroopMetrics.gap / 2) {
                            BroopCaps(String(localized: "VO₂ Max"), size: 11, color: BroopPalette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: BroopMetrics.gap / 3) {
                                Text(verbatim: String(format: "%.0f", vo2))
                                    .font(BroopType.number(44))
                                    .foregroundStyle(BroopHealthPalette.chartBlue)
                                Text(verbatim: "mL/kg/min").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                            }
                            Text(verbatim: "\(String(localized: "On-device")) · \(vo2MaxEstimatorDisplayName(data.vo2Estimator))")
                                .font(BroopType.regular(12))
                                .foregroundStyle(BroopPalette.textSecondary)
                        }
                    }
                }
                if !bound.isEmpty, data.vo2max != nil {
                    Text("Fitness Age stops here. VO₂max keeps moving.")
                        .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                }
                Text("± \(Int(FitnessAgeEngine.displayBandYears)) yr · a fitness comparison, not a biological age")
                    .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                BroopCaps(String(localized: "View trend →"), size: 11, color: BroopHealthPalette.chartBlue)
            }
            .padding(BroopMetrics.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        }
        .buttonStyle(BroopPressableStyle())
    }

    /// the whole-phrase variants (bounded readings are stated as a direction only).
    private func fitnessDeltaLine(years: Int, younger: Bool, bound: String) -> String {
        if bound == "≤" {
            if younger && years == 1 { return String(localized: "At least 1 year younger than your age") }
            if younger && years > 1 { return String(localized: "At least \(years) years younger than your age") }
            return String(localized: "\(Int(FitnessAgeEngine.minAge)) or younger")
        }
        if bound == "≥" {
            if !younger && years == 1 { return String(localized: "At least 1 year older than your age") }
            if !younger && years > 1 { return String(localized: "At least \(years) years older than your age") }
            return String(localized: "\(Int(FitnessAgeEngine.maxAge)) or older")
        }
        if years == 0 { return String(localized: "About the same as your age") }
        switch (younger, years == 1) {
        case (true, true): return String(localized: "1 year younger than your age")
        case (true, false): return String(localized: "\(years) years younger than your age")
        case (false, true): return String(localized: "1 year older than your age")
        case (false, false): return String(localized: "\(years) years older than your age")
        }
    }
}


/// Weekly six-month averages from the same resolver that supplies the contributor rows.
private struct BroopHealthspanFactorTrend: View {
    let factor: VitalityEngine.Factor
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var points: [Point] = []
    @State private var loaded = false

    private struct Point: Identifiable, Sendable {
        let id: String
        let date: Date
        let value: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BroopMetrics.section) {
                Text("Weekly six-month average")
                    .font(BroopType.regular(BroopMetrics.navTitleSize))
                    .foregroundStyle(BroopPalette.textSecondary)
                if let last = points.last {
                    Text(verbatim: HealthspanFormat.number(factor, last.value) + " " + HealthspanFormat.unit(factor))
                        .font(BroopType.number(BroopMetrics.section))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Chart(points) { point in
                        LineMark(x: .value("Week", point.date), y: .value("Value", point.value))
                            .foregroundStyle(BroopPalette.teal)
                        PointMark(x: .value("Week", point.date), y: .value("Value", point.value))
                            .foregroundStyle(BroopPalette.teal)
                    }
                    .frame(height: BroopMetrics.section * 7)
                    .accessibilityLabel(Text(verbatim: factor.label + " trend"))
                } else if loaded {
                    Text("Not enough history yet.").foregroundStyle(BroopPalette.textSecondary)
                } else {
                    ProgressView()
                }
                if factor == .strength {
                    NavigationLink("Log strength", value: BroopScreen.liftLog)
                } else if factor == .leanMass {
                    NavigationLink("Add lean mass", value: BroopScreen.labBook)
                }
            }
            .padding(BroopMetrics.page)
        }
        .background(BroopBackground())
        .broopScreenChrome(factor.label)
        .task(id: repo.refreshSeq) {
            let end = Repository.healthspanUpdateDay()
            let first = Repository.vitalityWindowStart(endingOn: end, days: 365)
            let history = await repo.healthspanHistory(
                from: Repository.vitalityWindowStart(endingOn: first), to: end)
            let sundays = VitalityEngine.sundays(from: first, to: end)
            let age = Double(profile.age), sex = profile.sex, factor = factor
            points = await Task.detached(priority: .utility) {
                sundays.compactMap { sunday in
                    guard let epoch = VitalityEngine.epochDay(sunday),
                          let current = VitalityEngine.epochDay(end),
                          let result = VitalityEngine.healthspan(days: history.days, leanMass: history.leanMass,
                              asOf: sunday, chronoAge: age - Double(current - epoch) / 365.25, sex: sex),
                          let value = result.longInputs.value(factor) else { return nil }
                    return Point(id: sunday, date: Date(timeIntervalSince1970: Double(epoch) * 86_400), value: value)
                }
            }.value
            loaded = true
        }
    }
}

// MARK: - Contributor row

/// One Healthspan contributor, WHOOP style: caps title, the 6-month value above a ten-segment bar coloured
/// by what each stretch of the range does to Broop Age (through `VitalityEngine.lnHazard`, the same curve
/// the impact comes from), ▼ at the 6-month value, ▲ at the 30-day value, and the age impact on the right.
private struct BroopHealthspanContributorRow: View {
    let impact: VitalityEngine.Impact
    let recent: Double?
    let age: Double
    let sex: String

    private var f: VitalityEngine.Factor { impact.factor }

    /// Display range of each bar (min, max, end labels).
    private var range: (lo: Double, hi: Double, loLabel: String, hiLabel: String) {
        switch f {
        case .sleepHours: return (5, 9, "5h", "9h")
        case .sleepConsistency: return (40, 100, "40%", "100%")
        case .zone13: return (0, 600, "0h", "10h")
        case .zone45: return (0, 60, "0h", "1h")
        case .strength: return (0, 120, "0h", "2h")
        case .steps: return (0, 16_000, "0K", "16K")
        case .vo2max: return (15, 70, "15", "70")
        case .rhr: return (40, 80, "40bpm", "80bpm")
        case .leanMass: return (60, 100, "60%", "100%")
        }
    }

    private func years(at v: Double) -> Double {
        VitalityEngine.yearsPerLnHazard * VitalityEngine.lnHazard(f, value: v, age: age, sex: sex)
    }

    private func frac(_ v: Double) -> CGFloat {
        let r = range
        return CGFloat(min(max((v - r.lo) / (r.hi - r.lo), 0), 1))
    }

    var body: some View {
        let r = range
        let segs = (0..<10).map { i -> Color in
            let mid = r.lo + (Double(i) + 0.5) / 10 * (r.hi - r.lo)
            return BroopHealthspanPalette.forYears(years(at: mid))
        }
        HStack(alignment: .center, spacing: BroopMetrics.page) {
            VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                HStack {
                    BroopCaps(f.label, size: 13)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: BroopMetrics.gap / 2)
                    Image(systemName: "chevron.right").font(BroopType.demi(12))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let x6 = frac(impact.value ?? r.lo) * w
                    ZStack(alignment: .topLeading) {
                        // Value label centred over the ▼, kept inside the row.
                        HStack(alignment: .firstTextBaseline, spacing: BroopMetrics.gap / 3) {
                            Text(verbatim: HealthspanFormat.number(f, impact.value ?? 0))
                                .font(BroopType.number(19)).foregroundStyle(BroopPalette.textPrimary)
                            let u = HealthspanFormat.unit(f)
                            if !u.isEmpty {
                                Text(verbatim: u).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                            }
                        }
                        .fixedSize()
                        .modifier(CentredLabel(x: x6, width: w))
                        HStack(spacing: BroopMetrics.gap / 3) {
                            ForEach(0..<10, id: \.self) { i in
                                Capsule().fill(segs[i]).frame(height: 5)
                            }
                        }
                        .offset(y: 34)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textPrimary)
                            .position(x: x6, y: 29)
                        if let recent {
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(BroopType.regular(8)).foregroundStyle(BroopPalette.textSecondary)
                                .position(x: frac(recent) * w, y: 46)
                        }
                        HStack {
                            Text(verbatim: r.loLabel).foregroundStyle(segs[0])
                            Spacer()
                            Text(verbatim: r.hiLabel).foregroundStyle(segs[9])
                        }
                        .font(BroopType.number(13))
                        .offset(y: 46)
                    }
                }
                .frame(height: 64)
                Text("Target: \(HealthspanFormat.value(f, impact.target))")
                    .font(BroopType.regular(BroopMetrics.navTitleSize))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: HealthspanFormat.years(impact.years))
                    .font(BroopType.number(24))
                    .foregroundStyle(BroopHealthspanPalette.text(impact.years))
                Text("years").font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            }
            .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, BroopMetrics.page)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(f.label): \(HealthspanFormat.value(f, impact.value ?? 0)), \(HealthspanFormat.years(impact.years)) \(String(localized: "years"))"))
    }
}

/// Positions a label so it is centred on `x` but never leaves `0…width`.
private struct CentredLabel: ViewModifier {
    let x: CGFloat
    let width: CGFloat
    @State private var labelWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.preference(key: LabelWidthKey.self, value: g.size.width) })
            .onPreferenceChange(LabelWidthKey.self) { labelWidth = $0 }
            .offset(x: min(max(x - labelWidth / 2, 0), max(0, width - labelWidth)))
    }
}

private struct LabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Trend card

/// "BROOP AGE TREND": the weekly Broop Age as a step line against the chronological age line.
private struct BroopHealthspanTrendCard: View {
    let points: [(day: String, age: Double, chrono: Double)]

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct P: Identifiable { let id: String; let date: Date; let age: Double; let chrono: Double }

    var body: some View {
        let ps = points.compactMap { p in Self.parser.date(from: p.day).map { P(id: p.day, date: $0, age: p.age, chrono: p.chrono) } }
        let last = ps.last
        let lo = (ps.map { min($0.age, $0.chrono) }.min() ?? 0) - 1
        let hi = (ps.map { max($0.age, $0.chrono) }.max() ?? 1) + 1
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            HStack {
                BroopCaps(String(localized: "Broop Age Trend"), size: 13)
                Spacer()
                Image(systemName: "chevron.right").font(BroopType.demi(12))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            if let last {
                HStack(alignment: .firstTextBaseline, spacing: BroopMetrics.section) {
                    VStack(alignment: .leading, spacing: BroopMetrics.gap / 5) {
                        Text(verbatim: BroopFormat.one(last.age)).font(BroopType.number(28))
                            .foregroundStyle(last.age < last.chrono ? BroopHealthspanPalette.good : BroopHealthspanPalette.bad)
                        BroopCaps(String(localized: "Broop Age"), size: 10, color: BroopPalette.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: BroopMetrics.gap / 5) {
                        Text(verbatim: BroopFormat.one(last.chrono)).font(BroopType.number(28))
                            .foregroundStyle(BroopPalette.textPrimary)
                        BroopCaps(String(localized: "Chronological age"), size: 10, color: BroopPalette.textSecondary)
                    }
                }
            }
            Chart {
                ForEach(ps) { p in
                    LineMark(x: .value("Week", p.date), y: .value("Age", p.chrono), series: .value("S", "chrono"))
                        .foregroundStyle(BroopHealthspanPalette.chrono.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
                ForEach(ps) { p in
                    LineMark(x: .value("Week", p.date), y: .value("Age", p.age), series: .value("S", "broop"))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(BroopHealthspanPalette.good)
                        .lineStyle(StrokeStyle(lineWidth: 2.4))
                }
                if let last {
                    PointMark(x: .value("Week", last.date), y: .value("Age", last.age))
                        .foregroundStyle(BroopHealthspanPalette.good).symbolSize(40)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(BroopHealthPalette.grid)
                    AxisValueLabel().foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .frame(height: 170)
            HStack(spacing: BroopMetrics.page) {
                legend(BroopHealthspanPalette.good, String(localized: "Broop Age"))
                legend(BroopHealthspanPalette.chrono, String(localized: "Chronological age"))
            }
        }
        .padding(BroopMetrics.page)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: BroopMetrics.gap / 2) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            BroopCaps(t, size: 10, color: BroopPalette.textSecondary)
        }
    }
}

// MARK: - Pieces

/// The hero: a thin ring in the result's hue with static rim dots (no glow).
private struct BroopHealthspanRing: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 4
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color), lineWidth: 1.6)

        }
        .accessibilityHidden(true)
    }
}

/// Pace of Aging tick ruler from -1.0x to 3.0x with a white marker at the value.
struct BroopHealthPaceRuler: View {
    let pace: Double?

    var body: some View {
        Canvas { ctx, size in
            let n = 60
            for i in 0...n {
                let x = CGFloat(i) / CGFloat(n) * (size.width - 2) + 1
                let major = i % 15 == 0
                let h = major ? size.height * 0.8 : size.height * 0.62
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height - h))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(BroopPalette.textSecondary.opacity(major ? 0.8 : 0.45)),
                           lineWidth: major ? 1.8 : 1.3)
            }
            if let pace {
                let t = CGFloat((min(max(pace, -1), 3) + 1) / 4)
                let x = t * (size.width - 2) + 1
                var m = Path()
                m.move(to: CGPoint(x: x, y: 0))
                m.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(m, with: .color(BroopPalette.textPrimary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Card with a small upward notch at its top centre (the WHOOP tooltip).
struct BroopHealthNotchCard: View {
    var fill: Color = BroopPalette.card

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                let r: CGFloat = 16, notch: CGFloat = 9
                p.move(to: CGPoint(x: r, y: 0))
                p.addLine(to: CGPoint(x: w / 2 - notch, y: 0))
                p.addLine(to: CGPoint(x: w / 2, y: -notch))
                p.addLine(to: CGPoint(x: w / 2 + notch, y: 0))
                p.addLine(to: CGPoint(x: w - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: h - r))
                p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: r, y: h))
                p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
            }
            .fill(fill)
        }
    }
}

/// The Fitness Age readiness checklist, grouped by what each input unlocks (classic
/// `ReadinessChecklistCard`, rebuilt). Required-missing profile inputs link to Settings.
struct BroopHealthReadinessCard: View {
    let readiness: FitnessAgeReadiness
    let lead: String?
    let onRefresh: (() -> Void)?
    let refreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            HStack {
                confidence
                Spacer()
                if let onRefresh {
                    if refreshing {
                        ProgressView().controlSize(.small).tint(BroopPalette.textPrimary)
                    } else {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise").font(BroopType.demi(15))
                                .foregroundStyle(BroopPalette.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Refresh Fitness Age now"))
                    }
                }
            }
            if let lead {
                Text(verbatim: lead)
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            group(String(localized: "Drives your Fitness Age"), readiness.items.filter { $0.role == .drivesAge })
            group(String(localized: "Sharpens your VO₂max"), readiness.items.filter { $0.role == .unlocksVO2max })
            Text("Built from published methods (Nes/HUNT) on \(Platform.deviceNounPhrase). It's a fitness comparison against an average peer your age, not a biological or medical age.")
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BroopMetrics.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
    }

    @ViewBuilder private var confidence: some View {
        switch readiness.confidence {
        case .ready: BroopHealthStatusPill(tone: .good, text: String(localized: "Ready"))
        case .estimate: BroopHealthStatusPill(tone: .warn, text: String(localized: "Estimate (partial data)"))
        case .notReady: BroopHealthStatusPill(tone: .none, text: String(localized: "Not enough data yet"))
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [FitnessReadinessItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                BroopCaps(title, size: 10.5, color: BroopPalette.textSecondary)
                ForEach(items, id: \.key) { item in
                    let fixable = item.status != .satisfied
                        && ["age", "sex", "bodyMetrics", "waist"].contains(item.key)
                    HStack(alignment: .firstTextBaseline, spacing: BroopMetrics.gap) {
                        Image(systemName: item.status == .satisfied ? "checkmark.circle.fill"
                              : (item.status == .partial ? "exclamationmark.triangle.fill" : "circle"))
                            .font(BroopType.demi(14))
                            .foregroundStyle(item.status == .satisfied ? BroopHealthPalette.mint
                                             : (item.status == .partial ? BroopHealthPalette.amber : BroopPalette.textSecondary))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: BroopMetrics.gap / 10) {
                            Text(verbatim: item.label).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                            Text(verbatim: item.detail).font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if fixable {
                            NavigationLink(value: BroopScreen.settings) {
                                BroopCaps(String(localized: "Fix"), size: 10.5, color: BroopHealthPalette.chartBlue)
                            }
                            .accessibilityLabel(Text(verbatim: "\(item.label): \(item.detail). \(String(localized: "Fix in Settings"))"))
                        }
                    }
                }
            }
        }
    }
}
#endif
