#if os(iOS)
import SwiftUI
import StrandDesign

/// Every screen the Broop shell can push or present, in one place.
///
/// Each case belongs to exactly one screen group, and each group owns one file that maps its cases to
/// views: `BroopOverviewScreens` (sleep and score deep dives), `BroopActivityScreens` (workouts, live,
/// strength, breathing), `BroopHealthScreens` (health monitor, stress, trends, metric pages),
/// `BroopInsightsScreens` (journal, insights, coach, alarms) and `BroopAccountScreens` (settings,
/// devices, data, integrations). Classic `TabRoute` pushes made from inside any screen land here too, so
/// nothing reachable from the Broop shell falls back to the classic interface by accident.
enum BroopScreen: Hashable, Identifiable {
    // Overview
    case sleep, fullDayChart, coupled
    // Activity
    case workouts, live, liftLog, breathe, intervals
    // Health
    case health, stress, labBook, rhythm, metricExplorer, trends, hydration, compare, healthspan, mind, energy, jetLag
    case metric(key: String, source: String?)
    // Insights
    case journal, insightsHub, intelligence, fusedRecord, coach, alarms
    // Account
    case settings, devices, appleHealth, miBand, dataSources, backupSync, shortcutsExport
    case noopLimitations, automations, siriShortcuts, powerSaving, testCentre

    var id: Self { self }

    init(_ route: TabRoute) {
        switch route {
        case .fullDayChart: self = .fullDayChart
        case .metric(let key): self = .metric(key: key, source: nil)
        case .metricSourced(let key, let source): self = .metric(key: key, source: source)
        case .metricExplorer: self = .metricExplorer
        case .workouts: self = .workouts
        case .dataSources: self = .dataSources
        case .stress: self = .stress
        case .sleep: self = .sleep
        case .health: self = .health
        case .hydration: self = .hydration
        case .coupled: self = .coupled
        }
    }

    /// The screen a shell-level router request opens. `nil` for requests the shell handles itself
    /// (Live Sessions has its own full-screen cover).
    init?(_ destination: NavRouter.Destination) {
        switch destination {
        case .devices: self = .devices
        case .insightsHub: self = .insightsHub
        case .labBook: self = .labBook
        case .fusedRecord: self = .fusedRecord
        case .rhythm: self = .rhythm
        case .trends: self = .trends
        case .activeWorkout: self = .live
        case .journal: self = .journal
        case .workouts: self = .workouts
        case .coach: self = .coach
        case .alarms: self = .alarms
        case .liveSession: return nil
        }
    }
}

/// The view for one `BroopScreen`, delegated to the group that owns it.
struct BroopScreenView: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .sleep, .fullDayChart, .coupled:
            BroopOverviewScreens(screen: screen)
        case .workouts, .live, .liftLog, .breathe, .intervals:
            BroopActivityScreens(screen: screen)
        case .health, .stress, .labBook, .rhythm, .metricExplorer, .trends, .hydration, .compare, .healthspan, .mind, .energy, .jetLag, .metric:
            BroopHealthScreens(screen: screen)
        case .journal, .insightsHub, .intelligence, .fusedRecord, .coach, .alarms:
            BroopInsightsScreens(screen: screen)
        case .settings, .devices, .appleHealth, .miBand, .dataSources, .backupSync, .shortcutsExport,
             .noopLimitations, .automations, .siriShortcuts, .powerSaving, .testCentre:
            BroopAccountScreens(screen: screen)
        }
    }
}

/// A `BroopScreen` presented as a sheet: its own stack, Broop destinations and a Done button.
struct BroopPresentedScreen: View {
    let screen: BroopScreen
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            BroopScreenView(screen: screen)
                .broopDestinations()
                .environment(\.broopCloseHostSheet, onClose)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onClose() } label: {
                            Text("Done").font(BroopType.demi(16))
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Closes the shell sheet a screen was presented in (nil when the screen is pushed on a tab). A screen
/// that hands off to something the shell presents (the running gym session) closes its host first,
/// since the shell cannot present a second sheet over its own.
private struct BroopCloseHostSheetKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var broopCloseHostSheet: (() -> Void)? {
        get { self[BroopCloseHostSheetKey.self] }
        set { self[BroopCloseHostSheetKey.self] = newValue }
    }
}

extension View {
    /// Registers every value route a Broop stack can push: `BroopScreen`, classic `TabRoute`, the score
    /// deep dives (`BroopRoute`) and the Account sub-pages (`BroopAccountRoute`). Apply once to the root
    /// content of each stack (a double registration double-pushes) and nowhere else.
    ///
    /// Screens push by VALUE only. On a path-bound stack a value link does nothing inside a page that was
    /// pushed with a view-destination link (`NavigationLink { Dest() }`), so a page that can itself link
    /// onwards must be a route here, never an inline destination. Leaf pages with no links may still be
    /// inline destinations.
    func broopDestinations() -> some View {
        self
            .navigationDestination(for: BroopScreen.self) { BroopScreenView(screen: $0) }
            .navigationDestination(for: TabRoute.self) { BroopScreenView(screen: BroopScreen($0)) }
            .navigationDestination(for: BroopRoute.self) { route in
                switch route {
                case .score(let score): BroopScoreDetailView(initial: score)
                }
            }
            .navigationDestination(for: BroopAccountRoute.self) { BroopAccountRouteView(route: $0) }
    }

    /// Chrome for a classic screen shown inside a Broop stack: the Broop background, a visible inline
    /// bar with a back button, and the classic accent.
    func broopClassicScreen() -> some View {
        self
            .background(BroopBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(StrandPalette.accent)
    }

    /// Chrome for a native Broop screen pushed onto a stack: Broop background, inline bar, white tint.
    func broopScreenChrome(_ title: String? = nil) -> some View {
        self
            .background(BroopBackground())
            .navigationTitle(title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(BroopPalette.textPrimary)
    }
}
#endif
