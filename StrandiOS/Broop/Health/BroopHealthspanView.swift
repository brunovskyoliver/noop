#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - Data

/// The weekly Healthspan figures (Vitality, Body Age, Pace of Aging, contributors) and the Fitness Age /
/// VO₂max pair, read exactly as the classic Health screen's `VitalitySection` and `FitnessAgeSection`
/// read them, so Broop and classic can never disagree.
struct BroopHealthspanData {
    var vitality: Double?
    var bodyAge: Double?
    var pace: Double?
    var contributions: [VitalityEngine.Contribution] = []
    var fitnessAge: Double?
    var vo2max: Double?
    var vo2Estimator: Vo2MaxEstimator?
    var loaded = false

    @MainActor
    static func load(repo: Repository, profile: ProfileStore) async -> BroopHealthspanData {
        var d = BroopHealthspanData()
        d.vitality = (await repo.exploreSeries(key: "vitality", source: "my-whoop")).last?.value
        let latestAge = (await repo.exploreSeries(key: "body_age", source: "my-whoop")).last
        d.bodyAge = latestAge?.value
        // Only the pace written alongside the current Body Age (classic rule).
        d.pace = (await repo.exploreSeries(key: "pace_of_aging", source: "my-whoop"))
            .last { $0.day == latestAge?.day }?.value
        let today = Repository.dayString(Date())
        let days = await repo.vitalityDays(endingOn: today)
        d.contributions = VitalityEngine.healthspan(days: days, asOf: today, chronoAge: Double(profile.age),
                                                    sex: profile.sex)?.bodyAge.contributions ?? []
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

    /// Positive = younger than the calendar age.
    func bodyAgeDelta(age: Int) -> Double? { bodyAge.map { Double(age) - $0 } }

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
}

// MARK: - Screen

/// Broop Healthspan: Body Age hero, Pace of Aging ruler, what moves the number, and the Fitness Age /
/// VO₂max pair. Rebuilt from the classic Health screen's Vitality and Fitness Age sections.
struct BroopHealthspanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @State private var data = BroopHealthspanData()
    @State private var showInfo = false
    @State private var showReadiness = false
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero.padding(.top, 8)
                if showInfo {
                    BroopHealthInfoBanner(symbol: "lightbulb",
                                          text: String(localized: "Body Age is a weekly wellness estimate built on-device from your last 180 days of habits (resting heart rate, sleep, HRV, activity and fitness) using a published mortality-hazard model. It is not a clinical biological age."))
                        .padding(.top, 18)
                        .transition(.opacity)
                }
                paceSection.padding(.top, 30)
                driversCard.padding(.top, 18)
                contributorsSection.padding(.top, BroopMetrics.section)
                fitnessSection.padding(.top, BroopMetrics.section)
                BroopHealthFootnote(text: String(localized: "A wellness estimate from your habits, not a clinical biological age."))
                    .padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Healthspan"),
                              subtitle: String(localized: "Updated weekly"), fill: .black) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "About Healthspan")) {
                    withAnimation(.snappy) { showInfo.toggle() }
                }
            }
        }
        .background(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35),
                                   .init(color: Color(broopHex: 0x101518), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: repo.refreshSeq) { data = await BroopHealthspanData.load(repo: repo, profile: profile) }
    }

    private var hue: Color {
        guard let delta = data.bodyAgeDelta(age: profile.age) else { return BroopPalette.textSecondary }
        return delta >= 0 ? BroopHealthPalette.stressMedium : BroopHealthPalette.amber
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                BroopHealthspanRing(color: hue)
                    .frame(width: 270, height: 270)
                VStack(spacing: 6) {
                    Text(verbatim: data.bodyAge.map(BroopFormat.one) ?? "--")
                        .font(BroopType.number(68))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .broopNumeral(68)
                    BroopCaps(String(localized: "Body Age"), size: 15, color: BroopPalette.textSecondary)
                    if let delta = data.bodyAgeDelta(age: profile.age) {
                        Text(verbatim: BroopHealthspanData.yearsLine(delta))
                            .font(BroopType.demi(19))
                            .foregroundStyle(Color(broopHex: 0xAFE4EC))
                    } else {
                        Text(data.loaded ? "A few more days and we can show your Body Age."
                                         : "Reading your Healthspan…")
                            .font(BroopType.regular(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 190)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                statColumn(value: data.vitality.map(BroopFormat.whole), unit: "/100",
                           label: String(localized: "Vitality"))
                Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 40)
                statColumn(value: profile.age > 0 ? "\(profile.age)" : nil, unit: nil,
                           label: String(localized: "Calendar age"))
            }
            .padding(.top, 18)
        }
        .accessibilityElement(children: .combine)
    }

    private func statColumn(value: String?, unit: String?, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value ?? "--").font(BroopType.number(24)).foregroundStyle(BroopPalette.textPrimary)
                if let unit, value != nil {
                    Text(verbatim: unit).font(BroopType.number(12)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            BroopCaps(label, size: 10, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Pace of Aging

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "Pace of Aging"), size: 14)
            HStack(alignment: .lastTextBaseline) {
                HStack(spacing: 6) {
                    Circle().fill(BroopPalette.textSecondary).frame(width: 12, height: 12)
                    Text("Slow").font(BroopType.medium(16)).foregroundStyle(BroopPalette.textSecondary)
                }
                Spacer()
                Text(verbatim: data.pace.map { BroopFormat.one($0) + "x" } ?? "--")
                    .font(BroopType.number(30))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text("Fast").font(BroopType.medium(16)).foregroundStyle(BroopPalette.textSecondary)
                    Image(systemName: "hare").font(.system(size: 13)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            BroopHealthPaceRuler(pace: data.pace)
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
            Text(verbatim: data.pace.map { BroopHealthspanData.paceBandLabel($0) + ". " + String(localized: "Your last 30 days compared with your last 6 months.") }
                 ?? String(localized: "Pace of Aging appears after about two months of wear."))
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: Drivers (tooltip card)

    @ViewBuilder private var driversCard: some View {
        let sorted = data.contributions.sorted { $0.ageImpactYears < $1.ageImpactYears }
        let best = sorted.first.flatMap { $0.lnHazard < 0 ? $0 : nil }
        let worst = sorted.last.flatMap { $0.lnHazard > 0 ? $0 : nil }
        if best != nil || worst != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let best {
                    Text("Helping most: \(best.label)")
                        .font(BroopType.demi(16)).foregroundStyle(BroopHealthPalette.mint)
                }
                if let worst {
                    Text("Holding you back: \(worst.label)")
                        .font(BroopType.demi(16)).foregroundStyle(BroopHealthPalette.amber)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BroopHealthNotchCard())
        }
    }

    // MARK: Contributors

    @ViewBuilder private var contributorsSection: some View {
        if !data.contributions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What moves it").font(BroopType.demi(22)).foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    BroopCaps(String(localized: "Impact"), size: 10, color: BroopPalette.textSecondary)
                }
                VStack(spacing: 0) {
                    let rows = data.contributions.sorted { $0.ageImpactYears < $1.ageImpactYears }
                    let scale = max(rows.map { abs($0.ageImpactYears) }.max() ?? 1, 0.5)
                    ForEach(Array(rows.enumerated()), id: \.element.key) { i, c in
                        contributorRow(c, scale: scale)
                        if i < rows.count - 1 { BroopHairline() }
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
            }
        }
    }

    private func contributorRow(_ c: VitalityEngine.Contribution, scale: Double) -> some View {
        let years = c.ageImpactYears
        let color: Color = abs(years) < 0.05 ? BroopPalette.textPrimary
            : (years < 0 ? BroopHealthPalette.stressMedium : BroopHealthPalette.amber)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                BroopCaps(c.label, size: 11.5)
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let w = CGFloat(min(abs(years) / scale, 1)) * half
                    ZStack(alignment: .leading) {
                        Capsule().fill(BroopPalette.track).frame(height: 6)
                        Capsule().fill(color).frame(width: max(w, 2), height: 6)
                            .offset(x: years < 0 ? half - w : half)
                        Rectangle().fill(BroopPalette.textSecondary).frame(width: 1.5, height: 12).offset(x: half - 0.75)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 12)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: (years > 0.05 ? "+" : (years < -0.05 ? "-" : "")) + BroopFormat.one(abs(years)))
                    .font(BroopType.number(20))
                    .foregroundStyle(color)
                Text("years").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
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
                        VStack(alignment: .trailing, spacing: 4) {
                            BroopCaps(String(localized: "VO₂ Max"), size: 11, color: BroopPalette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
        .buttonStyle(BroopPressableStyle())
    }

    /// The classic whole-phrase variants (bounded readings are stated as a direction only).
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

// MARK: - Pieces

/// The hero: a thin ring in the result's hue with static rim dots (no glow).
private struct BroopHealthspanRing: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [.black, color.opacity(0.10), color.opacity(0.30)]),
                                           center: c, startRadius: r * 0.45, endRadius: r))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color), lineWidth: 1.6)
            // Deterministic rim dots: denser and larger toward the rim.
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<150 {
                let a = next() * 2 * .pi
                let t = pow(next(), 0.45)
                let rr = r * (0.55 + 0.42 * t)
                let d = 1.0 + 3.2 * next() * t
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                         with: .color(color.opacity(0.25 + 0.55 * t)))
            }
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
                ctx.stroke(m, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                confidence
                Spacer()
                if let onRefresh {
                    if refreshing {
                        ProgressView().controlSize(.small).tint(BroopPalette.textPrimary)
                    } else {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
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
            VStack(alignment: .leading, spacing: 10) {
                BroopCaps(title, size: 10.5, color: BroopPalette.textSecondary)
                ForEach(items, id: \.key) { item in
                    let fixable = item.status != .satisfied
                        && ["age", "sex", "bodyMetrics", "waist"].contains(item.key)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: item.status == .satisfied ? "checkmark.circle.fill"
                              : (item.status == .partial ? "exclamationmark.triangle.fill" : "circle"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.status == .satisfied ? BroopHealthPalette.mint
                                             : (item.status == .partial ? BroopHealthPalette.amber : BroopPalette.textSecondary))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
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
