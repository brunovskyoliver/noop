#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Health Monitor (`.health`): the live heart-rate hero, the vitals against the wearer's range as a
/// two-column grid (each opens its trend), then everything else the classic Health screen carried — strap
/// sync, HRV status, Charge contributors, the skin-temperature suite, Healthspan, records and the
/// shareable report.
struct BroopHealthMonitorView: View {
    @EnvironmentObject private var repo: Repository

    @State private var vitals = BroopHealthVitalSet()
    @State private var loaded = false
    @State private var showReport = false
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2CandidateOn = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                BroopHealthLiveHeartRate()
                    .padding(.horizontal, -BroopMetrics.page)
                if let banner = calibrationBanner {
                    BroopHealthInfoBanner(symbol: "hourglass", text: banner).padding(.top, 14)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vitals.core) { reading in vitalCell(reading) }
                    if let raw = vitals.raw { vitalCell(raw) }
                }
                .padding(.top, 18)

                Button { showReport = true } label: {
                    HStack(spacing: 22) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(BroopPalette.textSecondary)
                        BroopCaps(String(localized: "Share your health report"), size: 13)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 40)
                BroopHealthFootnote(text: String(localized: "Printable report of recovery, sleep, HRV, resting HR, strain and stress over a range you choose, saved on your \(Platform.deviceNoun)."))
                    .padding(.top, 12)

                BroopHealthSyncCard().padding(.top, BroopMetrics.section)
                BroopHealthHRVStatusCard(showsLink: true).padding(.top, 12)
                BroopHealthChargeContributors().padding(.top, 12)
                BroopHealthSkinTempSection().padding(.top, BroopMetrics.section)

                VStack(spacing: 10) {
                    NavigationLink(value: BroopScreen.healthspan) {
                        BroopHealthRow(symbol: "hourglass", title: String(localized: "Healthspan & Fitness Age"))
                    }
                    NavigationLink(value: BroopScreen.labBook) {
                        BroopHealthRow(symbol: "books.vertical", title: String(localized: "Lab Book"),
                                       detail: String(localized: "Bloods, BP and body numbers, private on \(Platform.deviceNounPhrase)."))
                    }
                    NavigationLink(value: BroopScreen.fusedRecord) {
                        BroopHealthRow(symbol: "square.stack.3d.up", title: String(localized: "Your Data, Fused"),
                                       detail: String(localized: "The best-sourced number per metric across every band you use."))
                    }
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, BroopMetrics.section)

                BroopHealthFootnote(text: String(localized: "Once NOOP has 14 nights of history, in-range compares each vital to your own baseline (approximate, not medical advice); until then, typical adult ranges apply."))
                    .padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Health Monitor")) }
        .broopHealthScreen()
        .task(id: "\(repo.refreshSeq)|\(spo2CandidateOn)") {
            vitals = await BroopHealthVitalSet.load(repo: repo)
            loaded = true
        }
        .sheet(isPresented: $showReport) { TrendsReportSheet(days: repo.days) }
    }

    /// Shown while the personal baseline is still being learned (population ranges in use).
    private var calibrationBanner: String? {
        guard loaded else { return nil }
        let data = vitals.withData
        guard !data.isEmpty else {
            return String(localized: "Wear your strap overnight to see your vitals against your range.")
        }
        let personal = data.filter { $0.banding.basis == .personal }
        guard personal.isEmpty else { return nil }
        let nights = data.map(\.banding.nights).max() ?? 0
        let left = max(Baselines.minNightsSeed - nights, 1)
        return left == 1 ? String(localized: "Log 1 more sleep to start calibrating your ranges.")
            : String(localized: "Log \(left) more sleeps to start calibrating your ranges.")
    }

    @ViewBuilder
    private func vitalCell(_ reading: BodyVitalReading) -> some View {
        if let key = reading.broopMetricKey {
            NavigationLink(value: BroopScreen.metric(key: key, source: "my-whoop")) {
                BroopHealthVitalCard(reading: reading)
            }
            .buttonStyle(BroopPressableStyle())
        } else {
            BroopHealthVitalCard(reading: reading)
        }
    }
}

/// One vital: icon + caps label, big value + unit, status pill, day line.
struct BroopHealthVitalCard: View {
    let reading: BodyVitalReading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: reading.broopSymbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .frame(width: 20)
                BroopCaps(reading.broopTitle, size: 10.5, color: BroopPalette.textBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30, alignment: .topLeading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: reading.value.map(reading.format) ?? "--")
                    .font(BroopType.number(38))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .broopNumeral(38)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if reading.value != nil, !reading.unit.isEmpty {
                    Text(verbatim: reading.unit)
                        .font(BroopType.medium(16))
                        .foregroundStyle(BroopPalette.textPrimary)
                }
            }
            .padding(.top, 14)
            BroopHealthStatusPill(tone: reading.broopTone, text: reading.broopStateText)
                .padding(.top, 10)
            Text(verbatim: reading.broopFootnote)
                .font(BroopType.regular(11.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .lineLimit(2)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopHealthPalette.vitalCard))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: reading.accessibilityText))
    }
}

