#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Start Activity: the pre-start screen (activity type, live heart-rate disc, START ACTIVITY) and the
// in-activity screen (elapsed band, Effort ring, heart rate with the zone bar, averages, pause / discard /
// end). The session itself is `AppModel`'s manual workout, exactly as the classic Live Workout screen
// drives it; nothing here scores or stores anything of its own.
//
// Live values change every second, so no screen-level view here observes `AppModel` or `LiveState`.
// Each live number is its own small leaf that observes them, and only that leaf redraws per beat.

/// Full-screen cover that walks pre-start → live. Opens straight on the live screen when a workout is
/// already running, so the same entry doubles as "View active workout".
struct BroopActivityStartCover: View {
    let onClose: () -> Void
    @State private var sport: String = RecentSportsPrefs.recent().first ?? "Running"
    @State private var started = false

    var body: some View {
        ZStack {
            if started {
                BroopActivityLiveView(onClose: onClose)
                    .transition(.opacity)
            } else {
                BroopActivityPrestartView(sport: $sport, onClose: onClose, onStarted: {
                    withAnimation(.easeInOut(duration: 0.25)) { started = true }
                })
                .transition(.opacity)
            }
            BroopActivityActiveProbe { active in
                if active && !started { started = true }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Reports whether a workout is running without making its parent observe `AppModel`.
private struct BroopActivityActiveProbe: View {
    @EnvironmentObject private var model: AppModel
    let onChange: (Bool) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { onChange(model.activeWorkout != nil) }
            .onChange(of: model.activeWorkout != nil) { _, active in onChange(active) }
    }
}

// MARK: - Pre-start

struct BroopActivityPrestartView: View {
    @Binding var sport: String
    let onClose: () -> Void
    let onStarted: () -> Void
    @State private var picking = false

    var body: some View {
        VStack(spacing: 0) {
            Button { picking = true } label: {
                HStack(spacing: 14) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 40, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close"))
                    WorkoutTypeIcon(workoutType: sport, size: 30, weight: .semibold, color: .white)
                    BroopCaps(sport, size: 13).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(BroopPalette.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.black.opacity(0.35))
            .accessibilityHint(Text("Change the activity type"))

            if WorkoutCatalog.sport(named: sport)?.isDistanceSport == true {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 11))
                    Text("Route recorded with GPS")
                        .font(BroopType.demi(13))
                }
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Spacer()
            BroopActivityHRDisc()
            Spacer()

            VStack(spacing: 0) {
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 46, height: 5).padding(.top, 10)
                HStack(spacing: 14) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BroopActivityPalette.startBlue)
                    Text("Heart rate, Effort, average and peak are recorded from your strap until you end the activity.")
                        .font(BroopType.medium(13))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
                BroopActivityStartButton(sport: sport, onStarted: onStarted)
                    .padding(.horizontal, 44)
                    .padding(.top, 26)
                    .padding(.bottom, 34)
            }
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                    .fill(Color(broopHex: 0xF2F2F2))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(
            LinearGradient(colors: [Color(broopHex: 0x1B2A36), Color(broopHex: 0x0D1114)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .fullScreenCover(isPresented: $picking) {
            BroopActivityTypePicker(title: String(localized: "Start activity"), current: sport) { sport = $0 }
        }
    }
}

/// START ACTIVITY: starts `AppModel`'s manual workout for the picked sport.
private struct BroopActivityStartButton: View {
    @EnvironmentObject private var model: AppModel
    let sport: String
    let onStarted: () -> Void

    var body: some View {
        BroopActivityButton(title: String(localized: "Start activity"), kind: .blue, height: 58) {
            RecentSportsPrefs.recordSelection(sport)
            if model.activeWorkout == nil { model.startWorkout(sport: sport) }
            onStarted()
        }
    }
}

/// The blue live heart-rate disc with the strap battery under the number.
struct BroopActivityHRDisc: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    var diameter: CGFloat = 200

    var body: some View {
        ZStack {
            Circle().fill(BroopActivityPalette.startBlue.opacity(0.28))
                .frame(width: diameter * 1.25, height: diameter * 1.25)
            Circle().fill(Color(broopHex: 0x1E8FDB))
                .frame(width: diameter, height: diameter)
            VStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 26, weight: .bold))
                Text(verbatim: model.bpm.map(String.init) ?? "–")
                    .font(BroopType.number(78))
                    .broopNumeral(78)
                    .contentTransition(.numericText())
                if let pct = BroopActivityLiveDevice.battery(model, live) {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.75percent").font(.system(size: 15))
                        Text(verbatim: "\(pct)%").font(BroopType.number(17))
                    }
                    .foregroundStyle(Color(broopHex: 0x0B3F66))
                }
            }
            .foregroundStyle(.white)
        }
        .onAppear { model.startRealtimeHR() }
        .onDisappear { model.stopRealtimeHR() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.bpm.map { String(localized: "Heart rate \($0)") } ?? String(localized: "Heart rate not available")))
    }
}

