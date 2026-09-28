import SwiftUI

@main
struct BroopApp: App {
    @StateObject private var store = SampleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Native TabView, so iOS 26 draws its floating Liquid Glass tab bar (as the NOOP app does).
struct RootView: View {
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            TodayView(tab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.today)
            HealthTabView()
                .tabItem { Label("Health", systemImage: "heart") }
                .tag(AppTab.health)
            MoreTabView()
                .tabItem { Label("More", systemImage: "line.3.horizontal") }
                .tag(AppTab.more)
        }
        .tint(Broop.Palette.textPrimary)
    }
}
