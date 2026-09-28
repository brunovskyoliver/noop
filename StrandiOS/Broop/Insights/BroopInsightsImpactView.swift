#if os(iOS)
import SwiftUI
import StrandAnalytics

// Journal Insights, as WHOOP's "Recovery Impact Analysis": one card per behaviour with a signed percent and a
// diverging bar on a hatched track, a behaviour-detail sheet, then NOOP's personal experiment, activity cost
// and metric relationships in the same visual language. Data and ranking: `BroopInsightsImpactModel`.

struct BroopInsightsImpactView: View {
    typealias Outcome = InsightsView.Outcome

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = BroopInsightsImpactModel()
    @StateObject private var catalog = JournalCatalogStore()
    @State private var outcome: Outcome = .recovery
    @State private var detail: BehaviorEffect?

    // Personal experiment state: the same keys the classic Insights card and Android use.
    @AppStorage("noop.experiment.behaviour") private var experimentBehaviour = ""
    @AppStorage("noop.experiment.outcome") private var experimentOutcomeRaw = Outcome.recovery.rawValue
    @AppStorage("noop.experiment.startedDay") private var experimentStartedDay = ""
    @AppStorage("noop.experiment.durationDays") private var experimentDurationDays = 14
    @AppStorage("noop.experiment.baselineDays") private var experimentBaselineDays = 14

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                intro.padding(.top, 8)
                BroopUnderlineTabs(options: Outcome.allCases, selection: $outcome) { $0.label }
                    .padding(.top, 22)
                if !model.loaded {
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    impactList.padding(.top, 22)
                    experimentSection.padding(.top, BroopMetrics.section + 8)
                    activityCostSection.padding(.top, BroopMetrics.section + 8)
                    relationshipsSection.padding(.top, BroopMetrics.section + 8)
                    BroopInsightsBody(text: String(localized: "Patterns in your own logged days: associations, not causes. Not medical advice."),
                                      size: 12, color: BroopPalette.textTertiary)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .broopInsightsChrome(String(localized: "Journal insights"))
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .onChange(of: outcome) { _, o in model.rank(o) }
        .sheet(item: Binding(get: { detail.map { BroopInsightsEffectBox(effect: $0) } }, set: { detail = $0?.effect })) { box in
            BroopInsightsBehaviorDetail(effect: box.effect, outcome: outcome)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(String(localized: "Refreshed with every log"), size: 10.5, color: BroopPalette.textSecondary)
            BroopInsightsHeadline(text: String(localized: "\(outcome.outcomeName) Impact Analysis"), size: 26)
            BroopInsightsBody(text: String(localized: "See how the behaviours you log line up with your \(outcome.outcomeName.lowercased()). Tap a behaviour to view more details."),
                              color: BroopPalette.textSecondary)
        }
    }

    // MARK: Impact list

    @ViewBuilder private var impactList: some View {
        if model.behaviours.isEmpty {
            BroopInsightsNote(symbol: "square.and.pencil", title: String(localized: "Nothing logged yet"),
                              text: String(localized: "Log behaviours in your journal. After a few days of answers, Broop ranks how each one moves your charge, HRV and rest. Importing a WHOOP export (which includes its journal) backfills history instantly."))
        } else if model.ranked.isEmpty {
            BroopInsightsNote(symbol: "hourglass", title: nil,
                              text: String(localized: "Not enough overlap between your journal answers and \(outcome.outcomeName.lowercased()) to measure an effect yet. Keep logging. Effects need days both with and without each behaviour."))
        } else {
            VStack(spacing: 10) {
                BroopInsightsImpactLegend().padding(.horizontal, 4).padding(.bottom, 4)
                let scale = max(10, model.ranked.map { abs(Self.percent($0)) }.max() ?? 10)
                ForEach(model.ranked, id: \.behavior) { e in
                    Button { detail = e } label: { impactCard(e, scale: scale) }
                        .buttonStyle(BroopPressableStyle())
                }
            }
        }
    }

    /// The effect in percent of the without-mean; falls back to the raw delta when the ratio is undefined.
    static func percent(_ e: BehaviorEffect) -> Double { e.pctChange ?? e.delta }