// MARK: - In activity

/// The in-activity screen. Behaviour follows the classic `LiveWorkoutView`: the realtime stream is armed
/// while it is up, the screen can be held awake, End and Delete both confirm, and the screen closes by
/// itself when the workout ends elsewhere.
struct BroopActivityLiveView: View {
    let onClose: () -> Void
    @State private var confirmEnd = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            BroopActivityElapsedBand(onClose: onClose)
            ScrollView {
                VStack(spacing: 0) {
                    BroopActivityEffortRing()
                        .padding(.top, 26)
                    BroopActivityStrainCoach()
                        .padding(.top, 22)
                    BroopActivityLiveHeart()
                        .padding(.top, 30)
                    BroopActivityLiveAverages()
                        .padding(.top, 26)
                    BroopActivityDistanceRow()
                        .padding(.top, 14)
                    BroopActivitySensorRow()
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            BroopActivityLiveControls(confirmEnd: $confirmEnd, confirmDelete: $confirmDelete)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .background(
            LinearGradient(colors: [Color(broopHex: 0x1D2B33), Color(broopHex: 0x0D1114)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .background(BroopActivityLiveLifecycle(onClose: onClose))
        .overlay(BroopActivityEndDialogs(confirmEnd: $confirmEnd, confirmDelete: $confirmDelete, onClose: onClose))
        .preferredColorScheme(.dark)
    }
}

/// Arms the realtime stream, holds the screen awake when asked, and closes when the workout is gone.
private struct BroopActivityLiveLifecycle: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false
    let onClose: () -> Void

    var body: some View {
        Color.clear
            .onAppear {
                model.startRealtimeHR()
                if keepScreenOn { ScreenIdle.keepAwake(true) }
            }
            .onDisappear {
                model.stopRealtimeHR()
                ScreenIdle.keepAwake(false)
            }
            .onChange(of: model.activeWorkout == nil) { _, gone in if gone { onClose() } }
    }
}

private struct BroopActivityEndDialogs: View {
    @EnvironmentObject private var model: AppModel
    @Binding var confirmEnd: Bool
    @Binding var confirmDelete: Bool
    let onClose: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert("End this workout?", isPresented: $confirmEnd) {
                Button("Cancel", role: .cancel) { }
                Button("End", role: .destructive) {
                    model.endWorkout()
                    onClose()
                }
            } message: {
                Text("This stops recording and saves what's captured so far. It can't be resumed.")
            }
            .confirmationDialog("Delete", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.discardWorkout()
                    onClose()
                }
                Button("Cancel", role: .cancel) { }
            }
    }
}

/// The bright band behind the status bar: flag and elapsed time; grey while paused.
private struct BroopActivityElapsedBand: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    var body: some View {
        let workout = model.activeWorkout
        let paused = workout?.isPaused == true
        VStack(spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 40, height: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimise"))
                .accessibilityHint(Text("The workout keeps recording"))
                Spacer()
                if let workout {
                    HStack(spacing: 6) {
                        WorkoutTypeIcon(workoutType: workout.sport, size: 15, weight: .semibold, color: .white)
                        BroopCaps(workout.sport, size: 11)
                    }
                }
                Spacer()
                Color.clear.frame(width: 40, height: 32)
            }
            HStack(spacing: 10) {
                Image(systemName: paused ? "pause.fill" : "flag.fill").font(.system(size: 20, weight: .semibold))
                if let workout {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(verbatim: Self.clock(workout.elapsed(at: context.date)))
                            .font(BroopType.number(30))
                            .broopNumeral(30)
                            .monospacedDigit()
                    }
                }
                if paused { BroopCaps(String(localized: "Paused"), size: 12) }
            }
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background((paused ? BroopActivityPalette.chip : BroopActivityPalette.liveBand).ignoresSafeArea(edges: .top))
    }

    /// HH:MM:SS, WHOOP's live timer form, from the same pause-aware elapsed the classic clock reads.
    static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

