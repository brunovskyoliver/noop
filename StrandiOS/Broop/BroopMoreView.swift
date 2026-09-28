#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

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
                    row(.journal, "lightbulb", String(localized: "Insights & Journal"))
                    row(.metricExplorer, "square.grid.2x2", String(localized: "Explore"))
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
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopListHeader(title: title)
            VStack(spacing: 8) { rows() }
        }
    }

    private func row(_ destination: BroopScreen, _ symbol: String, _ title: String) -> some View {
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

#endif