    /// Signed "goodness": positive when the behaviour moved the outcome the good way.
    static func goodness(_ e: BehaviorEffect, outcome: Outcome) -> Double {
        percent(e) * (outcome.higherIsBetter ? 1 : -1)
    }

    static func tint(_ e: BehaviorEffect, outcome: Outcome) -> Color {
        guard e.significant, e.delta != 0 else { return BroopInsightsPalette.neutralBar }
        return goodness(e, outcome: outcome) > 0 ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts
    }

    private func impactCard(_ e: BehaviorEffect, scale: Double) -> some View {
        let tint = Self.tint(e, outcome: outcome)
        let pctText = e.pctChange.map(BroopInsightsFormat.signedPercent) ?? BroopInsightsImpactModel.formatDelta(e.delta, outcome: outcome)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(e.behavior, size: 12).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 10)
                Text(verbatim: pctText)
                    .font(BroopType.number(21))
                    .foregroundStyle(e.significant ? tint : BroopPalette.textSecondary)
            }
            BroopInsightsImpactBar(fraction: Self.goodness(e, outcome: outcome) / scale, color: tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopInsightsPalette.cardRaised))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: BehaviorInsights.sentence(e)))
    }

    // MARK: Experiment

    private var experimentCandidates: [String] {
        model.experimentCandidates(saved: experimentBehaviour, hidden: catalog.hiddenQuestions)
    }

    private var resolvedBehaviour: String? {
        let c = experimentCandidates
        let s = experimentBehaviour.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, c.contains(s) { return s }
        return c.first
    }

    private var experimentSection: some View {
        let snap = model.experiment(behavior: resolvedBehaviour, outcomeRaw: experimentOutcomeRaw,
                                    startedDay: experimentStartedDay, durationDays: experimentDurationDays,
                                    baselineDays: experimentBaselineDays)
        return VStack(alignment: .leading, spacing: 14) {
            BroopInsightsSectionRule(title: String(localized: "Personal experiment"),
                                     trailing: snap.map { $0.complete ? String(localized: "COMPLETE") : String(localized: "DAY \($0.daysElapsed)/\($0.durationDays)") }
                                        ?? String(localized: "Local only"))
            if let snap { activeExperiment(snap) } else { experimentSetup }
        }
    }

    private var experimentSetup: some View {
        BroopInsightsCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run a clean personal test")
                    .font(BroopType.demi(18)).foregroundStyle(BroopPalette.textPrimary)
                BroopInsightsBody(text: String(localized: "Pick one behaviour you log, one outcome, and a short window. Broop compares the days you log the behaviour against your behaviour-free days before the start."),
                                  size: 13, color: BroopPalette.textSecondary)
                if experimentCandidates.isEmpty {
                    BroopInsightsBody(text: String(localized: "Log at least one behaviour in your journal before starting an experiment."),
                                      size: 13, color: BroopPalette.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        BroopCaps(String(localized: "Behaviour"), size: 10, color: BroopPalette.textSecondary)
                        Menu {
                            ForEach(experimentCandidates, id: \.self) { q in
                                Button(q) { experimentBehaviour = q }
                            }
                        } label: {
                            HStack {
                                Text(verbatim: resolvedBehaviour ?? "").font(BroopType.medium(15)).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(BroopPalette.textPrimary)
                            .broopInsightsField()
                        }
                        .accessibilityLabel(Text("Experiment behaviour"))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        BroopCaps(String(localized: "Outcome"), size: 10, color: BroopPalette.textSecondary)
                        BroopUnderlineTabs(options: Outcome.allCases,
                                           selection: Binding(get: { Outcome(rawValue: experimentOutcomeRaw) ?? .recovery },
                                                              set: { experimentOutcomeRaw = $0.rawValue })) { $0.label }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        BroopCaps(String(localized: "Window"), size: 10, color: BroopPalette.textSecondary)
                        BroopUnderlineTabs(options: [7, 14, 28],
                                           selection: Binding(get: { [7, 14, 28].contains(experimentDurationDays) ? experimentDurationDays : 14 },
                                                              set: { experimentDurationDays = $0 })) { "\($0)d" }
                    }
                    BroopInsightsPrimaryButton(title: String(localized: "Start experiment"), symbol: "flask") { startExperiment() }
                        .disabled(resolvedBehaviour == nil)
                }
            }
        }
    }

    private func activeExperiment(_ s: BroopInsightsImpactModel.Experiment) -> some View {
        let deltaColor: Color = {
            guard let d = s.delta, abs(d) >= 0.05 else { return BroopPalette.textSecondary }
            return (s.outcome.higherIsBetter ? d > 0 : d < 0) ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts
        }()
        return BroopInsightsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: s.behavior).font(BroopType.demi(18)).foregroundStyle(BroopPalette.textPrimary).lineLimit(2)
                        Text("Started \(s.startDay) · testing \(s.outcome.outcomeName.lowercased())")
                            .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    BroopInsightsChip(text: s.confidenceLabel, color: s.confidenceColor)
                }
                BroopInsightsBody(text: experimentReading(s), size: 14)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    measure(String(localized: "Baseline"),
                            s.baselineMean.map { BroopInsightsImpactModel.format($0, as: s.outcome) } ?? "—",
                            String(localized: "\(s.baselineCount) days without it"), BroopPalette.textPrimary)
                    measure(String(localized: "Intervention"),
                            s.interventionMean.map { BroopInsightsImpactModel.format($0, as: s.outcome) } ?? "—",
                            String(localized: "\(s.interventionCount) logged days"), BroopPalette.textPrimary)
                    measure(String(localized: "Change"),
                            BroopInsightsImpactModel.formatDelta(s.delta, outcome: s.outcome),
                            s.delta == nil ? String(localized: "needs baseline + logged days") : String(localized: "vs behaviour-free baseline"),
                            deltaColor)
                    measure(String(localized: "Compliance"), "\(Int(s.compliance.rounded()))%",
                            s.loggedToday ? String(localized: "logged today") : String(localized: "not logged today"),
                            s.loggedToday ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts)
                }
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BroopPalette.track)
                            Capsule().fill(BroopInsightsPalette.helps).frame(width: g.size.width * s.progress)
                        }
                    }
                    .frame(height: 4)
                    Text("\(s.daysElapsed) of \(s.durationDays) days")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 10) {
                    Button { Task { await mark(true) } } label: {
                        BroopCaps(String(localized: "Done today"), size: 10.5, color: .black)
                            .frame(maxWidth: .infinity, minHeight: 38).background(Capsule().fill(Color.white))
                    }
                    .disabled(s.loggedToday).opacity(s.loggedToday ? 0.4 : 1)
                    Button { Task { await mark(false) } } label: {
                        BroopCaps(String(localized: "Skip today"), size: 10.5)
                            .frame(maxWidth: .infinity, minHeight: 38).overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.4))
                    }
                    Button(role: .destructive) { experimentStartedDay = "" } label: {
                        BroopCaps(String(localized: "End"), size: 10.5, color: BroopInsightsPalette.hurts)
                            .frame(minWidth: 64, minHeight: 38).overlay(Capsule().strokeBorder(BroopInsightsPalette.hurts, lineWidth: 1.4))
                    }
                    .accessibilityHint(Text("Ends the experiment plan. Journal and metric history stay untouched."))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func measure(_ label: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(22)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: caption).font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopPalette.row.opacity(0.6)))
    }

    private func experimentReading(_ s: BroopInsightsImpactModel.Experiment) -> String {
        guard let delta = s.delta else {
            return String(localized: "Collect a few logged intervention days before reading the effect. Baseline and imported metrics stay in place.")
        }
        let absDelta = BroopInsightsImpactModel.formatDelta(abs(delta), outcome: s.outcome, sign: false)
        if abs(delta) < 0.05 {
            return String(localized: "\(s.outcome.outcomeName) is flat against baseline on logged intervention days.")
        }
        let good = s.outcome.higherIsBetter ? delta > 0 : delta < 0
        return good
            ? String(localized: "\(s.outcome.outcomeName) is \(absDelta) better than baseline on days you logged this behaviour.")
            : String(localized: "\(s.outcome.outcomeName) is \(absDelta) worse than baseline on days you logged this behaviour.")
    }

    private func startExperiment() {
        guard let b = resolvedBehaviour else { return }
        experimentBehaviour = b
        if ![7, 14, 28].contains(experimentDurationDays) { experimentDurationDays = 14 }
        if Outcome(rawValue: experimentOutcomeRaw) == nil { experimentOutcomeRaw = Outcome.recovery.rawValue }
        experimentBaselineDays = experimentDurationDays
        experimentStartedDay = Repository.localDayKey(Date())
    }

    private func mark(_ yes: Bool) async {
        guard let b = resolvedBehaviour else { return }
        await repo.saveJournalAnswer(day: Repository.localDayKey(Date()), question: b, answeredYes: yes)
        await model.load(repo: repo)
    }

    // MARK: Activity cost

    private var activityCostSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopInsightsSectionRule(title: String(localized: "Activity cost"))
            BroopInsightsBody(text: String(localized: "What each activity costs your next-morning Charge."), size: 13, color: BroopPalette.textSecondary)
            if model.activityCosts.isEmpty {
                BroopInsightsNote(symbol: "figure.run", title: nil,
                                  text: String(localized: "Tag a few sessions of the same activity and Broop will learn its personal recovery cost."))
            } else {
                ForEach(model.activityCosts, id: \.sport) { costCard($0) }
            }
        }
    }

    private func costCard(_ c: ActivityCost) -> some View {
        let costing = c.delta >= ActivityCostEngine.barelyMovesPoints
        let lifting = c.delta <= -ActivityCostEngine.barelyMovesPoints
        let color = costing ? BroopInsightsPalette.hurts : (lifting ? BroopInsightsPalette.helps : BroopPalette.textSecondary)
        let points = String(format: "%@%.0f", c.delta >= 0 ? "−" : "+", abs(c.delta))
        return BroopInsightsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BroopCaps(c.sport, size: 12).lineLimit(1)
                    Spacer()
                    BroopInsightsChip(text: c.confidence == .solid ? String(localized: "Solid") : String(localized: "Building"),
                                      color: c.confidence == .solid ? BroopInsightsPalette.helps : BroopPalette.textSecondary)
                }
                BroopInsightsBody(text: c.sentence(), size: 13, color: BroopPalette.textSecondary)
                HStack(spacing: 0) {
                    stat(String(localized: "Next morning"), "\(Int(c.meanNextMorning.rounded()))%", color)
                    stat(String(localized: "Baseline"), "\(Int(c.baselineMean.rounded()))%", BroopPalette.textPrimary)
                    stat(String(localized: "Change"), points, color)
                    stat(String(localized: "Bounce back"), c.daysToBaseline.map { "\($0)d" } ?? "—", BroopPalette.textPrimary)
                }
                Text("\(c.n) sessions").font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(label, size: 8.5, color: BroopPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(BroopType.number(19)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Relationships

    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopInsightsSectionRule(title: String(localized: "Metric relationships"), trailing: "PEARSON R")
            if model.relationships.isEmpty {
                BroopInsightsNote(symbol: "chart.dots.scatter", title: nil,
                                  text: String(localized: "Not enough overlapping history to correlate your metrics yet."))
            } else {
                VStack(spacing: 10) {
                    BroopInsightsImpactLegend(center: String(localized: "Correlation"))
                        .padding(.horizontal, 4)
                    ForEach(model.relationships) { rel in relationshipCard(rel) }
                }
            }
        }
    }

    private func relationshipCard(_ rel: BroopInsightsImpactModel.Relationship) -> some View {
        let r = rel.corr.r
        let significant = rel.corr.pApprox < 0.05
        let color = significant ? (r >= 0 ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts) : BroopInsightsPalette.neutralBar
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(rel.title, size: 12)
                Spacer()
                Text(verbatim: String(format: "r = %+.2f", r)).font(BroopType.number(18)).foregroundStyle(significant ? color : BroopPalette.textSecondary)
            }
            BroopInsightsImpactBar(fraction: r, color: color)
            Text(verbatim: "\(Self.relationshipSentence(rel)) \(significant ? "p < 0.05" : "n.s.")")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: rel.blurb).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopInsightsPalette.cardRaised))
        .accessibilityElement(children: .combine)
    }

    static func relationshipSentence(_ rel: BroopInsightsImpactModel.Relationship) -> String {
        let r = rel.corr.r
        let dir = r > 0 ? String(localized: "positive") : (r < 0 ? String(localized: "negative") : String(localized: "flat"))
        let strength: String
        switch abs(r) {
        case ..<0.1: strength = String(localized: "no")
        case ..<0.3: strength = String(localized: "a weak")
        case ..<0.5: strength = String(localized: "a moderate")
        case ..<0.7: strength = String(localized: "a strong")
        default: strength = String(localized: "a very strong")
        }
        let cap = strength.prefix(1).uppercased() + strength.dropFirst()
        return String(localized: "\(cap) \(dir) relationship (r = \(String(format: "%.2f", r)), n = \(rel.corr.n)).")
    }
}

