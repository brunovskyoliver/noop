#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Health

/// Broop Health Monitor: last night's vitals against the wearer's range, then links to every
/// body-related classic screen. The readings come from `BroopVitals.readings(repo:)`, the same resolver
/// the classic Health screen uses, so the two screens cannot disagree about what is in range.
struct BroopHealthView: View {
    @EnvironmentObject private var repo: Repository

    var body: some View {
        let readings = BroopVitals.readings(repo: repo)
        ScrollView {
            VStack(spacing: 0) {
                BroopPageHeader(text: String(localized: "Health Monitor"))
                summary(readings).padding(.top, 20)
                VStack(spacing: 12) {
                    BroopListHeader(title: String(localized: "Last night · vs. your range"))
                    VStack(spacing: 8) {
                        ForEach(readings) { reading in
                            NavigationLink(value: TabRoute.health) {
                                BroopBodyVitalTile(reading: reading)
                            }
                            .buttonStyle(BroopPressableStyle())
                        }
                    }
                }
                .padding(.top, BroopMetrics.section)
                VStack(spacing: 12) {
                    BroopListHeader(title: String(localized: "Monitors"))
                    VStack(spacing: 8) {
                        link(TabRoute.health, "heart.text.square", String(localized: "Health details"))
                        link(TabRoute.stress, "bolt.heart", String(localized: "Stress"))
                        link(TabRoute.metricExplorer, "waveform.path.ecg", String(localized: "HRV & vitals explorer"))
                        link(BroopHealthDestination.labBook, "books.vertical", String(localized: "Lab Book"))
                        link(BroopHealthDestination.rhythm, "waveform.path", String(localized: "Rhythm"))
                        link(BroopHealthDestination.fusedRecord, "square.stack.3d.up", String(localized: "Your Data, Fused"))
                    }
                }
                .padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
        .navigationDestination(for: BroopHealthDestination.self) { route in
            route.destination.broopClassicScreen()
        }
    }

    private func link<Value: Hashable>(_ value: Value, _ symbol: String, _ title: String) -> some View {
        NavigationLink(value: value) {
            BroopNavTile(symbol: symbol, title: title)
        }
        .buttonStyle(BroopPressableStyle())
    }

    @ViewBuilder
    private func summary(_ readings: [BodyVitalReading]) -> some View {
        let withData = readings.filter { $0.banding.band != .noData }
        let inRange = withData.filter { $0.banding.band == .inRange }
        let outliers = withData.filter { $0.banding.band == .outOfRange }
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(verbatim: withData.isEmpty ? "–" : "\(inRange.count)")
                    .font(BroopType.number(64))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .broopNumeral(64)
                Text(verbatim: "/\(withData.count)")
                    .font(BroopType.number(28))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            BroopCaps(statusLine(withData: withData.count, outliers: outliers.count), size: 11,
                      color: withData.isEmpty ? BroopPalette.textSecondary
                          : (outliers.isEmpty ? BroopPalette.teal : BroopPalette.warning))
            Text(verbatim: bodyLine(withData: withData.count, outliers: outliers))
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusLine(withData: Int, outliers: Int) -> String {
        if withData == 0 { return String(localized: "No vitals yet") }
        if outliers == 0 { return String(localized: "Within range") }
        if outliers == withData { return String(localized: "Outside range") }
        return String(localized: "Metrics within range")
    }

    private func bodyLine(withData: Int, outliers: [BodyVitalReading]) -> String {
        if withData == 0 {
            return String(localized: "Wear your strap overnight to see your vitals against your range.")
        }
        if outliers.isEmpty { return String(localized: "Nothing unusual last night.") }
        let names = ListFormatter.localizedString(byJoining: outliers.map(\.label))
        return String(localized: "\(names) outside your usual range. One reading alone is rarely a concern; watch for two or more over several days.")
    }
}

/// Health-tab pushes that have no `TabRoute`. Registered once, in `BroopHealthView`.
private enum BroopHealthDestination: Hashable {
    case labBook, rhythm, fusedRecord

    @ViewBuilder var destination: some View {
        switch self {
        case .labBook: LabBookView()
        case .rhythm: RhythmHost()
        case .fusedRecord: FusedRecordHost()
        }
    }
}

/// One vital on a row tile: label, value, in-range badge, sparkline and the classic state caption.
private struct BroopBodyVitalTile: View {
    let reading: BodyVitalReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BroopCaps(reading.label, size: 10.5)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: reading.value.map(reading.format) ?? "–").font(BroopType.number(19))
                    if reading.value != nil && !reading.unit.isEmpty {
                        Text(verbatim: reading.unit)
                            .font(BroopType.number(11))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .foregroundStyle(reading.value == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                badge
            }
            if let points = reading.sparkline, points.count > 1 {
                BroopSparkline(values: points)
                    .stroke(BroopPalette.textPrimary.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 22)
            }
            Text(verbatim: reading.stateCaption)
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        switch reading.banding.band {
        case .inRange:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.pillInner))
        case .outOfRange:
            Image(systemName: "exclamationmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.bgBottom)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.warning))
        case .noData:
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.track))
        }
    }
}

