import SwiftUI
import StrandDesign
import StrandAnalytics

/// Tonight's bedtime for all / most / the minimum of the sleep need (`AppModel.tonightPlan`, built by
/// SleepPlanner). The same plan sets the caffeine cutoff and the wind-down reminder, so this card, that
/// cutoff and that reminder can never name different bedtimes.
struct TonightPlanCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Tonight", overline: "Sleep planner")
            NoopCard(tint: StrandPalette.restColor) {
                if let plan = model.tonightPlan {
                    content(plan)
                } else {
                    Text("Working out tonight's bedtime…")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: repo.refreshSeq) { await model.refreshTonightPlan() }
    }

    @ViewBuilder private func content(_ plan: SleepPlanner.Plan) -> some View {
        let target = plan.target
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Bed by").strandOverline()
                Text(verbatim: Self.clock(target.bedMinute))
                    .font(StrandFont.number(34)).foregroundStyle(StrandPalette.textPrimary)
                Text(target.reachable
                     ? String(localized: "for all of tonight's sleep need, \(Self.duration(plan.needMin))")
                     : String(localized: "the earliest that fits your usual bedtime, about \(Self.duration(target.expectedSleepMin)) of sleep"))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !target.reachable {
                Text("All of your need would mean going to bed much earlier than usual. Spread the rest over the next few nights.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(plan.tiers.dropFirst().enumerated()), id: \.offset) { _, tier in
                HStack {
                    Text(tier.fraction >= 0.8 ? String(localized: "Most of your need (85%)")
                                              : String(localized: "The minimum (70%)"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text(verbatim: Self.clock(tier.bedMinute))
                        .font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                }
            }
            Divider().overlay(StrandPalette.hairline)
            ChartFooter([
                ("Base need", Self.duration(plan.baseNeedMin)),
                ("Sleep debt", "+" + Self.duration(plan.debtAddMin)),
                ("Naps", "−" + Self.duration(plan.napSubMin)),
                ("Wake", Self.clock(plan.wakeMinute)),
            ])
            Text("Assumes \(Int((plan.efficiency * 100).rounded()))% sleep efficiency and \(Int(plan.latencyMin)) min to fall asleep. The wake time is your strap alarm, or your usual wake time in Alarms.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What every reader of an unreachable plan says (the planner's median-bedtime guard won): the bedtime
    /// shown is the guarded one, and the rest of the need moves to later nights. One string, so the Body
    /// Clock, the reminder and the caffeine cutoff state the planner's own verdict.
    static var unreachableNote: String {
        String(localized: "Tonight's full sleep need isn't reachable: this is the earliest bedtime that fits your usual one.")
    }

    /// A minute-of-day as the device's short clock format ("22:40" / "10:40 PM").
    static func clock(_ minuteOfDay: Int) -> String {
        var c = DateComponents(); c.hour = minuteOfDay / 60; c.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Minutes as a localized short duration ("8 hr 20 min").
    static func duration(_ minutes: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .short
        f.zeroFormattingBehavior = .dropAll
        let s = f.string(from: (minutes.rounded()) * 60) ?? ""
        return s.isEmpty ? f.string(from: 0) ?? "0" : s
    }
}