/// `BehaviorEffect` is not Identifiable; the sheet keys on the behaviour name.
struct BroopInsightsEffectBox: Identifiable {
    let effect: BehaviorEffect
    var sentence: String? = nil
    var id: String { effect.behavior }
}

/// WHOOP's behaviour-impact detail: Title Case name, an impact chip, the big signed percent, the plain
/// sentence, the diverging bar and the with / without evidence behind it.
struct BroopInsightsBehaviorDetail: View {
    let effect: BehaviorEffect
    let outcome: InsightsView.Outcome
    /// The ranker's own sentence when it carries a lead/lag clause; the plain effect sentence otherwise.
    var sentence: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tint = BroopInsightsImpactView.tint(effect, outcome: outcome)
        let good = BroopInsightsImpactView.goodness(effect, outcome: outcome) > 0
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            BroopInsightsHeadline(text: effect.behavior.capitalized, size: 28)
                            BroopInsightsChip(text: !effect.significant ? String(localized: "Exploratory")
                                                  : (good ? String(localized: "Positive impact") : String(localized: "Negative impact")),
                                              color: effect.significant ? tint : BroopPalette.textSecondary)
                        }
                        Spacer()
                        Text(verbatim: effect.pctChange.map(BroopInsightsFormat.signedPercent)
                             ?? BroopInsightsImpactModel.formatDelta(effect.delta, outcome: outcome))
                            .font(BroopType.number(40))
                            .foregroundStyle(effect.significant ? tint : BroopPalette.textPrimary)
                    }
                    BroopInsightsBody(text: sentence ?? BehaviorInsights.sentence(effect), size: 15)
                    VStack(spacing: 12) {
                        BroopInsightsImpactLegend(center: String(localized: "\(outcome.outcomeName) impact"))
                        BroopInsightsImpactBar(fraction: max(-1, min(1, BroopInsightsImpactView.goodness(effect, outcome: outcome) / 25)),
                                               color: tint, height: 14)
                    }
                    .padding(.top, 6)
                    VStack(spacing: 0) {
                        row(String(localized: "With it"), BroopInsightsImpactModel.format(effect.meanWith, as: outcome), "n = \(effect.nWith)")
                        BroopHairline()
                        row(String(localized: "Without it"), BroopInsightsImpactModel.format(effect.meanWithout, as: outcome), "n = \(effect.nWithout)")
                        BroopHairline()
                        row(String(localized: "Effect size"), String(format: "d = %.2f", effect.cohensD), BroopInsightsFormat.magnitudeWord(effect.cohensD))
                        BroopHairline()
                        row(String(localized: "Significance"), effect.significant ? String(localized: "Significant") : String(localized: "Not yet"),
                            String(format: "p ≈ %.3f", effect.pApprox))
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
                    BroopInsightsBody(text: String(localized: "An association in your own logged days, not a cause. A behaviour needs days both with and without it; significance needs at least five of each."),
                                      size: 12, color: BroopPalette.textTertiary)
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(BroopBackground())
            .broopInsightsChrome(String(localized: "Behavior impact"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ label: String, _ value: String, _ detail: String) -> some View {
        HStack {
            BroopCaps(label, size: 10.5, color: BroopPalette.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: value).font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: detail).font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
        .padding(.vertical, 12)
    }
}
#endif
