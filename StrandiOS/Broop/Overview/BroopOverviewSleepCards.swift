#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// The Rest deep dive's secondary cards: freshness, naps, sleep marks, the tonight plan, the debt ledger,
// statistics and stages against typical. Each reads the same model or store the Sleep card does.

/// Small amber-chip note ("Low confidence", "May be incomplete").
struct BroopOverviewNote: View {
    let chip: String
    let text: String
    var tint: Color = BroopPalette.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BroopCaps(chip, size: 9, color: tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.16)))
            Text(verbatim: text)
                .font(BroopType.medium(13))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Whether last night is still syncing, calculating or missing, through the Sleep screen's own
/// `resolveSleepFreshness` ladder. Owns the live observations so their ticks stay in this leaf.
struct BroopOverviewSleepFreshness: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var intelligence: IntelligenceEngine
    let latestWakeTs: Int?
    /// True when today's Rest is scored from today's own row: last night is in, even with no session here.
    var nightScored = false

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let current = nightScored
            || (latestWakeTs.map { calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0)), inSameDayAs: now) } ?? false)
        let queued = live.lastSyncedAt.map { (0..<5).contains(now.timeIntervalSince1970 - $0) } ?? false
        let status = resolveSleepFreshness(
            hasCurrentNight: current,
            morningReady: calendar.component(.hour, from: now) >= 6,
            syncing: live.backfilling,
            calculating: intelligence.computing || queued,
            syncedSinceDayStart: (live.lastSyncedAt ?? 0) >= start.timeIntervalSince1970,
            syncFailed: live.lastSyncError != nil)
        if let status {
            let (title, body, symbol) = copy(status)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(BroopPalette.rest)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                    Text(verbatim: body).font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func copy(_ s: SleepFreshnessStatus) -> (String, String, String) {
        switch s {
        case .syncing:
            return (String(localized: "Syncing strap history…"),
                    String(localized: "\(live.syncChunksThisSession) chunks so far. Last night appears when the sync finishes."),
                    "arrow.triangle.2.circlepath")
        case .calculating:
            return (String(localized: "Calculating last night's sleep…"),
                    String(localized: "Your strap history is in. NOOP is detecting and staging the night now."), "waveform.path.ecg")
        case .syncFailed:
            return (String(localized: "Last night's sleep hasn't synced"),
                    String(localized: "The history sync stopped before it finished. Keep the strap nearby and try Sync again."),
                    "exclamationmark.arrow.triangle.2.circlepath")
        case .awaitingSync:
            return (String(localized: "Waiting for last night's sleep"),
                    String(localized: "Connect the strap and sync its history. NOOP will calculate the night when the overnight data arrives."),
                    "arrow.triangle.2.circlepath")
        case .notDetected:
            return (String(localized: "Last night's sleep wasn't detected"),
                    String(localized: "Sync finished, but NOOP couldn't confidently identify a sleep window. Keep the strap connected and try Sync again."),
                    "moon.zzz")
        }
    }
}

// MARK: - Naps

/// The day's sleep blocks outside the main night, each editable, plus Add Nap.
struct BroopOverviewNapsCard: View {
    let night: Night
    let onAdd: () -> Void
    let onEdit: (CachedSleepSession) -> Void

