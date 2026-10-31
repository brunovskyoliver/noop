#if os(iOS)
import Charts
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import OuraProtocol

/// Which device is live, resolved the way the Live console resolves it.
@MainActor
enum BroopActivityLiveDevice {
    static func name(_ model: AppModel) -> String {
        guard let registry = model.deviceRegistry,
              let active = registry.devices.first(where: { $0.id == registry.activeDeviceId }) else { return "WHOOP" }
        return active.displayName
    }
    static func isWhoop(_ model: AppModel) -> Bool {
        LiveConsoleReadout.activeIsWhoop(devices: model.deviceRegistry?.devices ?? [], activeId: model.deviceRegistry?.activeDeviceId)
    }
    static func isOura(_ model: AppModel) -> Bool {
        LiveConsoleReadout.activeIsOura(devices: model.deviceRegistry?.devices ?? [], activeId: model.deviceRegistry?.activeDeviceId)
    }
    static func battery(_ model: AppModel, _ live: LiveState) -> Int? {
        LiveConsoleReadout.batteryPercent(activeIsWhoop: isWhoop(model), whoopPct: live.batteryPct, ringPct: live.ouraBatteryPct)
    }
    /// Built once: `lastSync` runs on every live publish.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func lastSync(_ ts: TimeInterval?) -> String {
        guard let ts else { return String(localized: "Never") }
        return relativeFormatter.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }
}

/// Live heart rate, in WHOOP's Health Monitor style, over everything the Live console does:
/// connection state and guidance, scan / buzz / disconnect (or the ring reconnect), the strap picker, live
/// physiology (R-R, rolling RMSSD, frames and events), the signal-trust tiles, the workout session
/// controls (start, pause, open, end, HRV reading), device management and the strap log with its export
/// and the Test Centre link.
///
/// The screen itself observes nothing live. Every card that reads `LiveState` or `AppModel` is its own
/// view, so a heartbeat or a log line redraws only the card that shows it.
struct BroopActivityLiveHRView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workoutCover = false
    @State private var hrvSheet = false
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LiveHero().padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    LiveBanners()
                    LiveConnectionCard()
                    LiveStandardNote()
                    LiveSessionCard(workoutCover: $workoutCover, hrvSheet: $hrvSheet)
                    BroopSectionTitle(String(localized: "Signal")).padding(.top, 20)
                    LiveSignalGrid()
                    LivePhysiologyCard()
                    BroopSectionTitle(String(localized: "Strap")).padding(.top, 20)
                    LiveModelPicker()
                    LiveControls()
                    NavigationLink(value: BroopScreen.devices) {
                        LiveDevicesRow()
                    }
                    .buttonStyle(BroopPressableStyle())
                    LiveLogCard()
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 16)
            }
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopActivityHeader(title: String(localized: "Live heart rate"), inBar: true, onBack: { dismiss() })
        }
        .broopActivityPage()
        .background(LiveLifecycle(workoutCover: $workoutCover))
        .fullScreenCover(isPresented: $workoutCover) {
            BroopActivityStartCover(onClose: { workoutCover = false })
        }
        .sheet(isPresented: $hrvSheet) {
            BroopFinalBHRVSnapshotView(onClose: { hrvSheet = false },
                                       source: LiveRules.hrvSnapshotSource(for: WhoopModel(rawValue: selectedModelRaw) ?? .whoop4))
        }
    }
}

/// the console's session edges: arm the realtime stream on appear (when a strap is actively
/// connected), release it on disappear, re-arm on a fresh bond or connection without taking another
/// reference, open the live workout the moment one starts, and honour "Return to workout".
private struct LiveLifecycle: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @Binding var workoutCover: Bool

    private var activeConnection: Bool { BroopActivityLiveDevice.isWhoop(model) && live.connected && live.bonded }

    var body: some View {
        Color.clear
            .onAppear {
                if activeConnection {
                    model.startRealtimeHR()
                    model.getBattery()
                }
                if router.presentActiveWorkout {
                    router.presentActiveWorkout = false
                    if model.activeWorkout != nil { workoutCover = true }
                }
            }
            .onDisappear { model.stopRealtimeHR() }
            .onChange(of: live.bonded) { _, _ in rearm() }
            .onChange(of: live.connected) { _, _ in rearm() }
            .onChange(of: model.activeWorkout != nil) { _, active in if active { workoutCover = true } }
    }

    private func rearm() {
        guard activeConnection else { return }
        model.rearmRealtimeIfWanted()
        model.getBattery()
    }
}

