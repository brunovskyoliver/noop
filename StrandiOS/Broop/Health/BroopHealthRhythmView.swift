#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore
import WhoopProtocol

/// Broop Rhythm (`.rhythm`): the experimental beat-to-beat visualization, rebuilt from the classic
/// `RhythmHost` + `RhythmView`. Same consent record (nothing loads or computes until the version-stamped
/// clickwrap is accepted), same night read and window gating, same descriptive stats, neutral wording,
/// CSV share and permanent disclaimer. Never a verdict, never alarm colours.
struct BroopHealthRhythmView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(RhythmConsent.acceptedVersionKey) private var acceptedVersion = ""
    @AppStorage(RhythmConsent.enabledKey) private var enabled = false

    @State private var night: RhythmScreener.NightRhythmSummary?
    @State private var windows: [RhythmScreener.WindowResult] = []
    @State private var emptyReason: RhythmEmptyState = .gatheringData
    @State private var loaded = false
    @State private var loading = false
    @State private var exportURL: URL?
    @State private var checked = false
    @Environment(\.dismiss) private var dismiss

    private static let calm = BroopPalette.rest
    private var consentGiven: Bool { enabled && RhythmConsent.isAccepted(acceptedVersion) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if consentGiven { visualization } else { consent }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Rhythm"), subtitle: String(localized: "Experimental"))
        }
        .broopHealthScreen()
        .task(id: "\(consentGiven)|\(repo.refreshSeq)") {
            guard consentGiven, !loaded else { return }
            loading = true
            await load()
            loaded = true
            loading = false
            exportURL = buildExport()
        }
    }

    // MARK: Consent

    private var consent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Before you turn on Rhythm").font(BroopType.demi(24)).foregroundStyle(BroopPalette.textPrimary)
                .padding(.top, 16)
            Text("An experimental picture of your beat-to-beat timing. Please read these first.")
                .font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(RhythmConsent.points, id: \.0) { point in
                    VStack(alignment: .leading, spacing: 4) {
                        BroopCaps(point.0, size: 11.5)
                        Text(verbatim: point.1).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
            BroopHealthFootnote(text: String(localized: "This is a wellness visualization, not a screening test. It does not tell you to see a clinician and it names no condition. This is not legal or medical advice."))
            Toggle(isOn: $checked) {
                Text("I understand this is an experimental wellness feature, not a medical device or a diagnosis.")
                    .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(BroopHealthPalette.mint)
            BroopHealthButton(title: String(localized: "Turn on Rhythm")) {
                acceptedVersion = RhythmConsent.currentVersion
                enabled = true
            }
            .disabled(!checked)
            BroopHealthButton(title: String(localized: "Not now"), kind: .secondary) { dismiss() }
        }
    }

    // MARK: Visualization

    private var headline: RhythmScreener.WindowResult? {
        let readable = windows.filter { $0.label != .unreadable }
        return readable.first { $0.label == .varied } ?? readable.first { $0.label == .occasionalEctopy } ?? readable.first
    }
    private var points: [RhythmScreener.PoincarePoint] { windows.flatMap { $0.poincare } }

    @ViewBuilder private var visualization: some View {
        if !loaded {
            ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 60)
        } else if points.isEmpty {
            BroopHealthEmpty(symbol: "waveform.path", title: emptyTitle, message: emptyMessage).padding(.top, 20)
        } else {
            summary.padding(.top, 14)
            scatter.padding(.top, 14)
            stats.padding(.top, BroopMetrics.section)
            if let exportURL {
                ShareLink(item: exportURL) {
                    BroopHealthRow(symbol: "square.and.arrow.up", title: String(localized: "Share the numbers"),
                                   detail: String(localized: "A neutral CSV of the descriptive data"))
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 14)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(String(localized: "How this is measured"), size: 11.5)
            Text("During quiet, still, resting windows, NOOP looks at the timing between your heartbeats (R-R intervals) and draws their Poincaré scatter. From the cloud it computes its short and long axes (SD1, SD2) and a few plain regularity numbers. Movement and noisy windows are skipped, not shown. These are transparent, published descriptive statistics: a picture of your timing, never a clinical measurement.")
                .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        .padding(.top, BroopMetrics.section)
        BroopHealthInfoBanner(text: String(localized: "Experimental wellness visualization: not a diagnosis, not an ECG, and not a medical device. It cannot detect any heart condition. Beat-to-beat variation has many ordinary, benign causes. If you feel unwell or are worried, contact a qualified professional; in an emergency, your local emergency service. Everything is computed on your device."))
            .padding(.top, 12)
        Button {
            enabled = false
        } label: {
            BroopCaps(String(localized: "Turn off Rhythm"), size: 11, color: BroopPalette.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    private var label: RhythmRegularity { night?.overall ?? headline?.label ?? .unreadable }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopCaps(String(localized: "Last night"), size: 12.5)
                Spacer()
                BroopCaps(confidenceText, size: 10, color: BroopPalette.textSecondary)
            }
            HStack(spacing: 8) {
                Image(systemName: label == .steady ? "checkmark.circle.fill"
                      : (label == .unreadable ? "questionmark.circle" : "waveform.path.ecg"))
                Text(verbatim: chip)
            }
            .font(BroopType.demi(15))
            .foregroundStyle(Self.calm)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Self.calm.opacity(0.16)))
            Text(verbatim: detail).font(BroopType.regular(14.5)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            if let hw = headline {
                bar(String(localized: "Beat-to-beat variation"), hw.normRmssd)
                bar(String(localized: "Extra or skipped beats"), hw.ectopicFraction)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func bar(_ title: String, _ frac: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
                Spacer()
                Text(verbatim: percent(frac)).font(BroopType.number(14)).foregroundStyle(BroopPalette.textPrimary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(Self.calm).frame(width: g.size.width * CGFloat(max(0, min(1, frac ?? 0))))
                }
            }
            .frame(height: 5)
        }
    }

    private var scatter: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopCaps(String(localized: "Beat-to-beat scatter"), size: 12.5)
            Canvas { ctx, size in
                let s = min(size.width, size.height), inset: CGFloat = 8, plot = s - 16
                let ox = (size.width - s) / 2
                func map(_ v: Double) -> CGFloat { inset + CGFloat((min(max(v, 300), 1500) - 300) / 1200) * plot }
                var grid = Path()
                for i in 0...4 {
                    let t = inset + CGFloat(i) / 4 * plot
                    grid.move(to: CGPoint(x: ox + inset, y: t)); grid.addLine(to: CGPoint(x: ox + s - inset, y: t))
                    grid.move(to: CGPoint(x: ox + t, y: inset)); grid.addLine(to: CGPoint(x: ox + t, y: s - inset))
                }
                ctx.stroke(grid, with: .color(BroopHealthPalette.grid), lineWidth: 1)
                var diag = Path()
                diag.move(to: CGPoint(x: ox + inset, y: s - inset)); diag.addLine(to: CGPoint(x: ox + s - inset, y: inset))
                ctx.stroke(diag, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                for p in points {
                    let r: CGFloat = 1.6
                    ctx.fill(Path(ellipseIn: CGRect(x: ox + map(p.x) - r, y: s - map(p.y) - r, width: 2 * r, height: 2 * r)),
                             with: .color(Self.calm.opacity(0.6)))
                }
            }
            .frame(height: 260)
            .accessibilityHidden(true)
            Text("Each dot pairs one heartbeat interval with the next. A tight line along the diagonal means a steady beat; a rounder, more spread-out cloud means the timing varied more.")
                .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopCaps(String(localized: "The numbers"), size: 12.5)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile(String(localized: "Short axis"), fmt(headline?.sd1, "%.0f"), String(localized: "SD1 · ms"))
                tile(String(localized: "Long axis"), fmt(headline?.sd2, "%.0f"), String(localized: "SD2 · ms"))
                tile(String(localized: "Cloud shape"), fmt(headline?.sd1sd2, "%.2f"), String(localized: "SD1:SD2 ratio"))
                tile(String(localized: "Beat-to-beat"), percent(headline?.normRmssd), String(localized: "variation index"))
                tile(String(localized: "Extra / skipped"), percent(headline?.ectopicFraction), String(localized: "of beats"))
                tile(String(localized: "Beats read"), headline.map { "\($0.nBeats)" } ?? "–", String(localized: "clean intervals"))
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
            Text(verbatim: value).font(BroopType.number(30)).foregroundStyle(BroopPalette.textPrimary)
            Text(verbatim: caption).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopHealthPalette.vitalCard))
    }

    // MARK: Copy (classic, neutral)

    private var chip: String {
        switch label {
        case .steady: return String(localized: "Steady")
        case .occasionalEctopy: return String(localized: "Some variation")
        case .varied: return String(localized: "More varied")
        case .unreadable: return String(localized: "No clear reading")
        }
    }

    private var detail: String {
        switch label {
        case .steady: return String(localized: "Across the quiet windows we could read, your beat-to-beat timing held a tight, even shape.")
        case .occasionalEctopy: return String(localized: "Mostly steady, with a few isolated extra or skipped beats. Very common and usually nothing.")
        case .varied: return String(localized: "The scatter looked rounder and more spread out than a tight, steady beat. This has many ordinary causes and is not a diagnosis.")
        case .unreadable: return String(localized: "There wasn't a calm, still window clean enough to describe. Try again after a settled night.")
        }
    }

    private var confidenceText: String {
        let readable = night?.readableWindows ?? windows.filter { $0.label != .unreadable }.count
        switch headline?.confidence ?? .calibrating {
        case .solid: return String(localized: "Solid")
        case .building: return readable <= 1 ? String(localized: "Building (1 window)") : String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    private var emptyTitle: String {
        switch emptyReason {
        case .deviceBanksBeats, .deviceNoMotion: return String(localized: "This device can't support a rhythm reading")
        case .none, .gatheringData: return String(localized: "No clear reading yet")
        }
    }

    private var emptyMessage: String {
        switch emptyReason {
        case .deviceBanksBeats:
            return String(localized: "Rhythm needs beat-to-beat timing measured one beat at a time. Your device stores its heartbeats in batches, so the exact spacing between them isn't recoverable. Nothing is wrong with your night.")
        case .deviceNoMotion:
            return String(localized: "Rhythm reads only during still, resting windows, and this device doesn't record the stillness signal it needs to find them. Nothing is wrong with your night.")
        case .none, .gatheringData:
            return String(localized: "Rhythm only looks during quiet, still, resting windows, so it needs a calm night's worth of steady beats. Once there's a clean window, the scatter and its description show here.")
        }
    }

    private func fmt(_ v: Double?, _ f: String) -> String { v.map { String(format: f, $0) } ?? "–" }
    private func percent(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }

    // MARK: Load (classic RhythmHost.load)

    private func load() async {
        guard let lastSleep = (await repo.allSleepSessions(days: 14)).last else { return }
        let lo = lastSleep.effectiveStartTs, hi = lastSleep.endTs
        guard hi > lo else { return }
        let rrRows = await repo.rrIntervals(from: lo, to: hi, limit: 200_000)
        guard !rrRows.isEmpty else { return }
        let grav = await repo.gravitySamplesUnion(from: lo, to: hi, limit: 200_000)
        let result: [RhythmScreener.WindowResult] = {
            let windowSec = 5 * 60
            var results: [RhythmScreener.WindowResult] = []
            var t = lo
            while t < hi {
                let wEnd = min(t + windowSec, hi)
                let wRR = rrRows.filter { $0.ts >= t && $0.ts < wEnd }
                if wRR.count >= RhythmScreener.windowMinBeats {
                    let still = Self.isStill(grav.filter { $0.ts >= t && $0.ts < wEnd })
                    results.append(RhythmScreener.screenWindow(RhythmScreener.WindowInput(rr: wRR, motionStill: still)))
                }
                t = wEnd
            }
            return results
        }()
        windows = result
        night = RhythmScreener.summarizeNight(result)
        emptyReason = RhythmScreener.classifyEmptyState(
            windows: result, hadMotionSignal: !grav.isEmpty,
            beatsAreBanked: RhythmScreener.nightBeatsAreBanked(rrMs: rrRows.map { Double($0.rrMs) }, tsSec: rrRows.map { $0.ts }))
    }

    /// The classic stillness gate: normalised gravity-magnitude SD under ~3 %.
    private static func isStill(_ grav: [GravitySample]) -> Bool {
        guard grav.count >= 4 else { return false }
        let mags = grav.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() }
        let mean = mags.reduce(0, +) / Double(mags.count)
        guard mean > 0 else { return false }
        let variance = mags.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(mags.count)
        return (variance.squareRoot() / mean) < 0.03
    }

    private func buildExport() -> URL? {
        guard let night, !windows.isEmpty else { return nil }
        let csv = RhythmExport.csv(summary: night, windows: windows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("noop-rhythm.csv")
        return (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}
#endif