    var body: some View {
        let groupStarts = night.mainGroupStarts
        let naps = night.sourceBlocks.filter { !groupStarts.contains($0.startTs) }.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        let napMin = naps.reduce(0.0) { $0 + Double($1.endTs - $1.effectiveStartTs) / 60.0 }
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(title: String(localized: "Naps")) {
                BroopOverviewCapsButton(title: String(localized: "Add nap"), symbol: "plus", action: onAdd)
            }
            BroopOverviewCard(padding: 14) {
                VStack(spacing: 10) {
                    if naps.isEmpty {
                        Text("No naps recorded for this day.")
                            .font(BroopType.medium(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    } else {
                        HStack {
                            summary(String(localized: "Main sleep"), night.stages.total)
                            summary(String(localized: "Naps"), napMin)
                            summary(String(localized: "Total"), night.stages.total + napMin)
                        }
                        .padding(.bottom, 4)
                        ForEach(naps, id: \.startTs) { nap in
                            Button { onEdit(nap) } label: {
                                HStack(spacing: 12) {
                                    BroopOverviewActivityRow(
                                        symbol: "powersleep",
                                        value: BroopFormat.duration(Double(nap.endTs - nap.effectiveStartTs) / 60),
                                        color: BroopPalette.rest,
                                        name: String(localized: "Nap"),
                                        start: Date(timeIntervalSince1970: TimeInterval(nap.effectiveStartTs)),
                                        end: Date(timeIntervalSince1970: TimeInterval(nap.endTs)))
                                }
                            }
                            .buttonStyle(BroopPressableStyle())
                            .accessibilityHint(Text("Edit nap times"))
                        }
                        Text("Logged as a nap because it is outside your main sleep. Tap a nap to change its times or delete it.")
                            .font(BroopType.medium(12))
                            .foregroundStyle(BroopPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func summary(_ label: String, _ minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: BroopFormat.duration(minutes)).font(BroopType.number(19)).foregroundStyle(BroopPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sleep marks

/// "Going to sleep" / "I'm awake" marks, logged exactly as the card logs them: a strap-log line
/// and a `sleep_mark` metric-series row. Logging only; it never moves the detected night.
struct BroopOverviewSleepMarks: View {
    @EnvironmentObject private var repo: Repository
    @State private var lastMark: SleepMark?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Sleep Marks"))
            BroopOverviewCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tap when you're heading to bed or when you wake. Each tap is logged with the time. It doesn't change tonight's detected sleep.")
                        .font(BroopType.medium(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        BroopOverviewFillButton(symbol: "moon.zzz", title: String(localized: "Going to sleep")) { log(.bedtime) }
                        BroopOverviewFillButton(symbol: "sun.max", title: String(localized: "I'm awake")) { log(.wake) }
                    }
                    if let lastMark {
                        Text(verbatim: lastMark.confirmation)
                            .font(BroopType.medium(13))
                            .foregroundStyle(BroopPalette.rest)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: lastMark?.tsMs ?? 0)
    }

    private func log(_ type: SleepMarkType) {
        let mark = SleepMark(type: type)
        withAnimation(.easeOut(duration: 0.2)) { lastMark = mark }
        AppModel.shared?.live.append(log: mark.logLine)  // not observed: marks must not follow the live stream
        Task {
            guard let store = await repo.storeHandle() else { return }
            _ = try? await store.upsertMetricSeries([mark.metricPoint], deviceId: repo.deviceId)
        }
    }
}

// MARK: - Tonight plan

/// Tonight's planner read: bedtimes for all / most / the minimum of the need, and how the need is built.
/// The same `AppModel.tonightPlan` the Home card, caffeine cutoff and wind-down reminder read.
struct BroopOverviewPlannerCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository

    var body: some View {
        BroopOverviewPlannerContent(plan: model.tonightPlan).equatable()
            .task(id: repo.refreshSeq) { await model.refreshTonightPlan() }
    }
}

struct BroopOverviewPlannerContent: View, Equatable {
    let plan: SleepPlanner.Plan?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(title: String(localized: "Sleep Planner")) {
                NavigationLink(value: BroopScreen.alarms) {
                    HStack(spacing: 8) {
                        BroopCaps(String(localized: "Alarm"), size: 11.5)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(BroopPalette.textPrimary)
                }
                .buttonStyle(BroopPressableStyle())
            }
            BroopOverviewCard {
                if let plan {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: BroopOverviewFormat.clock(plan.target.bedMinute))
                                    .font(BroopType.number(32)).broopNumeral(32)
                                    .foregroundStyle(BroopPalette.textPrimary)
                                BroopCaps(String(localized: "Suggested time to bed"), size: 10, color: BroopPalette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(verbatim: BroopOverviewFormat.clock(plan.wakeMinute))
                                    .font(BroopType.number(32)).broopNumeral(32)
                                    .foregroundStyle(BroopPalette.textPrimary)
                                BroopCaps(String(localized: "Your wake time"), size: 10, color: BroopPalette.textSecondary)
                            }
                        }
                        timeInBed(plan)
                        if !plan.target.reachable {
                            Text("All of your need would mean going to bed much earlier than usual. Spread the rest over the next few nights.")
                                .font(BroopType.medium(13))
                                .foregroundStyle(BroopPalette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 8) {
                            ForEach(Array(plan.tiers.dropFirst().enumerated()), id: \.offset) { _, tier in
                                row(tier.fraction >= 0.8 ? String(localized: "Most of your need (85%)") : String(localized: "The minimum (70%)"),
                                    BroopOverviewFormat.clock(tier.bedMinute))
                            }
                        }
                        Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1)
                        VStack(spacing: 8) {
                            row(String(localized: "Sleep need"), BroopFormat.duration(plan.needMin), bold: true)
                            row(String(localized: "Baseline"), BroopFormat.duration(plan.baseNeedMin))
                            row(String(localized: "Sleep debt"), "+" + BroopFormat.duration(plan.debtAddMin))
                            row(String(localized: "Recent naps"), "−" + BroopFormat.duration(plan.napSubMin))
                        }
                        Text("Assumes \(Int((plan.efficiency * 100).rounded()))% sleep efficiency and \(Int(plan.latencyMin)) min to fall asleep. The wake time is your strap alarm, or your usual wake time in Alarms.")
                            .font(BroopType.medium(12))
                            .foregroundStyle(BroopPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Working out tonight's bedtime…")
                        .font(BroopType.medium(14))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
    }

    /// The hatched time-in-bed bar with the duration pill.
    private func timeInBed(_ plan: SleepPlanner.Plan) -> some View {
        let minutes = Double(((plan.wakeMinute - plan.target.bedMinute) % 1440 + 1440) % 1440)
        return VStack(spacing: 6) {
            BroopCaps(String(localized: "Time in bed"), size: 9.5, color: BroopPalette.textSecondary)
            ZStack {
                BroopOverviewHatch()
                    .frame(height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(verbatim: BroopFormat.duration(minutes))
                    .font(BroopType.number(14))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white))
            }
        }
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(verbatim: label).font(bold ? BroopType.demi(14) : BroopType.medium(14))
                .foregroundStyle(bold ? BroopPalette.textPrimary : BroopPalette.textBody)
            Spacer()
            Text(verbatim: value).font(BroopType.number(15)).foregroundStyle(BroopPalette.textPrimary)
        }
    }
}

// MARK: - Sleep debt

/// The recency-weighted debt over the last 14 nights (`SleepModel.sleepDebtLedger`, as the card).
struct BroopOverviewDebtCard: View {
    let ledger: SleepDebtLedger

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Sleep Debt"),
                                      subtitle: Text("Last 14 nights").foregroundColor(BroopPalette.textSecondary))
            BroopOverviewCard {
                if ledger.nightCount == 0 {
                    Text("No nights with sleep data yet. Your ledger fills in as you wear the strap to bed.")
                        .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        let onTarget = ledger.magnitudeMin < SleepDebt.onTargetBandMin
                        let color = onTarget || !ledger.isDebt ? BroopOverviewPalette.optimal
                            : (ledger.magnitudeMin < 180 ? BroopOverviewPalette.poor : BroopPalette.bandLow)
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: onTarget ? String(localized: "On target") : BroopFormat.duration(ledger.magnitudeMin))
                                .font(BroopType.number(32)).broopNumeral(32, color: color)
                                .foregroundStyle(color)
                            Spacer()
                            BroopCaps(onTarget || !ledger.isDebt ? String(localized: "Balanced") : String(localized: "Sleep debt"),
                                      size: 10.5, color: color)
                        }
                        Text(verbatim: read(onTarget: onTarget))
                            .font(BroopType.medium(14))
                            .foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                        bars
                        HStack {
                            stat(String(localized: "Balance"), signed(ledger.balanceMin))
                            stat(String(localized: "Per-night need"), BroopFormat.duration(ledger.needMin))
                            stat(String(localized: "Nights"), "\(ledger.nightCount)")
                        }
                    }
                }
            }
        }
    }

    private func read(onTarget: Bool) -> String {
        if onTarget || !ledger.isDebt {
            return String(localized: "You've effectively met your current sleep need across the last \(ledger.nightCount) nights.")
        }
        return String(localized: "Add about \(BroopFormat.duration(ledger.magnitudeMin)) to your base sleep target tonight. Meeting that complete sleep need clears the debt; recent shortfalls carry forward at a reduced weight.")
    }

    private var bars: some View {
        let deltas = ledger.nights.map(\.deltaMin)
        let scale = max(deltas.map { abs($0) }.max() ?? 1, 1)
        return GeometryReader { geo in
            let n = max(deltas.count, 1)
            let slot = geo.size.width / CGFloat(n)
            let mid = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1).position(x: geo.size.width / 2, y: mid)
                ForEach(Array(deltas.enumerated()), id: \.offset) { i, d in
                    let h = max(2, CGFloat(abs(d) / scale) * (mid - 2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d >= 0 ? BroopPalette.rest : BroopOverviewPalette.poor)
                        .frame(width: max(2, slot * 0.55), height: h)
                        .position(x: slot * CGFloat(i) + slot / 2, y: d >= 0 ? mid - h / 2 : mid + h / 2)
                }
            }
        }
        .frame(height: 56)
        .accessibilityLabel(Text(verbatim: "Per-night sleep balance: \(ledger.nightCount) nights, net \(signed(ledger.balanceMin))"))
    }

