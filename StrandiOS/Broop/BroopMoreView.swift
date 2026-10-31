#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - More

/// Broop More: the WHOOP More / Profile page. A profile header, then every screen as its own card row
/// (thin outline icon, tracked caps label, optional grey line), grouped the way WHOOP groups its menu.
/// Every destination the classic More list reached is still one tap away; the switch back to the classic
/// interface now lives in Settings > App.
struct BroopMoreView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var streak: (current: Int, longest: Int) = (0, 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopCaps(String(localized: "More"), size: 13.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)

                profileHeader.padding(.top, 14)

                rows {
                    if coachEnabled {
                        BroopAccountLink(value: BroopScreen.coach, symbol: "sparkles",
                                         title: String(localized: "Coach"),
                                         subtitle: String(localized: "Ask about your data, get a daily outlook"))
                    }
                    Button { router.requestedDestination = .liveSession } label: {
                        BroopAccountMenuRow(symbol: "record.circle", title: String(localized: "Live Session"),
                                            subtitle: String(localized: "A guarded workout with strap cues"))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                .padding(.top, 22)

                section(String(localized: "My Day & Activity")) {
                    BroopAccountLink(value: BroopScreen.trends, symbol: "chart.line.uptrend.xyaxis", title: String(localized: "Trends"))
                    BroopAccountLink(value: BroopScreen.sleep, symbol: "bed.double", title: String(localized: "Sleep"))
                    BroopAccountLink(value: BroopScreen.live, symbol: "waveform.path.ecg", title: String(localized: "Live Heart Rate"))
                    BroopAccountLink(value: BroopScreen.workouts, symbol: "figure.run", title: String(localized: "Workouts"))
                    BroopAccountLink(value: BroopScreen.liftLog, symbol: "dumbbell", title: String(localized: "Lift Log"))
                    BroopAccountLink(value: BroopScreen.breathe, symbol: "wind", title: String(localized: "Breathe"))
                    BroopAccountLink(value: BroopScreen.intervals, symbol: "timer", title: String(localized: "Intervals"))
                    BroopAccountLink(value: BroopScreen.alarms, symbol: "alarm", title: String(localized: "Alarms"))
                }

                section(String(localized: "Insights")) {
                    BroopAccountLink(value: BroopScreen.insightsHub, symbol: "wand.and.sparkles", title: String(localized: "What Moves You"))
                    BroopAccountLink(value: BroopScreen.intelligence, symbol: "brain.head.profile", title: String(localized: "Intelligence"))
                    BroopAccountLink(value: BroopScreen.journal, symbol: "square.and.pencil", title: String(localized: "Insights & Journal"))
                    BroopAccountLink(value: BroopScreen.metricExplorer, symbol: "square.grid.2x2", title: String(localized: "Explore"))
                    BroopAccountLink(value: BroopScreen.compare, symbol: "rectangle.split.2x1", title: String(localized: "Compare"))
                    BroopAccountLink(value: BroopScreen.fusedRecord, symbol: "square.stack.3d.up", title: String(localized: "Your Data, Fused"))
                }

                section(String(localized: "Body")) {
                    BroopAccountLink(value: BroopScreen.health, symbol: "heart.text.square", title: String(localized: "Health"))
                    BroopAccountLink(value: BroopScreen.stress, symbol: "bolt.heart", title: String(localized: "Stress"))
                    BroopAccountLink(value: BroopScreen.labBook, symbol: "books.vertical", title: String(localized: "Lab Book"))
                    BroopAccountLink(value: BroopScreen.rhythm, symbol: "waveform.path", title: String(localized: "Rhythm"))
                }

                section(String(localized: "Account & Settings")) {
                    BroopAccountLink(value: BroopScreen.devices, symbol: "applewatch.side.right",
                                     title: String(localized: "Device Settings"))
                    BroopAccountLink(value: BroopScreen.settings, symbol: "list.bullet.clipboard",
                                     title: String(localized: "App Settings"))
                    BroopAccountLink(value: BroopAccountRoute.integrations, symbol: "link", title: String(localized: "Integrations"),
                                         subtitle: String(localized: "Apple Health, Mi Band, imports, Shortcuts"))
                    BroopAccountLink(value: BroopScreen.backupSync, symbol: "externaldrive.badge.icloud",
                                     title: String(localized: "Backup & Sync"))
                    BroopAccountLink(value: BroopScreen.automations, symbol: "wand.and.stars",
                                     title: String(localized: "Automations"))
                    BroopAccountLink(value: BroopScreen.powerSaving, symbol: "battery.25",
                                     title: String(localized: "Power Saving"))
                }

                section(String(localized: "Support")) {
                    BroopAccountLink(value: BroopScreen.testCentre, symbol: "stethoscope",
                                     title: String(localized: "Test Centre"),
                                     subtitle: String(localized: "Diagnostics and bug reports"))
                    BroopAccountLink(value: BroopScreen.noopLimitations, symbol: "checklist",
                                     title: String(localized: "What Your Strap Reads"))
                    BroopAccountLink(value: BroopAccountRoute.about, symbol: "info.circle", title: String(localized: "About"))
                }

                footer.padding(.top, 40)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
        .task(id: repo.refreshSeq) { streak = Self.streakCounts(repo.days) }
    }

    // MARK: Header

    private var profileHeader: some View {
        NavigationLink(value: BroopAccountRoute.profile) {
            HStack(spacing: 16) {
                ProfileAvatarView(imageData: profile.avatarImageData, size: 64)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    BroopCaps(String(localized: "My Profile"), size: 15)
                    Text(verbatim: profileLine)
                        .font(BroopType.medium(14))
                        .foregroundStyle(BroopAccountStyle.caption)
                        .lineLimit(1)
                    if streak.current > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill").font(.system(size: 11))
                            Text(verbatim: streak.current == 1
                                 ? String(localized: "1-day streak")
                                 : String(localized: "\(streak.current)-day streak"))
                                .font(BroopType.demi(12.5))
                        }
                        .foregroundStyle(BroopPalette.warning)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BroopAccountStyle.icon)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
    }

    /// "34 · Male · 78 kg", all from the profile the scores already use.
    private var profileLine: String {
        let sex: String
        switch profile.sex {
        case "female": sex = String(localized: "Female")
        case "nonbinary": sex = String(localized: "Non-binary")
        default: sex = String(localized: "Male")
        }
        let system = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let weight = UnitFormatter.massFromKilograms(profile.weightKg, system: system)
        return String(localized: "Age \(profile.age)") + " · " + sex + " · " + weight
    }

    private static func streakCounts(_ days: [DailyMetric]) -> (current: Int, longest: Int) {
        let today = AnalyticsEngine.dayString(Int(Date().timeIntervalSince1970),
                                              offsetSec: TimeZone.current.secondsFromGMT())
        let s = StreakCalculator.streaks(dayKeys: days.map(\.day), qualified: days.map { $0.recovery != nil }, today: today)
        return (s.current, s.longest)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 22) {
            Text(verbatim: String(localized: "App version: \(UpdateWatch.installedVersion) (build \(Self.buildNumber))").uppercased())
                .font(BroopType.caps(11))
                .tracking(1.4)
                .foregroundStyle(BroopPalette.textPrimary)
            BroopWordmark(size: 15)
        }
        .frame(maxWidth: .infinity)
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    // MARK: Layout

    private func section<Rows: View>(_ title: String, @ViewBuilder rows content: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopAccountSectionLabel(text: title)
            rows(content)
        }
        .padding(.top, 34)
    }

    private func rows<Rows: View>(@ViewBuilder _ content: () -> Rows) -> some View {
        VStack(spacing: BroopAccountStyle.rowGap) { content() }
    }
}

