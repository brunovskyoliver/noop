#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import StrandDesign

/// The Broop face of `OnboardingWizard`, styled after WHOOP's onboarding: dark canvas, back chevron,
/// a grey illustration over a large sentence-case title, and a white capsule pinned at the bottom.
///
/// Same twelve steps in the same order as the wizard, doing the same things: the scan and
/// disconnect calls on `AppModel`, the `selectedWhoopModel` choice, the profile fields bound straight to
/// `ProfileStore` and the unit prefs, the WHOOP / Apple Health importers, the one notification
/// permission request on leaving the Notifications step. It only calls
/// `onFinished()`; the caller owns what finishing stores (`noop.onboarded`).
struct BroopFinalBOnboardingWizard: View {
    var onFinished: () -> Void

    // Mirrors `OnboardingWizard.Step` one for one.
    fileprivate enum Step: Int, CaseIterable {
        case welcome, what, expectations, bluetooth, wear, scan, bonded, profile, importData, notifications, done
        var isFirst: Bool { self == .welcome }
        var isLast: Bool { self == .done }
    }

    @State private var step: Step = .welcome
    /// The Scan step's "Don't see it?" card, lifted here so the top bar's HELP pill can open it.
    @State private var scanHelpOpen = false

    // Like the root, this view does not observe the fast-moving live objects; the steps that
    // need them do, and a hidden watcher handles the bond transition.
    var body: some View {
        ZStack {
            BroopBackground()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, BroopMetrics.page)
                ZStack {
                    stepView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                        .id(step)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                BroopFinalBOnbFooter {
                    BroopFinalBOnbCapsuleButton(title: ctaTitle, symbol: ctaSymbol,
                                                symbolTrailing: true, action: primaryAction)
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(BroopFinalBBondWatcher(onBonded: handleBond))
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .welcome: BroopFinalBWelcomeStep()
        case .what: BroopFinalBWhatStep()
        case .expectations: BroopFinalBExpectationsStep()
        case .bluetooth: BroopFinalBBluetoothStep()
        case .wear: BroopFinalBWearStep()
        case .scan: BroopFinalBScanStep(showHelp: $scanHelpOpen)
        case .bonded: BroopFinalBBondedStep()
        case .profile: BroopFinalBProfileStep()
        case .importData: BroopFinalBImportStep()
        case .notifications: BroopFinalBNotificationsStep()
        case .done: BroopFinalBDoneStep()
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                if step.isFirst {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    BroopFinalBOnbBackChevron(action: back)
                }
                Spacer()
                if step == .scan {
                    BroopFinalBOnbBarPill(title: String(localized: "Help"), active: scanHelpOpen) {
                        withAnimation(.easeInOut(duration: 0.25)) { scanHelpOpen.toggle() }
                    }
                } else {
                    BroopCaps("\(step.rawValue + 1) / \(Step.allCases.count)", size: 10.5,
                              color: BroopPalette.textSecondary)
                }
            }
            .frame(height: 44)
            BroopFinalBOnbProgressTrack(progress: progress)
                .padding(.horizontal, 2)
        }
        .padding(.top, 4)
    }

    private var progress: Double {
        Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    private var ctaTitle: String {
        switch step {
        case .welcome: return String(localized: "Get Started")
        case .expectations: return String(localized: "I understand")
        case .wear: return String(localized: "I'm wearing it")
        case .profile: return String(localized: "Save & Continue")
        case .done: return String(localized: "Enter Broop")
        default: return String(localized: "Continue")
        }
    }

    private var ctaSymbol: String? {
        switch step {
        case .done: return "arrow.right"
        case .bonded: return "checkmark"
        default: return nil
        }
    }

    private func handleBond() {
        if step == .scan { withAnimation(.easeInOut(duration: 0.45)) { step = .bonded } }
    }

    private func primaryAction() {
        if step.isLast { onFinished() } else { advance() }
    }

    /// Same as the wizard: leaving Notifications is the one point onboarding asks the OS for
    /// notification permission, only when not yet determined, and it advances once the dialog closes.
    private func advance() {
        guard step != .notifications else {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else {
                    Task { @MainActor in advanceStep() }
                    return
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    Task { @MainActor in advanceStep() }
                }
            }
            return
        }
        advanceStep()
    }

