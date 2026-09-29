#if os(iOS)
import SwiftUI
import Combine
import StrandAnalytics
import StrandDesign

/// One app-wide 1 Hz buffer of live heart rate for the live stress reading, so the Stress screen's gauge,
/// the Home tile and the Health card all score the SAME window and cannot show two different "now" values.
/// It only runs while at least one live stress view is on screen, and it publishes only when the rounded
/// reading changes, so a subscriber redraws at most when the displayed number would.
@MainActor
final class BroopHealthStressLive: ObservableObject {
    static let shared = BroopHealthStressLive()

    /// The current live reading (nil = not connected, too few samples, or no waking reference yet).
    @Published private(set) var reading: StressMonitor.LiveReading?

    private var samples: [(ts: Int, bpm: Double)] = []
    private var wake: StressMonitor.WakeReference?
    private var clients = 0
    private var subscriptions = Set<AnyCancellable>()
    private var lastPacket: Date?
    private var loop: Task<Void, Never>?

    /// Start (or join) the sampler. `wake` is today's waking reference from `Repository.stressToday()`.
    func attach(live: LiveState, model: AppModel) {
        clients += 1
        guard loop == nil else { return }
        live.$heartRate.dropFirst().sink { [weak self] bpm in
            guard live.connected, let bpm, bpm > 0 else { return }
            self?.receive(bpm: Double(bpm))
        }.store(in: &subscriptions)
        live.$rrSeq.dropFirst().sink { [weak self] _ in
            guard live.connected else { return }
            // Fresh R-R packets can supply the pulse even when the HR characteristic is quiet.
            let valid = live.rr.filter { $0 >= 273 && $0 <= 2000 }
            guard !valid.isEmpty else { return }
            let mean = Double(valid.reduce(0, +)) / Double(valid.count)
            self?.receive(bpm: 60_000 / mean)
        }.store(in: &subscriptions)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick(live: live, model: model)
            }
        }
    }

    func detach() {
        clients = max(0, clients - 1)
        if clients == 0 {
            loop?.cancel(); loop = nil
            subscriptions.removeAll()
            samples.removeAll(); lastPacket = nil; reading = nil
        }
    }

    func setReference(_ ref: StressMonitor.WakeReference?) {
        guard ref != wake else { return }
        wake = ref
        recompute()
    }

    private func receive(bpm: Double) {
        let now = Date()
        let ts = Int(now.timeIntervalSince1970)
        lastPacket = now
        // At most one observation per second even if both characteristics publish.
        if samples.last?.ts == ts { samples.removeLast() }
        samples.append((ts, bpm))
        samples.removeAll { ts - $0.ts >= StressMonitor.liveWindowSeconds }
        recompute()
    }

    private func tick(live: LiveState, model: AppModel) {
        guard live.connected, let lastPacket, Date().timeIntervalSince(lastPacket) < 15 else {
            samples.removeAll(); reading = nil
            return
        }
        samples.removeAll { Int(Date().timeIntervalSince1970) - $0.ts >= StressMonitor.liveWindowSeconds }
        recompute()
    }

    private func recompute() {
        var next: StressMonitor.LiveReading?
        if let wake {
            next = StressMonitor.liveReading(hrWindow: samples.map(\.bpm), wake: wake)
            if case let .level(l)? = next { next = .level((l * 10).rounded() / 10) }
        }
        if next != reading { reading = next }
    }
}

/// The ONE rule for "the current stress value": the live reading while connected and scorable, else the
/// newest scored epoch of today's analysis. Used by the gauge, the Home tile and the Health card.
struct BroopHealthStressNow: Equatable {
    enum Source: Equatable { case live, latest }
    let level: Double?
    /// True when the live window reads as movement rather than stress.
    let active: Bool
    let time: Date?
    let source: Source

    static func resolve(live: StressMonitor.LiveReading?, latest: StressMonitor.Epoch?, now: Date = Date()) -> BroopHealthStressNow? {
        switch live {
        case .level(let l)?: return BroopHealthStressNow(level: l, active: false, time: now, source: .live)
        case .active?: return BroopHealthStressNow(level: nil, active: true, time: now, source: .live)
        case nil:
            guard let e = latest, let l = e.level else { return nil }
            return BroopHealthStressNow(level: l, active: false,
                                        time: Date(timeIntervalSince1970: TimeInterval(e.startTs + StressMonitor.epochSeconds)),
                                        source: .latest)
        }
    }
}

/// Attaches the calling view to the shared live sampler for its lifetime and hands it today's reference.
private struct BroopHealthStressLiveAttach: ViewModifier {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    let reference: StressMonitor.WakeReference?

