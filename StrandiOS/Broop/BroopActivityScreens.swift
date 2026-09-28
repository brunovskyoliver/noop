#if os(iOS)
import SwiftUI
import StrandDesign

/// Activity group: workouts, live heart rate, strength training, breathing and intervals.
struct BroopActivityScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .workouts: BroopActivityListView()
        case .live: BroopActivityLiveHRView()
        case .liftLog: BroopActivityStrengthView()
        case .breathe: BroopActivityBreatheView()
        case .intervals: BroopActivityIntervalsView()
        default: EmptyView()
        }
    }
}

/// The "+" menu, WHOOP's popover: Start Activity, Add Activity, Strength Trainer, Complete Your Journal,
/// then Broop's Live Heart Rate and a row of quick tools. Start and Add open here (they need no screen
/// behind them); everything else hands its screen to the shell through `onPick`.
struct BroopQuickMenu: View {
    let onPick: (BroopScreen) -> Void

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @Environment(\.dismiss) private var dismiss
    @State private var starting = false
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            row("stopwatch", String(localized: "Start activity")) { starting = true }
            row("plus", String(localized: "Add activity")) { adding = true }
            row("dumbbell", String(localized: "Strength trainer")) { onPick(.liftLog) }
            row("square.and.pencil", String(localized: "Complete your journal")) { onPick(.journal) }
            row("waveform.path.ecg", String(localized: "Live heart rate")) { onPick(.live) }
            HStack(spacing: 10) {
                tool("wind", String(localized: "Breathe")) { onPick(.breathe) }
                tool("timer", String(localized: "Intervals")) { onPick(.intervals) }
                tool("list.bullet", String(localized: "Activities")) { onPick(.workouts) }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BroopActivityPalette.popover.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $starting) {
            BroopActivityStartCover(onClose: {
                starting = false
                dismiss()
            })
        }
        .sheet(isPresented: $adding) {
            BroopActivityEditSheet(editing: nil) { row, _ in
                Task {
                    await repo.saveManualWorkout(row, replacing: nil)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }
                dismiss()
            }
        }
    }

    private func row(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(BroopPalette.textBody)
                    .frame(width: 30)
                BroopCaps(title, size: 13.5)
                Spacer()
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
    }

    private func tool(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                BroopCaps(title, size: 9.5)
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// Full-screen Live Sessions, presented by the shell.
struct BroopLiveSessionCover: View {
    let onClose: () -> Void
    var body: some View { BroopActivityGuardianView(onClose: onClose) }
}

/// The running gym session sheet, presented by the shell from any tab.
struct BroopLiftSessionSheet: View {
    var body: some View { BroopActivityLiftSessionView() }
}

/// The running gym session bar above the tab bar.
struct BroopLiftSessionBar: View {
    var body: some View { BroopActivityLiftBar() }
}
#endif
