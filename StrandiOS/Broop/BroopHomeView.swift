#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Home: dials, monitors, My Day, activities and dashboard for the selected day.
struct BroopHomeView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var store: BroopStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue

    /// Switches the shell to the Health tab.
    let onOpenHealth: () -> Void

    @State private var showOutlook = false

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            VStack(spacing: 0) {
                header.padding(.top, 6)
                BroopWordmark().padding(.top, 26)
                dials(snap).padding(.top, 20)
                monitors(snap).padding(.top, 26)
                BroopSectionTitle(String(localized: "My Day")).padding(.top, 32)
                coachRow.padding(.top, 16)
                activities(snap).padding(.top, 20)
                if let snap, !snap.dashboard.isEmpty {
                    BroopSectionTitle(String(localized: "My Dashboard")).padding(.top, 36)
                    dashboard(snap).padding(.top, 16)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
        .simultaneousGesture(daySwipe)
        // Keyed like Liquid's load(): data, day, and the settings the snapshot bakes in.
        .task(id: "\(repo.refreshSeq)-\(store.dayOffset)-\(effortScaleRaw)-\(dayCycleModeRaw)") {
            await store.reload(repo: repo, profile: profile)
        }
        .navigationDestination(for: BroopRoute.self) { route in
            switch route {
            case .score(let score): BroopScoreDetailView(initial: score)
            case .settings:
                SettingsView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar(.visible, for: .navigationBar)
                    .tint(StrandPalette.accent)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { router.requestQuickActions() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .accessibilityLabel(Text("Quick actions"))
            .padding(.trailing, 16)
            .padding(.bottom, 12)
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
                NavigationLink(value: BroopRoute.settings) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: 32)
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Settings"))
                .padding(.leading, 4)
                Spacer()
                Button { router.openDevices() } label: { BroopLiveStrapStatus() }
                    .buttonStyle(BroopPressableStyle())
            }
        }
    }

    // MARK: Dials

    private func dials(_ snap: BroopSnapshot?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(BroopScore.allCases) { score in
                NavigationLink(value: BroopRoute.score(score)) {
                    VStack(spacing: 11) {
                        BroopDial(score: score, value: snap?.value(score), maxValue: snap?.maxValue(score) ?? 100)
                        HStack(spacing: 4) {
                            BroopCaps(score.title)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(BroopPalette.textPrimary)
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
            Button(action: onOpenHealth) {
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

            NavigationLink(value: TabRoute.stress) {
                let stress = snap?.stress
                let color = stress.map { BroopVitals.stressColor($0.band) } ?? BroopPalette.textSecondary
                BroopMonitorTile(
                    title: [String(localized: "Stress"), String(localized: "Monitor")],
                    status: [stress.map { $0.band.title } ?? String(localized: "Calibrating")],
                    statusColor: color,
                    detail: stress == nil ? String(localized: "Needs a few nights") : String(localized: "Latest")
                ) {
                    Text(verbatim: stress.map { BroopFormat.one($0.score) } ?? "–")
                        .font(BroopType.number(13.5))
                        .broopNumeral(13.5, color: color)
                        .foregroundStyle(color)
                        .frame(width: 25, height: 24)
                        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.22)))
                }
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    // MARK: My Day

    private var coachRow: some View {
        HStack(spacing: 13) {
            if coachEnabled {
                Button { router.openCoach() } label: {
                    BroopBadge(size: 28, gradientRing: true)
                        .frame(width: 47, height: 46)
                        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Coach"))
            }

            Button { showOutlook = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sunrise")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(BroopPalette.textSecondary)
                    Text("Daily Outlook")
                        .font(BroopType.medium(14))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    private func activities(_ snap: BroopSnapshot?) -> some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return BroopCard(padding: 12) {
            VStack(spacing: 12) {
                NavigationLink(value: TabRoute.workouts) {
                    HStack {
                        BroopCaps(String(localized: "Today's Activities"), size: 11)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                }
                .buttonStyle(BroopPressableStyle())

                if let night = snap?.night {
                    NavigationLink(value: BroopRoute.score(.rest)) {
                        BroopActivityRow(
                            symbol: "moon.fill",
                            value: snap?.asleepMinutes.map(BroopFormat.duration) ?? "–",
                            color: BroopPalette.rest,
                            name: String(localized: "Sleep"),
                            start: night.onsetDate,
                            end: Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
                        )
                    }
                    .buttonStyle(BroopPressableStyle())
                }

                ForEach(snap?.workouts ?? [], id: \.startTs) { w in
                    Button {
                        router.openWorkouts(.detail(startTs: w.startTs, endTs: w.endTs))
                    } label: {
                        BroopActivityRow(
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

                if snap?.night == nil && (snap?.workouts.isEmpty ?? true) {
                    Text("No activities yet")
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: Dashboard

    private func dashboard(_ snap: BroopSnapshot) -> some View {
        BroopCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(snap.dashboard.enumerated()), id: \.element.reading.id) { index, row in
                    if index > 0 { BroopHairline() }
                    NavigationLink(value: BroopRoute.score(row.home)) {
                        BroopDashboardRow(reading: row.reading)
                    }
                    .buttonStyle(BroopPressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// The strap battery control on its own, so the ~1 Hz live stream re-renders only this view, not Home.
struct BroopLiveStrapStatus: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let display = LiquidTodayView.StrapBatteryDisplay.resolve(
            activeIsWhoop: live.activeIsWhoop, connected: live.connected,
            batteryPct: live.batteryPct, charging: live.charging,
            ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
        switch display {
        case .charge(let pct, _, _): BroopStrapStatus(level: Int(pct.rounded()), connected: true)
        case .pending: BroopStrapStatus(level: nil, connected: true)
        case .offline, .notActiveDevice: BroopStrapStatus(level: nil, connected: false)
        }
    }
}

/// Daily Outlook: the readiness read for the selected day, with a hand-off to Coach.
struct BroopOutlookSheet: View {
    @EnvironmentObject private var store: BroopStore
    let onAskCoach: (() -> Void)?

    var body: some View {
        let snap = store.snapshot
        let readiness = snap?.readiness
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    BroopBadge(size: 28, gradientRing: true)
                    BroopCaps(String(localized: "Daily Outlook"), size: 12)
                }
                if let readiness, readiness.level != .insufficient {
                    Text(verbatim: readiness.headline)
                        .font(BroopType.demi(17))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Text(verbatim: readiness.summary)
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopPalette.textBody)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(readiness.signals.enumerated()), id: \.offset) { _, signal in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(BroopVitals.flagColor(signal.flag))
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                BroopCaps(signal.label, size: 10, color: BroopPalette.textSecondary)
                                Text(verbatim: signal.detail)
                                    .font(BroopType.regular(14))
                                    .foregroundStyle(BroopPalette.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    Text(snap?.chargeDisplay.calibrationDetail
                         ?? String(localized: "Not enough history yet for an outlook. Keep wearing the strap overnight."))
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopPalette.textBody)
                }
                if let onAskCoach {
                    Button(action: onAskCoach) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Ask Coach")
                                .font(BroopType.demi(14))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
                    }
                    .buttonStyle(BroopPressableStyle())
                    .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BroopPalette.card.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
#endif