    private func advanceStep() {
        guard let next = Step(rawValue: step.rawValue + 1) else { onFinished(); return }
        scanHelpOpen = false
        withAnimation(.easeInOut(duration: 0.3)) { step = next }
    }

    private func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        scanHelpOpen = false
        withAnimation(.easeInOut(duration: 0.3)) { step = prev }
    }
}

/// Hidden observer that fires `onBonded` on the bond edge, keeping the wizard body off the live path.
private struct BroopFinalBBondWatcher: View {
    @EnvironmentObject private var live: LiveState
    let onBonded: () -> Void
    var body: some View {
        Color.clear.onChange(of: live.bonded) { _, bonded in if bonded { onBonded() } }
    }
}

// MARK: - Page layout

/// One onboarding page: illustration, large title, grey subtitle, then the step's content, scrolling if
/// it runs long. `centered` pushes the title block down into the lower half as WHOOP's pages do.
private struct BroopFinalBPage<Content: View>: View {
    var symbol: String? = nil
    var title: String
    var subtitle: String? = nil
    var centered = false
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if centered { Spacer(minLength: 24) }
                    if let symbol {
                        BroopFinalBOnbIllustration(symbol: symbol)
                            .padding(.bottom, 24)
                    }
                    BroopFinalBOnbTitleBlock(title: title, subtitle: subtitle)
                    content
                        .padding(.top, 28)
                    if centered { Spacer(minLength: 12) }
                }
                .padding(.horizontal, 22)
                .padding(.top, centered ? 0 : 28)
                .padding(.bottom, 16)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Steps

private struct BroopFinalBWelcomeStep: View {
    @State private var appear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            BroopMark()
                .fill(style: FillStyle(eoFill: true))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 84, height: 84)
                .padding(.leading, -8)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            BroopWordmark(size: 15)
                .padding(.bottom, 40)
            BroopFinalBOnbTitleBlock(
                title: String(localized: "All your data, none of the cloud."),
                subtitle: String(localized: "A private window into your recovery, sleep and strain. Read straight from your strap, kept only on \(Platform.deviceNounPhrase)."))
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
    }
}

private struct BroopFinalBWhatStep: View {
    var body: some View {
        BroopFinalBPage(symbol: "sparkles", title: String(localized: "What Broop does"),
                        subtitle: String(localized: "Three quiet promises.")) {
            BroopCard {
                VStack(alignment: .leading, spacing: 20) {
                    BroopFinalBOnbInfoRow(
                        symbol: "circle.dashed.inset.filled",
                        title: String(localized: "See recovery, beautifully"),
                        message: String(localized: "A signature ring distils HRV, resting heart rate and sleep into one calm read on whether to push or rest."))
                    BroopHairline()
                    BroopFinalBOnbInfoRow(
                        symbol: "waveform.path.ecg",
                        title: String(localized: "Watch your heart, live"),
                        message: String(localized: "Connect a WHOOP, a heart-rate strap or a gym machine and watch each beat in real time: heart rate, variability and zones as they happen. Already have history elsewhere? Import it from WHOOP, Apple Health, Oura, Fitbit or Garmin."))
                    BroopHairline()
                    BroopFinalBOnbInfoRow(
                        symbol: "lock.shield",
                        title: String(localized: "Own your data, offline"),
                        message: String(localized: "Everything lives on \(Platform.deviceNounPhrase). No account, no sync, no cloud. Your thread is yours alone."))
                }
            }
        }
    }
}

private struct BroopFinalBExpectationsStep: View {
    var body: some View {
        BroopFinalBPage(symbol: "flask", title: String(localized: "What to expect"),
                        subtitle: String(localized: "A few honest words, so nothing's a surprise.")) {
            BroopCard {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(AppChangelog.expectations) { e in
                        BroopFinalBOnbInfoRow(symbol: e.icon, title: e.title, message: e.body)
                        BroopHairline()
                    }
                    // The iPhone-only reality, as the wizard states it.
                    BroopFinalBOnbInfoRow(
                        symbol: "iphone.gen3",
                        title: String(localized: "Installed outside the App Store"),
                        message: String(localized: "On iPhone this is a sideloaded build. Re-sign it about every 7 days on a free Apple ID (longer on a paid account). After your phone reboots, unlock it once so NOOP can read and sync its data."))
                }
            }
        }
    }
}

