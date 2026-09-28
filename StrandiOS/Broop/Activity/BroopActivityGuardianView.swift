#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Live Sessions (silent guardian) in Broop's style, over the classic `LiveSessionView` behaviour: one
/// `LiveSessionRunner` per presentation, a ring coloured by the engine's position (in band, below, above,
/// grey when stale), a thin outer arc for time held in band, a long-press to reveal the smoothed bpm, the
/// one Charge sentence that fades after six seconds, End, and the summary. Every value is the engine's.
struct BroopActivityGuardianView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @StateObject private var runner = LiveSessionRunner()
    let onClose: () -> Void

    @State private var showBpm = false
    @State private var chargeVisible = true
    @State private var ringFraction: Double = 0
    @State private var heldFraction: Double = 0
    @State private var breathe = false
    @State private var showSummary = false
    @State private var guardedCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Silent guardian"), size: 10.5, color: BroopPalette.teal)
                    HStack(spacing: 8) {
                        BroopCaps(String(localized: "Live session"), size: 15)
                        BroopActivityChip(text: String(localized: "Beta"), color: BroopPalette.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.top, 16)
            Spacer()
            ring
            Text(verbatim: guardianLine)
                .font(BroopType.medium(16)).foregroundStyle(BroopPalette.textBody)
                .multilineTextAlignment(.center)
                .padding(.top, 30)
            Text(verbatim: chargeLine)
                .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(chargeVisible ? 1 : 0)
                .accessibilityHidden(!chargeVisible)
                .padding(.top, 10)
            Spacer()
            BroopActivityButton(title: String(localized: "End session"), kind: .outline, height: 58) { runner.end() }
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BroopBackground())
        .preferredColorScheme(.dark)
        .onAppear { runner.start(model: model, repo: repo, ble: model.ble, profile: profile) }
        .onDisappear { if runner.finalRow == nil { runner.end() } }
        .onChange(of: runner.finalRow) { _, row in
            guard row != nil else { return }
            let deviceId = repo.deviceId
            Task {
                guard let store = await repo.storeHandle() else { return }
                guardedCount = ((try? await store.recentLiveSessions(deviceId: deviceId, limit: 50)) ?? []).filter { $0.endTs != nil }.count
            }
            showSummary = true
        }
        .onChange(of: runner.output) { _, out in advance(out) }
        .onChange(of: isBreathing) { _, on in
            if on { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true } }
            else { withAnimation(.easeOut(duration: 0.5)) { breathe = false } }
        }
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.2)) { chargeVisible = false }
        }
        .sheet(isPresented: $showSummary, onDismiss: { onClose() }) {
            if let row = runner.finalRow {
                BroopActivityGuardianSummary(row: row, guardedCount: guardedCount) { showSummary = false }
            }
        }
    }

    private var tint: Color {
        guard let out = runner.output, out.smoothedBpm != nil else { return BroopPalette.textTertiary }
        switch out.position {
        case .inBand: return BroopPalette.teal
        case .below: return BroopPalette.teal.opacity(0.3)
        case .above: return BroopPalette.bandLow
        }
    }

    private var isBreathing: Bool {
        !motion.poseStill(reduceMotion) && runner.output?.status == .active && runner.output?.position == .inBand
    }

    private var ring: some View {
        let d: CGFloat = 250
        return ZStack {
            Circle().trim(from: 0, to: heldFraction * (240.0 / 360.0))
                .rotation(.degrees(150))
                .stroke(BroopPalette.teal.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: d + 28, height: d + 28)
            Circle().trim(from: 0, to: 240.0 / 360.0)
                .rotation(.degrees(150))
                .stroke(BroopPalette.track, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                .frame(width: d, height: d)
            Circle().trim(from: 0, to: ringFraction * (240.0 / 360.0))
                .rotation(.degrees(150))
                .stroke(tint, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                .frame(width: d, height: d)
            VStack(spacing: 4) {
                if showBpm {
                    Text(verbatim: runner.output?.smoothedBpm.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(BroopType.number(72)).broopNumeral(72)
                    BroopCaps(String(localized: "bpm"), size: 11, color: BroopPalette.textSecondary)
                } else {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 40, weight: .light)).foregroundStyle(tint)
                }
            }
        }
        .scaleEffect(breathe ? 1.03 : 1)
        .contentShape(Circle())
        .onLongPressGesture { showBpm.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ringLabel))
        .accessibilityHint(Text("Long press to show or hide your heart rate."))
    }

    private var ringLabel: String {
        guard let out = runner.output, out.smoothedBpm != nil else { return String(localized: "No live reading. Coaching is paused.") }
        switch out.position {
        case .inBand: return String(localized: "In your band. On track.")
        case .below: return String(localized: "Below your band.")
        case .above: return String(localized: "Above your band.")
        }
    }

    private func advance(_ out: LiveSessionEngine.Output?) {
        guard let out else { return }
        if let s = out.smoothedBpm {
            let lo = out.band.floorBpm - 20, hi = out.band.ceilingBpm + 20
            if hi > lo { withAnimation(.easeOut(duration: 0.9)) { ringFraction = min(max((s - lo) / (hi - lo), 0), 1) } }
        }
        withAnimation(.linear(duration: 1)) { heldFraction = min(out.inBandSeconds / 3600, 1) }
    }

    private var guardianLine: String {
        switch runner.output?.status {
        case .stale, .none: return String(localized: "No live reading. Coaching is paused until the strap comes back.")
        case .warmup: return String(localized: "Warming up. Cues stay quiet for the first minute.")
        case .active: return String(localized: "Guarding your session. Silence means you're on track.")
        }
    }

    private var chargeLine: String {
        guard let band = runner.baseBand else { return "" }
        let f = Int(band.floorBpm.rounded()), c = Int(band.ceilingBpm.rounded())
        if let charge = runner.chargeAtStart {
            return String(localized: "Charge \(Int(charge.rounded())) today, so your band is \(f)–\(c) bpm.")
        }
        return String(localized: "No Charge banked today, so your band takes a careful middle course: \(f)–\(c) bpm.")
    }
}

