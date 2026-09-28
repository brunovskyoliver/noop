#if os(iOS)
import Combine
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The fixed-pace breathing trainer's session: the classic `BreathingView` state machine moved into an
/// object, so the screen observes the session and not the strap. Pacing, buzzes, audio cues, the R-R
/// ingest, RMSSD and the outcome line are the classic logic, unchanged.
@MainActor
final class BroopActivityBreatheEngine: ObservableObject {
    enum Pace: Hashable {
        case catalog(String), resonance
        var label: String {
            switch self {
            case .catalog(let id):
                return String(localized: String.LocalizationValue(BreathProtocolCatalog.protocolById(id)?.title ?? id))
            case .resonance: return String(localized: "Resonance")
            }
        }
    }
    enum Length: Hashable, CaseIterable {
        case open, five, ten, fifteen
        var label: String {
            switch self {
            case .open: return String(localized: "Open")
            case .five: return String(localized: "5 min")
            case .ten: return String(localized: "10 min")
            case .fifteen: return String(localized: "15 min")
            }
        }
        var seconds: Int? {
            switch self { case .open: return nil; case .five: return 300; case .ten: return 600; case .fifteen: return 900 }
        }
        static func from(recommendedMs: Int) -> Length {
            switch recommendedMs {
            case ..<(7 * 60_000): return .five
            case ..<(12 * 60_000): return .ten
            default: return .fifteen
            }
        }
    }
    enum Phase { case inhale, hold, exhale, textOnly }

    @Published var pace: Pace = .catalog("coherence_5_5") {
        didSet {
            guard pace != oldValue else { return }
            if running { stop() }
            if case .catalog(let id) = pace, let proto = BreathProtocolCatalog.protocolById(id) {
                length = Length.from(recommendedMs: proto.recommendedDurationMs)
            }
        }
    }
    @Published var length: Length = .ten
    @Published private(set) var running = false
    @Published private(set) var orbProgress: CGFloat = 0
    @Published private(set) var phase: Phase = .inhale
    @Published private(set) var phaseLabel: String?
    @Published private(set) var sessionSeconds = 0
    @Published private(set) var breathCount = 0
    @Published private(set) var rmssd: Double?
    @Published private(set) var rrCount = 0
    @Published private(set) var endedOutcome: String?
    @Published var audioCues: Bool = UserDefaults.standard.bool(forKey: "breathe.audioCues") {
        didSet {
            UserDefaults.standard.set(audioCues, forKey: "breathe.audioCues")
            audioCues ? tones.activate() : tones.deactivate()
        }
    }

    weak var model: AppModel?
    var reduceMotion = false
    private let tones = BreathTonePlayer()
    private var stageIndex = 0
    private var phaseDeadline: Date = .distantFuture
    private var rrBuffer: [Int] = []
    private var baselineRmssd: Double?
    private var sumRmssd: Double = 0
    private var countRmssd = 0
    private var peakRmssd: Double = 0
    private var timers: Set<AnyCancellable> = []
    private let rrWindow = 30
    private let steadyOrb: CGFloat = 0.5