// MARK: - Hero

/// HEART RATE over a faint grid: the live number, its zone, a five-segment zone underline and a
/// sparkline of the last readings with a "now" marker.
private struct LiveHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var recent: [Int] = []

    var body: some View {
        let bpm = model.bpm
        let zone = bpm.map { model.profile.hrZoneSet.zoneNumber(forBPM: Double($0)) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    BroopCaps(String(localized: "Heart rate"), size: 12.5)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(bpm == nil ? BroopPalette.textTertiary : Color(broopHex: 0x1E90E0))
                        .symbolEffect(.pulse, isActive: bpm != nil)
                    Text(verbatim: bpm.map(String.init) ?? "--")
                        .font(BroopType.number(46)).broopNumeral(46)
                        .foregroundStyle(bpm == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                        .contentTransition(.numericText())
                    BroopCaps(String(localized: "bpm"), size: 11, color: BroopPalette.textBody)
                    Text(verbatim: zone.map { String(localized: "Zone \($0)") } ?? String(localized: "Calibrating…"))
                        .font(BroopType.medium(15))
                        .foregroundStyle(BroopPalette.textBody)
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { z in
                            Capsule().fill((zone ?? 0) >= z ? BroopActivityPalette.zone(z) : BroopPalette.pillInner)
                                .frame(width: 18, height: 3)
                        }
                    }
                }
                .frame(width: 110, alignment: .leading)
                sparkline.frame(height: 130)
            }
            Text(verbatim: trustSummary)
                .font(BroopType.regular(13))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BroopMetrics.page + 4)
        .padding(.vertical, 18)
        .background(LiveGrid())
        .onAppear { if let bpm { recent = [bpm] } }
        .onChange(of: model.bpm) { _, v in
            guard let v else { return }
            recent.append(v)
            if recent.count > 90 { recent.removeFirst(recent.count - 90) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var sparkline: some View {
        if recent.count >= 2 {
            let lo = Double((recent.min() ?? 60) - 6), hi = Double((recent.max() ?? 100) + 6)
            Chart {
                ForEach(Array(recent.map(Double.init).enumerated()), id: \.offset) { (i: Int, v: Double) in
                    AreaMark(x: .value("i", i), yStart: .value("lo", lo), yEnd: .value("bpm", v))
                        .foregroundStyle(LinearGradient(colors: [Color(broopHex: 0x1E8FDB).opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("i", i), y: .value("bpm", v))
                        .foregroundStyle(Color(broopHex: 0x1E8FDB))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                RuleMark(x: .value("now", recent.count - 1))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("i", recent.count - 1), y: .value("bpm", Double(recent.last ?? 0)))
                    .foregroundStyle(Color.white)
                    .symbolSize(60)
            }
            .chartXScale(domain: 0...max(recent.count - 1, 30))
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            Rectangle().fill(Color.clear)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1)
                        .mask(VStack(spacing: 3) { ForEach(0..<30, id: \.self) { _ in Rectangle().frame(height: 3) } })
                }
        }
    }

    private var trustSummary: String {
        let isWhoop = BroopActivityLiveDevice.isWhoop(model)
        let activeConnection = isWhoop && live.connected && live.bonded
        if activeConnection && live.encryptedBond { return String(localized: "Encrypted stream: deep controls and history sync available.") }
        if activeConnection { return String(localized: "Live heart rate is flowing; full strap controls need an encrypted bond.") }
        if BroopActivityLiveDevice.isOura(model) {
            return LiveRingCopy.status(model.ouraLinkPhase, streaming: live.connected && live.streamingLiveHR)
        }
        if live.connected { return String(localized: "Connected, waiting for a streaming state.") }
        return String(localized: "Live heart rate appears here once a strap is connected.")
    }
}

/// The faint square grid behind the Health Monitor heart-rate block, fading out downwards.
private struct LiveGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var p = Path()
            var x: CGFloat = 0
            while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(p, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Connection

private struct LiveBanners: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        VStack(spacing: 12) {
            if let guide = live.reconnectGuide {
                banner(String(localized: "Can't connect: your strap's pairing was reset"), guide)
            }
            if let hint = live.pairingHint {
                banner(String(localized: "Live HR works. Free the strap to unlock buzz, alarms & sync"), hint)
            }
            if BroopActivityLiveDevice.isWhoop(model), !live.connected {
                callout(title: String(localized: "Start a live stream"),
                        text: String(localized: "Scan connects to \(BroopActivityLiveDevice.name(model)). To pair or switch bands, open Devices."),
                        button: LiveScanButton())
            }
            if BroopActivityLiveDevice.isOura(model), model.ouraLinkPhase != .authenticated {
                callout(title: LiveRingCopy.status(model.ouraLinkPhase, streaming: false),
                        text: String(localized: "Reconnect drops the current link, if any, and connects to the ring again. To pair or switch bands, open Devices."),
                        button: LiveRingButton())
            }
        }
    }

    private func banner(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BroopPalette.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: text).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(BroopPalette.warning.opacity(0.7))
        )
        .accessibilityElement(children: .combine)
    }

    private func callout<B: View>(title: String, text: String, button: B) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(BroopPalette.connected)
                BroopCaps(title, size: 11.5)
            }
            Text(verbatim: text).font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            button
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
    }
}