/// The end-of-session read-out, all from the banked `LiveSessionRow` (verdict and clock are the classic
/// summary sheet's own functions).
private struct BroopActivityGuardianSummary: View {
    let row: LiveSessionRow
    let guardedCount: Int?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(String(localized: "Live session"), size: 10.5, color: BroopPalette.teal)
                Text("Session summary").font(BroopType.demi(24))
            }
            .padding(.top, 24)
            Text(verbatim: LiveSessionSummarySheet.verdict(row: row)).font(BroopType.medium(16)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                band(String(localized: "In band"), row.inBandSec, BroopPalette.teal)
                band(String(localized: "Below band"), row.belowSec, BroopPalette.textTertiary)
                band(String(localized: "Above band"), row.aboveSec, BroopPalette.bandLow)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
            VStack(spacing: 12) {
                HStack {
                    BroopCaps(String(localized: "Cues sent"), size: 10.5, color: BroopPalette.textBody)
                    Spacer()
                    Text(verbatim: cueLine).font(BroopType.number(15))
                }
                HStack {
                    BroopCaps(String(localized: "Band"), size: 10.5, color: BroopPalette.textBody)
                    Spacer()
                    Text(verbatim: "\(Int(row.floorBpm.rounded()))–\(Int(row.ceilingBpm.rounded())) bpm").font(BroopType.number(15))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
            if let n = guardedCount, n > 0 {
                Text(verbatim: n == 1 ? String(localized: "1 session guarded") : String(localized: "\(n) sessions guarded"))
                    .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
            BroopActivityButton(title: String(localized: "Done"), kind: .filled, height: 54, action: onDone)
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color(broopHex: 0x1E2327).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func band(_ label: String, _ seconds: Double, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8)
            BroopCaps(label, size: 10.5, color: BroopPalette.textBody)
            Spacer()
            Text(verbatim: LiveSessionSummarySheet.clock(seconds)).font(BroopType.number(18)).monospacedDigit()
        }
    }

    private var cueLine: String {
        if row.pushCount == 0 && row.easeCount == 0 { return String(localized: "None — silence, start to finish") }
        var parts: [String] = []
        if row.pushCount > 0 { parts.append(String(localized: "\(row.pushCount) push")) }
        if row.easeCount > 0 { parts.append(String(localized: "\(row.easeCount) ease-off")) }
        return parts.joined(separator: " · ")
    }
}
#endif