/// A plain polyline scaled to its own min/max.
private struct BroopSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return path }
        let span = hi - lo
        let step = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let t = span > 0 ? (v - lo) / span : 0.5
            let point = CGPoint(x: rect.minX + CGFloat(i) * step, y: rect.maxY - CGFloat(t) * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - More

/// Broop More: every classic screen, grouped, plus the switch back to the classic interface.
struct BroopMoreView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(BroopPrefs.enabledKey) private var broopEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopPageHeader(text: String(localized: "More"))
                group(String(localized: "Daily")) {
                    row(.trends, "chart.line.uptrend.xyaxis", String(localized: "Trends"))
                    row(.sleep, "bed.double", String(localized: "Sleep"))
                    if coachEnabled {
                        row(.coach, "sparkles", String(localized: "Coach"))
                    }
                    row(.live, "waveform.path.ecg", String(localized: "Live"))
                    Button { router.requestedDestination = .liveSession } label: {
                        BroopNavTile(symbol: "record.circle", title: String(localized: "Live Session"))
                    }
                    .buttonStyle(BroopPressableStyle())
                    row(.workouts, "figure.run", String(localized: "Workouts"))
                    row(.liftLog, "dumbbell", String(localized: "Lift Log"))
                    row(.breathe, "wind", String(localized: "Breathe"))
                    row(.intervals, "timer", String(localized: "Intervals"))
                    row(.alarms, "alarm", String(localized: "Alarms"))
                }
                .padding(.top, 12)
                group(String(localized: "Insights")) {
                    row(.insightsHub, "wand.and.sparkles", String(localized: "What Moves You"))
                    row(.intelligence, "brain.head.profile", String(localized: "Intelligence"))
                    row(.insights, "lightbulb", String(localized: "Insights & Journal"))
                    row(.explore, "square.grid.2x2", String(localized: "Explore"))
                    row(.compare, "rectangle.split.2x1", String(localized: "Compare"))
                }
                .padding(.top, 24)
                group(String(localized: "Body")) {
                    row(.health, "heart.text.square", String(localized: "Health"))
                    row(.stress, "bolt.heart", String(localized: "Stress"))
                    row(.labBook, "books.vertical", String(localized: "Lab Book"))
                    row(.rhythm, "waveform.path", String(localized: "Rhythm"))
                }
                .padding(.top, 24)
                group(String(localized: "Data")) {
                    row(.fusedRecord, "square.stack.3d.up", String(localized: "Your Data, Fused"))
                    row(.appleHealth, "heart", String(localized: "Apple Health"))
                    row(.miBand, "figure.walk.motion", String(localized: "Mi Band"))
                    row(.dataSources, "externaldrive", String(localized: "Data Sources"))
                    row(.backupSync, "externaldrive.badge.icloud", String(localized: "Backup & Sync"))
                    row(.shortcutsExport, "square.and.arrow.up", String(localized: "Shortcuts Export"))
                    row(.noopLimitations, "list.bullet.rectangle", String(localized: "NOOP Limitations"))
                    row(.devices, "dot.radiowaves.left.and.right", String(localized: "Devices"))
                }
                .padding(.top, 24)
                group(String(localized: "App")) {
                    row(.automations, "wand.and.stars", String(localized: "Automations"))
                    row(.siriShortcuts, "mic", String(localized: "Siri & Shortcuts"))
                    row(.powerSaving, "battery.25", String(localized: "Power saving"))
                    row(.testCentre, "stethoscope", String(localized: "Test Centre"))
                    row(.settings, "gearshape", String(localized: "Settings"))
                    row(.classicToday, "square.grid.2x2", String(localized: "Classic Today"))
                }
                .padding(.top, 24)
                classicToggle.padding(.top, 24)
                BroopWordmark(size: 15)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
        .navigationDestination(for: BroopMoreDestination.self) { route in
            route.destination.broopClassicScreen()
        }
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopListHeader(title: title)
            VStack(spacing: 8) { rows() }
        }
    }

    private func row(_ destination: BroopMoreDestination, _ symbol: String, _ title: String) -> some View {
        NavigationLink(value: destination) {
            BroopNavTile(symbol: symbol, title: title)
        }
        .buttonStyle(BroopPressableStyle())
    }

    private var classicInterface: Binding<Bool> {
        Binding(get: { !broopEnabled }, set: { broopEnabled = !$0 })
    }

    private var classicToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: classicInterface) {
                BroopCaps(String(localized: "Classic NOOP interface"), size: 11)
            }
            .tint(BroopPalette.teal)
            Text(verbatim: String(localized: "Use the original five-tab NOOP layout. To return, turn on More → Broop interface."))
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
    }
}