private struct LiveScanButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    var body: some View {
        BroopActivityButton(title: live.connected ? String(localized: "Re-scan") : String(localized: "Scan & connect"),
                            symbol: "antenna.radiowaves.left.and.right", kind: .filled, height: 46) {
            model.scan(model: WhoopModel(rawValue: selectedModelRaw) ?? .whoop4)
        }
    }
}

private struct LiveRingButton: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        BroopActivityButton(title: String(localized: "Reconnect ring"), symbol: "arrow.clockwise", kind: .filled, height: 46) {
            model.reconnectOuraRing()
        }
    }
}

/// The connection pill, the mode badge, a SYNCING badge during an offload, and device / battery / worn /
/// last-sync figures. Wording and colours follow the console header.
private struct LiveConnectionCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let isWhoop = BroopActivityLiveDevice.isWhoop(model)
        let active = isWhoop && live.connected && live.bonded
        let ring = live.connected && live.streamingLiveHR
        let (label, color): (String, Color) =
            (active && live.encryptedBond) ? (String(localized: "Bonded · streaming"), BroopPalette.connected)
            : active ? (String(localized: "Live HR (not fully paired)"), BroopPalette.warning)
            : ring ? (String(localized: "Streaming"), BroopPalette.connected)
            : live.connected ? (String(localized: "Connected"), BroopPalette.warning)
            : live.encryptedBond ? (String(localized: "Paired · idle"), BroopPalette.warning)
            : (String(localized: "Disconnected"), BroopPalette.bandLow)
        let badge: String? = (active && live.encryptedBond) ? String(localized: "Full bond")
            : active ? String(localized: "Live HR only")
            : ring ? String(localized: "Streaming")
            : live.connected ? String(localized: "Connecting")
            : live.encryptedBond ? String(localized: "Paired") : nil
        let liveLink = active || ring
        let worn: Bool = {
            if let w = live.ouraWearState { return w == .worn }
            return live.worn || ring
        }()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(verbatim: label).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                if let badge { BroopActivityChip(text: badge, color: color, fill: color.opacity(0.14)) }
                if live.backfilling {
                    BroopActivityChip(text: String(localized: "Syncing \(live.syncChunksThisSession)"),
                                      color: BroopPalette.effort, fill: BroopPalette.effort.opacity(0.15))
                }
            }
            HStack(spacing: 0) {
                stat(String(localized: "Device"), BroopActivityLiveDevice.name(model))
                stat(String(localized: "Battery"), BroopActivityLiveDevice.battery(model, live).map { "\($0)%" } ?? "–")
                stat(String(localized: "Worn"), liveLink ? (worn ? String(localized: "Yes") : String(localized: "No")) : "–")
                stat(String(localized: "Last sync"), BroopActivityLiveDevice.lastSync(live.lastSyncedAt))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(title, size: 9, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(15)).foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveStandardNote: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        if BroopActivityLiveView_standardNote(live.standardHRMode) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Standard HR mode (low bandwidth)").font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: live.standardHRMode ?? "").font(BroopType.regular(13)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Other metrics (R-R, frames, battery, history) need a full sync.")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.connected.opacity(0.1)))
        }
    }
}