private struct BroopFinalBBluetoothStep: View {
    var body: some View {
        BroopFinalBPage(symbol: "wave.3.right", title: String(localized: "A quick word before we connect"),
                        subtitle: String(localized: "\(Platform.deviceNoun) will ask for Bluetooth in a moment."),
                        centered: true) {
            VStack(alignment: .leading, spacing: 18) {
                BroopCard {
                    BroopFinalBOnbInfoRow(
                        symbol: "lock.fill",
                        title: String(localized: "Nothing leaves your \(Platform.deviceNoun)"),
                        message: String(localized: "NOOP talks to your strap directly over Bluetooth Low Energy. There's no server in the middle. The connection is local, and so is every reading it pulls in."),
                        tint: BroopPalette.connected)
                }
                BroopFootnote(text: String(localized: "When the system prompt appears, choose Allow so NOOP can find your strap."))
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct BroopFinalBWearStep: View {
    var body: some View {
        BroopFinalBPage(symbol: "applewatch.side.right", title: String(localized: "Put your strap on"),
                        subtitle: String(localized: "And make sure it's charged."), centered: true) {
            VStack(alignment: .leading, spacing: 16) {
                BroopFinalBOnbCheckline(text: String(localized: "Wear it snug on your wrist or bicep, sensor against skin."))
                BroopFinalBOnbCheckline(text: String(localized: "Give it a few minutes of charge if the battery is low."))
                BroopFinalBOnbCheckline(text: String(localized: "Keep it within about a metre of \(Platform.deviceNounPhrase)."))
            }
        }
    }
}

/// WHOOP's "SEARCHING FOR STRAP..." page: caps status, grey hint, a large visual, and the pairing
/// controls below. Same actions as the Scan step.
private struct BroopFinalBScanStep: View {
    @Binding var showHelp: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    @State private var scanning = false
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                BroopCaps(statusTitle, size: 15)
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)
                Text(verbatim: live.bonded
                     ? String(localized: "Bonded. You're set.")
                     : String(localized: "Pick your strap below, then tap Scan. NOOP will find it."))
                    .font(BroopType.medium(15.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 30)

                BroopFinalBPairingPulse(active: scanning && !live.bonded, bonded: live.bonded, connecting: live.connected)
                    .frame(width: 230, height: 230)
                    .padding(.vertical, 26)

                if !live.bonded {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            BroopFinalBOnbFieldLabel(text: String(localized: "Which strap are you pairing?"))
                            BroopFinalBOnbSegmented(
                                options: WhoopModel.allCases,
                                selection: Binding(get: { selectedModel }, set: { restartScan(for: $0) }),
                                label: { $0.displayName })
                        }

                        // #130: a 5/MG bonds to one host at a time.
                        if selectedModel == .whoop5mg {
                            BroopFootnote(text: String(localized: "WHOOP 5.0/MG pairs with one app at a time. If nothing's found, unpair it in the official WHOOP app and fully close that app, then Scan."))
                                .padding(.horizontal, 4)
                        }

                        BroopFinalBOnbCapsuleButton(
                            title: scanning ? String(localized: "Scanning…") : String(localized: "Scan"),
                            symbol: "dot.radiowaves.left.and.right", kind: .outline, height: 48
                        ) { startScan() }
                        .disabled(scanning)

                        if !showHelp {
                            BroopFinalBOnbCapsuleButton(title: String(localized: "Don't see your device?"),
                                                     kind: .outline, height: 48) {
                                withAnimation(.easeInOut(duration: 0.25)) { showHelp = true }
                            }
                        } else {
                            reassurance
                        }

                        BroopFootnote(text: String(localized: "No WHOOP? You can still continue. Pair a heart-rate strap (Polar, Wahoo, Coospo, Garmin HRM…) or a gym machine under Devices, or import from WHOOP, Apple Health, Oura, Fitbit, Garmin and more under Data Sources. You can do either any time."),
                                      color: BroopPalette.textTertiary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onDisappear { scanning = false }
    }

    private var statusTitle: String {
        if live.bonded { return String(localized: "Connected") }
        if live.connected { return String(localized: "Connecting…") }
        if scanning { return String(localized: "Searching for strap…") }
        return String(localized: "Find your strap")
    }

    private var reassurance: some View {
        BroopCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Don't see it? That's normal.")
                    .font(BroopType.demi(16))
                    .foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: String(localized: "WHOOP straps don't appear in your \(Platform.deviceNoun)'s Bluetooth settings. They advertise on a custom profile that only apps like NOOP can find, so there's nothing to pair there, and you shouldn't try."))
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                BroopHairline()
                VStack(alignment: .leading, spacing: 12) {
                    BroopFinalBOnbCheckline(text: String(localized: "It's charged and worn. The sensor needs skin contact to wake."))
                    BroopFinalBOnbCheckline(text: String(localized: "It isn't held by the WHOOP phone app. Only one host at a time: close the app or turn off its Bluetooth."))
                    BroopFinalBOnbCheckline(text: String(localized: "It's within about a metre of \(Platform.deviceNounPhrase)."))
                }
                BroopFinalBOnbCapsuleButton(title: String(localized: "Try again"), symbol: "arrow.clockwise",
                                         kind: .outline, height: 44, action: retry)
                    .padding(.top, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func startScan(model scanModel: WhoopModel? = nil) {
        let modelToScan = scanModel ?? selectedModel
        scanning = true
        showHelp = false
        model.scan(model: modelToScan)
        // Same calm beat as the step before the "can't find it" card appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !live.bonded {
                scanning = false
                withAnimation(.easeInOut(duration: 0.25)) { showHelp = true }
            }
        }
    }

    private func restartScan(for newModel: WhoopModel) {
        selectedModelRaw = newModel.rawValue
        guard !live.bonded else { return }
        model.disconnect()
        startScan(model: newModel)
    }

    private func retry() {
        withAnimation(.easeInOut(duration: 0.25)) { showHelp = false }
        startScan()
    }
}

/// Thin concentric rings around the Broop "B" with a slow outward pulse while searching; the centre
/// turns green once bonded. Flat, no glow.
private struct BroopFinalBPairingPulse: View {
    var active: Bool
    var bonded: Bool
    var connecting: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    private var poseStill: Bool { motion.poseStill(reduceMotion) }

    var body: some View {
        ZStack {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.07 + 0.03 * Double(3 - i)), lineWidth: 1)
                    .frame(width: 230 * Double(i) / 3, height: 230 * Double(i) / 3)
            }
            if active && !poseStill {
                Circle()
                    .stroke(BroopPalette.effort.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 2.85 : 1)
                    .opacity(pulse ? 0 : 0.9)
                    .onAppear {
                        pulse = false
                        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) { pulse = true }
                    }
                    .onDisappear { pulse = false }
            }
            Circle()
                .fill(bonded ? BroopPalette.bandHigh : Color(broopHex: 0x1A2025))
                .frame(width: 80, height: 80)
                .overlay(Circle().strokeBorder(bonded ? Color.clear : (connecting ? BroopPalette.bandMid : BroopPalette.effort), lineWidth: 2))
            if bonded {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                BroopMark()
                    .fill(style: FillStyle(eoFill: true))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .frame(width: 38, height: 38)
            }
        }
        .accessibilityHidden(true)
    }
}