/// Every screen reachable from Broop More. Covers the whole classic `MoreDestination` list plus the
/// classic tabs (Trends, Sleep, Coach, Today) and Devices, which the Broop shell has no tab for.
private enum BroopMoreDestination: Hashable {
    case trends, sleep, coach, live, workouts, liftLog, breathe, intervals, alarms
    case insightsHub, intelligence, insights, explore, compare
    case health, stress, labBook, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport, noopLimitations, devices
    case automations, siriShortcuts, powerSaving, testCentre, settings, classicToday

    @ViewBuilder var destination: some View {
        switch self {
        case .trends:          TrendsView()
        case .sleep:           SleepView()
        case .coach:           CoachView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .liftLog:         LiftLogView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .alarms:          SmartAlarmView()
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .insights:        InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .health:          HealthView()
        case .stress:          StressView()
        case .labBook:         LabBookView()
        case .rhythm:          RhythmHost()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .noopLimitations: NoopLimitationsView()
        case .devices:         DevicesView()
        case .automations:     AutomationsView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        case .powerSaving:     PowerSavingView()
        case .testCentre:      TestCentreView()
        case .settings:        SettingsView()
        case .classicToday:    ClassicTodayRoot()
        }
    }
}

private extension View {
    /// The chrome the classic More tab gives a pushed screen, plus a visible bar so it has a back button
    /// inside a Broop stack that hides the bar at its root.
    func broopClassicScreen() -> some View {
        self
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(StrandPalette.accent)
    }
}
/// Classic Today as the wearer configured it (Liquid or the original), like the classic shell's tab.
private struct ClassicTodayRoot: View {
    @AppStorage("noop.liquidTodayEnabled") private var liquidTodayEnabled = true
    var body: some View {
        if liquidTodayEnabled { LiquidTodayView() } else { TodayView() }
    }
}
#endif