    var lastStoredOutcome: String { UserDefaults.standard.string(forKey: "breathe.lastOutcome") ?? "" }
    var lockedBpm: Double? { BiofeedbackPrefs.lockedPace }
    var selectedProtocol: BreathProtocol? {
        if case .catalog(let id) = pace { return BreathProtocolCatalog.protocolById(id) }
        return nil
    }
    var isGuided: Bool { selectedProtocol?.mode == .guided }
    var selectedBpm: Double {
        if case .resonance = pace { return lockedBpm ?? ResonanceEngine.fallbackBpm }
        guard let p = selectedProtocol, p.cycleDurationMs > 0 else { return 0 }
        return 60_000.0 / Double(p.cycleDurationMs)
    }
    var tagline: String {
        if case .resonance = pace {
            return String(localized: "Your locked pace · \(String(format: "%.1f", lockedBpm ?? ResonanceEngine.fallbackBpm)) br/min")
        }
        return String(localized: String.LocalizationValue(selectedProtocol?.subtitle ?? ""))
    }
    var paces: [Pace] {
        var items = BreathProtocolCatalog.pickerProtocols.map { Pace.catalog($0.id) }
        if lockedBpm != nil { items.append(.resonance) }
        return items
    }
    var phaseWord: String {
        if let phaseLabel, !phaseLabel.isEmpty { return String(localized: String.LocalizationValue(phaseLabel)) }
        switch phase {
        case .inhale: return String(localized: "Breathe in…")
        case .hold: return String(localized: "Hold…")
        case .exhale: return String(localized: "Breathe out…")
        case .textOnly: return String(localized: "Follow the cue…")
        }
    }
    var paceCaption: String {
        if case .resonance = pace {
            let cycle = 60.0 / (lockedBpm ?? ResonanceEngine.fallbackBpm)
            return String(format: "%.0f / %.0fs", cycle * BreathPacer.defaultInhaleFraction, cycle * (1 - BreathPacer.defaultInhaleFraction))
        }
        guard let p = selectedProtocol, !p.stages.isEmpty else { return isGuided ? String(localized: "Guided timer") : "—" }
        return p.stages.map { String(format: "%.1f", Double($0.durationMs) / 1000) }.joined(separator: " · ") + "s"
    }
    var outcomeLine: String? {
        if running { return nil }
        if let endedOutcome {
            return endedOutcome == "—" ? String(localized: "No RMSSD · not enough R-R data") : String(localized: "RMSSD \(endedOutcome)")
        }
        if !lastStoredOutcome.isEmpty { return String(localized: "Last session: \(lastStoredOutcome)") }
        return nil
    }
    var outcomePercent: Int? {
        guard let source = endedOutcome ?? (lastStoredOutcome.isEmpty ? nil : lastStoredOutcome), source != "—",
              let r = source.range(of: "%") else { return nil }
        return Int(source[source.startIndex..<r.lowerBound].replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces))
    }

    func appear() { if audioCues { tones.activate() } }
    func disappear() { stop(); tones.deactivate() }

    func start() {
        running = true
        ScreenIdle.keepAwake(true)
        sessionSeconds = 0; breathCount = 0; stageIndex = 0; phaseLabel = nil; endedOutcome = nil
        baselineRmssd = rmssd; sumRmssd = 0; countRmssd = 0; peakRmssd = 0
        if isGuided {
            phase = .textOnly
            phaseLabel = selectedProtocol?.title
            phaseDeadline = .distantFuture
            if !reduceMotion { orbProgress = steadyOrb }
        } else {
            arm(from: Date(), buzz: true)
        }
        Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.advance(now) }.store(in: &timers)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.second() }.store(in: &timers)
    }

    func stop() {
        let was = running
        running = false
        timers.removeAll()
        ScreenIdle.keepAwake(false)
        phaseDeadline = .distantFuture
        phaseLabel = nil
        if was { model?.stopHaptics() }
        if was { captureOutcome() }
        if reduceMotion { orbProgress = 0 } else { withAnimation(.easeInOut(duration: 0.8)) { orbProgress = 0 } }
    }

    private func second() {
        guard running else { return }
        sessionSeconds += 1
        if let target = length.seconds, sessionSeconds >= target { stop() }
    }

    private func captureOutcome() {
        guard sessionSeconds >= 120 else { return }
        guard let base = baselineRmssd, base > 0, countRmssd > 0 else { endedOutcome = "—"; return }
        let mean = sumRmssd / Double(countRmssd)
        let pct = Int(((mean - base) / base * 100).rounded())
        let core = String(localized: "\(String(format: "%+d%%", pct)) vs start · peak \(String(format: "%.0f", peakRmssd)) ms")
        endedOutcome = core
        UserDefaults.standard.set(core, forKey: "breathe.lastOutcome")
    }

    private func stages() -> [BreathStage] {
        if case .resonance = pace {
            let bpm = lockedBpm ?? ResonanceEngine.fallbackBpm
            let cycleMs = Int((60_000.0 / bpm).rounded())
            let inhaleMs = Int((Double(cycleMs) * BreathPacer.defaultInhaleFraction).rounded())
            return [BreathStage(type: .inhale, durationMs: inhaleMs), BreathStage(type: .exhale, durationMs: max(1, cycleMs - inhaleMs))]
        }
        return selectedProtocol?.stages.filter { $0.durationMs > 0 } ?? []
    }

    private func arm(from now: Date, buzz: Bool) {
        let all = stages()
        guard !all.isEmpty else { return }
        let stage = all[stageIndex % all.count]
        let mapped: Phase
        switch stage.type {
        case .inhale: mapped = .inhale
        case .hold: mapped = .hold
        case .exhale: mapped = .exhale
        case .textOnly: mapped = .textOnly
        }
        phase = mapped
        phaseLabel = stage.label
        let duration = Double(stage.durationMs) / 1000
        phaseDeadline = now.addingTimeInterval(duration)
        if reduceMotion {
            orbProgress = steadyOrb
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                switch mapped {
                case .inhale: orbProgress = 1
                case .exhale: orbProgress = 0
                case .hold, .textOnly: break
                }
            }
        }
        if buzz {
            let loops = BreathProtocolPlayer.loops(for: stage.type)
            if loops > 0 { model?.buzz(loops: UInt8(clamping: loops), gate: HapticPrefs.breathing) }
            if audioCues {
                switch mapped {
                case .inhale: tones.play(.inhale)
                case .exhale: tones.play(.exhale)
                case .hold, .textOnly: break
                }
            }
        }
    }

    private func advance(_ now: Date) {
        guard running, !isGuided, now >= phaseDeadline else { return }
        let all = stages()
        guard !all.isEmpty else { return }
        let completed = all[stageIndex % all.count]
        stageIndex += 1
        if completed.type == .exhale { breathCount += 1 }
        arm(from: now, buzz: true)
    }

    func ingest(_ rr: [Int]) {
        guard !rr.isEmpty else { return }
        rrBuffer.append(contentsOf: rr)
        if rrBuffer.count > rrWindow { rrBuffer.removeFirst(rrBuffer.count - rrWindow) }
        rrCount = rrBuffer.count
        if rrBuffer.count >= 2 {
            var sum = 0.0
            for i in 1..<rrBuffer.count { let d = Double(rrBuffer[i] - rrBuffer[i - 1]); sum += d * d }
            rmssd = (sum / Double(rrBuffer.count - 1)).squareRoot()
        } else {
            rmssd = nil
        }
        if running, let r = rmssd {
            if baselineRmssd == nil && sessionSeconds <= 60 { baselineRmssd = r }
            sumRmssd += r; countRmssd += 1; peakRmssd = max(peakRmssd, r)
        }
    }
}