// MARK: - Sync

/// Manual "Sync now" and honest sync status (#364), gated exactly as the classic control.
struct BroopHealthSyncCard: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel

    private var canSync: Bool { live.connected && live.bonded && live.historyReady && !live.backfilling }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BroopCaps(String(localized: "Strap sync"), size: 12.5)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(live.connected ? BroopPalette.connected : BroopPalette.textTertiary)
                        .frame(width: 7, height: 7)
                    BroopCaps(live.connected ? (live.bonded ? String(localized: "Connected") : String(localized: "Pairing…"))
                              : String(localized: "Offline"), size: 10, color: BroopPalette.textSecondary)
                }
            }
            Text(verbatim: status)
                .font(BroopType.medium(15))
                .foregroundStyle(BroopPalette.textPrimary)
            BroopHealthButton(title: live.backfilling ? String(localized: "Syncing…") : String(localized: "Sync now"),
                              symbol: "arrow.triangle.2.circlepath", kind: .secondary) {
                model.startUserSync()
            }
            .disabled(!canSync)
            BroopHealthCatchUp(controller: model.syncCatchUp, cancel: model.cancelUserSync)
            Text(verbatim: helper)
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private var status: String {
        if live.backfilling {
            return live.syncChunksThisSession > 0
                ? String(localized: "Syncing history · \(live.syncChunksThisSession) chunks")
                : String(localized: "Syncing history…")
        }
        if !live.connected { return String(localized: "No strap connected") }
        if let last = live.lastSyncedAt {
            return String(localized: "History synced \(relativeAgo(last))")
        }
        return live.historyReady ? String(localized: "Ready to sync") : String(localized: "Pairing…")
    }

    private var helper: String {
        if live.backfilling {
            return String(localized: "Pulling your strap's stored history. This drains oldest-first; a deep backlog now continues automatically across passes instead of waiting between syncs.")
        }
        if !live.connected {
            return String(localized: "Connect your strap to sync its stored history. Until then, only imported data shows here.")
        }
        if !live.historyReady {
            return String(localized: "Finishing the pairing handshake. Sync now becomes available once the strap is paired.")
        }
        return String(localized: "Syncs your strap's stored history right away, instead of waiting for the next automatic sync.")
    }
}

/// The finite catch-up operation, observed separately from the live stream.
private struct BroopHealthCatchUp: View {
    @ObservedObject var controller: SyncCatchUpTask
    let cancel: () -> Void