/// the `LiveRules.shouldShowStandardHRNote` rule.
private func BroopActivityLiveView_standardNote(_ note: String?) -> Bool { LiveRules.shouldShowStandardHRNote(note) }

// MARK: - Session

private struct LiveSessionCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Binding var workoutCover: Bool
    @Binding var hrvSheet: Bool
    @State private var confirmEnd = false
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    var body: some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let active = BroopActivityLiveDevice.isWhoop(model) && live.connected && live.bonded
        VStack(alignment: .leading, spacing: 14) {
            if let w = model.activeWorkout {
                HStack(spacing: 8) {
                    Circle().fill(w.isPaused ? BroopPalette.textSecondary : BroopPalette.bandLow).frame(width: 8, height: 8)
                    BroopCaps(w.isPaused ? String(localized: "Paused") : String(localized: "Recording \(w.sport)"), size: 11,
                              color: w.isPaused ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(verbatim: ActiveWorkoutClock.clock(Int(w.elapsed(at: ctx.date))))
                            .font(BroopType.number(18)).monospacedDigit()
                    }
                }
                HStack(spacing: 0) {
                    mini(String(localized: "HR"), model.bpm.map(String.init) ?? "–")
                    mini(String(localized: "Avg"), w.avgHr > 0 ? "\(w.avgHr)" : "–")
                    mini(String(localized: "Peak"), w.peakHr > 0 ? "\(w.peakHr)" : "–")
                    mini(String(localized: "Effort"), UnitFormatter.effortDisplay(w.liveStrain, scale: scale))
                }
                BroopActivityStrainCoach()
                HStack(spacing: 10) {
                    BroopActivityButton(title: w.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                                        symbol: w.isPaused ? "play.fill" : "pause.fill", kind: .grey, height: 44) {
                        model.toggleWorkoutPause()
                    }
                    BroopActivityButton(title: String(localized: "Open"), symbol: "arrow.up.left.and.arrow.down.right", kind: .grey, height: 44) {
                        workoutCover = true
                    }
                }
                BroopActivityButton(title: String(localized: "End workout"), kind: .destructive, height: 44) { confirmEnd = true }
            } else {
                BroopCaps(String(localized: "Ready for a marked effort"), size: 11.5)
                Text(active
                     ? "Start a workout when the stream matters. Broop records the interval, HR, peak, average and effort from the same live feed."
                     : "Connect the strap first, then mark a workout from the live stream.")
                    .font(BroopType.regular(13.5))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                BroopActivityButton(title: String(localized: "Start activity"), symbol: "stopwatch", kind: .blue, height: 48) {
                    workoutCover = true
                }
                .disabled(!active)
                HStack(spacing: 10) {
                    BroopActivityButton(title: String(localized: "Refresh"), symbol: "arrow.clockwise", kind: .grey, height: 44) {
                        model.getBattery()
                    }
                    .disabled(!active)
                    BroopActivityButton(title: String(localized: "HRV reading"), symbol: "waveform.path.ecg", kind: .grey, height: 44) {
                        hrvSheet = true
                    }
                    .disabled(!active)
                }
                if let last = model.lastWorkout {
                    let mins = Int((last.durationS ?? 0) / 60)
                    let parts = [String(localized: "\(mins) min"), last.avgHr.map { String(localized: "\($0) avg bpm") },
                                 last.strain.map { String(localized: "effort \(UnitFormatter.effortDisplay($0, scale: scale))") }].compactMap { $0 }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(BroopPalette.connected)
                        Text(verbatim: String(localized: "Workout saved") + " · " + parts.joined(separator: " · "))
                            .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        .alert("End this workout?", isPresented: $confirmEnd) {
            Button("Cancel", role: .cancel) { }
            Button("End workout", role: .destructive) { model.endWorkout() }
        } message: {
            Text("This stops recording and saves what's captured so far. It can't be resumed.")
        }
    }

    private func mini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BroopCaps(title, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(22)).broopNumeral(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Signal

/// the Signal Trust tiles as Health Monitor cards: heart rate, R-R intervals, connection, history
/// sync, battery and wear state, each with its value and a status chip.
private struct LiveSignalGrid: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    private struct Tile: Identifiable {
        let symbol: String, title: String, value: String, detail: String, good: Bool?
        var id: String { title }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(tiles) { t in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: t.symbol).font(.system(size: 15)).foregroundStyle(BroopPalette.textSecondary)
                        BroopCaps(t.title, size: 10, color: BroopPalette.textBody).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(verbatim: t.value).font(BroopType.number(24)).broopNumeral(24)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        if let good = t.good {
                            Image(systemName: good ? "checkmark" : "exclamationmark").font(.system(size: 9, weight: .heavy))
                        } else {
                            Circle().frame(width: 6, height: 6)
                        }
                        Text(verbatim: t.detail).font(BroopType.demi(11.5)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(t.good == true ? BroopActivityPalette.mint : t.good == false ? BroopPalette.warning : BroopPalette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(
                        t.good == true ? Color(broopHex: 0x173B30) : t.good == false ? BroopPalette.warning.opacity(0.14) : BroopPalette.row))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var tiles: [Tile] {
        let isWhoop = BroopActivityLiveDevice.isWhoop(model)
        let active = isWhoop && live.connected && live.bonded
        let ring = live.connected && live.streamingLiveHR
        let liveLink = active || ring
        let worn: Bool = { if let w = live.ouraWearState { return w == .worn }; return live.worn || ring }()
        let battery = BroopActivityLiveDevice.battery(model, live)
        let rmssd: Double? = {
            let v = Array(live.rrRecent.suffix(12)).map(Double.init)
            guard v.count >= 3 else { return nil }
            let d = zip(v.dropFirst(), v).map { $0 - $1 }
            return sqrt(d.map { $0 * $0 }.reduce(0, +) / Double(d.count))
        }()
        let syncDetail: String = {
            if let err = live.lastSyncError { return err }
            if live.backfilling { return String(localized: "\(live.decodedChunksThisSession) decoded, \(live.consoleChunksThisSession) console") }
            return live.lastSyncedAt == nil ? String(localized: "No completed offload yet") : String(localized: "Last offload completed")
        }()
        return [
            Tile(symbol: "waveform.path.ecg", title: String(localized: "Heart rate"),
                 value: model.bpm.map { "\($0) bpm" } ?? String(localized: "Missing"),
                 detail: liveLink ? String(localized: "Streaming now") : String(localized: "No active stream"),
                 good: model.bpm == nil ? nil : true),
            Tile(symbol: "point.3.connected.trianglepath.dotted", title: String(localized: "R-R intervals"),
                 value: live.rrRecent.isEmpty ? String(localized: "Missing") : String(localized: "\(live.rrRecent.count) recent"),
                 detail: rmssd.map { String(localized: "RMSSD \(Int($0.rounded())) ms") } ?? String(localized: "Needs interval frames"),
                 good: live.rrRecent.isEmpty ? nil : true),
            Tile(symbol: "lock.shield", title: String(localized: "Connection"),
                 value: active && live.encryptedBond ? String(localized: "Encrypted") : active ? String(localized: "Partial")
                    : ring ? String(localized: "Streaming") : live.connected ? String(localized: "Connected") : String(localized: "Offline"),
                 detail: active && live.encryptedBond ? String(localized: "Controls unlocked")
                    : ring ? String(localized: "Authenticated ring stream") : String(localized: "Standard HR is not a full bond"),
                 good: (active && live.encryptedBond) || ring ? true : (active || live.connected ? false : nil)),
            Tile(symbol: "clock.arrow.circlepath", title: String(localized: "History sync"),
                 value: live.backfilling ? String(localized: "\(live.syncChunksThisSession) chunks") : BroopActivityLiveDevice.lastSync(live.lastSyncedAt),
                 detail: syncDetail, good: live.lastSyncError != nil ? false : (live.lastSyncedAt == nil ? nil : true)),
            Tile(symbol: "battery.75percent", title: String(localized: "Battery"),
                 value: battery.map { "\($0)%" } ?? String(localized: "Unknown"),
                 detail: live.charging == true ? String(localized: "Charging")
                    : isWhoop ? String(localized: "Last reported by strap") : String(localized: "Last reported by the ring"),
                 good: battery.map { $0 > 30 ? true : false }),
            Tile(symbol: "sensor.tag.radiowaves.forward", title: String(localized: "Wear state"),
                 value: liveLink ? (worn ? String(localized: "On wrist") : String(localized: "Off wrist")) : String(localized: "Unknown"),
                 detail: liveLink ? (worn ? String(localized: "Eligible for live physiology") : String(localized: "Wear the strap for scoring"))
                    : String(localized: "Connect to read wear state"),
                 good: liveLink ? worn : nil),
        ]
    }
}

/// Live physiology: the recent R-R trace, a rolling RMSSD, and the last R-R / frame / event.
private struct LivePhysiologyCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let active = BroopActivityLiveDevice.isWhoop(model) && live.connected && live.bonded
        let ring = live.connected && live.streamingLiveHR
        let values = Array(live.rrRecent.suffix(18))
        let rmssd: Double? = {
            let v = Array(live.rrRecent.suffix(12)).map(Double.init)
            guard v.count >= 3 else { return nil }
            let d = zip(v.dropFirst(), v).map { $0 - $1 }
            return sqrt(d.map { $0 * $0 }.reduce(0, +) / Double(d.count))
        }()
        let mode: String = active && live.encryptedBond ? String(localized: "Full strap stream is active.")
            : (active || ring) ? String(localized: "Heart rate stream is active.")
            : live.connected ? String(localized: "Radio connected, stream not yet trusted.") : String(localized: "No live stream.")
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Live physiology"), size: 11)
                    Text(verbatim: mode).font(BroopType.demi(13)).foregroundStyle(BroopPalette.textBody)
                }
                Spacer()
                if let rmssd {
                    VStack(alignment: .trailing, spacing: 2) {
                        BroopCaps(String(localized: "RMSSD"), size: 9.5, color: BroopPalette.textSecondary)
                        Text(verbatim: "\(Int(rmssd.rounded())) ms").font(BroopType.number(22)).foregroundStyle(BroopPalette.teal)
                    }
                }
            }
            if values.count >= 2 {
                Chart(Array(values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("i", i), y: .value("ms", v))
                        .foregroundStyle(BroopPalette.teal)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 44)
            }
            Text(verbatim: values.isEmpty ? String(localized: "Waiting for R-R intervals.")
                 : String(localized: "Recent intervals: \(values.suffix(5).map(String.init).joined(separator: " · ")) ms"))
                .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                proof("R-R", active ? (live.rr.last.map { "\($0) ms" } ?? "—") : String(localized: "Offline"), active)
                proof(String(localized: "Frame"), active ? (live.lastFrameType ?? "—") : String(localized: "Offline"), active)
                proof(String(localized: "Event"), active ? (live.lastEvent ?? "—") : String(localized: "Offline"), active)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
    }

    private func proof(_ label: String, _ value: String, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(label, size: 9, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(13))
                .foregroundStyle(on ? BroopPalette.textPrimary : BroopPalette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(BroopPalette.row))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Strap

private struct LiveModelPicker: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    var body: some View {
        let isWhoop = BroopActivityLiveDevice.isWhoop(model)
        let active = isWhoop && live.connected && live.bonded
        if isWhoop, !active {
            let selected = WhoopModel(rawValue: selectedModelRaw) ?? .whoop4
            VStack(alignment: .leading, spacing: 12) {
                BroopCaps(String(localized: "Strap model"), size: 10.5, color: BroopPalette.textSecondary)
                HStack(spacing: 4) {
                    ForEach(WhoopModel.allCases, id: \.self) { m in
                        Button {
                            guard m.rawValue != selectedModelRaw else { return }
                            selectedModelRaw = m.rawValue
                            model.prepareStrapSwitch()
                        } label: {
                            Text(verbatim: m.displayName)
                                .font(m == selected ? BroopType.caps(12) : BroopType.demi(12))
                                .foregroundStyle(m == selected ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 8).fill(m == selected ? Color(broopHex: 0x2C3136) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(broopHex: 0x151618)))
                if selected == .whoop5mg {
                    Text("WHOOP 5.0/MG pairs with one app at a time. If a scan finds nothing, unpair it in the official WHOOP app and fully close that app, then Scan again.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
        }
    }
}

private struct LiveControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        if BroopActivityLiveDevice.isWhoop(model) {
            let active = live.connected && live.bonded
            VStack(spacing: 10) {
                LiveScanButton()
                HStack(spacing: 10) {
                    BroopActivityButton(title: String(localized: "Buzz strap"), symbol: "waveform.path", kind: .grey, height: 46) {
                        model.buzzStrapOnce()
                    }
                    .disabled(!active)
                    BroopActivityButton(title: String(localized: "Disconnect"), symbol: "xmark.circle", kind: .destructive, height: 46) {
                        model.disconnect()
                    }
                    .disabled(!live.connected)
                }
            }
        } else if BroopActivityLiveDevice.isOura(model) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: LiveRingCopy.status(model.ouraLinkPhase, streaming: live.connected && live.streamingLiveHR))
                    .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textBody)
                LiveRingButton()
            }
        }
    }
}

