#if os(iOS)
import SwiftUI
import StrandDesign

/// The passive stress check-in (the classic `StressCheckInCard`) as a Broop card. Same surface and rules:
/// it renders only while `StressNudgeCenter` holds a pending nudge; Breathe now dismisses and hands the
/// host a one-minute session, Not now dismisses, Turn off flips `BiofeedbackPrefs.checkInEnabled` and
/// dismisses. Never an alarm and never a diagnosis.
struct BroopFinalBStressCheckIn: View {
    @ObservedObject var center: StressNudgeCenter
    var onBreatheNow: () -> Void

    var body: some View {
        if let nudge = center.pending {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BroopPalette.rest)
                        .accessibilityHidden(true)
                    BroopCaps(String(localized: "Stress check-in"), size: 11)
                    Spacer()
                    BroopActivityChip(text: String(localized: "Passive"), color: BroopPalette.textSecondary)
                }

                Text("Your HRV dipped while you were still. Want a minute to breathe?")
                    .font(BroopType.demi(17))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let line = Self.honestLine(nudge) {
                    Text(verbatim: line)
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    BroopActivityButton(title: String(localized: "Breathe now"), symbol: "wind", kind: .filled, height: 44) {
                        center.dismiss()
                        onBreatheNow()
                    }
                    BroopActivityButton(title: String(localized: "Not now"), kind: .outline, height: 44) {
                        center.dismiss()
                    }
                    .frame(width: 112)
                }

                Button {
                    BiofeedbackPrefs.checkInEnabled = false
                    center.dismiss()
                } label: {
                    BroopCaps(String(localized: "Turn off check-ins"), size: 10.5, color: BroopPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BroopPressableStyle())

                BroopHairline()
                Text("Relaxation guidance from your own numbers: not a health alert, and not a diagnosis. Trends matter more than any single number.")
                    .font(BroopType.regular(12))
                    .foregroundStyle(BroopPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
            .transition(.opacity)
        }
    }

    /// The classic card's honest one-liner: the two estimates the engine surfaced, as "your own number".
    private static func honestLine(_ nudge: StressNudgeCenter.Nudge) -> String? {
        guard let fast = nudge.fastRMSSD, let base = nudge.baselineRMSSD, base > 0 else { return nil }
        return String(format: String(localized: "RMSSD %.0f ms now vs your ~%.0f ms baseline (estimate from PPG-derived R-R)."),
                      fast, base)
    }
}
#endif