    func body(content: Content) -> some View {
        content
            .onAppear { BroopHealthStressLive.shared.attach(live: live, model: model) }
            .onDisappear { BroopHealthStressLive.shared.detach() }
            .onChange(of: reference) { _, r in if let r { BroopHealthStressLive.shared.setReference(r) } }
            .task { if let reference { BroopHealthStressLive.shared.setReference(reference) } }
    }
}

extension View {
    func broopHealthStressLive(reference: StressMonitor.WakeReference?) -> some View {
        modifier(BroopHealthStressLiveAttach(reference: reference))
    }
}

/// Home "STRESS MONITOR" tile: badge with the current value, band word, and the reading time. Its own view
/// so only it redraws when the live reading moves.
struct BroopHealthStressHomeTile: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var liveStress = BroopHealthStressLive.shared
    @State private var today: StressMonitor.DayResult?
    @State private var loaded = false

    var body: some View {
        let now = BroopHealthStressNow.resolve(live: liveStress.reading, latest: today?.latest)
        let band = now?.level.map { StressBand(score: $0) }
        let color = band.map { BroopVitals.stressColor($0) } ?? BroopPalette.textSecondary
        BroopMonitorTile(
            title: [String(localized: "Stress"), String(localized: "Monitor")],
            status: [now?.active == true ? String(localized: "Elevated pulse") : (band?.title ?? (loaded ? String(localized: "No data") : String(localized: "Calibrating")))],
            statusColor: now?.active == true ? BroopPalette.textPrimary : color,
            detail: now.map { n in n.source == .live ? String(localized: "Live") : (n.time.map { $0.formatted(date: .omitted, time: .shortened) } ?? "") }
                ?? String(localized: "Wear to measure")
        ) {
            Text(verbatim: now?.level.map { StressTrace.formatLevel($0) } ?? "–")
                .font(BroopType.number(13.5))
                .broopNumeral(13.5, color: color)
                .foregroundStyle(color)
                .frame(width: 25, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.22)))
        }
        .task(id: repo.refreshSeq) {
            today = await repo.stressToday()
            loaded = true
        }
        .broopHealthStressLive(reference: today?.wake)
    }
}

/// The Health tab's Stress Monitor card body: current value, band, time, and today's line in miniature.
struct BroopHealthStressCardBody: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var liveStress = BroopHealthStressLive.shared
    @State private var today: StressMonitor.DayResult?
    @State private var loaded = false

    var body: some View {
        let now = BroopHealthStressNow.resolve(live: liveStress.reading, latest: today?.latest)
        Group {
            if let now {
                let band = now.level.map { StressBand(score: $0) }
                let color = band.map(BroopHealthStressBand.color) ?? BroopPalette.textPrimary
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: now.level.map(StressTrace.formatLevel) ?? "--")
                        .font(BroopType.number(40))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .broopNumeral(40)
                    VStack(alignment: .leading, spacing: 3) {
                        BroopCaps(now.active ? String(localized: "Elevated pulse") : (band?.title ?? ""), size: 13, color: color)
                        Text(verbatim: now.source == .live ? String(localized: "Live")
                             : String(localized: "Last updated \(now.time?.formatted(date: .omitted, time: .shortened) ?? "")"))
                            .font(BroopType.medium(13))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    Spacer()
                }
                if let today {
                    BroopHealthStressSparkline(epochs: today.epochs)
                        .frame(height: 46)
                        .padding(.top, 10)
                }
            } else {
                Text(loaded ? "No stress reading yet today. Wear your strap and it appears once there are a few minutes of heart rate."
                            : "Reading today's heart rate…")
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: repo.refreshSeq) {
            today = await repo.stressToday()
            loaded = true
        }
        .broopHealthStressLive(reference: today?.wake)
    }
}

/// A small, non-interactive version of the day line (no axes).
struct BroopHealthStressSparkline: View {
    let epochs: [StressMonitor.Epoch]

    var body: some View {
        Canvas { ctx, size in
            guard epochs.count > 1 else { return }
            let n = CGFloat(epochs.count - 1)
            func y(_ l: Double) -> CGFloat { size.height * (1 - CGFloat(min(max(l / 3, 0), 1))) }
            let ramp = Gradient(colors: [BroopHealthPalette.stressHigh, BroopHealthPalette.stressMedium, BroopHealthPalette.stressLow])
            var path = Path(); var open = false
            for (i, e) in epochs.enumerated() {
                guard let l = e.level else { open = false; continue }
                let p = CGPoint(x: size.width * CGFloat(i) / n, y: y(l))
                if open { path.addLine(to: p) } else { path.move(to: p); open = true }
            }
            ctx.stroke(path, with: .linearGradient(ramp, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
#endif