// MARK: - Integrations hub

/// WHOOP's "Integrations" list: every data source and export in one place.
struct BroopAccountIntegrationsView: View {
    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Connected apps")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountLink(value: BroopScreen.appleHealth, symbol: "heart",
                                     title: String(localized: "Apple Health"),
                                     subtitle: String(localized: "Read and write your health data"))
                    BroopAccountLink(value: BroopScreen.miBand, symbol: "figure.walk.motion",
                                     title: String(localized: "Mi Band"),
                                     subtitle: String(localized: "History imported from Mi Fitness"))
                }
            }
            BroopAccountSection(title: String(localized: "Import & export")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountLink(value: BroopScreen.dataSources, symbol: "square.and.arrow.down",
                                     title: String(localized: "Data Sources"),
                                     subtitle: String(localized: "WHOOP, Health, nutrition, lifting and workout files"))
                    BroopAccountLink(value: BroopScreen.shortcutsExport, symbol: "square.and.arrow.up",
                                     title: String(localized: "Shortcuts Export"),
                                     subtitle: String(localized: "Strap data into Apple Health without HealthKit"))
                    BroopAccountLink(value: BroopScreen.siriShortcuts, symbol: "mic",
                                     title: String(localized: "Siri & Shortcuts"))
                }
            }
        }
        .broopAccountChrome(String(localized: "Integrations"))
    }
}
#endif
