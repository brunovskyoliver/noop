#if os(iOS)
import SwiftUI
import StrandDesign

/// The iOS shell: Home, Health and More in the Broop interface. Every screen outside those tabs is
/// pushed by value (`broopDestinations`) or presented as a `BroopScreen` sheet.
struct RootTabView: View {
    /// #1841: the "Hide bar when scrolling" preference. Off by default because Apple's forums report
    /// `.tabBarMinimizeBehavior(.onScrollDown)` failing on tabs built on `NavigationStack(path:)`.
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false

    /// The live gym session, owned at the app root — see `LiftSessionController`.
    @EnvironmentObject private var liftSession: LiftSessionController
    /// External entry points must wait until the mandatory first-run gates have completed. The root owns
    /// that state; keeping it explicit here prevents this shell's window-level sheet from covering a gate.
    let homeScreenQuickActionsEnabled: Bool

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    /// The scene-local receiver for actions chosen from the Home Screen icon menu.
    @EnvironmentObject private var homeScreenQuickActions: HomeScreenQuickActionSceneDelegate

    /// The "+" menu, or a screen it or the Home Screen icon menu opened.
    @State private var quickAction: QuickAction?
    @State private var selectedTab = Tab.home
    /// One `NavigationPath` per tab. Re-tapping the active tab pops its stack to the root by clearing the
    /// path (#135), which leaves the root view alive so it keeps its scroll position and `.task` (#198).
    @State private var tabPaths = [Tab: NavigationPath]()
    /// Selected day shared by the Broop screens.
    @StateObject private var broopStore = BroopStore()
    @State private var broopSheet: BroopScreen?
    @State private var broopLiveSessionPresented = false

    private enum Tab: Hashable { case home, health, more }

    /// SwiftUI sends taps on the already-selected item through the setter, which keeps the refresh,
    /// pop-to-root convention without a hit-testing layer over the system bar.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { tag in
                if tag == selectedTab { reselect(tag) } else { selectedTab = tag }
            }
        )
    }

    private func reselect(_ tag: Tab) {
        Task { await repo.refresh() }
        tabPaths[tag] = NavigationPath()
    }

    private func path(_ tag: Tab) -> Binding<NavigationPath> {
        Binding(get: { tabPaths[tag] ?? NavigationPath() }, set: { tabPaths[tag] = $0 })
    }

    var body: some View {
        // The platform tab bar is intentionally left fully native. iOS 26 supplies Liquid Glass and
        // its dynamic interaction with scrolling content automatically.
        TabView(selection: tabSelection) {
            tab(BroopHomeView(onOpenHealth: { selectedTab = .health }), "Home", "house", .home)
            tab(BroopHealthView(), "Health", "heart", .health)
            tab(BroopMoreView(), "More", "line.3.horizontal", .more)
        }
        .tint(BroopPalette.textPrimary)
        .environmentObject(broopStore)
        .sheet(item: $broopSheet) { screen in
            BroopPresentedScreen(screen: screen, onClose: { broopSheet = nil })
        }
        .fullScreenCover(isPresented: $broopLiveSessionPresented) {
            BroopLiveSessionCover(onClose: { broopLiveSessionPresented = false })
        }
        // #1841: iOS 26's tab bar minimises to a pill on scroll down.
        .noopTabBarAutoHide(bottomBarAutoHide)
        .task {
            await repo.refresh()
            // Backup & Sync: on-launch catch-up. Detached + utility priority so a 100MB+ whole-DB ZIP
            // never blocks startup; gated on the auto toggle (default OFF).
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Every routed screen presents through the Broop sheet (Live Sessions through its cover). Cleared
        // so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            guard let dest else { return }
            quickAction = nil
            if let screen = BroopScreen(dest) {
                broopSheet = screen
            } else {
                broopSheet = nil
                broopLiveSessionPresented = true
            }
            router.requestedDestination = nil
        }
        // A screen's top-bar "+" routes here. The menu supersedes a routed sheet; otherwise the request
        // would be consumed with nothing shown.
        .onChange(of: router.quickActionsRequested) { _, requested in
            guard requested else { return }
            broopSheet = nil
            withAnimation(Self.sheetEase) { quickAction = .menu }
            router.quickActionsRequested = false
        }
        // A cold-launch selection is already pending when this shell appears; a warm selection arrives
        // through the change callback.
        .onAppear { presentPendingHomeScreenQuickActionIfPossible() }
        .onChange(of: homeScreenQuickActions.pendingAction) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChange(of: homeScreenQuickActionsEnabled) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        // The running gym session, reachable from ANY tab. It sits above the tab bar because a workout
        // outlives whichever screen you wandered to, and swiping its sheet away minimises it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if liftSession.isActive {
                BroopLiftSessionBar()
                    .padding(.horizontal, 14)
                    .padding(.bottom, NoopMetrics.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: liftSession.isActive)
        // A session left running by a previous launch is back before this view exists
        // (`LiftSessionController.resumeSaved`) as the bar, not as a sheet.
        .sheet(isPresented: $liftSession.isPresented) {
            BroopLiftSessionSheet()
        }
    }

    /// Mandatory launch gates defer an external action. Once the shell is available, an explicit Home
    /// Screen choice supersedes any ordinary sheet.
    private func presentPendingHomeScreenQuickActionIfPossible() {
        guard homeScreenQuickActionsEnabled,
              let action = homeScreenQuickActions.pendingAction else { return }

        let destination: QuickAction = switch action {
        case .liveHeartRate: .live
        case .startWorkout: .workout
        case .logJournal: .journal
        case .breathe: .breathe
        }
        homeScreenQuickActions.consume(action)
        withAnimation(Self.sheetEase) {
            broopSheet = nil
            broopLiveSessionPresented = false
            quickAction = destination
        }
    }

    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            BroopQuickMenu { picked in
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { broopSheet = picked }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        case .live: BroopPresentedScreen(screen: .live, onClose: { quickAction = nil })
        case .workout: BroopPresentedScreen(screen: .workouts, onClose: { quickAction = nil })
        case .journal: BroopPresentedScreen(screen: .journal, onClose: { quickAction = nil })
        case .breathe: BroopPresentedScreen(screen: .breathe, onClose: { quickAction = nil })
        }
    }

    /// Each tab owns a `NavigationStack` bound to its path, with the Broop destinations registered once
    /// per stack (a double registration double-pushes, #38).
    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String, _ tag: Tab) -> some View {
        NavigationStack(path: path(tag)) {
            view
                .toolbar(.hidden, for: .navigationBar)
                .broopDestinations()
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }
}

/// The "+" menu and the Home Screen icon menu's destinations. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// #1841: apply the iOS 26 tab-bar minimise behaviour, doing nothing on older systems. The preference
/// selects the modifier's argument and only the availability check picks a branch, so toggling the setting
/// never changes view identity (#519).
extension View {
    @ViewBuilder
    func noopTabBarAutoHide(_ enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}
#endif
