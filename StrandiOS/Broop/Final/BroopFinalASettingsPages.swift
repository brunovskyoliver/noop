#if os(iOS)
import SwiftUI

// Settings pages rebuilt in Broop form: Storage, About Apple Watch data and the Apple Watch setup sheet.
// Same model calls (`AppModel.storageReport` / `cleanUpStorage`, `HealthKitBridge.requestAuthorization`) and
// the copy (the watch capability table is `AppleWatchAboutView.metrics` itself).

// MARK: - Storage

struct BroopFinalAStoragePage: View {
    @EnvironmentObject private var model: AppModel
    @State private var report: AppModel.StorageReport?
    @State private var loading = true
    @State private var cleaning = false
    @State private var lastCleanedSummary: String?

    var body: some View {
        BroopAccountPage {
            Text("Where NOOP's on-device space is going, and a one-tap clean-up.")
                .font(BroopType.regular(15))
                .foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
            if loading && report == nil {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Measuring…").font(BroopType.medium(15)).foregroundStyle(BroopAccountStyle.caption)
                }
            } else if let report {
                footprint(report)
                cleanUp(report)
            } else {
                BroopAccountNotice(symbol: "internaldrive", title: String(localized: "Storage unavailable"),
                                   text: String(localized: "Couldn't read the local store right now. Try again in a moment."),
                                   tint: BroopPalette.textSecondary)
            }
            BroopAccountSection(title: String(localized: "Why does this grow?")) {
                BroopAccountFootnote(text: String(localized: "When you import an Apple Health or WHOOP export, iOS hands NOOP a private copy of the file. NOOP reads it, saves your data into the health database, then deletes the copy. Older builds didn't delete every copy. This screen reclaims any that were left behind."))
            }
        }
        .broopAccountChrome(String(localized: "Storage"))
        .task { await load() }
    }

    private func footprint(_ r: AppModel.StorageReport) -> some View {
        BroopAccountSection(title: String(localized: "On-device footprint")) {
            BroopAccountGroup {
                row("cylinder.split.1x2", String(localized: "Health database"), r.db, note: nil)
                row("tray.full", String(localized: "Leftover import copies"), r.inbox,
                    note: r.inbox > 0 ? String(localized: "Reclaimable") : nil)
                row("clock.arrow.circlepath", String(localized: "Import temp files"), r.importTemp,
                    note: r.importTemp > 0 ? String(localized: "Reclaimable") : nil)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ bytes: Int64?, note: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(note == nil ? BroopAccountStyle.icon : BroopPalette.warning)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                if let note { BroopCaps(note, size: 9, color: BroopPalette.warning) }
            }
            Spacer()
            Text(verbatim: bytes.map(StorageFormat.format) ?? "—")
                .font(BroopType.number(18))
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func cleanUp(_ r: AppModel.StorageReport) -> some View {
        let reclaimable = r.inbox + r.importTemp
        return BroopAccountSection(title: String(localized: "Clean up")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(reclaimable > 0
                     ? "There's about \(StorageFormat.format(reclaimable)) of leftover import scratch space to reclaim. This never removes your imported data."
                     : "Nothing to reclaim right now. NOOP already cleans up import scratch space automatically.")
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastCleanedSummary {
                    Text(verbatim: lastCleanedSummary).font(BroopType.demi(14)).foregroundStyle(BroopPalette.teal)
                }
                BroopFinalAPill(title: cleaning ? String(localized: "Cleaning up…") : String(localized: "Clean up now"),
                                busy: cleaning, enabled: reclaimable > 0) {
                    Task { await clean() }
                }
                .accessibilityLabel(Text("Clean up leftover import files"))
            }
        }
    }

    private func load() async {
        loading = true
        report = await model.storageReport()
        loading = false
    }

    private func clean() async {
        guard !cleaning else { return }
        cleaning = true
        let before = (report?.inbox ?? 0) + (report?.importTemp ?? 0)
        let r = await model.cleanUpStorage()
        let freed = max(0, before - (r.inbox + r.importTemp))
        report = r
        lastCleanedSummary = freed > 0 ? String(localized: "Reclaimed \(StorageFormat.format(freed)).") : String(localized: "Already clean.")
        cleaning = false
    }
}

// MARK: - About Apple Watch data

struct BroopFinalAAppleWatchAboutPage: View {
    var onStartSetup: (() -> Void)? = nil

