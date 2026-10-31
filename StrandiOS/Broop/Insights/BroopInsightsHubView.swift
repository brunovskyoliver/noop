#if os(iOS)
import SwiftUI
import StrandAnalytics

// What Moves You: the lag-aware ranked mover feed and the alcohol / caffeine dose-response, drawn in WHOOP's
// Journal Insights language (signed percent + diverging bar per behaviour, a behaviour-detail sheet) and a
// report-style dose card. Data: the `InsightsHubViewModel` (EffectRanker + DoseResponseEngine).

struct BroopInsightsHubView: View {
    typealias Outcome = InsightsHubViewModel.Outcome

    @EnvironmentObject private var repo: Repository
    @StateObject private var model = InsightsHubViewModel()
    @State private var outcome: Outcome = .recovery
    @State private var detail: RankedEffect?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    BroopCaps(String(localized: "Ranked · your data"), size: 10.5, color: BroopPalette.textSecondary)
                    BroopInsightsHeadline(text: String(localized: "What moves your \(outcome.outcomeName.lowercased())"), size: 26)
                    BroopInsightsBody(text: String(localized: "Patterns in your own data: association, not cause. Each behaviour keeps the lag that reads strongest, same day or up to two mornings later."),
                                      color: BroopPalette.textSecondary)
                }
                .padding(.top, 8)
                BroopUnderlineTabs(options: Outcome.allCases, selection: $outcome) { $0.label }
                    .padding(.top, 22)
                if !model.loaded {
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    movers.padding(.top, 22)
                    dose.padding(.top, BroopMetrics.section + 8)
                    BroopInsightsNote(symbol: "info.circle", title: String(localized: "How to read this"),
                                      text: String(localized: "Everything here is a pattern in your own logged days: an association with an effect size and confidence, never a cause or a diagnosis. Population patterns are shown as \u{201C}typical\u{201D} and are always overridden by your own data once you have enough of it. Approximations, not WHOOP\u{2019}s scores; not a medical device."))
                        .padding(.top, BroopMetrics.section)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .broopInsightsChrome(String(localized: "What moves you"))
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .onChange(of: outcome) { _, o in model.rankFor(o) }
        .sheet(item: Binding(get: { detail.map { BroopInsightsEffectBox(effect: $0.effect, sentence: $0.sentence()) } },
                             set: { if $0 == nil { detail = nil } })) { box in
            BroopInsightsBehaviorDetail(effect: box.effect,
                                        outcome: InsightsRules.Outcome(rawValue: outcome.rawValue) ?? .recovery,
                                        sentence: box.sentence)
        }
    }

    private var rulesOutcome: InsightsRules.Outcome { InsightsRules.Outcome(rawValue: outcome.rawValue) ?? .recovery }

    @ViewBuilder private var movers: some View {
        if model.ranked.isEmpty {
            BroopInsightsNote(symbol: "hourglass", title: nil,
                              text: String(localized: "Not enough overlap between your journal answers and \(outcome.outcomeName.lowercased()) yet. Keep logging. Each behaviour needs days both with and without it before Broop can read its effect."))
        } else {
            VStack(spacing: 10) {
                BroopInsightsImpactLegend().padding(.horizontal, 4).padding(.bottom, 4)
                let scale = max(10, model.ranked.map { abs(BroopInsightsImpactView.percent($0.effect)) }.max() ?? 10)
                ForEach(Array(model.ranked.enumerated()), id: \.offset) { _, r in
                    Button { detail = r } label: { moverCard(r, scale: scale) }
                        .buttonStyle(BroopPressableStyle())
                }
            }
        }
    }

    private func moverCard(_ r: RankedEffect, scale: Double) -> some View {
        let e = r.effect
        let tint = BroopInsightsImpactView.tint(e, outcome: rulesOutcome)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(r.behavior, size: 12).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 10)
                Text(verbatim: e.pctChange.map(BroopInsightsFormat.signedPercent) ?? BroopInsightsImpactModel.formatDelta(e.delta, outcome: rulesOutcome))
                    .font(BroopType.number(21))
                    .foregroundStyle(e.significant ? tint : BroopPalette.textSecondary)
            }
            BroopInsightsImpactBar(fraction: BroopInsightsImpactView.goodness(e, outcome: rulesOutcome) / scale, color: tint)
            HStack(spacing: 8) {
                BroopInsightsChip(text: r.leadLagText, color: BroopPalette.rest)
                BroopInsightsChip(text: Self.confidenceWord(r.confidence), color: Self.confidenceColor(r.confidence))
                Spacer()
                Text(verbatim: String(format: "d = %.2f", e.cohensD))
                    .font(BroopType.number(12)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopInsightsPalette.cardRaised))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: r.sentence()))
    }

    static func confidenceWord(_ c: ScoreConfidence) -> String {
        switch c {
        case .solid: return String(localized: "Solid")
        case .building: return String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    static func confidenceColor(_ c: ScoreConfidence) -> Color {
        switch c {
        case .solid: return BroopInsightsPalette.helps
        case .building: return BroopPalette.textBody
        case .calibrating: return BroopInsightsPalette.hurts
        }
    }

    @ViewBuilder private var dose: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopInsightsSectionRule(title: String(localized: "Dose-response"), trailing: String(localized: "Prior-shrunk"))
            if model.doseCards.isEmpty {
                BroopInsightsNote(symbol: "wineglass", title: nil,
                                  text: String(localized: "Log alcohol or late caffeine with an amount and Broop fits a personal dose curve: how much each extra unit tends to move your numbers. Until then it shows typical patterns, clearly labelled as not yet yours."))
            } else {
                ForEach(model.doseCards) { BroopInsightsDoseCard(card: $0) }
            }
        }
    }
}