    var body: some View {
        if let status = controller.status {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if controller.isRunning { ProgressView().controlSize(.small).tint(BroopPalette.textPrimary) }
                    Text(verbatim: status)
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if controller.isRunning {
                    Button(action: cancel) {
                        BroopCaps(String(localized: "Pause catch-up"), size: 10.5, color: BroopHealthPalette.chartBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - HRV status

/// The 7-night HRV status against the usual range (`HRVStatus`, classic `HRVStatusSection` rebuilt).
struct BroopHealthHRVStatusCard: View {
    @EnvironmentObject private var model: AppModel
    var showsLink = false

    var body: some View {
        // AppModel republishes about once a second; only the illness flag matters here, and the card below
        // is equatable on it, so a tick re-runs this line and nothing else.
        let unwell = model.illnessSignal.map { $0.level == .raised || $0.level == .alreadyUnwell } == true
        BroopHealthHRVStatusContent(unwell: unwell, showsLink: showsLink).equatable()
    }
}

/// The HRV status card itself: the history pass runs once per data refresh, not per render.
private struct BroopHealthHRVStatusContent: View, Equatable {
    let unwell: Bool
    let showsLink: Bool
    @EnvironmentObject private var repo: Repository
    @State private var outcome: HRVStatus.Outcome?

    static func == (a: Self, b: Self) -> Bool { a.unwell == b.unwell && a.showsLink == b.showsLink }

    var body: some View {
        Group {
            if let outcome { linked(outcome) }
        }
        .task(id: "\(repo.refreshSeq)|\(unwell)") {
            let nights = repo.days.map { HRVStatus.Night(day: $0.day, rmssd: $0.avgHrv) }
            let today = Repository.dayString(Date())
            let flagged: Set<String> = unwell ? [today] : []
            outcome = await CancellableAnalysis.run { HRVStatus.evaluate(nights: nights, asOf: today, flaggedDays: flagged) }
        }
    }

    @ViewBuilder
    private func linked(_ outcome: HRVStatus.Outcome) -> some View {
        let content = card(outcome)
        if showsLink {
            NavigationLink(value: BroopScreen.metric(key: "hrv", source: "my-whoop")) { content }
                .buttonStyle(BroopPressableStyle())
        } else {
            content
        }
    }

    private func card(_ o: HRVStatus.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthCardTitle(title: String(localized: "HRV Status"), trailing: String(localized: "7 nights"), chevron: showsLink)
            switch o {
            case .calibrating(let n):
                Text("Learning your usual range: \(n) of \(HRVStatus.minBaselineNights) nights.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            case .noRecentData:
                Text("No HRV from the last few nights. Wear the strap to sleep to update this.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            case .status(let r):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(Int(r.mean7Ms.rounded()))")
                        .font(BroopType.number(34)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(34)
                    Text(verbatim: "ms").font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Text(verbatim: title(r.band)).font(BroopType.demi(16)).foregroundStyle(color(r.band))
                }
                rangeBar(r)
                Text("Usual \(Int(r.usualLowMs.rounded()))–\(Int(r.usualHighMs.rounded())) ms · 7-night average")
                    .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                Text(verbatim: detail(r.band)).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                if r.mayReflectFlaggedDays {
                    Text("This week may reflect feeling unwell.")
                        .font(BroopType.regular(13)).foregroundStyle(BroopHealthPalette.amber)
                }
                if r.tentative {
                    Text("Based on \(r.shortNights) of the last 7 nights.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func rangeBar(_ r: HRVStatus.Reading) -> some View {
        let lo = min(r.lowMs, r.mean7Ms) * 0.95, hi = max(r.usualHighMs, r.mean7Ms) * 1.05
        func x(_ v: Double, _ w: CGFloat) -> CGFloat { CGFloat((v - lo) / (hi - lo)) * w }
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track).frame(height: 5)
                Capsule().fill(BroopPalette.textSecondary.opacity(0.7))
                    .frame(width: max(2, x(r.usualHighMs, w) - x(r.usualLowMs, w)), height: 5)
                    .offset(x: x(r.usualLowMs, w))
                Circle().fill(color(r.band)).frame(width: 11, height: 11)
                    .offset(x: min(max(0, x(r.mean7Ms, w) - 5.5), w - 11))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func title(_ b: HRVStatus.Band) -> String {
        switch b {
        case .balanced: return String(localized: "Balanced")
        case .above: return String(localized: "Above usual")
        case .below: return String(localized: "Below usual")
        case .low: return String(localized: "Low")
        }
    }

    private func detail(_ b: HRVStatus.Band) -> String {
        switch b {
        case .balanced: return String(localized: "Your 7-night HRV is within your usual range.")
        case .above: return String(localized: "Higher than usual. This can follow rest, or heavy fatigue.")
        case .below: return String(localized: "Lower than usual. Keep an eye on recovery and training load.")
        case .low: return String(localized: "Well below your usual range. An easier day may help.")
        }
    }

    private func color(_ b: HRVStatus.Band) -> Color {
        switch b {
        case .balanced: return BroopHealthPalette.mint
        case .above: return BroopPalette.textPrimary
        case .below: return BroopHealthPalette.amber
        case .low: return BroopPalette.bandLow
        }
    }
}

// MARK: - Charge contributors

/// The inputs to today's Charge as bars scored against the on-device baseline. Same arithmetic as the
/// classic `RecoveryContributorsSection` (70 at baseline), so the two can never read differently.
struct BroopHealthChargeContributors: View {
    @EnvironmentObject private var repo: Repository

    private struct Row: Identifiable {
        let id: String
        let label: String
        let strength: Double?
        let detail: String
    }

    var body: some View {
        let latest = repo.days.last
        let priorCount = repo.days.dropLast().compactMap(\.avgHrv).filter { $0 > 0 }.count
        let ready = priorCount >= Baselines.minNightsSeed
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BroopCaps(String(localized: "Charge contributors"), size: 12.5)
                Spacer()
                BroopCaps(ready ? String(localized: "vs. baseline")
                          : String(localized: "Calibrating \(priorCount) of \(Baselines.minNightsSeed)"),
                          size: 10, color: BroopPalette.textSecondary)
            }
            ForEach(rows(latest)) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        BroopCaps(row.label, size: 11, color: BroopPalette.textBody)
                        Text(verbatim: ready ? word(row.strength) : String(localized: "Calibrating"))
                            .font(BroopType.demi(13))
                            .foregroundStyle(ready && row.strength != nil ? BroopHealthPalette.mint : BroopPalette.textSecondary)
                        Spacer()
                        Text(verbatim: row.detail).font(BroopType.number(16)).foregroundStyle(BroopPalette.textPrimary)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BroopPalette.track)
                            Capsule().fill(BroopHealthPalette.stressMedium.opacity(0.85))
                                .frame(width: g.size.width * CGFloat((ready ? (row.strength ?? 0) : 0) / 100))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Baselines are learned on-device over your first 14 days. Until then, typical ranges apply.")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func rows(_ latest: DailyMetric?) -> [Row] {
        let hrvBase = baseline { $0.avgHrv }
        let rhrBase = baseline { $0.restingHr.map(Double.init) }
        let sleepBase = baseline { $0.totalSleepMin }
        let respBase = baseline { $0.respRateBpm }
        return [
            Row(id: "hrv", label: String(localized: "HRV"),
                strength: higher(latest?.avgHrv, hrvBase),
                detail: latest?.avgHrv.map { "\(Int($0.rounded())) ms" } ?? "–"),
            Row(id: "rhr", label: String(localized: "Resting HR"),
                strength: lower(latest?.restingHr.map(Double.init), rhrBase),
                detail: latest?.restingHr.map { "\($0) bpm" } ?? "–"),
            Row(id: "sleep", label: String(localized: "Sleep"),
                strength: higher(latest?.totalSleepMin, sleepBase),
                detail: latest?.totalSleepMin.map { BroopFormat.duration($0) } ?? "–"),
            Row(id: "resp", label: String(localized: "Respiratory"),
                strength: lower(latest?.respRateBpm, respBase),
                detail: latest?.respRateBpm.map { String(format: "%.1f rpm", $0) } ?? "–"),
        ]
    }

    private func baseline(_ key: (DailyMetric) -> Double?) -> Double? {
        let prior = repo.days.dropLast().compactMap(key).filter { $0 > 0 }
        guard prior.count >= Baselines.minNightsSeed else { return nil }
        return prior.reduce(0, +) / Double(prior.count)
    }
    private func higher(_ v: Double?, _ base: Double?) -> Double? {
        guard let v, let base, base > 0 else { return nil }
        return min(100, max(0, 70 + (v / base - 1) * 100))
    }
    private func lower(_ v: Double?, _ base: Double?) -> Double? {
        guard let v, let base, base > 0 else { return nil }
        return min(100, max(0, 70 - (v / base - 1) * 200))
    }
    private func word(_ s: Double?) -> String {
        guard let s else { return "–" }
        switch s {
        case ..<40: return String(localized: "Low")
        case ..<60: return String(localized: "Fair")
        case ..<78: return String(localized: "Good")
        default: return String(localized: "Strong")
        }
    }
}

// MARK: - Skin temperature suite

/// The v5 skin-temperature suite: illness heads-up, body clock and the opt-in cycle awareness. The three
/// cards are the classic components (their engines' copy and controls are dense and shared with Android),
/// shown under the Broop skin; the opt-in/opt-out gating is the classic rule.
struct BroopHealthSkinTempSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleEnabled = false
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false
    @State private var trackerPresented = false

    private var optInApplies: Bool { model.profile.cycleAwarenessApplies && !cycleHidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Skin temperature"), trailing: String(localized: "Nightly sensor"))
            if let illness = model.illnessSignal, illness.level != .quiet {
                HeadsUpCard(result: illness, distance: model.illnessDistance)
            }
            if let phase = model.circadianPhase {
                BodyClockCard(estimate: phase)
            }
            if cycleEnabled, let cycle = model.cyclePhase {
                CycleAwarenessCard(result: cycle, curve: model.cycleCurve,
                                   onLogPeriod: {
                                       Task {
                                           await repo.logPeriodStart(day: Repository.localDayKey(Date()))
                                           await model.refreshV5Signals()
                                       }
                                   },
                                   onOpenDetail: { trackerPresented = true },
                                   onTurnOff: {
                                       cycleEnabled = false
                                       model.cycleAwarenessEnabled = false
                                       Task { await model.refreshV5Signals() }
                                   })
            } else if !cycleEnabled && optInApplies {
                CycleAwarenessOptInCard(onEnable: {
                    cycleEnabled = true
                    model.cycleAwarenessEnabled = true
                    Task { await model.refreshV5Signals() }
                })
            }
            if (cycleEnabled || !optInApplies)
                && model.illnessSignal == nil && model.circadianPhase == nil && model.cyclePhase == nil {
                BroopHealthCard {
                    HStack(spacing: 12) {
                        Image(systemName: "thermometer.medium").font(.system(size: 18, weight: .light))
                            .foregroundStyle(BroopPalette.textSecondary)
                        Text("Wear the strap overnight and these read from your nightly skin temperature.")
                            .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .sheet(isPresented: $trackerPresented) {
            if let cycle = model.cyclePhase {
                CycleTrackerView(result: cycle, curve: model.cycleCurve)
                    .environmentObject(repo)
                    .environmentObject(model)
            }
        }
    }
}
#endif