/// Breathwork, WHOOP-style, over the classic `BreathingView`: BREATHE (the paced trainer), RESONANCE (the
/// find-your-pace sweep) and CALM ME (the below-heart-rate metronome), plus the stress check-in card.
struct BroopActivityBreatheView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var engine = BroopActivityBreatheEngine()
    @StateObject private var fallbackNudge = StressNudgeCenter()
    @Environment(\.stressNudgeCenter) private var injectedNudge
    @StateObject private var box = BroopActivityBiofeedbackBox()

    enum Mode: Hashable { case breathe, resonance, calm }
    @State private var mode: Mode = .breathe
    @State private var showEdu = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopActivityHeader(title: String(localized: "Breathwork"), onBack: { dismiss() }).padding(.top, 4)
                BroopUnderlineTabs(options: [Mode.breathe, .resonance, .calm], selection: $mode) {
                    switch $0 {
                    case .breathe: return String(localized: "Breathe")
                    case .resonance: return String(localized: "Resonance")
                    case .calm: return String(localized: "Calm me")
                    }
                }
                .padding(.top, 14)
                StressCheckInCard(center: injectedNudge ?? fallbackNudge) { startOneMinute() }
                    .padding(.top, 16)
                if let controller = box.controller {
                    switch mode {
                    case .breathe: breatheMode
                    case .resonance: BroopActivityResonanceMode(controller: controller).padding(.top, 20)
                    case .calm: BroopActivityCalmMode(controller: controller).padding(.top, 20)
                    }
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 80)
        }
        .broopActivityPage()
        .background(BroopActivityBreatheBinder(engine: engine, box: box))
        .onChange(of: mode) { _, _ in
            if engine.running { engine.stop() }
            box.controller?.stop()
        }
        .onAppear { engine.reduceMotion = reduceMotion; engine.appear() }
        .onDisappear { engine.disappear(); box.controller?.stop() }
        .sheet(isPresented: $showEdu) { eduSheet }
    }

    private func startOneMinute() {
        if engine.running { engine.stop() }
        let bpm = engine.lockedBpm ?? ResonanceEngine.fallbackBpm
        box.controller?.startResonanceSession(bpm: bpm, cycles: max(1, Int((60.0 * bpm / 60.0).rounded())))
    }

    // MARK: Breathe

    @ViewBuilder private var breatheMode: some View {
        HStack(spacing: 10) {
            BroopActivityChip(text: engine.running ? String(localized: "Session live") : String(localized: "Ready"),
                              symbol: engine.running ? "circle.fill" : nil,
                              color: engine.running ? BroopActivityPalette.mint : BroopPalette.textPrimary)
            BroopActivityHapticsChip()
            Spacer()
            Text(verbatim: engine.length.seconds.map { "\(clock(engine.sessionSeconds)) / \(clock($0))" } ?? clock(engine.sessionSeconds))
                .font(BroopType.number(16))
            Text(verbatim: "· \(engine.breathCount)").font(BroopType.number(16)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.top, 20)

        ZStack {
            Circle().strokeBorder(BroopPalette.rest.opacity(0.35), lineWidth: 1.5)
            Circle()
                .fill(RadialGradient(colors: [Color(broopHex: 0x7BA1BB).opacity(0.9), Color(broopHex: 0x42627F).opacity(0.6)],
                                     center: .center, startRadius: 5, endRadius: 150))
                .scaleEffect(0.35 + 0.65 * engine.orbProgress)
            VStack(spacing: 2) {
                BroopActivityBreatheBPM()
                BroopCaps(String(localized: "bpm"), size: 10, color: Color.white.opacity(0.75))
            }
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
        .padding(.top, 26)

        Text(verbatim: engine.running ? engine.phaseWord : engine.tagline)
            .font(BroopType.medium(17))
            .foregroundStyle(engine.running ? BroopPalette.textPrimary : BroopPalette.textBody)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .animation(.easeInOut(duration: 0.2), value: engine.phaseWord)

        HStack {
            BroopCaps(engine.pace.label, size: 11)
            Button { showEdu = true } label: {
                Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(BroopPalette.textSecondary)
            }
            .accessibilityLabel(Text("Protocol info"))
            Spacer()
            Text(verbatim: engine.selectedBpm > 0 ? String(format: "%.1f br/min", engine.selectedBpm)
                 : (engine.isGuided ? String(localized: "Guided") : ""))
                .font(BroopType.number(14)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.top, 26)

        chips(engine.paces, selected: engine.pace, label: { $0.label }) { engine.pace = $0 }
            .padding(.top, 10)
        BroopCaps(String(localized: "Session length"), size: 10, color: BroopPalette.textSecondary).padding(.top, 16)
        chips(BroopActivityBreatheEngine.Length.allCases, selected: engine.length, label: { $0.label }) { engine.length = $0 }
            .padding(.top, 8)
            .disabled(engine.running)
            .opacity(engine.running ? 0.5 : 1)

        HStack(spacing: 12) {
            Image(systemName: engine.audioCues ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .foregroundStyle(engine.audioCues ? BroopPalette.textPrimary : BroopPalette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio cues").font(BroopType.demi(14))
                Text("Soft tone on each phase · respects silent mode").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $engine.audioCues).labelsHidden().tint(BroopActivityPalette.mint)
        }
        .padding(.top, 18)

        HStack(spacing: 10) {
            BroopActivityButton(title: engine.running ? String(localized: "Stop session") : String(localized: "Start session"),
                                kind: engine.running ? .outline : .filled, height: 54) {
                engine.running ? engine.stop() : engine.start()
            }
            BroopActivityTestBuzz()
        }
        .padding(.top, 22)

        if let line = engine.outcomeLine {
            HStack(spacing: 10) {
                Image(systemName: "wind").foregroundStyle(BroopPalette.rest)
                Text(verbatim: line).font(BroopType.demi(13.5)).foregroundStyle(BroopPalette.textBody)
                Spacer()
                if let pct = engine.outcomePercent {
                    Text(verbatim: "\(pct >= 0 ? "+" : "−")\(abs(pct))% HRV")
                        .font(BroopType.number(13))
                        .foregroundStyle(pct >= 0 ? BroopActivityPalette.mint : BroopPalette.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(pct >= 0 ? Color(broopHex: 0x173B30) : BroopPalette.row))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(BroopPalette.card))
            .padding(.top, 16)
        }

        HStack(spacing: 10) {
            BroopActivityBreatheHRTile()
            tile(String(localized: "HRV (RMSSD)"), engine.rmssd.map { String(format: "%.0f", $0) } ?? "—", "ms",
                 engine.rrCount == 0 ? String(localized: "Waiting for R-R") : String(localized: "Last \(engine.rrCount) beats"))
            tile(String(localized: "Pace"), engine.selectedBpm > 0 ? String(format: "%.1f", engine.selectedBpm) : "—", "br/min", engine.paceCaption)
        }
        .padding(.top, 16)

        coherence.padding(.top, 12)
        BroopActivityHapticHint(text: String(localized: "Connect your strap for haptic guidance. You'll feel one pulse on the inhale, two on the exhale, so you can breathe with your eyes closed."))
            .padding(.top, 12)
    }

    private func chips<T: Hashable>(_ items: [T], selected: T, label: @escaping (T) -> String, pick: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { pick(item) } label: {
                        BroopCaps(label(item), size: 10.5, color: item == selected ? .black : BroopPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(item == selected ? Color.white : BroopActivityPalette.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ caption: String) -> some View {
        BroopActivityBreatheTile(title: title, value: value, unit: unit, caption: caption)
    }

    private var coherence: some View {
        let r = engine.rmssd
        let frac = r.map { min(max($0 / 120, 0), 1) } ?? 0
        let label: String = {
            guard let r else { return String(localized: "No data") }
            switch r {
            case ..<20: return String(localized: "Building")
            case ..<45: return String(localized: "Settling")
            case ..<80: return String(localized: "Coherent")
            default: return String(localized: "Deep calm")
            }
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopCaps(String(localized: "Coherence estimate"), size: 11)
                Spacer()
                BroopCaps(label, size: 10.5, color: (r ?? 0) >= 45 ? BroopActivityPalette.mint : BroopPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(BroopPalette.rest).frame(width: max(4, geo.size.width * frac))
                }
            }
            .frame(height: 6)
            .accessibilityLabel(Text("Coherence estimate"))
            .accessibilityValue(Text("\(Int(frac * 100)) percent"))
            Text("Estimate only: a higher RMSSD while paced usually means your parasympathetic \"rest\" branch is engaging. It is not a clinical reading; trends over a session matter more than any single number.")
                .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
    }

    private func clock(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }

    private var eduSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BroopActivityHeader(title: String(localized: "About this pace"), leadingSymbol: "xmark", onBack: { showEdu = false })
                if let p = engine.selectedProtocol {
                    Text(verbatim: String(localized: String.LocalizationValue(p.title))).font(BroopType.demi(22))
                    Text(verbatim: String(localized: String.LocalizationValue(p.subtitle))).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textBody)
                    if p.category == .presence {
                        Text(verbatim: String(localized: String.LocalizationValue(BreathProtocolCatalog.presenceIntroTitle))).font(BroopType.demi(17))
                        Text(verbatim: String(localized: String.LocalizationValue(BreathProtocolCatalog.presenceIntroBody))).font(BroopType.regular(15))
                    }
                    Text(verbatim: String(localized: String.LocalizationValue(p.edu))).font(BroopType.regular(15))
                    if let hint = p.sessionHint {
                        Text(verbatim: String(localized: String.LocalizationValue(hint))).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    if let caution = p.caution {
                        Text(verbatim: String(localized: String.LocalizationValue(caution))).font(BroopType.regular(13)).foregroundStyle(BroopPalette.warning)
                    }
                    Text("Estimate only — not medical advice. Stop if you feel unwell.").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                } else {
                    Text("Your locked resonance pace from the Resonance sweep.").font(BroopType.regular(15))
                }
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .padding(BroopMetrics.page)
        }
        .background(Color(broopHex: 0x1E2327).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Holds the resonance / calm controller, built once the environment's model and live state exist.
@MainActor
final class BroopActivityBiofeedbackBox: ObservableObject {
    @Published private(set) var controller: BiofeedbackController?
    func prepare(model: AppModel, live: LiveState) {
        if controller == nil { controller = BiofeedbackController(model: model, live: live) }
    }
}

/// Connects the engine to the strap without making the screen observe it: arms the realtime stream while
/// Breathe is up (as the classic screen does), hands R-R packets to the engine, builds the controller.
private struct BroopActivityBreatheBinder: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let engine: BroopActivityBreatheEngine
    let box: BroopActivityBiofeedbackBox

    var body: some View {
        Color.clear
            .onRRPackets(live) { engine.ingest($0) }
            .onAppear {
                engine.model = model
                model.startRealtimeHR()
                box.prepare(model: model, live: live)
            }
            .onDisappear { model.stopRealtimeHR() }
    }
}

private struct BroopActivityBreatheBPM: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Text(verbatim: model.bpm.map(String.init) ?? "—")
            .font(BroopType.number(46)).broopNumeral(46)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
    }
}

private struct BroopActivityBreatheHRTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    var body: some View {
        BroopActivityBreatheTile(title: String(localized: "Heart rate"), value: model.bpm.map { "\($0)" } ?? "—", unit: "bpm",
                                 caption: live.worn ? String(localized: "Live") : String(localized: "Strap not worn"))
    }
}

private struct BroopActivityBreatheTile: View {
    let title: String, value: String, unit: String, caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(title, size: 9.5, color: BroopPalette.textBody).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(BroopType.number(26)).broopNumeral(26).lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: unit).font(BroopType.demi(11)).foregroundStyle(BroopPalette.textSecondary)
            }
            Text(verbatim: caption).font(BroopType.regular(11)).foregroundStyle(BroopPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
    }
}

private struct BroopActivityHapticsChip: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        BroopActivityChip(text: live.bonded ? String(localized: "Haptics on") : String(localized: "Visual only"),
                          color: live.bonded ? BroopActivityPalette.mint : BroopPalette.warning)
    }
}