    var body: some View {
        BroopAccountPage {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "applewatch")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(BroopPalette.textPrimary)
                BroopAccountHeading(title: String(localized: "Your Apple Watch as a device"),
                                    detail: String(localized: "NOOP can run off only an Apple Watch, no chest strap needed. The watch is the sensor; NOOP does the thinking on your phone, computing Charge, Rest, Effort and your Fitness Age from your Health data, all on-device."))
                Text("The honest catch: a watch isn't a chest strap. It's brilliant at sleep, steps, workouts and fitness, and lighter on the dense heart-rate-variability a strap measures all night. So recovery takes about a week to calibrate, and a couple of metrics depend on your watch model. NOOP is upfront about all of it. Every watch-derived number carries a confidence, and where the watch can't be honest, NOOP shows nothing instead of a made-up figure.")
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BroopAccountSection(title: String(localized: "What the watch can do"),
                                footer: String(localized: "Each metric, where your Apple Watch sits on it, and why.")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    ForEach(AppleWatchAboutView.metrics) { item in metricRow(item) }
                }
            }

            explainer(symbol: "waveform.path.ecg",
                      title: String(localized: "Why recovery calibrates over about a week"),
                      paragraphs: [
                        String(localized: "Recovery, NOOP's Charge score, is led by your heart-rate variability measured against your own personal baseline. A chest strap streams beat-to-beat data densely all night, so it can learn that baseline fast. An Apple Watch instead samples HRV, a handful of readings through the day plus overnight, so the signal is real but sparser."),
                        String(localized: "That's why a watch-only Charge starts out \u{201C}Calibrating\u{201D}. NOOP needs about seven nights of your HRV to learn what normal looks like for you. Until it has them it withholds the score rather than guess. Once the baseline is set, your Charge appears with its confidence, on the same 0-100 scale as a strap's."),
                      ])
            explainer(symbol: "drop.degreesign",
                      title: String(localized: "A note on blood oxygen and your model"),
                      paragraphs: [
                        String(localized: "A couple of metrics depend on which Apple Watch you wear. Wrist temperature, which feeds skin temp, arrived with Series 8, so older watches don't report it. Blood oxygen is the bigger one: Apple removed the SpO₂ sensor from the newest US units over a patent dispute, so those simply don't measure it."),
                        String(localized: "Where a sensor isn't on your watch, NOOP reads \u{201C}not available\u{201D} for that metric, never a zero, never an invented number. Everything else keeps working."),
                      ])

            if let onStartSetup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to connect your watch?").font(BroopType.demi(18)).foregroundStyle(BroopPalette.textPrimary)
                    Text("NOOP reads your Apple Watch data through Apple Health, on your phone, nothing leaves the device. You choose exactly what to share.")
                        .font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    BroopFinalAPill(title: String(localized: "Set up Apple Watch"), symbol: "applewatch", action: onStartSetup)
                        .accessibilityHint(Text("Opens the Apple Watch setup and Health permission"))
                }
            }

            BroopAccountFootnote(text: String(localized: "These are independent estimates computed on your device from your Apple Health data, not medical advice. Confidence labels are honest about how much NOOP knows so far."))
        }
        .broopAccountChrome(String(localized: "Apple Watch Data"))
    }

    private func metricRow(_ item: WatchMetric) -> some View {
        let tint: Color = {
            switch item.confidence {
            case .great: return BroopPalette.teal
            case .good: return BroopFinalAPalette.accent
            case .calibrating: return BroopPalette.warning
            case .unavailable: return BroopPalette.textSecondary
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(BroopPalette.textBody)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                BroopCaps(item.metric, size: 11.5).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                BroopFinalAChip(text: item.confidence.pillLabel, tint: tint)
            }
            Text(verbatim: item.detail)
                .font(BroopType.regular(13))
                .foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 36)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.metric). \(item.confidence.pillLabel). \(item.detail)"))
    }

    private func explainer(symbol: String, title: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(BroopPalette.textBody)
                Text(verbatim: title).font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(paragraphs, id: \.self) { p in
                Text(verbatim: p).font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }
}

// MARK: - Apple Watch setup

