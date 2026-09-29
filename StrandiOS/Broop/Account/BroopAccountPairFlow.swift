#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Pair a WHOOP

/// WHOOP-style pairing for a WHOOP 4.0 or 5.0 / MG: choose the family, get it ready, SEARCHING FOR
/// STRAP…, pick it, name it, done. It runs the classic Add-a-device wizard's WHOOP path call for call:
/// `model.presentWhoopScan(model:)`, `ble.discoveredWhoops`, `model.stopWhoopScan()`, the same
/// `PairedDevice` shape and `model.registerDevice(_:makeActive:)` after the same make-active question.
/// Every other device type (heart-rate straps, gym equipment, the experimental bands and the Oura
/// adopt flow) opens the classic wizard under the Broop skin.
struct BroopAccountPairFlow: View {
    let onClose: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    private enum Step { case choose, prep, search, confirm, done }
    private enum Family { case whoop5mg, whoop4 }

    @State private var step: Step = .choose
    @State private var family: Family = .whoop5mg
    @State private var picked: (uuid: String, name: String, rssi: Int)?
    @State private var nameDraft = ""
    @State private var askMakeActive = false
    @State private var madeActive = false
    @State private var showOtherDevices = false
    @State private var showHelp = false

    private var whoopModel: WhoopModel { family == .whoop4 ? .whoop4 : .whoop5mg }
    private var familyTitle: String { family == .whoop4 ? "WHOOP 4.0" : "WHOOP 5.0 / MG" }

    var body: some View {
        NavigationStack {
            ZStack {
                BroopBackground()
                switch step {
                case .choose: chooseStep
                case .prep: prepStep
                case .search: searchStep
                case .confirm: confirmStep
                case .done: doneStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbar }
            .tint(BroopPalette.textPrimary)
        }
        .preferredColorScheme(.dark)
        .onDisappear { model.stopWhoopScan() }
        .alert("Make this your active device?", isPresented: $askMakeActive) {
            Button("Not now", role: .cancel) { finishAdd(makeActive: false) }
            Button("Make active") { finishAdd(makeActive: true) }
        } message: {
            Text("Make \(confirmName) your active device now? It will provide your live data. You can change this any time.")
        }
        .sheet(isPresented: $showOtherDevices) {
            AddDeviceWizard(live: live) { showOtherDevices = false; onClose() }
                .environmentObject(model)
                .environmentObject(live)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if step == .choose || step == .done {
                Button { model.stopWhoopScan(); onClose() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Close"))
            } else {
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Back"))
            }
        }
        if step == .search {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp.toggle() } label: {
                    BroopCaps(String(localized: "Help"), size: 11, color: BroopAccountStyle.broadcast)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                        .background(Capsule().strokeBorder(BroopAccountStyle.broadcast, lineWidth: 1.5))
                }
            }
        }
    }

    // MARK: Steps

