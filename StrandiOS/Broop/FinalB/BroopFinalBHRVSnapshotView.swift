#if os(iOS)
import Combine
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The manual HRV snapshot (#127) as a Broop sheet, laid out like WHOOP's ECG reading: a caps title over
/// a faint grid, the live number, a big seconds countdown with a progress bar, the instruction, and the
/// action pinned at the bottom.
///
/// Behaviour is the `HRVSnapshotView`'s: a 60-second capture on the monotonic clock (the
/// countdown and the ingest cutoff both derive from it), every R-R interval in the window kept, a running
/// RMSSD while capturing, then `HRVSnapshotRules.analyzeCapture` (the over-count gate, the spot cleaning
/// and the Test Centre trace) and `HRVSnapshotRules.persist` (key "hrv_snapshot", source "manual-hrv").
/// The capture lives in an object so the sheet observes the capture, not the strap.
@MainActor
final class BroopFinalBHRVCapture: ObservableObject {
    enum Phase: Equatable { case idle, capturing, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var beats = 0
    @Published private(set) var secondsRemaining = HRVSnapshotRules.captureSeconds
    @Published private(set) var runningRMSSD: Double?
    @Published private(set) var result: HRVAnalyzer.HRVResult?
    @Published private(set) var saved = false
    @Published var bonded = false

    /// Uncapped on purpose: the analyzer wants the whole window.
    private var buffer: [Int] = []
    private var captureStart: ContinuousClock.Instant?
    private var ticker: AnyCancellable?
    var traceLog: ((String) -> Void)?

    var fraction: Double {
        switch phase {
        case .idle: return 0
        case .capturing:
            return Double(HRVSnapshotRules.captureSeconds - secondsRemaining) / Double(HRVSnapshotRules.captureSeconds)
        case .done: return 1
        }
    }

    func start() {
        guard bonded else { return }
        captureStart = ContinuousClock().now
        buffer.removeAll()
        beats = 0
        secondsRemaining = HRVSnapshotRules.captureSeconds
        runningRMSSD = nil
        result = nil
        saved = false
        phase = .capturing
        ScreenIdle.keepAwake(true)
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func cancel() {
        ticker = nil
        phase = .idle
        captureStart = nil
        secondsRemaining = HRVSnapshotRules.captureSeconds
        runningRMSSD = nil
        ScreenIdle.keepAwake(false)
    }

    /// The sheet went away: stop the clock and release the screen, as the `onDisappear` does.
    func release() {
        ticker = nil
        if phase == .capturing { cancel() }
        ScreenIdle.keepAwake(false)
    }

    private func elapsedMs() -> Int? {
        guard let start = captureStart else { return nil }
        let c = (ContinuousClock().now - start).components
        return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
    }

    /// A late timer fire jumps to the right remaining value instead of stretching the window.
    private func tick() {
        guard phase == .capturing, let ms = elapsedMs() else { return }
        secondsRemaining = HRVSnapshotRules.remainingSeconds(elapsedMs: ms)
        if secondsRemaining == 0 { finish() }
    }

    private func finish() {
        ticker = nil
        ScreenIdle.keepAwake(false)
        let captureMs = elapsedMs() ?? HRVSnapshotRules.captureSeconds * 1000
        captureStart = nil
        result = HRVSnapshotRules.analyzeCapture(rawRR: buffer, captureMs: captureMs) { [traceLog] line in
            traceLog?(line)
        }
        phase = .done
    }

    func ingest(_ rr: [Int]) {
        guard phase == .capturing, !rr.isEmpty,
              let ms = elapsedMs(), HRVSnapshotRules.captureWindowOpen(elapsedMs: ms) else { return }
        buffer.append(contentsOf: rr)
        beats = buffer.count
        runningRMSSD = HRVAnalyzer.rmssdRaw(buffer.map(Double.init))
    }

    func save(repo: Repository) {
        guard let rmssd = result?.rmssd, !saved else { return }
        saved = true                        // optimistic: the write is local and idempotent
        Task { [weak self] in
            if !(await HRVSnapshotRules.persist(rmssd: rmssd, repo: repo)) { self?.saved = false }
        }
    }
}

struct BroopFinalBHRVSnapshotView: View {
    var onClose: () -> Void
    var source: SpotHrvReading.Source = .unknown
    @StateObject private var capture = BroopFinalBHRVCapture()
    @EnvironmentObject private var model: AppModel

    private static let accent = Color(broopHex: 0x9B6CF0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    BroopActivityChip(text: phaseChip, symbol: capture.phase == .capturing ? "circle.fill" : nil,
                                      color: capture.phase == .capturing ? Self.accent
                                          : capture.phase == .done ? BroopActivityPalette.mint : BroopPalette.textPrimary)
                    BroopActivityChip(text: capture.bonded ? String(localized: "Strap live") : String(localized: "Not connected"),
                                      color: capture.bonded ? BroopActivityPalette.mint : BroopPalette.warning)
                    Spacer()
                }
                .padding(.top, 6)

                BroopFinalBHRVLiveBPM().padding(.top, 26)

                if capture.phase != .idle { rmssdBlock.padding(.top, 30) }

                // Once done the countdown has nothing left to say; the result carries the beats.
                if capture.phase != .done { countdown.padding(.top, 34) }

                Text(verbatim: instruction)
                    .font(BroopType.demi(23))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                if let sub = subInstruction {
                    Text(verbatim: sub)
                        .font(BroopType.medium(15))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                if capture.phase == .done, let result = capture.result { resultSection(result).padding(.top, 28) }

                if !capture.bonded {
                    BroopActivityNotice(symbol: "applewatch.radiowaves.left.and.right",
                                        text: String(localized: "An HRV reading needs the live R-R stream. Open the Live screen and connect your strap, then come back."))
                        .padding(.top, 24)
                }

                methodology.padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page + 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopActivityHeader(title: String(localized: "HRV reading"), leadingSymbol: "xmark", onBack: onClose)
                .padding(.horizontal, BroopMetrics.page)
                .accessibilityLabel(Text("Close HRV reading"))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(background)
        .background(BroopFinalBHRVBinder(capture: capture))
        .preferredColorScheme(.dark)
        .onDisappear { capture.release() }
    }

    // MARK: Pieces

    private var phaseChip: String {
        switch capture.phase {
        case .idle: return String(localized: "Ready")
        case .capturing: return String(localized: "Capturing")
        case .done: return String(localized: "Reading complete")
        }
    }

    /// The running RMSSD while capturing, the cleaned figure once done.
    private var rmssdBlock: some View {
        let value: String = {
            switch capture.phase {
            case .idle: return "–"
            case .capturing: return capture.runningRMSSD.map { String(format: "%.0f", $0) } ?? "…"
            case .done: return capture.result?.rmssd.map { String(format: "%.0f", $0) } ?? "–"
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            BroopCaps(capture.phase == .done ? String(localized: "Your HRV") : String(localized: "Live HRV"),
                      size: 10.5, color: BroopPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value)
                    .font(BroopType.number(52)).broopNumeral(52)
                    .foregroundStyle(capture.phase == .idle ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text("ms RMSSD").font(BroopType.demi(17)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(capture.phase == .done ? 0 : capture.secondsRemaining)")
                    .font(BroopType.number(84)).broopNumeral(84)
                    .foregroundStyle(BroopPalette.textPrimary)
                    .contentTransition(.numericText(countsDown: true))
                    .monospacedDigit()
                BroopCaps(String(localized: "Sec"), size: 24, color: BroopPalette.textSecondary)
                Spacer()
                if capture.phase != .idle {
                    Text("\(capture.beats) beats")
                        .font(BroopType.number(15))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(Self.accent)
                        .frame(width: max(capture.fraction > 0 ? 6 : 0, geo.size.width * capture.fraction))
                        .animation(.linear(duration: 0.9), value: capture.fraction)
                }
            }
            .frame(height: 6)
        }
        .accessibilityHidden(true)
    }

    private var instruction: String {
        switch capture.phase {
        case .idle:
            return capture.bonded
                ? String(localized: "Sit still and breathe normally. Tap below to take a 60-second reading.")
                : String(localized: "Connect your strap on the Live screen to take a reading.")
        case .capturing:
            return String(localized: "Sit still, breathe normally. Keep your wrist relaxed and steady.")
        case .done:
            if let r = capture.result, r.rmssd == nil {
                return String(localized: "Not enough clean beats. Sit still and try again.")
            }
            return String(localized: "Done. Save this reading to keep it in your trends.")
        }
    }

    private var subInstruction: String? {
        switch capture.phase {
        case .capturing: return String(localized: "The reading finishes on its own.")
        default: return nil
        }
    }

    private var accessibilityLabel: String {
        switch capture.phase {
        case .idle: return String(localized: "HRV reading not started")
        case .capturing:
            return String(localized: "Capturing. \(capture.secondsRemaining) seconds remaining, \(capture.beats) beats collected.")
        case .done:
            return capture.result?.rmssd.map { String(localized: "RMSSD \(Int($0.rounded())) milliseconds") }
                ?? String(localized: "Reading incomplete")
        }
    }

    @ViewBuilder private func resultSection(_ result: HRVAnalyzer.HRVResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopActivityDivider(title: String(localized: "Your reading"))
            if result.rmssd == nil {
                BroopActivityNotice(symbol: "exclamationmark.triangle.fill",
                                    text: String(localized: "Not enough clean beats. Sit still and try again. \(result.nClean) of \(result.nInput) beats survived filtering (need \(HRVAnalyzer.minBeats))."))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile(String(localized: "RMSSD"), HRVSnapshotRules.format(result.rmssd, "%.0f"), "ms")
                    tile(String(localized: "SDNN"), HRVSnapshotRules.format(result.sdnn, "%.0f"), "ms")
                    tile(String(localized: "Mean HR"),
                         HRVSnapshotRules.format(HRVSnapshotRules.meanHR(meanNN: result.meanNN), "%.0f"), "bpm")
                    tile(String(localized: "Beats"), "\(result.nClean)", String(localized: "used"))
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value.replacingOccurrences(of: "—", with: "–"))
                    .font(BroopType.number(28)).broopNumeral(28)
                    .foregroundStyle(BroopPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: unit).font(BroopType.demi(13)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.innerRadius, style: .continuous).fill(BroopPalette.card))
    }

    /// Source-aware methodology (#537), single-sourced with Android through `SpotHrvReading.caveatFor`.
    private var methodology: some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(String(localized: "How this is measured"), size: 10.5, color: BroopPalette.textSecondary)
            BroopFootnote(text: String(localized: "A 60-second snapshot of your beat-to-beat (R-R) intervals from the strap, cleaned (range and ectopic-beat filtering) before computing RMSSD the same way your overnight HRV is computed."))
            BroopFootnote(text: SpotHrvReading.caveatFor(source))
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if capture.phase == .done, let r = capture.result, r.rmssd != nil {
                BroopActivityButton(title: capture.saved ? String(localized: "Saved") : String(localized: "Save reading"),
                                    symbol: capture.saved ? "checkmark" : nil, kind: .filled, height: 52) {
                    capture.save(repo: model.repo)
                }
                .disabled(capture.saved)
            }
            switch capture.phase {
            case .idle:
                BroopActivityButton(title: String(localized: "Take an HRV reading"), kind: .filled, height: 52) { capture.start() }
                    .disabled(!capture.bonded)
            case .capturing:
                BroopActivityButton(title: String(localized: "Cancel"), kind: .outline, height: 52) { capture.cancel() }
            case .done:
                BroopActivityButton(title: String(localized: "Take another reading"),
                                    kind: capture.result?.rmssd == nil ? .filled : .outline, height: 52) { capture.start() }
                    .disabled(!capture.bonded)
            }
        }
        .padding(.horizontal, BroopMetrics.page + 4)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.18))
                .ignoresSafeArea()
        )
    }

    /// The ECG reading's canvas: the Broop gradient under a faint square grid that fades out downward.
    private var background: some View {
        ZStack {
            BroopBackground()
            Canvas { ctx, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
                ctx.stroke(path, with: .color(Color.white.opacity(0.05)), lineWidth: 0.5)
            }
            .mask(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.7)))
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Feeds the strap into the capture without making the sheet observe `LiveState`: R-R packets (rrSeq
/// keyed, so equal consecutive packets both count), the bond state and the Test Centre log.
private struct BroopFinalBHRVBinder: View {
    @EnvironmentObject private var live: LiveState
    let capture: BroopFinalBHRVCapture

    var body: some View {
        Color.clear
            .onRRPackets(live) { capture.ingest($0) }
            .onAppear {
                capture.bonded = live.bonded
                let log = live
                capture.traceLog = { line in log.append(log: line, domain: .hrv) }
            }
            .onChange(of: live.bonded) { _, bonded in capture.bonded = bonded }
    }
}

/// Heart icon and the live bpm, redrawn on its own.
private struct BroopFinalBHRVLiveBPM: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "heart")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(broopHex: 0x9B6CF0))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            Text(verbatim: model.bpm.map(String.init) ?? "–")
                .font(BroopType.number(32)).broopNumeral(32)
                .foregroundStyle(model.bpm == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                .contentTransition(.numericText())
            Text("bpm").font(BroopType.medium(17)).foregroundStyle(BroopPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