    private func signed(_ m: Double) -> String {
        abs(m) < 1 ? "0:00" : (m >= 0 ? "+" : "−") + BroopFormat.duration(abs(m))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Statistics

/// The seven Night-detail metrics (latest night, from `SleepModel`) against their typical, in
/// dashboard-row form, each opening its trend page.
struct BroopOverviewSleepStatsCard: View {
    let model: SleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Sleep Statistics"),
                                      subtitle: Text("Latest night vs. your typical").foregroundColor(BroopPalette.textSecondary))
            VStack(spacing: 10) {
                row("sleep_performance", "moon", String(localized: "Sleep Performance"), model.performance, pct)
                row("hours_vs_needed_pct", "clock", String(localized: "Hours vs. Needed"), model.hoursVsNeeded, pct)
                // The imported WHOOP consistency has a stored trend; the 7-day regularity is computed here.
                row(model.consistencyIsImported ? "sleep_consistency" : nil, "moon.stars",
                    model.consistencyIsImported ? String(localized: "Sleep Consistency")
                                                : String(localized: "Sleep regularity, 7 days"),
                    model.consistency, pct)
                row("sleep_efficiency", "bed.double", String(localized: "Sleep Efficiency"), model.efficiency, pct)
                row("restorative_pct", "sparkles", String(localized: "Restorative Sleep"), model.restorative, pct)
                row("resp_rate", "lungs", String(localized: "Respiratory Rate"), model.respiratory) { BroopFormat.one($0) }
                row("sleep_debt_min", "arrow.down.right", String(localized: "Sleep Debt"), model.sleepDebt) { BroopFormat.duration($0) }
            }
        }
    }

    private func pct(_ v: Double) -> String { BroopFormat.whole(v) + "%" }

    @ViewBuilder
    private func row(_ key: String?, _ symbol: String, _ label: String, _ m: SleepModel.Metric,
                     _ format: @escaping (Double) -> String) -> some View {
        if let key {
            NavigationLink(value: BroopScreen.metric(key: key, source: nil)) { rowBody(symbol, label, m, format) }
                .buttonStyle(BroopPressableStyle())
        } else {
            rowBody(symbol, label, m, format)
        }
    }

    private func rowBody(_ symbol: String, _ label: String, _ m: SleepModel.Metric,
                         _ format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(label, size: 11)
                if let carried = SleepModel.carriedMetricCaption(latestDay: m.latestDay, latest: m.latest) {
                    Text(verbatim: carried).font(BroopType.medium(11.5)).foregroundStyle(BroopPalette.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: m.latest.map(format) ?? "--")
                    .font(BroopType.number(21)).broopNumeral(21)
                    .foregroundStyle(BroopPalette.textPrimary)
                if let t = m.typical {
                    Text(verbatim: format(t)).font(BroopType.number(12.5)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
    }
}

/// Deep, REM and light for the night against each stage's 30-night mean (`SleepModel.typical*`).
struct BroopOverviewStagesVsTypical: View {
    let stages: Stages
    let model: SleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Stages vs. Typical"))
            BroopOverviewCard {
                VStack(spacing: 16) {
                    row(.deep, stages.deep, model.typicalDeepMin)
                    row(.rem, stages.rem, model.typicalRemMin)
                    row(.light, stages.light, model.typicalLightMin)
                }
            }
        }
    }

    private func row(_ stage: SleepStage, _ minutes: Double, _ typical: Double?) -> some View {
        let top = max(minutes, typical ?? 0) * 1.15
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                BroopCaps(stage.broopTitle, size: 11)
                Spacer()
                Text(verbatim: BroopFormat.duration(minutes)).font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
                if let typical, typical > 0 {
                    let d = minutes - typical
                    Text(verbatim: (d >= 0 ? "+" : "−") + BroopFormat.duration(abs(d)))
                        .font(BroopType.demi(12))
                        .foregroundStyle(d >= 0 ? BroopOverviewPalette.optimal : BroopOverviewPalette.poor)
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    BroopOverviewHatch()
                    Rectangle().fill(stage.broopColor)
                        .frame(width: top > 0 ? geo.size.width * CGFloat(minutes / top) : 0)
                    if let typical, top > 0 {
                        Rectangle().fill(Color.white).frame(width: 2)
                            .offset(x: geo.size.width * CGFloat(typical / top) - 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 12)
        }
    }
}
#endif