private struct LiveDevicesRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let name = BroopActivityLiveDevice.name(model)
        let active = BroopActivityLiveDevice.isWhoop(model) && live.connected && live.bonded
        HStack(spacing: 14) {
            BroopStrapGlyph()
                .stroke(BroopPalette.textPrimary, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 23.5)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(String(localized: "Manage devices"), size: 11)
                Text(verbatim: active ? String(localized: "Connected to \(name). Pair or switch bands in Devices.")
                                      : String(localized: "\(name) is your active band. Pair or switch bands in Devices."))
                    .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius).fill(BroopPalette.row))
    }
}

/// The strap log (newest 300 lines), Copy / Save with the same diagnostic header the export
/// writes, and the Test Centre link.
private struct LiveLogCard: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                BroopCaps(String(localized: "Strap log"), size: 11)
                Spacer()
                Button("Copy") { PlatformPasteboard.copy(live.exportableLogText()) }
                    .font(BroopType.demi(14))
                Button("Save…") {
                    Task {
                        let extra = await DebugDataDiagnostics.dynamicLines(repo: model.repo)
                        FileExport.exportText(live.exportableLogText(extraHeaderLines: extra),
                                              suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
                    }
                }
                .font(BroopType.demi(14))
            }
            .foregroundStyle(BroopPalette.textPrimary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(live.log.suffix(300).enumerated()), id: \.offset) { i, line in
                            Text(verbatim: line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(BroopPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                }
                .frame(height: 200)
                .onChange(of: live.log.count) { _, _ in
                    let tail = min(live.log.count, 300)
                    if tail > 0 { proxy.scrollTo(tail - 1, anchor: .bottom) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            NavigationLink(value: BroopScreen.testCentre) {
                HStack(spacing: 10) {
                    Image(systemName: "testtube.2")
                    BroopCaps(String(localized: "Open Test Centre to report a bug"), size: 10.5)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
                }
                .foregroundStyle(BroopPalette.textPrimary)
                .padding(.vertical, 6)
            }
            .buttonStyle(BroopPressableStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }
}
#endif
