#if os(iOS)
import Combine
import SwiftUI
import StrandDesign

/// The classic `IntervalTimerView` timer in an object: work / rest / rounds, the 1 Hz tick, strap buzzes
/// (triple into work, single into rest, 3-2-1 ticks, a long finish) and the iPhone haptic cues.
@MainActor
final class BroopActivityIntervalEngine: ObservableObject {
    enum Phase { case work, rest, done }
    enum Cue { case work, rest, tick, done }

    @Published var workSeconds = 30 { didSet { if !running { reset() } } }
    @Published var restSeconds = 15 { didSet { if !running { reset() } } }
    @Published var rounds = 8 {
        didSet {
            if currentRound > rounds { currentRound = rounds }
            if !running { reset() }
        }
    }
    @Published private(set) var phase: Phase = .work
    @Published private(set) var currentRound = 1
    @Published private(set) var remaining = 30
    @Published private(set) var running = false { didSet { ScreenIdle.keepAwake(running) } }
    @Published private(set) var elapsed = 0
    @Published private(set) var hapticTick = 0
    private(set) var lastCue: Cue = .work

    weak var model: AppModel?
    weak var live: LiveState?
    private var ticker: AnyCancellable?

    var phaseDuration: Int {
        switch phase { case .work: return max(1, workSeconds); case .rest: return max(1, restSeconds); case .done: return 1 }
    }
    var progress: Double { min(1, max(0, Double(phaseDuration - remaining) / Double(phaseDuration))) }
    var totalPlanned: Int { rounds > 0 ? workSeconds * rounds + restSeconds * max(0, rounds - 1) : 0 }
    var isFinished: Bool { phase == .done }
    var isPristine: Bool { !running && remaining == phaseDuration && currentRound == 1 && phase == .work && elapsed == 0 }

    init() {
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }

    func toggle() {
        if isFinished { reset() }
        if running { running = false; return }
        let fresh = phase == .work && currentRound == 1 && remaining == max(1, workSeconds) && elapsed == 0
        running = true
        if fresh { buzz(3); cue(.work) }
    }

    func stopAndReset() { running = false; reset() }

    func reset() {
        phase = .work; currentRound = 1; remaining = max(1, workSeconds); elapsed = 0
    }

    private func tick() {
        guard running, !isFinished else { return }
        if remaining <= 3 && remaining >= 1 { buzz(1); cue(.tick) }
        if remaining > 1 { remaining -= 1; elapsed += 1; return }
        elapsed += 1
        switch phase {
        case .work:
            if currentRound >= rounds {
                withAnimation(.snappy) { phase = .done; remaining = 0; running = false }
                buzz(5); cue(.done)
            } else {
                phase = .rest; remaining = max(1, restSeconds); buzz(1); cue(.rest)
            }
        case .rest:
            currentRound += 1; phase = .work; remaining = max(1, workSeconds); buzz(3); cue(.work)
        case .done: break
        }
    }

    private func buzz(_ loops: UInt8) {
        guard live?.bonded == true else { return }
        model?.buzz(loops: loops, gate: HapticPrefs.intervals)
    }

    private func cue(_ c: Cue) { lastCue = c; hapticTick &+= 1 }
}

