#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// The Rest deep dive and the Sleep screen in one: WHOOP's Sleep Performance ring with its four
/// contributors, the coach read, Last Night's Sleep (heart rate, stages, restorative), naps, and every
/// card of the classic Sleep screen in the wearer's saved order. The ring and the night come from the
/// shared `BroopStore` snapshot, so they match the Home dial for the selected day.
struct BroopOverviewSleepScreen: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(SleepLayoutPrefs.orderKey) private var orderRaw = ""
    @AppStorage(SleepLayoutPrefs.hiddenKey) private var hiddenRaw = ""

    @State private var model: SleepModel?
    @State private var nightHR: [HRBucket] = []
    @State private var habitual: Int??
    @State private var typicals: [SleepStage: BroopOverviewStageTypical] = [:]
    @State private var edit: BroopOverviewSleepEdit?
    @State private var addNap: BroopOverviewSleepEdit?
    @State private var undo: BroopOverviewSleepUndo?
    @State private var showCustomize = false
    @State private var showGuide = false
    @State private var showWhy = false

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            LazyVStack(spacing: 0) {

                if let undo { undoBanner(undo).padding(.top, 8) }
                if store.dayOffset == 0 {
                    BroopOverviewSleepFreshness(latestWakeTs: snap?.night?.session.endTs,
                                                nightScored: snap.map { $0.rest != nil && $0.restCarryCaption == nil } ?? false)
                        .padding(.top, 8)
                }

                BroopOverviewHeroRing(
                    fraction: snap?.rest.map { $0 / 100 },
                    color: BroopPalette.rest,
                    valueText: snap?.rest.map { BroopFormat.whole($0) },
                    unit: "%",
                    label: [String(localized: "Sleep"), String(localized: "Performance")],
                    rating: snap?.rest.map(BroopOverviewRating.performance))
                .padding(.top, 22)
                if let caption = snap?.restCarryCaption {
                    BroopCaps(caption, size: 10, color: BroopPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }

                BroopOverviewContributorCard(rows: contributors(snap)) { BroopOverviewRatingLegend() }
                    .padding(.top, 30)

                BroopOverviewCoachCard(text: coachText(snap),
                                       link: coachEnabled ? String(localized: "Learn more with Coach") : nil,
                                       action: coachEnabled ? { router.openCoach() } : nil)
                    .padding(.top, 20)

                lastNight(snap).padding(.top, BroopMetrics.section)

                ForEach(sections, id: \.self) { section in
                    sectionView(section, snap).padding(.top, BroopMetrics.section)
                }

                BroopOverviewSleepHeartRateCards(day: snap?.dayKey ?? Repository.logicalDayKey(Date()))
                    .padding(.top, BroopMetrics.section)

                BroopOverviewTrendCard(metrics: BroopOverviewTrendMetric.restSet, dayKey: snap?.dayKey ?? Repository.logicalDayKey(Date()))
                    .padding(.top, BroopMetrics.section)

                NavigationLink(value: BroopScreen.jetLag) {
                    BroopNavTile(symbol: "airplane", title: String(localized: "Jet-lag planner"))
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, BroopMetrics.section)

                Button { showCustomize = true } label: {
                    BroopNavTile(symbol: "slider.horizontal.3", title: String(localized: "Customize Sleep"),
                                 detail: String(localized: "Order and hide cards"))
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopOverviewNavBar(
                title: BroopOverviewFormat.dayTitle(store),
                canGoBack: store.dayOffset < store.maxOffset(repo: repo),
                canGoForward: store.dayOffset > 0,
                onBack: { withAnimation(.snappy) { store.step(1, repo: repo) } },
                onForward: { withAnimation(.snappy) { store.step(-1, repo: repo) } },
                onInfo: { showGuide = true })
        }
        .background(BroopBackground())
        .broopBarChrome()
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)") { await store.reload(repo: repo, profile: profile) }
        .task(id: repo.refreshSeq) { await loadModel() }
        .task(id: snap?.night?.session.effectiveStartTs ?? 0) { await loadHR(snap?.night) }
        .sheet(isPresented: $showGuide) {
            BroopOverviewScoreGuide(initialSection: .rest, onClose: { showGuide = false })
        }
        .sheet(isPresented: $showCustomize) {
            BroopFinalASleepCustomizeSheet(sectionOrderRaw: $orderRaw, hiddenSectionsRaw: $hiddenRaw)
        }
        .sheet(item: $edit) { e in editor(e).presentationDetents([.large]).presentationDragIndicator(.visible) }
        .sheet(item: $addNap) { seed in
            BroopFinalASleepTimeEditor(
                bedTs: seed.bedTs, wakeTs: seed.wakeTs,
                title: seed.isNap ? String(localized: "Add a nap") : String(localized: "Add sleep"),
                blurb: seed.isNap
                    ? String(localized: "Pick when the nap started and ended. NOOP stages it from your data as its own session, separate from the night's sleep.")
                    : String(localized: "Pick when you fell asleep and woke. NOOP stages the window from your data and saves it as its own sleep session."),
                bedLabel: seed.isNap ? String(localized: "Nap started") : String(localized: "Asleep"),
                wakeLabel: seed.isNap ? String(localized: "Nap ended") : String(localized: "Woke")) { start, end in
                await repo.addManualNap(startTs: start, endTs: end)
                await intelligence.analyzeRecent()
                await repo.refresh()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// The saved card order minus the hidden set. `.stages` is Last Night's Sleep, drawn above.
    private var sections: [SleepSection] {
        SleepLayoutPrefs.visibleOrder(orderRaw: orderRaw, hiddenRaw: hiddenRaw).filter { $0 != .stages }
    }

    // MARK: Ring contributors

    private func contributors(_ snap: BroopSnapshot?) -> [BroopOverviewContributor] {
        func row(_ id: String, _ symbol: String, _ label: String, _ v: Double?, rating: (Double) -> BroopOverviewRating,
                 key: String) -> BroopOverviewContributor {
            BroopOverviewContributor(id: id, symbol: symbol, label: label, value: v.map { BroopFormat.whole($0) + "%" } ?? "--",
                                     rating: v.map(rating) ?? .sufficient, link: .metric(key: key, source: nil))
        }
        return [
            row("need", "clock", String(localized: "Hours vs. Needed"), snap?.hoursVsNeededPct.map { min($0, 100) },
                rating: BroopOverviewRating.performance, key: "hours_vs_needed_pct"),
            // Rest's own part (tonight vs the previous 4 days), not the 7-day regularity in the statistics.
            // Only an imported WHOOP figure has a stored trend to open.
            {
                var c = row("cons", "moon.stars", String(localized: "Consistency"), snap?.consistency,
                            rating: BroopOverviewRating.performance, key: "sleep_consistency")
                if snap?.consistencyImported != true { c.link = nil }
                return c
            }(),
            row("eff", "bed.double", String(localized: "Sleep Efficiency"), snap?.efficiency,
                rating: BroopOverviewRating.performance, key: "sleep_efficiency"),
        ] + (RestScoringPrefs.v2Enabled
            // Rest v2 scores Sleep Stress, not restorative sleep (which stays in the night card and stats).
            ? [BroopOverviewContributor(id: "stress", symbol: "gauge.with.dots.needle.33percent",
                                        label: String(localized: "High Sleep Stress"),
                                        value: snap?.sleepStressPct.map { BroopFormat.whole($0) + "%" } ?? "--",
                                        rating: snap?.sleepStressPct.map(BroopOverviewSleepStressRating.rating) ?? .sufficient,
                                        link: .metric(key: StressDaySummary.Key.sleepStressPct, source: nil))]
            : [row("rest", "sparkles", String(localized: "Restorative Sleep"), snap?.restorativePct,
                   rating: BroopOverviewRating.restorative, key: "restorative_pct")])
    }

    /// One read of the night: the band word, then the weakest contributor to work on.
    private func coachText(_ snap: BroopSnapshot?) -> String {
        guard let rest = snap?.rest else {
            return String(localized: "No Sleep Performance for this day. Wear the strap overnight and sync to see how restorative your sleep was.")
        }
        let band = BroopOverviewRating.performance(rest)
        var weakest: (String, Double)?
        let parts: [(String, Double?)] = [
            (String(localized: "Hours vs. Needed"), snap?.hoursVsNeededPct),
            (String(localized: "Consistency"), snap?.consistency),
            (String(localized: "Sleep Efficiency"), snap?.efficiency),
            (String(localized: "Sleep Stress"), RestScoringPrefs.v2Enabled
                ? snap?.sleepStressPct.map { 100 - min($0 / AnalyticsEngine.RestV2.sleepStressZeroCreditPct, 1) * 100 } : nil),
        ]
        for (name, v) in parts { if let v, v < (weakest?.1 ?? .infinity) { weakest = (name, v) } }
        switch band {
        case .optimal:
            return String(localized: "Your Sleep Performance is optimal. You got the sleep your body asked for, so you are set up to perform today.")
        case .sufficient:
            if let weakest {
                return String(localized: "Your Sleep Performance is sufficient, but there's room to improve - \(weakest.0) could use attention to help you get to optimal sleep.")
            }
            return String(localized: "Your Sleep Performance is sufficient, but there's room to improve.")
        case .poor:
            if let asleep = snap?.asleepMinutes, let need = snap?.needMinutes, need > asleep {
                return String(localized: "Your Sleep Performance is poor. You slept \(BroopFormat.duration(need - asleep)) less than you needed; an earlier bedtime tonight helps pay it back.")
            }
            return String(localized: "Your Sleep Performance is poor. A regular bedtime tonight is the quickest way back to optimal sleep.")
        }
    }

    // MARK: Last night

    @ViewBuilder
    private func lastNight(_ snap: BroopSnapshot?) -> some View {
        let dayWord = store.dayOffset == 0 ? String(localized: "Today") : BroopOverviewFormat.dayTitle(store).capitalized
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(
                title: store.dayOffset == 0 ? String(localized: "Last Night's Sleep") : String(localized: "Night's Sleep"),
                subtitle: Text(verbatim: dayWord).foregroundColor(BroopPalette.textPrimary)
                    + Text(verbatim: " " + String(localized: "vs. prior 30 days")).foregroundColor(BroopPalette.textSecondary)
            ) {
                if let target = snap?.night?.editTarget {
                    BroopOverviewCapsButton(title: String(localized: "Edit"), symbol: target.userEdited ? "pencil.circle.fill" : "pencil") {
                        edit = BroopOverviewSleepEdit(target: target)
                    }
                    .accessibilityLabel(Text("Edit sleep times"))
                }
            }
            if let night = snap?.night {
                BroopOverviewNightCard(night: night, asleepReading: snap?.asleepReading,
                                       restorativeReading: snap?.restorativeMinReading,
                                       typicals: typicals, hr: nightHR)
                windowRow(night)
                if night.motionEpochs.count >= 2 {
                    BroopOverviewCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            BroopCaps(String(localized: "Movement"), size: 10.5, color: BroopPalette.textSecondary)
                            MotionTrace(epochs: night.motionEpochs, height: 40, tint: BroopPalette.rest)
                        }
                    }
                }
                notes(night)
                BroopOverviewNapsCard(night: night, onAdd: { addNap = .napSeed(after: night) },
                                      onEdit: { edit = BroopOverviewSleepEdit(nap: $0) })
                    .padding(.top, 18)
            } else {
                BroopOverviewCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text((snap?.asleepMinutes ?? 0) > 0
                             ? String(localized: "This night's stages aren't on this iPhone; its figures above come from your day's record.")
                             : String(localized: "No sleep recorded for this day."))
                            .font(BroopType.medium(15))
                            .foregroundStyle(BroopPalette.textBody)
                        BroopOverviewFillButton(symbol: "plus", title: String(localized: "Add sleep")) {
                            let end = Int(min(Date(), store.selectedLogicalDay.addingTimeInterval(8 * 3600)).timeIntervalSince1970)
                            var seed = BroopOverviewSleepEdit(bedTs: end - 8 * 3600, wakeTs: end)
                            seed.isNap = false
                            addNap = seed
                        }
                    }
                }
            }
        }
    }

    /// Bed and wake times with provenance and the "why this sleep" explainer.
    private func windowRow(_ night: Night) -> some View {
        BroopOverviewCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    time("moon.zzz", String(localized: "Asleep"), night.onsetText)
                    Spacer()
                    time("sun.max", String(localized: "Woke"), night.wakeText)
                    Spacer()
                }
                HStack {
                    BroopCaps(source(night), size: 9.5, color: BroopPalette.rest)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(BroopPalette.rest.opacity(0.14)))
                    Spacer()
                    if let why = reasonText(night) {
                        Button { showWhy.toggle() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "info.circle")
                                Text("Why this sleep?")
                            }
                            .font(BroopType.demi(12.5))
                            .foregroundStyle(BroopPalette.rest)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showWhy) {
                            Text(verbatim: why)
                                .font(BroopType.medium(14))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .padding(16)
                                .frame(width: 260)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
        }
    }

    private func time(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(BroopPalette.rest)
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
                Text(verbatim: value).font(BroopType.number(20)).foregroundStyle(BroopPalette.textPrimary)
            }
        }
    }

    /// The per-day merge winner, as the classic badge names it.
    private func source(_ night: Night) -> String {
        let wakeDay = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(night.session.endTs)))
        if repo.importedSleep[wakeDay] != nil { return String(localized: "Whoop") }
        if repo.activeDeviceIsOura { return String(localized: "Oura") }
        return String(localized: "On-device")
    }

    /// The selector's own reason for picking this block (`SleepStageTotals.mainNightSelection`).
    private func reasonText(_ night: Night) -> String? {
        guard let sel = SleepStageTotals.mainNightSelection(
            night.sourceBlocks.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) },
            offsetSec: SleepView.tzOffsetSec, habitualMidsleepSec: night.habitualMidsleepSec) else { return nil }
        let dur = BroopFormat.duration(sel.asleepMinutes)
        switch sel.reason {
        case .onlyBlock: return String(localized: "This is your only sleep block today.")
        case .longest: return String(localized: "Picked as your main sleep because it was your longest block (\(dur)).")
        case .longestNearUsual: return String(localized: "Picked as your main sleep because it was your longest block (\(dur)), near your usual bedtime.")
        case .alignedToUsual: return String(localized: "Picked as your main sleep because it started near your usual sleep time.")
        }
    }

    /// The classic screen's honesty notes, from the same gates.
    @ViewBuilder
    private func notes(_ night: Night) -> some View {
        let s = night.stages
        let eff = night.session.efficiency.map { $0 <= 1 ? $0 * 100 : $0 }
            ?? (night.timeInBed > 0 ? min(100, s.asleep / night.timeInBed * 100) : nil)
        if let eff, SleepView.isStagingLowConfidence(asleepMin: s.asleep, deepMin: s.deep, remMin: s.rem, efficiency: eff / 100) {
            BroopOverviewNote(chip: String(localized: "Low confidence"),
                              text: String(localized: "This night scored high efficiency but very little deep or REM, more likely a staging estimate miss than a real restorative shortfall. Read the split with care."))
        }
        if SleepView.stageSparseNoteApplies(stagingSparse: night.sourceBlocks.contains { $0.stagingSparse == true }, asleepMin: s.asleep) {
            BroopOverviewNote(chip: String(localized: "May be incomplete"),
                              text: String(localized: "Your strap recorded little movement overnight, so this night may be under-detected and the sleep total can read short. Make sure the strap fully synced."))
        }
        let group = SleepView.mainNightGroup(night.sourceBlocks, habitualMidsleepSec: night.habitualMidsleepSec)
        if let c = HypnogramCoverage.groupFraction(group.isEmpty ? night.sourceBlocks : group), c < HypnogramCoverage.minCoverage {
            BroopOverviewNote(chip: String(localized: "Partly recorded"),
                              text: String(localized: "Only \(Int((c * 100).rounded(.down)))% of this night's window has stage data. The stage totals cover only that part of the night."))
        }
        if repo.activeDeviceIsOura {
            BroopOverviewNote(chip: String(localized: "Raw ring stages"),
                              text: String(localized: "This split is the ring's raw on-device classification, not the adjusted stages the Oura app shows."),
                              tint: BroopPalette.rest)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: SleepSection, _ snap: BroopSnapshot?) -> some View {
        switch section {
        case .tonight: if store.dayOffset == 0 { BroopOverviewPlannerCard() }
        case .sleepMarks: if store.dayOffset == 0 { BroopOverviewSleepMarks() }
        case .stages: EmptyView()
        case .bodyClock:
            if let night = snap?.night {
                BroopFinalABodyClockSection(actualBedHour: SleepView.localClockHour(night.session.effectiveStartTs),
                                            actualWakeHour: SleepView.localClockHour(night.session.endTs))
            }
        case .nightDetail: if let model { BroopOverviewSleepStatsCard(model: model) }
        case .sleepDebt: if let model { BroopOverviewDebtCard(ledger: model.sleepDebtLedger) }
        case .stagesVsTypical:
            if let model, let night = snap?.night { BroopOverviewStagesVsTypical(stages: night.stages, model: model) }
        case .asleepDuration: EmptyView() // Hours of Sleep lives in the trend card below.
        }
    }

    // MARK: Editing

    private func editor(_ e: BroopOverviewSleepEdit) -> some View {
        let lo = min(e.detectedStartTs, e.bedTs)
        return BroopFinalASleepTimeEditor(bedTs: e.bedTs, wakeTs: e.wakeTs,
                               coverage: lo...max(e.wakeTs, lo + 1),
                               suppressesReDetection: !e.userEdited,
                               onSave: { bed, wake in
            await repo.editSleepTimes(detectedStartTs: e.detectedStartTs, oldEndTs: e.wakeTs,
                                      storedStagesJSON: e.stagesJSON, newStartTs: bed, newEndTs: wake)
            await intelligence.analyzeRecent()
            await repo.refresh()
        }, onDelete: {
            let snapshot = await repo.deleteSleepSession(detectedStartTs: e.detectedStartTs, endTs: e.wakeTs)
            await intelligence.analyzeRecent()
            await repo.refresh()
            if let snapshot {
                await MainActor.run {
                    withAnimation { undo = BroopOverviewSleepUndo(snapshot: snapshot, start: e.bedTs, end: e.wakeTs) }
                }
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                await MainActor.run {
                    if undo?.snapshot.session.startTs == snapshot.session.startTs { withAnimation { undo = nil } }
                }
            }
        })
    }

    private func undoBanner(_ u: BroopOverviewSleepUndo) -> some View {
        let message = u.snapshot.session.userEdited
            ? String(localized: "Sleep deleted.")
            : String(localized: "Sleep deleted. NOOP won't detect sleep between \(BroopFormat.time(Date(timeIntervalSince1970: TimeInterval(u.start)))) and \(BroopFormat.time(Date(timeIntervalSince1970: TimeInterval(u.end)))) again.")
        return HStack(spacing: 12) {
            Text(verbatim: message).font(BroopType.medium(13)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                Task {
                    await repo.undoDeleteSleepSession(u.snapshot)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                    withAnimation { undo = nil }
                }
            } label: { BroopCaps(String(localized: "Undo"), size: 11, color: BroopPalette.rest) }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
    }

    // MARK: Loading

    /// The classic Sleep model (stats, debt, typicals) from the same inputs SleepView builds it from.
    private func loadModel() async {
        let sessions = await repo.allSleepSessions()
        let hab = await repo.habitualMidsleepSec()
        let motion = await repo.sessionMotions(sessions: sessions)
        guard !Task.isCancelled else { return }
        let inputs = SleepModelInputs(days: repo.days, sleeps: repo.sleeps, allSessions: sessions,
                                      importedSleep: repo.importedSleep, habitualMidsleepSec: hab, motionByStart: motion,
                                      computedSleep: repo.computedSleepFigures)
        let days = repo.days
        let built = await CancellableAnalysis.run { SleepModel.build(inputs) }
        var t: [SleepStage: BroopOverviewStageTypical] = [:]
        for st in SleepStage.allCases { t[st] = BroopOverviewStageTypical.compute(days: days, stage: st) }
        guard !Task.isCancelled else { return }
        model = built
        typicals = t
        habitual = .some(hab)
    }

    private func loadHR(_ night: Night?) async {
        guard let night else { nightHR = []; return }
        let onset = night.session.effectiveStartTs, wake = night.session.endTs
        let pad = max(600, (wake - onset) / 20)
        let hr = await repo.hrBuckets(from: onset - pad, to: wake + pad, bucketSeconds: 60)
        guard !Task.isCancelled else { return }
        nightHR = hr
    }
}

/// A sleep block being edited, or a seed window for a new nap.
struct BroopOverviewSleepEdit: Identifiable {
    let detectedStartTs: Int
    let bedTs: Int
    let wakeTs: Int
    let stagesJSON: String?
    let userEdited: Bool
    var isNap = true
    var id: Int { detectedStartTs }

    init(target: CachedSleepSession) {
        detectedStartTs = target.startTs; bedTs = target.effectiveStartTs; wakeTs = target.endTs
        stagesJSON = target.stagesJSON; userEdited = target.userEdited
    }

    /// A nap row is always hand-added, so deleting it writes no re-detection tombstone.
    init(nap: CachedSleepSession) {
        detectedStartTs = nap.startTs; bedTs = nap.effectiveStartTs; wakeTs = nap.endTs
        stagesJSON = nap.stagesJSON; userEdited = true
    }

    init(bedTs: Int, wakeTs: Int) {
        detectedStartTs = bedTs; self.bedTs = bedTs; self.wakeTs = wakeTs; stagesJSON = nil; userEdited = true
    }

    /// A 30-minute window an hour after the night's wake, as the classic Add Nap seeds it.
    static func napSeed(after night: Night) -> BroopOverviewSleepEdit {
        let anchor = night.session.endTs + 3_600
        return BroopOverviewSleepEdit(bedTs: anchor, wakeTs: anchor + 30 * 60)
    }
}

struct BroopOverviewSleepUndo {
    let snapshot: SleepDeletionSnapshot
    let start: Int
    let end: Int
}
#endif

