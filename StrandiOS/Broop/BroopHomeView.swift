#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Home, laid out like the Oct 2025 WHOOP Home: header, wordmark, three dials, the two monitor
/// tiles, My Day (outlook row, activities, tonight's sleep, journal) and My Dashboard. A compact ring bar
/// replaces the header once the dials scroll away.
struct BroopHomeView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    /// The strain target's non-Charge inputs (debt, illness, goal); rarely publishes.
    @ObservedObject private var strainContext = StrainTargetContext.shared
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(EnergyPrefs.showKey) private var showEnergy = true
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue

    /// Switches the shell to the Health tab. Kept for the shell's call site; the Health Monitor tile now
    /// pushes the Health Monitor screen, as WHOOP's does.
    let onOpenHealth: () -> Void

    @State private var showOutlook = false
    /// Add Activity and Start Activity open the same form and flow as the "+" menu, not a list.
    @State private var addingActivity = false
    @State private var startingActivity = false
    /// True once the dials have scrolled under the status bar. Flipped only on the crossing, so scrolling
    /// does not re-render Home.
    @State private var collapsed = false

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            VStack(spacing: 0) {
                header.padding(.top, 6)
                BroopWordmark().padding(.top, 26)
                dials(snap)
                    .padding(.top, 20)
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 30 } action: { now in
                        if now != collapsed { withAnimation(.easeOut(duration: 0.18)) { collapsed = now } }
                    }
                monitors(snap).padding(.top, 26)
                if showEnergy && store.dayOffset == 0 {
                    NavigationLink(value: BroopScreen.energy) { BroopEnergyCard() }
                        .buttonStyle(BroopPressableStyle())
                        .padding(.top, 10)
                }
                myDayTitle.padding(.top, 34)
                outlookRow.padding(.top, 14)
                activities(snap).padding(.top, 12)
                if store.dayOffset == 0 {
                    NavigationLink(value: BroopScreen.alarms) { BroopOverviewTonightCard() }
                        .buttonStyle(BroopPressableStyle())
                        .padding(.top, 12)
                }
                journalCard(snap).padding(.top, 12)
                if let snap, !snap.dashboard.isEmpty {
                    BroopSectionTitle(String(localized: "My Dashboard")).padding(.top, 34)
                    dashboard(snap).padding(.top, 14)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .overlay(alignment: .top) {
            if collapsed { collapsedBar(snap).transition(.opacity) }
        }
        .background(BroopBackground())
        .simultaneousGesture(daySwipe)
        // Keyed like Liquid's load(): data, day, and the settings the snapshot bakes in.
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)-\(effortScaleRaw)-\(dayCycleModeRaw)") {
            await store.reload(repo: repo, profile: profile)
        }
        .sheet(isPresented: $addingActivity) { BroopHomeAddActivitySheet { addingActivity = false } }
        .fullScreenCover(isPresented: $startingActivity) {
            BroopActivityStartCover(onClose: { startingActivity = false })
        }
        .sheet(isPresented: $showOutlook) {
            BroopOutlookSheet(onAskCoach: coachEnabled ? {
                showOutlook = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.openCoach() }
            } : nil)
            .environmentObject(store)
        }
        // A quick action or a routed screen supersedes the outlook sheet, as the shell's own sheets do.
        .onChange(of: router.quickActionsRequested) { _, requested in if requested { showOutlook = false } }
        .onChange(of: router.requestedDestination) { _, dest in if dest != nil { showOutlook = false } }
    }

    /// Horizontal swipe changes the day, like the classic Today.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.6 else { return }
                withAnimation(.snappy) { store.step(dx > 0 ? 1 : -1, repo: repo) }
            }
    }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // MARK: Header

    private var header: some View {
        ZStack {
            BroopDateNavigator(
                label: store.dayLabel,
                canGoBack: store.dayOffset < store.maxOffset(repo: repo),
                canGoForward: store.dayOffset > 0,
                onBack: { withAnimation(.snappy) { store.step(1, repo: repo) } },
                onForward: { withAnimation(.snappy) { store.step(-1, repo: repo) } },
                onToday: { withAnimation(.snappy) { store.dayOffset = 0 } }
            )
            HStack {
                NavigationLink(value: BroopScreen.settings) {
                    HStack(spacing: -6) {
                        ProfileAvatarView(imageData: profile.avatarImageData, size: 32)
                            .zIndex(1)
                        if let streak = store.snapshot?.streak, streak > 0 {
                            BroopOverviewStreak(count: streak)
                        }
                    }
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Profile and settings"))
                .padding(.leading, 2)
                Spacer()
                Button { router.openDevices() } label: { BroopLiveStrapStatus() }
                    .buttonStyle(BroopPressableStyle())
            }
        }
    }

    /// The compact ring bar shown once the dials scroll away.
    private func collapsedBar(_ snap: BroopSnapshot?) -> some View {
        HStack(spacing: 0) {
            ForEach(BroopScore.allCases) { score in
                NavigationLink(value: BroopRoute.score(score)) {
                    HStack(spacing: 9) {
                        BroopOverviewMiniRing(fraction: fraction(score, snap), color: score.color(for: snap?.value(score) ?? 0))
                        BroopCaps(score.title, size: 11)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(BroopPalette.bgTop.ignoresSafeArea(edges: .top))
    }

    // MARK: Dials

    private func fraction(_ score: BroopScore, _ snap: BroopSnapshot?) -> Double? {
        guard let v = snap?.value(score) else { return nil }
        return v / (snap?.maxValue(score) ?? 100)
    }

    private func dials(_ snap: BroopSnapshot?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(BroopScore.allCases) { score in
                NavigationLink(value: BroopRoute.score(score)) {
                    VStack(spacing: 11) {
                        let value = snap?.value(score)
                        let target = score == .effort ? BroopOverviewEffortTarget(snap: snap) : nil
                        BroopOverviewDial(fraction: fraction(score, snap),
                                          color: score.color(for: value ?? 0),
                                          valueText: value.map(score.format),
                                          unit: value == nil ? (score == .effort ? "" : "%") : score.unit,
                                          band: target?.band, tick: target?.tick,
                                          diameter: 82, lineWidth: 5.3)
                        HStack(spacing: 4) {
                            BroopCaps(score.title)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(BroopPalette.textPrimary)
                        }
                        if let target, let value {
                            // Progress toward today's band, from the same resolver as the dial's arc.
                            Text(verbatim: target.progressText(displayEffort: value))
                                .font(BroopType.medium(11)).foregroundStyle(BroopPalette.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
    }

    // MARK: Monitors

    private func monitors(_ snap: BroopSnapshot?) -> some View {
        let vitals = snap?.vitals ?? []
        let withData = vitals.filter { $0.banding.band != .noData }
        let outside = withData.filter { $0.banding.band == .outOfRange }
        let ok = outside.isEmpty
        let statusColor = withData.isEmpty ? BroopPalette.textSecondary : (ok ? BroopPalette.teal : BroopPalette.warning)
        return HStack(spacing: 10) {
            // WHOOP: the tile opens the Health Monitor screen (not the Health tab).
            NavigationLink(value: BroopScreen.health) {
                BroopMonitorTile(
                    title: [String(localized: "Health"), String(localized: "Monitor")],
                    status: withData.isEmpty ? [String(localized: "No data")]
                        : (ok ? [String(localized: "Within"), String(localized: "Range")]
                              : [String(localized: "Outside"), String(localized: "Range")]),
                    statusColor: statusColor,
                    detail: String(localized: "\(withData.count - outside.count)/\(withData.count) Metrics")
                ) {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(statusColor)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 4).fill(statusColor.opacity(0.22)))
                }
            }
            .buttonStyle(BroopPressableStyle())

            NavigationLink(value: BroopScreen.stress) {
                BroopHealthStressHomeTile()
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    // MARK: My Day

    private var myDayTitle: some View {
        BroopSectionTitle(text: String(localized: "My Day")) {
            Button { router.requestQuickActions() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
            }
            .buttonStyle(BroopPressableStyle())
            .accessibilityLabel(Text("Quick actions"))
        }
        .padding(.trailing, -4)
    }

    /// Morning to late afternoon it is the Daily Outlook (warm gradient, sun); from 5 pm it becomes the
    /// Day in Review (purple gradient, moon), as WHOOP swaps them.
    private var outlookRow: some View {
        let evening = store.dayOffset > 0 || Calendar.current.component(.hour, from: Date()) >= 17
        return HStack(spacing: 10) {
            if coachEnabled {
                Button { router.openCoach() } label: {
                    BroopBadge(size: 30, gradientRing: true)
                        .frame(width: 50, height: 46)
                        .background(RoundedRectangle(cornerRadius: BroopMetrics.tileRadius, style: .continuous).fill(BroopPalette.card))
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Coach"))
            }
            Button { showOutlook = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: evening ? "moon" : "sun.max")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(BroopPalette.textBody)
                    Text(evening ? String(localized: "Your Day In Review") : String(localized: "Your Daily Outlook"))
                        .font(BroopType.medium(15))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(evening ? Color(broopHex: 0x8C9BFF) : Color(broopHex: 0xE8C9A0))
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: evening
                                ? [BroopOverviewPalette.reviewPurple, BroopOverviewPalette.reviewIndigo]
                                : [BroopOverviewPalette.outlookWarm, BroopOverviewPalette.outlookSlate],
                            startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    private func activities(_ snap: BroopSnapshot?) -> some View {
        let scale = effortScale
        let title = store.dayOffset == 0 ? String(localized: "Today's Activities") : String(localized: "Activities")
        return BroopOverviewCard(padding: 12) {
            VStack(spacing: 10) {
                NavigationLink(value: BroopScreen.workouts) {
                    HStack {
                        BroopCaps(title, size: 11)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
                .buttonStyle(BroopPressableStyle())

                if let night = snap?.night {
                    NavigationLink(value: BroopScreen.sleep) {
                        BroopOverviewActivityRow(
                            symbol: "moon.fill",
                            value: snap?.asleepMinutes.map(BroopFormat.duration) ?? "–",
                            color: BroopPalette.rest,
                            name: String(localized: "Sleep"),
                            start: night.onsetDate,
                            end: Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
                        )
                    }
                    .buttonStyle(BroopPressableStyle())
                } else if let asleep = snap?.asleepMinutes, asleep > 0 {
                    // The day row carries the night (an import, or a session removed after scoring) but no
                    // session on this iPhone: still the night the Rest dial scores, so show it, without times.
                    NavigationLink(value: BroopScreen.sleep) {
                        BroopOverviewActivityRow(symbol: "moon.fill", value: BroopFormat.duration(asleep),
                                                 color: BroopPalette.rest, name: String(localized: "Sleep"),
                                                 start: nil, end: nil)
                    }
                    .buttonStyle(BroopPressableStyle())
                } else if snap != nil {
                    noSleepRow
                }

                ForEach(snap?.workouts ?? [], id: \.startTs) { w in
                    Button {
                        router.openWorkouts(.detail(startTs: w.startTs, endTs: w.endTs))
                    } label: {
                        BroopOverviewActivityRow(
                            symbol: sportSymbol(w.sport),
                            value: w.strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                            color: BroopPalette.effort,
                            name: WorkoutSource.displaySport(w),
                            start: Date(timeIntervalSince1970: TimeInterval(w.startTs)),
                            end: Date(timeIntervalSince1970: TimeInterval(w.endTs))
                        )
                    }
                    .buttonStyle(BroopPressableStyle())
                }

                HStack(spacing: 10) {
                    BroopOverviewFillButton(symbol: "plus", title: String(localized: "Add Activity")) {
                        addingActivity = true
                    }
                    if store.dayOffset == 0 {
                        BroopOverviewFillButton(symbol: "stopwatch", title: String(localized: "Start Activity")) {
                            startingActivity = true
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// No night for the selected day: an outlined moon pill and an "Add sleep" button into Sleep, where
    /// naps and nights are added and edited.
    private var noSleepRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "moon").font(.system(size: 14, weight: .regular))
                BroopCaps(String(localized: "No sleep"), size: 10.5)
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(width: 104, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BroopPalette.textSecondary, lineWidth: 1))
            Spacer()
            NavigationLink(value: BroopScreen.sleep) {
                BroopCaps(String(localized: "Add sleep"), size: 10.5)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .overlay(Capsule().stroke(BroopPalette.textPrimary, lineWidth: 1.4))
            }
            .buttonStyle(BroopPressableStyle())
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopOverviewPalette.inner))
    }

    // MARK: Journal

    /// MY JOURNAL with the week strip: a filled check for each day that carries a journal entry.
    private func journalCard(_ snap: BroopSnapshot?) -> some View {
        let logged = snap?.journalDays ?? []
        let end = store.selectedLogicalDay
        let days: [Date] = (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: end) }
        let todayLogged = logged.contains(Repository.localDayKey(end))
        return NavigationLink(value: BroopScreen.journal) {
            BroopOverviewCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: todayLogged ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(todayLogged ? BroopOverviewPalette.optimal : BroopPalette.textSecondary)
                        BroopCaps(String(localized: "My Journal"), size: 11.5)
                        Spacer()
                        HStack(spacing: 7) {
                            Image(systemName: "pencil").font(.system(size: 14, weight: .regular))
                            BroopCaps(todayLogged ? String(localized: "Edit") : String(localized: "Fill out"), size: 10.5)
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopOverviewPalette.button))
                    }
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            let done = logged.contains(Repository.localDayKey(day))
                            VStack(spacing: 7) {
                                Text(verbatim: day.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.activeLocale)))
                                    .font(BroopType.demi(11))
                                    .foregroundStyle(BroopPalette.textSecondary)
                                ZStack {
                                    Circle()
                                        .fill(done ? BroopOverviewPalette.optimal : Color.clear)
                                        .overlay(Circle().stroke(done ? Color.clear : BroopPalette.textTertiary, lineWidth: 1.2))
                                    if done {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .heavy))
                                            .foregroundStyle(Color.black)
                                    }
                                }
                                .frame(width: 24, height: 24)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .buttonStyle(BroopPressableStyle())
    }

    // MARK: Dashboard

    private func dashboard(_ snap: BroopSnapshot) -> some View {
        VStack(spacing: 10) {
            ForEach(snap.dashboard) { item in
                NavigationLink(value: BroopScreen.metric(key: item.metricKey, source: nil)) {
                    BroopOverviewDashboardRow(item: item)
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
    }
}

// MARK: - Home pieces

/// Streak capsule tucked behind the avatar: flame (amber, orange, then blue past 1000) and the count.
struct BroopOverviewStreak: View {
    let count: Int

    var body: some View {
        let flame: Color = count >= 1000 ? Color(broopHex: 0x6FA8FF) : (count >= 7 ? Color(broopHex: 0xFF7A2E) : Color(broopHex: 0xF5B53D))
        HStack(spacing: 5) {
            Image(systemName: "flame.fill").font(.system(size: 13)).foregroundStyle(flame)
            Text(verbatim: "\(count)")
                .font(BroopType.number(15))
                .broopNumeral(15)
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .padding(.leading, 13)
        .padding(.trailing, 10)
        .frame(height: 30)
        .background(Capsule().fill(BroopPalette.pillOuter))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(localized: "Streak") + " \(count)"))
    }
}

/// An activity row: coloured value pill, caps name, two-line time range and a timeline tick. A start on
/// an earlier day carries a "[Thu]" prefix, as WHOOP writes it.
struct BroopOverviewActivityRow: View {
    let symbol: String
    let value: String
    let color: Color
    let name: String
    /// nil when the activity has figures but no clock window on this iPhone (an imported night).
    let start: Date?
    let end: Date?

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(verbatim: value).font(BroopType.number(17)).broopNumeral(17)
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(width: 94, height: 40)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))

            BroopCaps(name, size: 11.5).lineLimit(2)
            Spacer(minLength: 4)
            if let start, let end {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: startText(start, end))
                    Text(verbatim: BroopFormat.time(end))
                }
                .font(BroopType.demi(12))
                .foregroundStyle(BroopPalette.textBody)
            }
            Capsule().fill(color).frame(width: 2, height: 28)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopOverviewPalette.inner))
    }

    private func startText(_ start: Date, _ end: Date) -> String {
        let t = BroopFormat.time(start)
        guard !Calendar.current.isDate(start, inSameDayAs: end) else { return t }
        let day = start.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.activeLocale))
        return "[\(day)] \(t)"
    }
}

/// A My Dashboard tile: icon and caps name, today's value with a trend triangle, the 30-day baseline under.
struct BroopOverviewDashboardRow: View {
    let item: BroopDashboardItem

    var body: some View {
        let r = item.reading
        HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 24)
            BroopCaps(r.name, size: 11)
                .lineLimit(2)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .center, spacing: 5) {
                    Text(verbatim: r.text + (r.unit == "%" ? "%" : ""))
                        .font(BroopType.number(22))
                        .broopNumeral(22)
                        .foregroundStyle(BroopPalette.textPrimary)
                    Image(systemName: r.trendSymbol ?? "circle.fill")
                        .font(.system(size: r.trendSymbol == nil ? 4 : 7))
                        .foregroundStyle(r.trendSymbol == nil ? BroopPalette.textTertiary : r.trendTint)
                        .frame(width: 8)
                }
                Text(verbatim: r.format(r.baseline) + (r.unit == "%" ? "%" : ""))
                    .font(BroopType.number(12.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .padding(.trailing, 13)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
    }
}

/// A day's Effort target band from the one resolver (`StrainTargetContext.band`) as dial fractions, the
/// tick at its midpoint, and its bounds on the dial's own scale (`effortMax` 21 or 100), so the copy beside a
/// dial never quotes the other scale. nil without a Charge.
struct BroopOverviewEffortTarget {
    let band: ClosedRange<Double>
    let tick: Double
    let target: StrainTarget.Band
    let lowerText: String
    let upperText: String
    private let effortMax: Double

    init?(_ target: StrainTarget.Band?, effortMax: Double) {
        guard let target else { return nil }
        self.target = target
        self.effortMax = effortMax
        band = (target.lower / StrainScorer.maxStrain)...(target.upper / StrainScorer.maxStrain)
        tick = (band.lowerBound + band.upperBound) / 2
        lowerText = BroopScore.effort.format(target.lower * effortMax / StrainScorer.maxStrain)
        upperText = BroopScore.effort.format(target.upper * effortMax / StrainScorer.maxStrain)
    }

    /// From a snapshot: the day's OWN scored Charge only. A carried prior-night Charge gets no target, the
    /// same rule the notifier, the Coupled reads and the live coach follow (they read the day row).
    @MainActor
    init?(snap: BroopSnapshot?) {
        guard case .scored(let charge)? = snap?.chargeDisplay else { return nil }
        self.init(StrainTargetContext.shared.band(charge: charge, isToday: snap?.isToday ?? false),
                  effortMax: snap?.effortMax ?? 21)
    }

    /// Where a displayed Effort (on this dial's scale) sits against the band.
    func zone(displayEffort: Double) -> StrainTarget.Zone {
        target.zone(effort: displayEffort * StrainScorer.maxStrain / effortMax)
    }

    /// Home's progress line under the Effort dial: how far below the band, in it, or above it.
    func progressText(displayEffort: Double) -> String {
        switch zone(displayEffort: displayEffort) {
        case .restoring:
            let gap = target.lower * effortMax / StrainScorer.maxStrain - displayEffort
            return String(localized: "\(BroopScore.effort.format(gap)) to target")
        case .optimal: return String(localized: "In target")
        case .overreaching: return String(localized: "Above target")
        }
    }
}

/// TONIGHT'S SLEEP: tonight's recommended bedtime and wake from `AppModel.tonightPlan` (the plan the
/// wind-down reminder and caffeine cutoff use) and whether the strap alarm sets that wake
/// (`tonightAlarmFire`, the gate `tonightWakeMinute` uses). An unreachable plan is labelled as the
/// planner labels it. Owns the `AppModel` observation so its 1 Hz publishes stay in this leaf.
struct BroopOverviewTonightCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository

    var body: some View {
        BroopOverviewTonightContent(
            bedMinute: model.tonightPlan?.target.bedMinute,
            wakeMinute: model.tonightPlan?.wakeMinute,
            reachable: model.tonightPlan?.target.reachable ?? true,
            alarmOn: model.tonightAlarmFire() != nil
        )
        .equatable()
        .task(id: repo.refreshSeq) { await model.refreshTonightPlan() }
    }
}

struct BroopOverviewTonightContent: View, Equatable {
    let bedMinute: Int?
    let wakeMinute: Int?
    let reachable: Bool
    let alarmOn: Bool

    var body: some View {
        BroopOverviewCard {
            VStack(spacing: 18) {
                HStack {
                    BroopCaps(String(localized: "Tonight's Sleep"), size: 11.5)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                HStack(alignment: .top, spacing: 0) {
                    column(symbol: "sunset", value: bedText,
                           lines: reachable ? [String(localized: "Recommended"), String(localized: "Bedtime")]
                                            : [String(localized: "Earliest that fits"), String(localized: "Your usual bedtime")],
                           color: reachable ? BroopPalette.textSecondary : BroopPalette.warning)
                    Rectangle()
                        .fill(BroopPalette.textTertiary)
                        .frame(width: 56, height: 1)
                        .mask(HStack(spacing: 3) { ForEach(0..<10, id: \.self) { _ in Rectangle().frame(width: 3) } })
                        .padding(.top, 16)
                    column(symbol: "sunrise", value: wakeMinute.map(BroopOverviewFormat.clock) ?? "--",
                           lines: alarmOn ? [String(localized: "● Alarm on")] : [String(localized: "Wake time"), String(localized: "(Alarm off)")],
                           color: alarmOn ? BroopOverviewPalette.alarmOn : BroopPalette.textSecondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: alarmOn ? "pencil" : "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .regular))
                    BroopCaps(alarmOn ? String(localized: "Edit alarm") : String(localized: "Set alarm"), size: 11.5)
                }
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopOverviewPalette.button))
            }
        }
    }

    /// "Now" once the recommended bedtime has passed and the wake has not.
    private var bedText: String {
        guard let bedMinute else { return "--" }
        if let wakeMinute {
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let sinceBed = ((now - bedMinute) % 1440 + 1440) % 1440
            let window = ((wakeMinute - bedMinute) % 1440 + 1440) % 1440
            if sinceBed < window { return String(localized: "Now") }
        }
        return BroopOverviewFormat.clock(bedMinute)
    }

    private func column(symbol: String, value: String, lines: [String], color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
                Text(verbatim: value)
                    .font(BroopType.number(30))
                    .broopNumeral(30)
                    .foregroundStyle(BroopPalette.textPrimary)
            }
            VStack(spacing: 2) {
                ForEach(lines, id: \.self) { BroopCaps($0, size: 10.5, color: color) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Live strap status and vitals

/// The strap battery control on its own, so the ~1 Hz live stream re-renders only this view, not Home.
struct BroopLiveStrapStatus: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let display = LiquidTodayView.StrapBatteryDisplay.resolve(
            activeIsWhoop: live.activeIsWhoop, connected: live.connected,
            batteryPct: live.batteryPct, charging: live.charging,
            ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
        switch display {
        case .charge(let pct, let charging, _):
            HStack(spacing: 2) {
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(BroopPalette.textSecondary)
                }
                BroopStrapStatus(level: Int(pct.rounded()), connected: true)
            }
        case .pending: BroopStrapStatus(level: nil, connected: true)
        case .offline, .notActiveDevice: BroopStrapStatus(level: nil, connected: false)
        }
    }
}

/// Vital-sign readings through the SAME resolver the Health screen uses, so the in-range counts here
/// always match what Health shows.
enum BroopVitals {
    static let keys = ["hrv", "rhr", "resp", "spo2", "skin"]

    @MainActor
    static func readings(repo: Repository, spo2CandidateByDay: [String: Double] = [:],
                         hrvOverCountByDay: [String: Double] = [:]) -> [BodyVitalReading] {
        let d = UserDefaults.standard
        let system = UnitSystem(rawValue: d.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let temperature = UnitPrefs.resolveTemperature(system: system, override: d.string(forKey: UnitPrefs.temperatureKey) ?? "")
        let skinPref = SkinTempDisplay.Kind(rawValue: d.string(forKey: UnitPrefs.skinTempDisplayKey) ?? "") ?? .absolute
        let all = BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows, temperatureUnit: temperature,
                                          spo2CandidateByDay: spo2CandidateByDay,
                                          hrvOverCountByDay: hrvOverCountByDay,
                                          skinTempPreferred: skinPref)
        return keys.compactMap { k in all.first { $0.key == k } }
    }

    static func stressColor(_ band: StressBand) -> Color {
        switch band {
        case .low: return BroopPalette.rest
        case .medium: return BroopPalette.teal
        case .high: return BroopPalette.warning
        }
    }

    static func flagColor(_ flag: ReadinessEngine.Flag) -> Color {
        switch flag {
        case .good: return BroopPalette.teal
        case .neutral: return BroopPalette.textSecondary
        case .watch: return BroopPalette.bandMid
        case .bad: return BroopPalette.warning
        }
    }
}
/// Home's Add Activity: the "+" menu's manual-activity form, saved through the same repository path.
/// Its own view so Home does not observe the intelligence engine.
private struct BroopHomeAddActivitySheet: View {
    let onClose: () -> Void
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine

    var body: some View {
        BroopActivityEditSheet(editing: nil) { row, _ in
            Task {
                await repo.saveManualWorkout(row, replacing: nil)
                await intelligence.analyzeRecent()
                await repo.refresh()
            }
            onClose()
        }
    }
}
#endif