/// Two steps: what the watch is good at and where it is lighter, then the Apple Health permission, which the
/// bridge requests (the type list, entitlement checks and live ingestion stay in `HealthKitBridge`).
struct BroopFinalAAppleWatchSetup: View {
    let onClose: () -> Void
    @EnvironmentObject private var health: HealthKitBridge
    @State private var step = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        BroopCaps(String(localized: "Step \(step + 1) of 2"), size: 10.5, color: BroopPalette.textSecondary)
                        Text("Use NOOP with your watch").font(BroopType.demi(26)).foregroundStyle(BroopPalette.textPrimary)
                        Text(step == 0 ? "What to expect" : "Connect Apple Health")
                            .font(BroopType.medium(15)).foregroundStyle(BroopAccountStyle.caption)
                    }
                    if step == 0 { intro } else { permission }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .background(BroopBackground())
            .broopFinalASheetBar(String(localized: "Apple Watch"), onClose: onClose)
        }
        .preferredColorScheme(.dark)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("No chest strap? No problem. NOOP can run off only your Apple Watch. It reads your watch's data through Apple Health and works out your Charge, Rest, Effort and Fitness Age right here on your phone. Everything stays on the device.")
                .font(BroopType.regular(14.5)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            group(String(localized: "What it's great at"), tint: BroopPalette.teal, items: [
                ("bed.double", String(localized: "Sleep & Rest"), String(localized: "Apple's sleep stages are strong, and they drive your Rest score directly.")),
                ("figure.walk", String(localized: "Steps & workouts"), String(localized: "Steps, active energy and logged workouts feed your Effort. Dense and reliable.")),
                ("bolt.heart", String(localized: "Fitness Age"), String(localized: "Built from the watch's cardio-fitness VO₂ max, the same number the Fitness app shows.")),
            ])
            group(String(localized: "Where it's lighter than a strap"), tint: BroopPalette.warning, items: [
                ("heart", String(localized: "Recovery takes about a week"), String(localized: "A watch samples your heart-rate variability rather than streaming it all night, so your Charge score needs roughly seven nights to calibrate. Until then NOOP shows \u{201C}needs more data\u{201D}, never a guessed number.")),
                ("drop.degreesign", String(localized: "A couple of metrics depend on your model"), String(localized: "Wrist temperature needs Series 8 or later, and the newest US units dropped the blood-oxygen sensor. Where a sensor isn't there, NOOP reads \u{201C}not available\u{201D} instead of zero.")),
            ])
            BroopAccountFootnote(text: String(localized: "Want the full breakdown of every metric and how sure NOOP is about each one? The \u{201C}About Apple Watch data\u{201D} page in Settings has the honest table."))
        }
    }

    private func group(_ title: String, tint: Color, items: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { BroopHairline().padding(.leading, 52) }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.0).font(.system(size: 17, weight: .light)).foregroundStyle(tint).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: item.1).font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                            Text(verbatim: item.2).font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        }
    }

    @ViewBuilder private var permission: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square").font(.system(size: 22, weight: .light)).foregroundStyle(BroopPalette.textPrimary)
                BroopCaps(String(localized: "Apple Health"), size: 12)
                Spacer()
                if health.auth == .authorized {
                    BroopFinalAChip(text: health.syncing ? String(localized: "Syncing") : String(localized: "Connected"), tint: BroopPalette.teal)
                }
            }
            switch health.auth {
            case .unavailable:
                para("Apple Health isn't available on this device, so there's nothing to connect here.")
            case .entitlementMissing:
                para("This install can't connect to Apple Health directly. It was signed with a profile that doesn't include Apple's Health permission, so there's nothing to grant here.")
                BroopAccountFootnote(text: String(localized: "You can still bring your data in by importing a Health export from Data Sources. A build from the App Store, or one signed with a paid Apple Developer account, connects directly."))
            case .unknown, .denied:
                para("NOOP reads your heart rate, HRV, resting heart rate, sleep, steps, energy and VO₂ max from Apple Health to compute your scores. It all stays on this iPhone, and you pick exactly what to share on the next screen.")
                if health.auth == .denied {
                    BroopAccountFootnote(text: String(localized: "If you don't see the prompt, turn NOOP on under Settings › Health › Data Access & Devices."))
                }
            case .authorized:
                para("You're connected. NOOP is reading your Apple Watch data now. Your Charge score will spend its first week or so calibrating, then settle in.")
                BroopAccountFootnote(text: String(localized: "You can change what you share any time in Settings › Health › Data Access & Devices."))
            }
            if let err = health.lastError {
                Text(verbatim: err).font(BroopType.regular(13)).foregroundStyle(BroopFinalAPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private func para(_ text: LocalizedStringKey) -> some View {
        Text(text).font(BroopType.regular(14.5)).foregroundStyle(BroopPalette.textBody)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if step == 0 {
                BroopFinalAPill(title: String(localized: "Continue")) { withAnimation(.snappy) { step = 1 } }
                    .accessibilityHint(Text("Goes to the Apple Health permission step"))
            } else {
                switch health.auth {
                case .unknown, .denied:
                    BroopFinalAPill(title: String(localized: "Allow Apple Health access"), symbol: "heart.fill") {
                        Task { await health.requestAuthorization() }
                    }
                    .accessibilityHint(Text("Shows the Apple Health permission sheet"))
                case .authorized:
                    BroopFinalAPill(title: String(localized: "Done"), action: onClose)
                default:
                    EmptyView()
                }
                HStack {
                    Button { withAnimation(.snappy) { step = 0 } } label: {
                        BroopCaps(String(localized: "Back"), size: 11, color: BroopPalette.textSecondary).frame(minHeight: 40)
                    }
                    Spacer()
                    if health.auth != .authorized {
                        Button(action: onClose) {
                            BroopCaps(String(localized: "Not now"), size: 11, color: BroopPalette.textSecondary).frame(minHeight: 40)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                                   startPoint: .top, endPoint: .center).ignoresSafeArea())
    }
}
#endif