    private var chooseStep: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountHeading(title: String(localized: "Pair a device"),
                                detail: String(localized: "Which band are you adding? NOOP pairs directly over Bluetooth: no WHOOP app, no cloud."))
            VStack(spacing: BroopAccountStyle.rowGap) {
                choice(String(localized: "WHOOP 5.0 / MG"), String(localized: "Newer WHOOP band with live data and history sync")) {
                    family = .whoop5mg; step = .prep
                }
                choice(String(localized: "WHOOP 4.0"), String(localized: "NOOP's primary, fully-supported band")) {
                    family = .whoop4; step = .prep
                }
            }
            BroopAccountSection(title: String(localized: "Other devices")) {
                Button { showOtherDevices = true } label: {
                    BroopAccountMenuRow(symbol: "heart.circle", title: String(localized: "Heart-rate strap, gym or other band"),
                                        subtitle: String(localized: "Polar, Wahoo, Garmin, FTMS machines, Oura, Amazfit, Mi Band"))
                }
                .buttonStyle(BroopPressableStyle())
            }
            BroopAccountFootnote(text: String(localized: "WHOOP is NOOP's primary, fully-supported band. Other heart-rate straps stream live heart rate and HRV, but not WHOOP's deeper sleep and recovery data."))
        }
    }

    private func choice(_ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopAccountMenuRow(symbol: "applewatch.side.right", title: title, subtitle: subtitle)
        }
        .buttonStyle(BroopPressableStyle())
    }

    private var prepStep: some View {
        VStack(spacing: 0) {
            BroopAccountPage(spacing: 22) {
                BroopAccountHeading(title: String(localized: "Get your \(familyTitle) ready"))
                if family == .whoop5mg {
                    BroopAccountNotice(symbol: "flask",
                                       text: String(localized: "WHOOP 5.0 / MG supports live data and strap history. Protocol-research tools are available separately in Test Centre."))
                }
                BroopAccountNotice(title: String(localized: "Your WHOOP only talks to one phone at a time."),
                                   text: String(localized: "Force-quit the official WHOOP app first, or pairing may fail."))
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 14) {
                            Text(verbatim: "\(index + 1)")
                                .font(BroopType.number(15))
                                .foregroundStyle(.black)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white))
                            Text(verbatim: line)
                                .font(BroopType.medium(15.5))
                                .foregroundStyle(BroopPalette.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 6)
            }
            BroopAccountButton(title: String(localized: "Search for strap")) {
                model.presentWhoopScan(model: whoopModel)
                step = .search
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var instructions: [String] {
        switch family {
        case .whoop4:
            return [
                String(localized: "Put your WHOOP 4.0 on your wrist and make sure it's awake."),
                String(localized: "Make sure it's NOT connected to the official WHOOP app right now."),
                String(localized: "NOOP will look for it nearby."),
            ]
        case .whoop5mg:
            return [
                String(localized: "WHOOP 5.0 / MG bonds to one device at a time. Unpair it from the official WHOOP app first."),
                String(localized: "Put the band into pairing mode, on your wrist and awake."),
                String(localized: "NOOP will look for it nearby."),
            ]
        }
    }

    private var searchStep: some View {
        BroopAccountSearchStep(showHelp: showHelp, onRescan: { model.presentWhoopScan(model: whoopModel) }) { strap in
            picked = strap
            nameDraft = strap.name.isEmpty ? familyTitle : strap.name
            model.stopWhoopScan()
            step = .confirm
        }
    }

    private var confirmStep: some View {
        VStack(spacing: 0) {
            BroopAccountPage(spacing: 22) {
                BroopAccountPairIllustration(state: .found)
                    .frame(height: 200)
                BroopAccountHeading(title: String(localized: "Name your strap"),
                                    detail: String(localized: "\(confirmAdvertisedName) · WHOOP"))
                VStack(alignment: .leading, spacing: 8) {
                    BroopCaps(String(localized: "Name"), size: 11, color: BroopAccountStyle.caption)
                    TextField(String(localized: "Device name"), text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(BroopType.medium(17))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopAccountStyle.field))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BroopAccountStyle.fieldBorder, lineWidth: 1))
                        .accessibilityLabel(Text("Device name"))
                }
            }
            BroopAccountButton(title: String(localized: "Add"),
                               enabled: !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                askMakeActive = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer()
            BroopAccountPairIllustration(state: .paired)
                .frame(height: 260)
            Spacer()
            Text(madeActive ? "You're connected" : "Strap added")
                .font(BroopType.demi(24))
                .foregroundStyle(BroopPalette.textPrimary)
            Text(madeActive
                 ? "\(confirmName) is now your active device. NOOP connects and starts syncing its history."
                 : "\(confirmName) is in your bands. Make it active from Device Settings when you want it to provide your data.")
                .font(BroopType.medium(15.5))
                .foregroundStyle(BroopAccountStyle.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 30)
            BroopAccountButton(title: String(localized: "Done")) { onClose() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
    }

    // MARK: Actions (the wizard's WHOOP path)

    private var confirmAdvertisedName: String {
        guard let picked else { return familyTitle }
        return picked.name.isEmpty ? familyTitle : picked.name
    }

    private var confirmName: String {
        let n = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? confirmAdvertisedName : n
    }

    private func goBack() {
        switch step {
        case .choose, .done: break
        case .prep: step = .choose
        case .search: model.stopWhoopScan(); step = .prep
        case .confirm:
            model.presentWhoopScan(model: whoopModel)
            picked = nil
            step = .search
        }
    }

    private func finishAdd(makeActive: Bool) {
        model.stopWhoopScan()
        guard let picked else { onClose(); return }
        let now = Int(Date().timeIntervalSince1970)
        let modelLabel = (whoopModel == .whoop4) ? "4.0" : "5.0 MG"
        let device = PairedDevice(
            id: "whoop-\(picked.uuid)",
            brand: "WHOOP",
            model: modelLabel,
            nickname: confirmName,
            peripheralId: picked.uuid,
            sourceKind: .liveBLE,
            capabilities: WhoopLiveCapabilities.metrics(forModel: modelLabel),
            status: .paired,
            addedAt: now, lastSeenAt: now)
        model.registerDevice(device, makeActive: makeActive)
        madeActive = makeActive
        step = .done
    }
}

