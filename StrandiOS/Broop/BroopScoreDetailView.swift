#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// The three deep dives the Home dials open. Rest is the full Sleep screen; Charge and Effort follow
/// WHOOP's Recovery and Strain deep dives. All three read the shared `BroopStore` snapshot, so the ring
/// here and the dial on Home always agree for the selected day.
struct BroopScoreDetailView: View {
    let initial: BroopScore

    init(initial: BroopScore) { self.initial = initial }

    var body: some View {
        switch initial {
        case .rest: BroopOverviewSleepScreen()
        case .charge: BroopOverviewChargeScreen()
        case .effort: BroopOverviewEffortScreen()
        }
    }
}

/// Shared shell of the Charge and Effort deep dives: nav bar, scroll, reload and the method sheet.
private struct BroopOverviewDeepDive<Content: View>: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var store: BroopStore
    let section: ScoreSection
    @ViewBuilder var content: (BroopSnapshot?) -> Content
    @State private var showGuide = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content(store.snapshot)
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
        .sheet(isPresented: $showGuide) {
            BroopOverviewScoreGuide(initialSection: section, onClose: { showGuide = false })
        }
    }
}

// MARK: - Charge

/// Charge (recovery) deep dive: the band-coloured ring, HRV / RHR / respiratory rate / sleep performance
/// (and SpO2 when measured) against the prior 30 days, the readiness read, what shaped the score, and the
/// trends.
struct BroopOverviewChargeScreen: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var showBreakdown = false

    var body: some View {
        BroopOverviewDeepDive(section: .charge) { snap in
            let charge = snap?.charge
            BroopOverviewHeroRing(fraction: charge.map { $0 / 100 },
                                  color: charge.map(BroopPalette.band) ?? BroopPalette.textSecondary,
                                  valueText: charge.map { BroopFormat.whole($0) }, unit: "%",
                                  label: [String(localized: "Charge")])
                .padding(.top, 22)
            if case .carried(_, let caption)? = snap?.chargeDisplay {
                BroopCaps(caption, size: 10, color: BroopPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            BroopOverviewContributorCard(rows: rows(snap)) {
                BroopOverviewTrendLegend(dayWord: store.dayOffset == 0 ? String(localized: "Today") : String(localized: "This day"))
            }
            .padding(.top, 30)

            BroopOverviewCoachCard(text: coachText(snap),
                                   link: coachEnabled ? String(localized: "Explore your Charge insights") : nil,
                                   action: coachEnabled ? { BroopAskCoach.ask(.charge, store: store, router: router, coach: coach) } : nil)
                .padding(.top, 20)

            if let readiness = snap?.readiness, readiness.level != .insufficient, !readiness.signals.isEmpty {
                signals(readiness).padding(.top, BroopMetrics.section)
            }

            BroopHealthHRVStatusCard(asOf: snap?.dayKey)
                .padding(.top, BroopMetrics.section)

            VStack(spacing: 10) {
                Button { showBreakdown = true } label: {
                    BroopNavTile(symbol: "chart.bar.doc.horizontal", title: String(localized: "What shaped your Charge"))
                }
                .buttonStyle(BroopPressableStyle())
                NavigationLink(value: BroopScreen.insightsHub) {
                    BroopNavTile(symbol: "lightbulb", title: String(localized: "Behavior insights"))
                }
                .buttonStyle(BroopPressableStyle())
            }
            .padding(.top, BroopMetrics.section)

            BroopOverviewTrendCard(metrics: BroopOverviewTrendMetric.chargeSet,
                                   dayKey: snap?.dayKey ?? Repository.logicalDayKey(Date()))
                .padding(.top, BroopMetrics.section)
        }
        .sheet(isPresented: $showBreakdown) {
            // The same "What shaped it" sheet the classic Coupled view opens (shared components, the
            // Today derivation), kept classic: it is the engine's own explainer.
            BroopOverviewChargeBreakdownSheet(onClose: { showBreakdown = false })
        }
    }

    private func rows(_ snap: BroopSnapshot?) -> [BroopOverviewContributor] {
        guard let snap else { return [] }
        let byName = Dictionary(snap.chargeStats.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [BroopOverviewContributor] = []
        if let r = byName[String(localized: "HRV")] {
            out.append(.init(reading: r, symbol: "waveform.path.ecg", label: String(localized: "Heart Rate Variability"),
                             link: .metric(key: "hrv", source: nil)))
        }
        if let r = byName[String(localized: "Resting heart rate")] {
            out.append(.init(reading: r, symbol: "heart", label: String(localized: "Resting Heart Rate"),
                             link: .metric(key: "rhr", source: nil)))
        }
        if let r = byName[String(localized: "Respiratory rate")] {
            out.append(.init(reading: r, symbol: "lungs", label: String(localized: "Respiratory Rate"),
                             link: .metric(key: "resp_rate", source: nil)))
        }
        if let r = snap.restReading {
            out.append(.init(reading: r, symbol: "moon", label: String(localized: "Sleep Performance"),
                             link: .metric(key: "sleep_performance", source: nil)))
        }
        if let r = byName[String(localized: "Blood oxygen")] {
            out.append(.init(reading: r, symbol: "drop", label: String(localized: "Blood Oxygen"),
                             link: .metric(key: "spo2", source: nil)))
        }
        return out
    }

    private func coachText(_ snap: BroopSnapshot?) -> String {
        if let r = snap?.readiness, r.level != .insufficient { return r.headline + ". " + r.summary }
        return snap?.chargeDisplay.calibrationDetail
            ?? String(localized: "Not enough history yet for a Charge read. Keep wearing the strap overnight.")
    }

    private func signals(_ readiness: ReadinessEngine.Readiness) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Readiness Signals"))
            BroopOverviewCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(readiness.signals.enumerated()), id: \.offset) { i, signal in
                        if i > 0 { Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1) }
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(BroopVitals.flagColor(signal.flag)).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                BroopCaps(signal.label, size: 10.5)
                                Text(verbatim: signal.detail)
                                    .font(BroopType.medium(14))
                                    .foregroundStyle(BroopPalette.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// "What shaped your Charge": the classic Charge breakdown components over the displayed row, as the
/// classic Coupled and Today sheets host them.
private struct BroopOverviewChargeBreakdownSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var store: BroopStore
    let onClose: () -> Void
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let row = row, let baselines = repo.chargeBaselines, let b = ChargeBreakdownWiring.breakdown(
                        baselines: baselines, row: row,
                        sleepPerfPercent: repo.restScore(for: row)), !b.drivers.isEmpty {
                        BroopOverviewCard {
                            BroopFinalAChargeBreakdown(drivers: b.drivers, confidence: b.confidence,
                                                   skinTempRel: RecoveryScorer.skinTempRelative(deviationC: row.skinTempDevC))
                        }
                    } else {
                        BroopOverviewCard {
                            Text(store.snapshot?.chargeDisplay.calibrationDetail
                                 ?? String(localized: "No Charge breakdown yet. Wear the strap overnight to score a night first."))
                                .font(BroopType.medium(15))
                                .foregroundStyle(BroopPalette.textBody)
                        }
                    }
                    Button { showGuide = true } label: {
                        BroopNavTile(symbol: "function", title: String(localized: "How Charge is calculated"))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .broopSheetBar(String(localized: "What shaped your Charge"), onDone: onClose)
            .sheet(isPresented: $showGuide) {
                BroopOverviewScoreGuide(initialSection: .charge, onClose: { showGuide = false })
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The scored row the ring shows: the day's own, else the carried prior score.
    private var row: DailyMetric? {
        guard let key = store.snapshot?.dayKey else { return nil }
        if let d = repo.days.last(where: { $0.day == key }), d.recovery != nil { return d }
        return repo.days.last(where: { $0.recovery != nil && $0.day < key })
    }
}

// MARK: - Effort

/// Effort (strain) deep dive: the ring with the day's target band, HR zones 1-3 and 4-5, steps and
/// calories against the prior 30 days, the strain read, today's activities, the zone breakdown and trends.
struct BroopOverviewEffortScreen: View {
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    @EnvironmentObject private var coach: AICoachEngine
    @ObservedObject private var strainContext = StrainTargetContext.shared
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""

    var body: some View {
        BroopOverviewDeepDive(section: .effort) { snap in
            let effort = snap?.effort
            let max = snap?.effortMax ?? 21
            let target = BroopOverviewEffortTarget(snap: snap)
            BroopOverviewHeroRing(fraction: effort.map { $0 / max }, color: BroopPalette.effort,
                                  valueText: effort.map(BroopScore.effort.format),
                                  label: [String(localized: "Effort")],
                                  band: target?.band, tick: target?.tick)
                .padding(.top, 22)
            BroopOverviewContributorCard(rows: rows(snap)) {
                BroopOverviewTrendLegend(dayWord: store.dayOffset == 0 ? String(localized: "Today") : String(localized: "This day"))
            }
            .padding(.top, 30)

            BroopOverviewCoachCard(text: coachText(snap, target: target),
                                   link: coachEnabled ? String(localized: "Explore your Effort insights") : nil,
                                   action: coachEnabled ? { BroopAskCoach.ask(.effort, store: store, router: router, coach: coach) } : nil)
                .padding(.top, 20)

            activities(snap).padding(.top, BroopMetrics.section)

            if let zones = snap?.zoneMinutes, zones.count >= 5 {
                BroopOverviewZonesCard(minutes: Array(zones.prefix(5))).padding(.top, BroopMetrics.section)
            }

            BroopOverviewTrendCard(metrics: BroopOverviewTrendMetric.effortSet,
                                   dayKey: snap?.dayKey ?? Repository.logicalDayKey(Date()))
                .padding(.top, BroopMetrics.section)
        }
    }

    private func rows(_ snap: BroopSnapshot?) -> [BroopOverviewContributor] {
        guard let snap else { return [] }
        var out: [BroopOverviewContributor] = []
        if let z = snap.zoneMinutes, z.count >= 5 {
            out.append(.init(id: "z13", symbol: "heart.text.square", label: String(localized: "Heart Rate Zones 1-3"),
                             value: BroopFormat.duration(z[0] + z[1] + z[2]), link: .metric(key: "hr_zones13_min", source: nil)))
            out.append(.init(id: "z45", symbol: "heart.circle", label: String(localized: "Heart Rate Zones 4-5"),
                             value: BroopFormat.duration(z[3] + z[4]), link: .metric(key: "hr_zones45_min", source: nil)))
        }
        let byName = Dictionary(snap.effortStats.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        if let r = byName[String(localized: "Steps")] {
            out.append(.init(reading: r, symbol: "shoeprints.fill", label: String(localized: "Steps"), link: .metric(key: "steps", source: nil)))
        } else if let steps = snap.steps {
            out.append(.init(id: "steps", symbol: "shoeprints.fill", label: String(localized: "Steps"), value: BroopFormat.whole(steps),
                             link: .metric(key: "steps", source: nil)))
        }
        if let r = byName[String(localized: "Active calories")] {
            out.append(.init(reading: r, symbol: "flame", label: String(localized: "Calories"), link: .metric(key: "active_kcal", source: nil)))
        }
        return out
    }

    /// WHOOP's Effort bands, stated on the scale the dial shows (0–21 or 0–100), so the copy never quotes
    /// a number from a different scale than the one beside it.
    private func coachText(_ snap: BroopSnapshot?, target: BroopOverviewEffortTarget?) -> String {
        guard let effort = snap?.effort else { return String(localized: "No Effort recorded for this day yet.") }
        let max = snap?.effortMax ?? 21
        let on21 = max == 21 ? effort : effort * 21 / max
        func v(_ x21: Double) -> String {
            let x = x21 * max / 21
            return max == 21 ? (x == x.rounded() ? String(Int(x)) : BroopFormat.one(x)) : BroopFormat.whole(x)
        }
        let top = v(21)
        let band: String
        switch on21 {
        case ..<10: band = String(localized: "Effort under \(v(10)) is light, leaving room for more activity or recovery.")
        case ..<14: band = String(localized: "Effort between \(v(10)) and \(v(14)) is moderate: your cardiovascular system has been active without overreaching.")
        case ..<18: band = String(localized: "Effort between \(v(14)) and \(v(18)) is strenuous, meaning your cardiovascular system has been working hard.")
        default: band = String(localized: "Effort between \(v(18)) and \(top) is near maximal. Dedicate additional time to rest and recovery.")
        }
        if let target {
            return band + " " + String(localized: "For today's Charge, a target between \(target.lowerText) and \(target.upperText) balances training and recovery.")
        }
        return band + " " + String(localized: "Your optimal target appears once today's Charge is calculated.")
    }

    private func activities(_ snap: BroopSnapshot?) -> some View {
        let workouts = snap?.workouts ?? []
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(store.dayOffset == 0 ? String(localized: "Today's Activities") : String(localized: "Activities"))
            VStack(spacing: 10) {
                if workouts.isEmpty {
                    BroopOverviewCard {
                        Text("No activities logged.")
                            .font(BroopType.medium(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                ForEach(workouts, id: \.startTs) { w in
                    Button { router.openWorkouts(.detail(startTs: w.startTs, endTs: w.endTs)) } label: {
                        BroopOverviewActivityRow(
                            symbol: sportSymbol(w.sport),
                            value: w.strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                            color: BroopPalette.effort,
                            name: WorkoutSource.displaySport(w),
                            start: Date(timeIntervalSince1970: TimeInterval(w.startTs)),
                            end: Date(timeIntervalSince1970: TimeInterval(w.endTs)))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                HStack(spacing: 10) {
                    BroopOverviewFillButton(symbol: "plus", title: String(localized: "Add Activity")) { router.openWorkouts() }
                    NavigationLink(value: BroopScreen.fullDayChart) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg").font(.system(size: 15))
                            BroopCaps(String(localized: "Day Heart Rate"), size: 11.5)
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopOverviewPalette.button))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
            }
        }
    }
}

/// Time in zones 1–5 for the day, WHOOP's zone colours, longest bar full width.
struct BroopOverviewZonesCard: View {
    let minutes: [Double]
    static let colors: [Color] = [Color(broopHex: 0xAEC2CD), Color(broopHex: 0x479AC2), Color(broopHex: 0x7FBEA3),
                                  Color(broopHex: 0xEFB164), Color(broopHex: 0xED6E39)]

    var body: some View {
        let total = max(minutes.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 14) {
            BroopOverviewSectionTitle(String(localized: "Heart Rate Zones"))
            BroopOverviewCard {
                VStack(spacing: 12) {
                    ForEach((0..<5).reversed(), id: \.self) { i in
                        HStack(spacing: 12) {
                            BroopCaps(String(localized: "Zone \(i + 1)"), size: 10.5, color: Self.colors[i])
                                .frame(width: 58, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(BroopOverviewPalette.segmentOff)
                                    RoundedRectangle(cornerRadius: 3).fill(Self.colors[i])
                                        .frame(width: max(3, geo.size.width * minutes[i] / total))
                                }
                            }
                            .frame(height: 10)
                            Text(verbatim: "\(Int((minutes[i] / total * 100).rounded()))%")
                                .font(BroopType.number(13))
                                .foregroundStyle(Self.colors[i])
                                .frame(width: 36, alignment: .trailing)
                            Text(verbatim: BroopFormat.duration(minutes[i]))
                                .font(BroopType.number(15))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

/// "Ask Coach about this" on the screens driven by the shared store: the question for `topic` on the day
/// the store shows, sent as Coach opens.
@MainActor
enum BroopAskCoach {
    static func ask(_ topic: CoachAskAbout.Topic, store: BroopStore, router: NavRouter, coach: AICoachEngine) {
        let day = store.selectedLogicalDay
        router.openCoach(asking: CoachAskAbout.question(topic, daysAgo: store.dayOffset, day: day),
                         aboutDay: CoachAskAbout.dayKey(daysAgo: store.dayOffset, day: day), coach: coach)
    }
}
#endif