/// The Effort ring: the running workout's Effort on the wearer's scale, with the intensity word.
private struct BroopActivityEffortRing: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    var body: some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let strain = model.activeWorkout?.liveStrain ?? 0
        let value = UnitFormatter.effortValue(strain, scale: scale)
        let maxValue = scale == .whoop ? 21.0 : 100.0
        let fraction = min(max(value / maxValue, 0), 1)
        let diameter: CGFloat = 250
        ZStack {
            Circle().stroke(Color(broopHex: 0x252C32), lineWidth: 26)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(BroopPalette.effort, style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            VStack(spacing: 6) {
                BroopCaps(String(localized: "Activity Effort"), size: 12.5)
                Text(verbatim: scale == .whoop ? String(format: "%.1f", value) : "\(Int(value.rounded()))")
                    .font(BroopType.number(76))
                    .broopNumeral(76)
                    .foregroundStyle(BroopPalette.textPrimary)
                    .contentTransition(.numericText())
                BroopCaps(StrainGauge.stateLabel(forFraction: fraction), size: 12, color: BroopPalette.textSecondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Effort") + " " + UnitFormatter.effortDisplay(strain, scale: scale)))
    }
}

/// HEART RATE, the live number and the zone bar.
private struct BroopActivityLiveHeart: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(String(localized: "Heart rate"), size: 12.5, color: BroopPalette.textBody)
            Text(verbatim: model.bpm.map(String.init) ?? "–")
                .font(BroopType.number(54))
                .broopNumeral(54)
                .foregroundStyle(BroopPalette.textPrimary)
                .contentTransition(.numericText())
            BroopActivityZoneBar(bpm: model.bpm, zoneSet: model.profile.hrZoneSet)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BroopActivityLiveAverages: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let w = model.activeWorkout
        HStack(spacing: 0) {
            column("heart.fill", String(localized: "Avg HR"), (w?.avgHr ?? 0) > 0 ? "\(w!.avgHr)" : "–")
            Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 84)
            column("bolt.heart.fill", String(localized: "Max HR"), (w?.peakHr ?? 0) > 0 ? "\(w!.peakHr)" : "–")
        }
    }

    private func column(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(BroopPalette.textSecondary)
            BroopCaps(title, size: 11, color: BroopPalette.textBody)
            Text(verbatim: value).font(BroopType.number(38)).broopNumeral(38)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
    }
}

/// Live GPS distance and pace, shown only once the recorder has an accepted fix (classic gate).
private struct BroopActivityDistanceRow: View {
    @EnvironmentObject private var model: AppModel
    var body: some View { BroopActivityDistanceLeaf(recorder: model.gpsRecorder) }
}

private struct BroopActivityDistanceLeaf: View {
    @ObservedObject var recorder: GpsWorkoutRecorder
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    var body: some View {
        if recorder.isRecording, recorder.pointCount > 0 {
            let system = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
            HStack(spacing: 0) {
                stat(String(localized: "Distance"), UnitFormatter.distanceFromMeters(recorder.distanceM, system: system))
                Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
                stat(String(localized: "Pace"), UnitFormatter.paceFromSecPerKm(recorder.paceSecPerKm, system: system))
            }
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(BroopType.number(24)).broopNumeral(24)
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Speed, cadence and power from a connected fitness sensor, when one is feeding them.
private struct BroopActivitySensorRow: View {
    @EnvironmentObject private var live: LiveState
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    var body: some View {
        if live.hasSensorMetrics {
            let system = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
            let speed = UnitFormatter.speedFromKilometersPerHour(live.sensorSpeedKmh, system: system)
            let cadence = LiveState.formatCadence(live.sensorCadence)
            let power = LiveState.formatPowerWatts(live.sensorPowerWatts)
            HStack(spacing: 0) {
                if let speed { stat(String(localized: "Speed"), speed) }
                if let cadence { stat(String(localized: "Cadence"), "\(cadence)/min") }
                if let power { stat(String(localized: "Power"), "\(power) W") }
            }
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(BroopType.number(22)).broopNumeral(22)
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BroopActivityLiveControls: View {
    @EnvironmentObject private var model: AppModel
    @Binding var confirmEnd: Bool
    @Binding var confirmDelete: Bool

    var body: some View {
        let paused = model.activeWorkout?.isPaused == true
        HStack(spacing: 12) {
            circle("trash", tint: BroopPalette.bandLow, label: String(localized: "Delete")) { confirmDelete = true }
            circle(paused ? "play.fill" : "pause.fill", tint: .white,
                   label: paused ? String(localized: "Resume") : String(localized: "Pause")) { model.toggleWorkoutPause() }
            BroopActivityButton(title: String(localized: "End activity"), kind: .outline, height: 56) { confirmEnd = true }
        }
    }

    private func circle(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Circle().fill(BroopActivityPalette.chip))
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(label))
    }
}
#endif