/// One dose-response card: the prior-shrunk curve, the honest read, and an evening what-if on the latest
/// outcome. Every number is the engine's (`DoseResponse.perUnit`, `delta(fromDose:toDose:)`).
struct BroopInsightsDoseCard: View {
    let card: InsightsHubViewModel.DoseCard
    @State private var previewDose = 2

    var body: some View {
        let r = card.response
        let accent = card.outcomeName == "HRV" ? BroopPalette.rest : BroopInsightsPalette.helps
        BroopInsightsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: card.symbol).font(.system(size: 15)).foregroundStyle(BroopPalette.textPrimary)
                    BroopCaps(card.title, size: 12)
                    Spacer()
                    BroopInsightsChip(text: BroopInsightsHubView.confidenceWord(r.confidence),
                                      color: BroopInsightsHubView.confidenceColor(r.confidence))
                }
                BroopInsightsBody(text: r.sentence(), size: 14)
                curve(r.curve, accent: accent)
                    .frame(height: 120)
                    .accessibilityLabel(Text(verbatim: r.sentence()))
                if r.priorDominated {
                    banner(String(localized: "Based mostly on typical patterns, not yet yours. Log a few more \(card.unitLabel.lowercased()) days and this becomes yours."))
                } else if r.contradictsPrior {
                    banner(String(localized: "In your data so far, this doesn\u{2019}t move your \(card.outcomeName) the way it typically does."))
                }
                if card.timingProxy {
                    BroopInsightsBody(text: String(localized: "\u{201C}Dose\u{201D} here is timing (later in the day = stronger), not milligrams."),
                                      size: 12, color: BroopPalette.textTertiary)
                }
                BroopHairline()
                forecast(r)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(BroopPalette.textSecondary)
            BroopInsightsBody(text: text, size: 12.5, color: BroopPalette.textSecondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(BroopPalette.row.opacity(0.5)))
    }

    private func curve(_ points: [DoseCurvePoint], accent: Color) -> some View {
        Canvas { ctx, size in
            guard points.count > 1 else { return }
            let maxAbs = max(1, points.map { abs($0.outcomeDelta) }.max() ?? 1)
            func y(_ d: Double) -> CGFloat { size.height - CGFloat((d / maxAbs + 1) / 2) * (size.height - 16) - 8 }
            func x(_ i: Int) -> CGFloat { 8 + CGFloat(i) / CGFloat(points.count - 1) * (size.width - 16) }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0))); zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            ctx.stroke(zero, with: .color(Color.white.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var line = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: x(i), y: y(p.outcomeDelta))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for (i, p) in points.enumerated() {
                let r = CGRect(x: x(i) - 4, y: y(p.outcomeDelta) - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: r), with: .color(BroopPalette.bgBottom))
                ctx.stroke(Path(ellipseIn: r), with: .color(accent), lineWidth: 2)
            }
        }
    }

    @ViewBuilder private func forecast(_ r: DoseResponse) -> some View {
        let delta = r.delta(fromDose: 1, toDose: previewDose)
        let projected = card.latestOutcome.map { max(0, min(card.outcomeCeiling, $0 + delta)) }
        let stepLabel = previewDose <= 1 ? String(localized: "no extra") : card.stepLabel(previewDose)
        VStack(alignment: .leading, spacing: 12) {
            BroopCaps(card.forecastOverline, size: 10.5, color: BroopPalette.textSecondary)
            BroopUnderlineTabs(options: card.doseChoices, selection: $previewDose) { card.doseChoiceLabel($0) }
            BroopInsightsBody(text: sentence(delta: delta, stepLabel: stepLabel), size: 13, color: BroopPalette.textSecondary)
            HStack(spacing: 10) {
                tile(String(localized: "Per extra \(card.unitNoun)"), signed(r.perUnit),
                     r.priorDominated ? String(localized: "typical") : String(localized: "your data"),
                     r.perUnit < 0 ? BroopInsightsPalette.hurts : BroopInsightsPalette.helps)
                tile(String(localized: "Tomorrow\u{2019}s \(card.outcomeName)"),
                     projected.map { "\(Int($0.rounded()))\(card.outcomeSuffix)" } ?? "—",
                     projected != nil ? String(localized: "projected · \(stepLabel)") : String(localized: "needs a recent day"),
                     BroopPalette.textPrimary)
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary).lineLimit(2)
            Text(verbatim: value).font(BroopType.number(22)).foregroundStyle(color)
            Text(verbatim: caption).font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(BroopPalette.row.opacity(0.6)))
    }

    private func sentence(delta: Double, stepLabel: String) -> String {
        if previewDose <= 1 {
            return String(localized: "No extra tonight. Your \(card.outcomeName.lowercased()) forecast stays where it is.")
        }
        let mag = "\(Int(abs(delta).rounded()))\(card.outcomeSuffix)"
        let lower = delta <= 0
        if card.response.priorDominated {
            return lower
                ? String(localized: "A \(stepLabel) tonight tends to line up with about \(mag) lower on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on typical patterns.")
                : String(localized: "A \(stepLabel) tonight tends to line up with about \(mag) higher on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on typical patterns.")
        }
        return lower
            ? String(localized: "A \(stepLabel) tonight tends to line up with about \(mag) lower on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on \(card.response.nUser) of your \(card.unitLabel.lowercased()) days.")
            : String(localized: "A \(stepLabel) tonight tends to line up with about \(mag) higher on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on \(card.response.nUser) of your \(card.unitLabel.lowercased()) days.")
    }

    private func signed(_ v: Double) -> String {
        let rounded = (abs(v) * 10).rounded() / 10
        let sign = v < 0 ? "−" : (v > 0 ? "+" : "")
        let body = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(sign)\(body)\(card.outcomeSuffix)"
    }
}
#endif