private struct BroopActivityTestBuzz: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    var body: some View {
        Button { model.buzz(loops: 1) } label: {
            Image(systemName: "waveform.path").font(.system(size: 18, weight: .semibold))
                .frame(width: 54, height: 54)
                .background(Circle().fill(BroopActivityPalette.chip))
        }
        .buttonStyle(BroopPressableStyle())
        .foregroundStyle(BroopPalette.textPrimary)
        .disabled(!live.bonded)
        .opacity(live.bonded ? 1 : 0.4)
        .accessibilityLabel(Text("Test buzz"))
    }
}

struct BroopActivityHapticHint: View {
    @EnvironmentObject private var live: LiveState
    let text: String
    var body: some View {
        if !live.bonded { BroopActivityNotice(symbol: "applewatch.radiowaves.left.and.right", text: text) }
    }
}

// MARK: - Resonance

private struct BroopActivityResonanceMode: View {
    @ObservedObject var controller: BiofeedbackController
    private var sweeping: Bool { if case .resonanceSweep = controller.session { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                HStack {
                    BroopCaps(String(localized: "Find your resonance pace"), size: 11)
                    Spacer()
                    BroopActivityHapticsChip()
                }
                Text("Everyone has a breathing pace (usually between 4.5 and 7 breaths a minute) where the heart's rhythm swings the most with each breath. We pace you through a few candidate paces, measure how your HRV responds, and lock the one that resonates best for you.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody).fixedSize(horizontal: false, vertical: true)
                Text("Estimate from PPG-derived R-R: relaxation guidance, not a clinical reading. Your pace drifts, so we date it and you can re-measure anytime.")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if sweeping {
                card {
                    HStack {
                        Text(verbatim: controller.sweepLabel ?? String(localized: "Sweeping…")).font(BroopType.demi(16))
                        Spacer()
                        BroopActivityChip(text: String(localized: "Live"), symbol: "circle.fill", color: BroopActivityPalette.mint)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BroopPalette.track)
                            Capsule().fill(BroopPalette.rest).frame(width: max(4, geo.size.width * controller.sweepProgress))
                        }
                    }
                    .frame(height: 6)
                    BroopActivityButton(title: String(localized: "Stop sweep"), kind: .destructive, height: 48) { controller.stop() }
                }
            } else {
                VStack(spacing: 10) {
                    BroopActivityButton(title: String(localized: "Full sweep · ~13 min"), symbol: "waveform.path.ecg", kind: .filled, height: 52) {
                        controller.startSweep(quick: false)
                    }
                    BroopActivityButton(title: String(localized: "Quick sweep · ~7 min"), symbol: "bolt", kind: .grey, height: 48) {
                        controller.startSweep(quick: true)
                    }
                    Text("Sit still and breathe with the buzz. You can stop anytime; a stopped sweep won't lock a pace.")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            if let result = controller.lastSweep {
                card {
                    HStack {
                        BroopCaps(result.didLock ? String(localized: "Your resonance pace") : String(localized: "Couldn't lock today"), size: 11)
                        Spacer()
                        BroopActivityChip(text: result.didLock ? String(localized: "Locked") : String(localized: "Fallback"),
                                          color: result.didLock ? BroopActivityPalette.mint : BroopPalette.textSecondary)
                    }
                    paceValue(result.lockedBpm)
                    if !result.didLock {
                        Text("Not enough clean beat data to lock a pace today. Try again rested, sitting still with the strap snug. For now we'll pace you at 5.5 br/min (coherence).")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    let maxRsa = result.scores.compactMap(\.rsaAmplitude).max() ?? 1
                    BroopCaps(String(localized: "RSA response by pace"), size: 9.5, color: BroopPalette.textSecondary)
                    ForEach(result.scores, id: \.bpm) { s in
                        HStack(spacing: 8) {
                            Text(verbatim: String(format: "%.1f", s.bpm)).font(BroopType.number(13)).frame(width: 34, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(BroopPalette.rest.opacity(s.scored ? 1 : 0.35))
                                    .frame(width: max(3, geo.size.width * (s.rsaAmplitude ?? 0) / max(maxRsa, 0.0001)))
                            }
                            .frame(height: 6)
                            Text(verbatim: s.rsaAmplitude.map { String(format: "%.1f", $0) } ?? "—").font(BroopType.number(13))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    if let date = BiofeedbackPrefs.lockedPaceDate, result.didLock {
                        Text("Locked \(date.formatted(date: .abbreviated, time: .omitted)) · paces drift, re-measure anytime.")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
            } else if let bpm = BiofeedbackPrefs.lockedPace {
                card {
                    BroopCaps(String(localized: "Your locked pace"), size: 11)
                    paceValue(bpm)
                    if let date = BiofeedbackPrefs.lockedPaceDate {
                        Text("Locked \(date.formatted(date: .abbreviated, time: .omitted)). Switch to Breathe to use it, or re-measure above.")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            BroopActivityHapticHint(text: String(localized: "Connect your strap for the felt cue. The sweep paces you with one buzz on the inhale, two on the exhale."))
        }
    }

    private func paceValue(_ bpm: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: String(format: "%.1f", bpm)).font(BroopType.number(40)).broopNumeral(40, color: BroopPalette.rest)
                .foregroundStyle(BroopPalette.rest)
            Text("br/min").font(BroopType.demi(14)).foregroundStyle(BroopPalette.textSecondary)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
    }
}

// MARK: - Calm me

private struct BroopActivityCalmMode: View {
    @ObservedObject var controller: BiofeedbackController
    @EnvironmentObject private var model: AppModel
    private var running: Bool { if case .calmMe = controller.session { return true }; return false }
    private var canRun: Bool { controller.canBuzz && (model.bpm.map { $0 >= 55 && $0 <= 120 } ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BroopCaps(String(localized: "Calm me"), size: 11)
                    Spacer()
                    BroopActivityChip(text: canRun ? String(localized: "Ready") : String(localized: "Strap needed"),
                                      color: canRun ? BroopPalette.textPrimary : BroopPalette.warning)
                }
                Text("The strap buzzes a gentle rhythm just below your current heart rate, a felt metronome to relax toward. It trails your heart down rather than yanking it, and stops on its own.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody).fixedSize(horizontal: false, vertical: true)
                Text("A relaxation rhythm, not cardiac control. It never paces below a safe rate and you can stop anytime. If your heart rate doesn't settle, we'll say so plainly.")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))

            if running {
                VStack(spacing: 16) {
                    HStack {
                        BroopCaps(String(localized: "Settling"), size: 11)
                        Spacer()
                        BroopActivityChip(text: String(localized: "Live"), symbol: "circle.fill", color: BroopActivityPalette.mint)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: model.bpm.map(String.init) ?? "—").font(BroopType.number(54)).broopNumeral(54)
                        Image(systemName: "arrow.right").foregroundStyle(BroopPalette.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            BroopCaps(String(localized: "Target"), size: 9.5, color: BroopPalette.textSecondary)
                            Text(verbatim: controller.calmTargetBpm.map { String(format: "%.0f", $0) } ?? "—")
                                .font(BroopType.number(26)).foregroundStyle(BroopPalette.rest)
                        }
                        Spacer()
                    }
                    if let h0 = controller.calmStartHR {
                        Text("Started at \(h0) bpm · the rhythm trails your heart down.")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    BroopActivityButton(title: String(localized: "Stop"), kind: .destructive, height: 48) { controller.stop() }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
            } else {
                BroopActivityButton(title: String(localized: "Calm me · 3 min"), symbol: "heart.fill", kind: .filled, height: 54) {
                    controller.startCalmMe()
                }
                .disabled(!canRun)
                if !controller.canBuzz {
                    Text("Connect your strap. Calm me is a felt rhythm on the wrist, so it needs a bonded connection.")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                } else if !canRun {
                    Text("Waiting for a resting heart rate. Start a live reading first, or come back when you're still.")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
                if let outcome = controller.calmOutcome {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: controller.calmDidNotFall ? "minus.circle" : "checkmark.circle")
                                .foregroundStyle(controller.calmDidNotFall ? BroopPalette.textSecondary : BroopActivityPalette.mint)
                            Text(verbatim: outcome).font(BroopType.demi(14))
                        }
                        if controller.calmDidNotFall {
                            Text("That's normal. A paced breath often settles things when a metronome alone doesn't.")
                                .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BroopPalette.card))
                }
            }
        }
    }
}
#endif