/// WHOOP's pairing-success scene: the phone (Broop "B") at the left, the strap at the right, joined by a
/// green line with a check in the middle.
private struct BroopFinalBBondedStep: View {
    @EnvironmentObject private var live: LiveState
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            scene
                .frame(height: 300)
            Spacer()
            VStack(spacing: 10) {
                Text("You're connected.")
                    .font(BroopType.demi(26))
                    .foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: batteryLine)
                    .font(BroopType.medium(16))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .opacity(appear ? 1 : 0)
            Spacer().frame(height: 40)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appear = true } }
    }

    private var scene: some View {
        GeometryReader { geo in
            let w = geo.size.width, midY = geo.size.height / 2
            ZStack {
                // Phone, cropped by the left edge.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color.black, Color(broopHex: 0x141618)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 150, height: 290)
                    .position(x: 30, y: midY)
                BroopMark()
                    .fill(style: FillStyle(eoFill: true))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .position(x: 62, y: midY)
                // Strap.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0x2E3336), Color(broopHex: 0x1A1D1F)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .frame(width: 84, height: 250)
                    .position(x: w - 58, y: midY)
                // The sensor pod: a brighter metal band with a small "B".
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0x4A5054), Color(broopHex: 0x2A2E31)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    .overlay(BroopMark().fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(Color.white.opacity(0.55)).frame(width: 14, height: 14))
                    .frame(width: 96, height: 32)
                    .position(x: w - 58, y: midY + 40)
                // Link.
                Path { p in
                    p.move(to: CGPoint(x: 112, y: midY))
                    p.addLine(to: CGPoint(x: w - 76, y: midY))
                }
                .trim(from: 0, to: appear ? 1 : 0)
                .stroke(BroopPalette.bandHigh, lineWidth: 2.5)
                Circle().fill(BroopPalette.bandHigh).frame(width: 12, height: 12).position(x: 112, y: midY)
                Circle().fill(BroopPalette.bandHigh).frame(width: 12, height: 12).position(x: w - 76, y: midY)
                ZStack {
                    Circle().fill(BroopPalette.bandHigh.opacity(0.3)).frame(width: 74, height: 74)
                    Circle().fill(BroopPalette.bandHigh).frame(width: 56, height: 56)
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                .scaleEffect(appear ? 1 : 0.5)
                .opacity(appear ? 1 : 0)
                .position(x: (112 + w - 76) / 2, y: midY)
            }
        }
        .accessibilityHidden(true)
    }

    private var batteryLine: String {
        if let pct = live.batteryPct {
            return String(localized: "Your strap is bonded · \(Int(pct))% battery.")
        }
        return String(localized: "Your strap is bonded and ready to stream.")
    }
}