/// SEARCHING FOR STRAP…: the drawn strap, then nearby WHOOPs as they appear. Observes `BLEManager`
/// so the list follows `discoveredWhoops` without re-rendering the whole flow.
private struct BroopAccountSearchStep: View {
    let showHelp: Bool
    let onRescan: () -> Void
    let onSelect: ((uuid: String, name: String, rssi: Int)) -> Void
    @EnvironmentObject private var ble: BLEManager
    @State private var pulse = false

    var body: some View {
        let found = ble.discoveredWhoops.sorted { $0.rssi > $1.rssi }
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                BroopCaps(found.isEmpty ? String(localized: "Searching for strap…") : String(localized: "Strap found"), size: 14)
                Text(found.isEmpty
                     ? "Ensure your WHOOP strap is in range and discoverable."
                     : "Tap the one that's yours.")
                    .font(BroopType.medium(15.5))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 30)

            if found.isEmpty {
                ZStack {
                    Circle().stroke(BroopAccountStyle.broadcast.opacity(pulse ? 0 : 0.35), lineWidth: 2)
                        .frame(width: pulse ? 320 : 120, height: pulse ? 320 : 120)
                    BroopAccountStrapArt(connected: false)
                        .frame(width: 170, height: 300)
                        .rotationEffect(.degrees(-12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true } }
            } else {
                ScrollView {
                    VStack(spacing: BroopAccountStyle.rowGap) {
                        ForEach(found, id: \.uuid) { strap in
                            Button { onSelect(strap) } label: {
                                HStack(spacing: 14) {
                                    SignalBars(rssi: strap.rssi)
                                    BroopCaps(strap.name.isEmpty ? "WHOOP" : strap.name, size: 13)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(BroopAccountStyle.icon)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 58)
                                .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BroopPressableStyle())
                            .accessibilityLabel(Text("\(strap.name.isEmpty ? "WHOOP" : strap.name), signal \(SignalBars.level(for: strap.rssi)) of 4"))
                        }
                    }
                    .padding(.horizontal, BroopMetrics.page)
                    .padding(.top, 28)
                }
                .frame(maxHeight: .infinity)
            }

            VStack(spacing: 14) {
                if showHelp || found.isEmpty {
                    Text("Not showing up? The official WHOOP app may still be holding it. Force-quit that app, then tap Search again.")
                        .font(BroopType.regular(13))
                        .foregroundStyle(showHelp ? BroopPalette.warning : BroopAccountStyle.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                BroopAccountButton(title: String(localized: "Search again"), kind: .secondary) { onRescan() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// Phone — link — strap, with a centre badge (found / paired).
private struct BroopAccountPairIllustration: View {
    enum State { case found, paired }
    let state: State

    var body: some View {
        let tint = state == .paired ? Color(broopHex: 0x44CC10) : BroopAccountStyle.broadcast
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(broopHex: 0x0B0C0D), Color(broopHex: 0x1C1F22)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5))
                .overlay(BroopMark().fill(style: FillStyle(eoFill: true)).foregroundStyle(.white).frame(width: 34, height: 34))
                .frame(width: 96, height: 170)
            ZStack {
                Rectangle().fill(tint).frame(height: 3)
                HStack {
                    Circle().fill(tint).frame(width: 10, height: 10)
                    Spacer()
                    Circle().fill(tint).frame(width: 10, height: 10)
                }
                Circle().fill(tint.opacity(0.35)).frame(width: 64, height: 64)
                Circle().fill(tint).frame(width: 48, height: 48)
                    .overlay(Image(systemName: state == .paired ? "checkmark" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(.white))
            }
            .frame(maxWidth: .infinity)
            BroopAccountStrapArt(connected: state == .paired)
                .frame(width: 80, height: 170)
        }
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }
}
#endif