/// Interval timer, WHOOP-style: a big ring counting down the current block, WORK / REST in caps, the
/// round, start / pause / reset, the session overview and the configuration steppers.
struct BroopActivityIntervalsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = BroopActivityIntervalEngine()

    private var color: Color {
        switch engine.phase {
        case .work: return BroopPalette.effort
        case .rest: return BroopActivityPalette.rest
        case .done: return BroopActivityPalette.mint
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BroopActivityIntervalBondChip()
                    Spacer()
                    BroopActivityChip(text: engine.running ? String(localized: "Running") : engine.isFinished ? String(localized: "Complete") : String(localized: "Paused"),
                                      color: engine.running ? BroopActivityPalette.mint : BroopPalette.textSecondary)
                }
                .padding(.top, 12)

                ZStack {
                    Circle().stroke(Color(broopHex: 0x1E2328), lineWidth: 22)
                    Circle().trim(from: 0, to: max(0.0001, engine.isFinished ? 1 : engine.progress))
                        .stroke(color, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .animation(.snappy, value: engine.remaining)
                    VStack(spacing: 6) {
                        BroopCaps(engine.phase == .work ? String(localized: "Work") : engine.phase == .rest ? String(localized: "Rest") : String(localized: "Done"),
                                  size: 15, color: color)
                        Text(verbatim: engine.isFinished ? "✓" : "\(engine.remaining)")
                            .font(BroopType.number(90)).broopNumeral(90)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        BroopCaps(String(localized: "Round \(min(engine.currentRound, engine.rounds)) of \(engine.rounds)"), size: 11,
                                  color: BroopPalette.textSecondary)
                    }
                }
                .frame(width: 260, height: 260)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(engine.isFinished ? "Session done" : "\(engine.remaining) seconds remaining"))

                HStack(spacing: 10) {
                    BroopActivityButton(title: engine.running ? String(localized: "Pause") : (engine.isFinished ? String(localized: "Restart") : String(localized: "Start")),
                                        symbol: engine.running ? "pause.fill" : "play.fill", kind: .filled, height: 54) { engine.toggle() }
                    BroopActivityButton(title: String(localized: "Reset"), symbol: "arrow.counterclockwise", kind: .grey, height: 54) { engine.stopAndReset() }
                        .disabled(engine.isPristine)
                        .frame(width: 130)
                }
                .padding(.top, 30)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        BroopCaps(String(localized: "Session"), size: 11)
                        Spacer()
                        Text(verbatim: "\(clock(engine.elapsed)) / \(clock(engine.totalPlanned))").font(BroopType.number(16))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BroopPalette.track)
                            Capsule().fill(BroopPalette.effort)
                                .frame(width: max(4, geo.size.width * (engine.totalPlanned > 0 ? min(1, Double(engine.elapsed) / Double(engine.totalPlanned)) : 0)))
                        }
                    }
                    .frame(height: 6)
                    HStack(spacing: 0) {
                        stat(String(localized: "Work"), "\(engine.workSeconds)s")
                        stat(String(localized: "Rest"), "\(engine.restSeconds)s")
                        stat(String(localized: "Rounds"), "\(engine.rounds)")
                        stat(String(localized: "Remaining"), clock(max(0, engine.totalPlanned - engine.elapsed)))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
                .padding(.top, 26)

                VStack(spacing: 0) {
                    stepper(String(localized: "Work"), String(localized: "sec"), $engine.workSeconds, 5...600, 5)
                    BroopHairline()
                    stepper(String(localized: "Rest"), String(localized: "sec"), $engine.restSeconds, 5...600, 5)
                    BroopHairline()
                    stepper(String(localized: "Rounds"), nil, $engine.rounds, 1...30, 1)
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
                .disabled(engine.running)
                .opacity(engine.running ? 0.5 : 1)
                .padding(.top, 12)

                BroopActivityHapticHint(text: String(localized: "Bond your strap on the Live screen to feel the transitions hands-free."))
                    .padding(.top, 12)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopActivityHeader(title: String(localized: "Interval timer"), inBar: true, onBack: { dismiss() })
        }
        .broopActivityPage()
        .background(BroopActivityIntervalBinder(engine: engine))
        .onAppear { if engine.remaining == 0 { engine.reset() } }
        .onDisappear { ScreenIdle.keepAwake(false) }
        .sensoryFeedback(trigger: engine.hapticTick) { _, _ in
            switch engine.lastCue {
            case .work: return .impact(weight: .heavy)
            case .rest: return .impact(weight: .light)
            case .tick: return .selection
            case .done: return .success
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BroopCaps(title, size: 9, color: BroopPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(BroopType.number(18)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepper(_ title: String, _ unit: String?, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(title, size: 11.5)
                Text(verbatim: "\(range.lowerBound)-\(range.upperBound)\(unit.map { " \($0)" } ?? "") · step \(step)")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer()
            Text(verbatim: "\(value.wrappedValue)\(unit.map { " \($0)" } ?? "")").font(BroopType.number(20))
            Stepper("", value: value, in: range, step: step).labelsHidden()
                .accessibilityLabel(Text("\(title) \(unit ?? "")"))
        }
        .frame(minHeight: 64)
    }

    private func clock(_ s: Int) -> String { String(format: "%d:%02d", max(0, s) / 60, max(0, s) % 60) }
}

private struct BroopActivityIntervalBinder: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let engine: BroopActivityIntervalEngine
    var body: some View {
        Color.clear.onAppear { engine.model = model; engine.live = live }
    }
}

private struct BroopActivityIntervalBondChip: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        BroopActivityChip(text: live.bonded ? String(localized: "Buzz cues on") : String(localized: "Connect strap for buzz cues"),
                          color: live.bonded ? BroopActivityPalette.mint : BroopPalette.warning)
    }
}
#endif