/// WHOOP's name page carries caps labels over dark fields; the profile step uses the same fields, bound
/// straight to `ProfileStore` and the unit prefs exactly as the step is.
private struct BroopFinalBProfileStep: View {
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw)
    }
    private var distanceSystemBinding: Binding<String> {
        Binding(get: { distanceUnitSystem.rawValue }, set: { distanceSystemRaw = $0 })
    }

    private let sexes: [(String, String)] = [
        ("male", String(localized: "Male")), ("female", String(localized: "Female")),
        ("nonbinary", String(localized: "Other")),
    ]

    var body: some View {
        BroopFinalBPage(symbol: "person.crop.circle", title: String(localized: "About you"),
                        subtitle: String(localized: "So your zones, calories and baselines are accurate.")) {
            VStack(alignment: .leading, spacing: 22) {
                field(String(localized: "Date of birth")) {
                    BroopFinalBOnbField {
                        HStack {
                            Text(verbatim: String(localized: "\(profile.age) yrs"))
                                .font(BroopType.number(18))
                                .foregroundStyle(BroopPalette.textPrimary)
                            Spacer()
                            DatePicker("Date of birth", selection: $profile.dateOfBirth,
                                       in: ProfileStore.dateOfBirthRange, displayedComponents: .date)
                                .labelsHidden()
                                .tint(BroopPalette.textPrimary)
                        }
                    }
                }
                field(String(localized: "Sex")) {
                    BroopFinalBOnbSegmented(options: sexes.map(\.0), selection: $profile.sex) { key in
                        sexes.first { $0.0 == key }?.1 ?? key
                    }
                }
                field(String(localized: "Body measurements")) {
                    BroopFinalBOnbSegmented(options: [UnitSystem.metric.rawValue, UnitSystem.imperial.rawValue],
                                         selection: $unitSystemRaw) { raw in
                        raw == UnitSystem.metric.rawValue ? String(localized: "Metric") : String(localized: "Imperial")
                    }
                }
                field(String(localized: "Exercise distance & pace")) {
                    BroopFinalBOnbSegmented(options: [UnitSystem.metric.rawValue, UnitSystem.imperial.rawValue],
                                         selection: distanceSystemBinding) { raw in
                        raw == UnitSystem.metric.rawValue ? String(localized: "Kilometres") : String(localized: "Miles")
                    }
                }
                // Same ranges and steps as the steppers.
                field(String(localized: "Weight")) {
                    stepperField(value: UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem),
                                 binding: $profile.weightKg, range: 30...250, step: 0.5)
                }
                field(String(localized: "Height")) {
                    stepperField(value: UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem),
                                 binding: $profile.heightCm, range: 120...230, step: 1)
                }
                HStack(spacing: 8) {
                    Image(systemName: "bolt.heart")
                        .foregroundStyle(BroopPalette.textSecondary)
                    Text(verbatim: String(localized: "Estimated max heart rate · \(profile.hrMax) bpm"))
                        .font(BroopType.medium(13.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopFinalBOnbFieldLabel(text: label)
            content()
        }
    }

    private func stepperField(value: String, binding: Binding<Double>, range: ClosedRange<Double>,
                              step: Double) -> some View {
        BroopFinalBOnbField {
            HStack {
                Text(verbatim: value)
                    .font(BroopType.number(18))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                Stepper("", value: binding, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private struct BroopFinalBImportStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .whoop

    var body: some View {
        BroopFinalBPage(symbol: "square.and.arrow.down", title: String(localized: "Bring your history"),
                        subtitle: String(localized: "Optional: import now, or continue and return to Data Sources later.")) {
            VStack(alignment: .leading, spacing: 16) {
                BroopCard {
                    BroopFinalBOnbInfoRow(
                        symbol: "clock.arrow.circlepath",
                        title: String(localized: "History fills the dashboard immediately"),
                        message: String(localized: "A WHOOP export backfills recovery, strain, sleep and workouts. Apple Health can add HR, HRV, sleep, SpO₂, steps, workouts and weight."))
                }
                importRow(title: model.isImporting(.whoop) ? String(localized: "Importing…") : String(localized: "Import WHOOP export"),
                          symbol: "tray.and.arrow.down") { presentImporter(.whoop) }
                importRow(title: model.isImporting(.appleHealth) ? String(localized: "Working…") : String(localized: "Import Apple Health export"),
                          symbol: "heart.fill") { presentImporter(.appleHealth) }

                if model.hasActiveImport {
                    ProgressView().controlSize(.small).tint(BroopPalette.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                // Styled off the typed failure flag, as the step does.
                if let summary = lastSummary {
                    Text(verbatim: summary)
                        .font(BroopType.medium(14))
                        .foregroundStyle(model.importFailed(importKind) ? BroopPalette.warning : BroopPalette.connected)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: importTarget.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch importTarget {
            case .whoop: model.importWhoop(url: url)
            case .appleHealth: model.importAppleHealth(url: url)
            }
        }
    }

    private func importRow(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopFinalBOnbField {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 22)
                    Text(verbatim: title.uppercased())
                        .font(BroopType.caps(12))
                        .tracking(1.2)
                        .foregroundStyle(BroopPalette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(model.hasActiveImport)
        .opacity(model.hasActiveImport ? 0.5 : 1)
    }

    private var importKind: DataSourceImportKind {
        switch importTarget {
        case .whoop: return .whoop
        case .appleHealth: return .appleHealth
        }
    }

    private var lastSummary: String? {
        switch importTarget {
        case .whoop: return model.whoopImportSummary
        case .appleHealth: return model.appleHealthImportSummary
        }
    }

    private func presentImporter(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }

    private enum ImportTarget {
        case whoop, appleHealth
        // iOS offers only concrete file types (#179), as the step does.
        var allowedContentTypes: [UTType] {
            switch self {
            case .whoop: return [.zip]
            case .appleHealth: return [.zip, .xml]
            }
        }
    }
}

private struct BroopFinalBNotificationsStep: View {
    var body: some View {
        BroopFinalBPage(symbol: "bell.badge", title: String(localized: "Stay in the loop"),
                        subtitle: String(localized: "NOOP can tap your wrist when your \(Platform.deviceNoun) needs you. No glance at the screen required."),
                        centered: true) {
            VStack(alignment: .leading, spacing: 18) {
                BroopCard {
                    BroopFinalBOnbInfoRow(
                        symbol: "applewatch.radiowaves.left.and.right",
                        title: String(localized: "A buzz, not a banner"),
                        message: String(localized: "NOOP taps your strap so an alert lands on your wrist instead of your screen. No need to reach for it. Everything stays on \(Platform.deviceNounPhrase)."),
                        tint: BroopPalette.connected)
                }
                BroopFinalBOnbCheckline(text: String(localized: "Strain nudges and your smart alarm tap your wrist the moment they fire."))
                BroopFinalBOnbCheckline(text: String(localized: "It all stays on your strap and \(Platform.deviceNounPhrase): no account, no cloud."))
            }
        }
    }
}

private struct BroopFinalBDoneStep: View {
    @State private var appear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            BroopBadge(size: 76)
                .padding(.bottom, 32)
                .accessibilityHidden(true)
            BroopFinalBOnbTitleBlock(
                title: String(localized: "Your thread starts here."),
                subtitle: String(localized: "Every beat, every night, every day, woven into one quiet picture of you. Welcome to Broop."))
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
    }
}
#endif
