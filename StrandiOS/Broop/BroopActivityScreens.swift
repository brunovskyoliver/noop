#if os(iOS)
import SwiftUI
import StrandDesign

/// Activity group: workouts, live heart rate, strength training, breathing and intervals.
struct BroopActivityScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .workouts: WorkoutsView().broopClassicScreen()
        case .live: LiveView().broopClassicScreen()
        case .liftLog: LiftLogView().broopClassicScreen()
        case .breathe: BreathingView().broopClassicScreen()
        case .intervals: IntervalTimerView().broopClassicScreen()
        default: EmptyView()
        }
    }
}

/// The "+" menu: what the wearer can start or log. Picking an entry hands its screen to the shell.
struct BroopQuickMenu: View {
    let onPick: (BroopScreen) -> Void

    var body: some View {
        VStack(spacing: 8) {
            item("waveform.path.ecg", String(localized: "Live heart rate"), .live)
            item("figure.run", String(localized: "Start workout"), .workouts)
            item("book.closed", String(localized: "Log journal"), .journal)
            item("wind", String(localized: "Breathe"), .breathe)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BroopBackground())
        .preferredColorScheme(.dark)
    }

    private func item(_ symbol: String, _ title: String, _ screen: BroopScreen) -> some View {
        Button { onPick(screen) } label: { BroopNavTile(symbol: symbol, title: title) }
            .buttonStyle(BroopPressableStyle())
    }
}

/// Full-screen Live Sessions, presented by the shell.
struct BroopLiveSessionCover: View {
    let onClose: () -> Void
    var body: some View { LiveSessionView(onClose: onClose) }
}

/// The running gym session sheet, presented by the shell from any tab.
struct BroopLiftSessionSheet: View {
    var body: some View { LiftSessionView { } }
}

/// The running gym session bar above the tab bar.
struct BroopLiftSessionBar: View {
    var body: some View { LiftSessionBar() }
}
#endif
