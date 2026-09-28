#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - Device Settings

/// WHOOP's Device Settings for NOOP's device registry: a connection header, STATUS (strap, battery,
/// buzz, broadcast) and ADVANCED (identity, pairing, restart, removal, developer probes, every paired
/// band). Every action goes through the same registry ops and AppModel / BLEManager calls the classic
/// Devices screen uses, behind the same gates and confirmations. No BLE command is new.
struct BroopAccountDeviceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let registry = model.deviceRegistry {
                BroopAccountDeviceContent(registry: registry)
            } else {
                BroopAccountPage {
                    BroopAccountHeading(title: String(localized: "Getting your devices ready"),
                                        detail: String(localized: "NOOP is opening your on-device data. Your paired bands will appear here in a moment."))
                }
            }
        }
        .broopAccountChrome(String(localized: "Device Settings"))
    }
}

private enum DeviceTab: Hashable { case status, advanced }

private struct BroopAccountDeviceContent: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage(PuffinExperiment.ecgKey) private var ecgEnabled = false

    @State private var tab: DeviceTab = .status
    @State private var showPair = false
    @State private var dialogs = BroopAccountDeviceDialogState()
    @State private var strapCompare: BroopAccountStrapCompare?

    private var activeDevices: [PairedDevice] { registry.devices.filter { $0.status != .archived } }
    private var removedDevices: [PairedDevice] { registry.devices.filter { $0.status == .archived } }
    private var activatableDevices: [PairedDevice] { activeDevices.filter { !$0.isImportSource } }
    private var active: PairedDevice? { registry.devices.first { $0.status == .active } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopAccountDeviceHeader(device: active, onRename: { device in
                    dialogs.renameDraft = device.nickname ?? device.displayName
                    dialogs.renameTarget = device
                })
                BroopAccountDeviceTabs(selection: $tab)
                    .padding(.top, 26)
                Group {
                    switch tab {
                    case .status: statusTab
                    case .advanced: advancedTab
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .task(id: activeDevices.count) { strapCompare = await BroopAccountStrapCompare.load(devices: activeDevices, repo: model.repo) }
        .fullScreenCover(isPresented: $showPair) {
            BroopAccountPairFlow(onClose: { showPair = false })
                .environmentObject(model)
                .environmentObject(live)
                .environmentObject(model.ble)
        }
        .modifier(BroopAccountDeviceDialogs(registry: registry, state: $dialogs, activatable: activatableDevices))
        .modifier(BroopAccountDeviceProbeDialogs(state: $dialogs))
        .modifier(BodyLocationProbeSheets(target: $dialogs.bodyLocationProbeTarget))
        .modifier(FeatureFlagProbeSheets(target: $dialogs.featureFlagProbeTarget))
        .modifier(EcgProbeSheets(target: $dialogs.ecgProbeTarget, wristTarget: $dialogs.ecgWristTarget))
        .modifier(DeviceConfigProbeSheets(target: $dialogs.deviceConfigProbeTarget))
    }

    // MARK: Status

    @ViewBuilder private var statusTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let guide = live.reconnectGuide {
                BroopAccountNotice(title: String(localized: "Can't connect: your strap's pairing was reset"), text: guide)
            }
            if let active {
                if bondRefused(active), let hint = live.pairingHint {
                    BroopAccountNotice(text: hint)
                }
                BroopAccountStrapHero(device: active, liveBatteryPct: liveBatteryPct(active),
                                      liveBatteryMv: isLive(active) ? live.batteryMv : nil,
                                      charging: isLive(active) ? live.charging == true : false)
                if let clock = strapClockState {
                    Text(verbatim: clock.line)
                        .font(BroopType.regular(12.5))
                        .foregroundStyle(BroopAccountStyle.caption)
                    if let warning = clock.warning { BroopAccountNotice(text: warning) }
                }
                BroopAccountSyncStatusRow()
                if SourceCoordinator.isWhoop(active) {
                    buzzCard(active)
                    BroopAccountBroadcastRow()
                }
                capabilities(active)
            } else {
                BroopAccountHeading(title: String(localized: "No active device"),
                                    detail: String(localized: "Pair a WHOOP to start collecting your data, or make one of your paired bands active in Advanced."))
                BroopAccountButton(title: String(localized: "Pair a device")) { showPair = true }
            }
        }
    }

    private func buzzCard(_ device: PairedDevice) -> some View {
        let enabled = isLive(device) && live.bonded
        return Button { model.buzzStrapOnce() } label: {
            HStack(spacing: 16) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(BroopPalette.row))
                VStack(alignment: .leading, spacing: 3) {
                    BroopCaps(String(localized: "Find my strap"), size: 13)
                    BroopCaps(enabled ? String(localized: "Buzz it now") : String(localized: "Needs an active strap connection"),
                              size: 10.5, color: BroopAccountStyle.caption)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(Text("Buzz strap"))
    }

    private func capabilities(_ device: PairedDevice) -> some View {
        let profile = DeviceCapabilityProfile.make(for: device)
        return VStack(alignment: .leading, spacing: 10) {
            BroopAccountSectionLabel(text: String(localized: "What it captures"))
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: profile.captures).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: profile.powers).font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if !profile.footnote.isEmpty {
                    Text(verbatim: profile.footnote).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        }
        .padding(.top, 8)
    }

    // MARK: Advanced

    @ViewBuilder private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let active { identity(active).padding(.bottom, 8) }

            BroopAccountActionCard(symbol: "plus.circle", title: String(localized: "Pair a device"),
                                   caption: String(localized: "Pair a WHOOP, a heart-rate strap, gym equipment or an experimental band. You choose whether it becomes your active device.")) {
                showPair = true
            }
            if let active, canReboot(active) {
                BroopAccountActionCard(symbol: "power", title: String(localized: "Restart device"),
                                       caption: String(localized: "Restart your strap. It disconnects for about 30 seconds and reconnects on its own. Your recorded data is kept.")) {
                    dialogs.rebootTarget = active
                }
            }
            if let active, isLive(active), live.backfilling, SourceCoordinator.isWhoop(active) {
                BroopAccountActionCard(symbol: "stop.circle", title: String(localized: "Stop sync"),
                                       caption: String(localized: "End the history sync that is running. Nothing is lost: records the strap has not handed over stay on it for next time.")) {
                    model.ble.abortBackfill()
                }
            }
            if let active {
                BroopAccountActionCard(symbol: "minus.circle", title: String(localized: "Unpair device"),
                                       caption: String(localized: "Remove \(active.displayName) from NOOP and release its Bluetooth connection. Its recorded data is kept and you can re-add it any time.")) {
                    dialogs.removeTarget = active
                }
            }
            if let active, !probes(active).isEmpty {
                probeMenu(active)
            }

            bandsSection
            if let strapCompare { BroopAccountStrapCompareCard(data: strapCompare) }
            if !removedDevices.isEmpty { removedSection }

            BroopAccountFootnote(text: String(localized: "WHOOP is NOOP's primary, fully-supported band. Other heart-rate straps are an early, in-development addition: they stream live heart rate and HRV, but not WHOOP's deeper sleep and recovery data."))
        }
    }

    private func identity(_ device: PairedDevice) -> some View {
        let firmware = firmware(for: device)
        let idLabel: String
        let idValue: String
        if isLive(device), SourceCoordinator.isWhoop(device), let name = live.advertisingName, !name.isEmpty {
            idLabel = String(localized: "Device ID"); idValue = name
        } else {
            idLabel = String(localized: "Model"); idValue = DeviceCapabilityProfile.make(for: device).displayModel
        }
        let layout = isLive(device) ? live.strapRange?.firmwareLayout : nil
        return HStack(alignment: .top, spacing: 0) {
            infoColumn(symbol: "applewatch.side.right", label: idLabel, value: idValue, second: nil)
            infoColumn(symbol: "cpu", label: String(localized: "Firmware"), value: firmware ?? "—",
                       second: layout.map { String(localized: "v\($0) history") })
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private func infoColumn(symbol: String, label: String, value: String, second: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(BroopAccountStyle.icon)
                .frame(height: 34)
            BroopCaps(label, size: 11, color: BroopAccountStyle.caption)
            Text(verbatim: value)
                .font(BroopType.number(15))
                .foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let second {
                Text(verbatim: second).font(BroopType.number(13)).foregroundStyle(BroopAccountStyle.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func probeMenu(_ device: PairedDevice) -> some View {
        let items = probes(device)
        return VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(items, id: \.title) { item in
                    Button { item.action() } label: { Label(item.title, systemImage: item.symbol) }
                }
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(BroopAccountStyle.icon)
                        .frame(width: 30, height: 30)
                        .padding(.leading, 14)
                    BroopCaps(String(localized: "Developer probes"), size: 13).padding(.leading, 18)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BroopAccountStyle.card))
            }
            Text("Read-only protocol probes from Test Centre → Connection. Each asks before it sends anything.")
                .font(BroopType.medium(14))
                .foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
    }

    private struct ProbeItem { let title: String; let symbol: String; let action: () -> Void }

    /// The classic card menu's probe entries, behind the same gates (DevicesContent in DevicesView).
    private func probes(_ device: PairedDevice) -> [ProbeItem] {
        let probeGate = device.status == .active && live.connected
            && SourceCoordinator.isWhoop(device) && TestCentre.active(.connection)
        let ecgGate = probeGate && (ecgEnabled || model.ecgMayBeRunning) && model.isWhoop5MG
        var items: [ProbeItem] = []
        if device.status == .active && live.connected && SourceCoordinator.isWhoop(device)
            && model.ble.isWhoop4 && TestCentre.active(.connection) {
            items.append(ProbeItem(title: String(localized: "Reboot probe (4.0 RE)…"), symbol: "ladybug") { dialogs.probeTarget = device })
        }
        if probeGate {
            items.append(ProbeItem(title: String(localized: "Battery-info probe (#592 RE)…"), symbol: "ladybug") { dialogs.batteryProbeTarget = device })
            items.append(ProbeItem(title: String(localized: "Body-location probe (#690 RE)…"), symbol: "ladybug") { dialogs.bodyLocationProbeTarget = device })
            items.append(ProbeItem(title: String(localized: "Feature-flag probe (#761 RE)…"), symbol: "ladybug") { dialogs.featureFlagProbeTarget = device })
        }
        if ecgGate {
            items.append(ProbeItem(title: String(localized: "ECG capture (MG, experimental)…"), symbol: "waveform.path.ecg") { dialogs.ecgProbeTarget = device })
        }
        if probeGate {
            items.append(ProbeItem(title: String(localized: "Device-config read probe (#103 RE)…"), symbol: "ladybug") { dialogs.deviceConfigProbeTarget = device })
        }
        return items
    }

    private var bandsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopAccountSectionLabel(text: String(localized: "Your bands"))
                Spacer()
                BroopCaps(activeDevices.count == 1 ? String(localized: "1 paired") : String(localized: "\(activeDevices.count) paired"),
                          size: 10.5, color: BroopAccountStyle.caption)
            }
            VStack(spacing: BroopAccountStyle.rowGap) {
                ForEach(activeDevices) { device in
                    BroopAccountBandRow(
                        device: device,
                        pill: pill(device),
                        subtitle: lastSeen(device),
                        onPrimary: device.status == .active || device.isImportSource ? nil : { dialogs.switchTarget = device },
                        menu: { bandMenu(device) })
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func bandMenu(_ device: PairedDevice) -> some View {
        if device.status != .active && !device.isImportSource {
            Button { dialogs.switchTarget = device } label: { Label("Make active", systemImage: "bolt.fill") }
        }
        Button {
            dialogs.renameDraft = device.nickname ?? device.displayName
            dialogs.renameTarget = device
        } label: { Label("Rename", systemImage: "pencil") }
        if canReboot(device) {
            Button { dialogs.rebootTarget = device } label: { Label("Restart strap…", systemImage: "arrow.clockwise") }
        }
        if isLive(device), live.backfilling, SourceCoordinator.isWhoop(device) {
            Button { model.ble.abortBackfill() } label: { Label("Stop sync", systemImage: "stop.circle") }
        }
        ForEach(probes(device), id: \.title) { item in
            Button { item.action() } label: { Label(item.title, systemImage: item.symbol) }
        }
        Divider()
        Button(role: .destructive) { dialogs.removeTarget = device } label: { Label("Remove", systemImage: "minus.circle") }
    }

    private var removedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopAccountSectionLabel(text: String(localized: "Removed"))
                Spacer()
                BroopCaps(String(localized: "Data kept"), size: 10.5, color: BroopAccountStyle.caption)
            }
            VStack(spacing: BroopAccountStyle.rowGap) {
                ForEach(removedDevices) { device in
                    BroopAccountBandRow(
                        device: device,
                        pill: DevicePillState.resolve(isArchived: true, isActive: false, isReconnecting: false,
                                                      bondRefused: false, isLiveConnected: false),
                        subtitle: String(localized: "Removed · data kept"),
                        onPrimary: device.isImportSource ? nil : { registry.setActive(device.id) },
                        menu: {
                            if !device.isImportSource {
                                Button { registry.setActive(device.id) } label: { Label("Make active", systemImage: "bolt.fill") }
                            }
                            Button {
                                dialogs.renameDraft = device.nickname ?? device.displayName
                                dialogs.renameTarget = device
                            } label: { Label("Rename", systemImage: "pencil") }
                            Divider()
                            Button(role: .destructive) { dialogs.deleteDataTarget = device } label: {
                                Label("Delete this device's data…", systemImage: "trash")
                            }
                            Button(role: .destructive) { dialogs.forgetTarget = device } label: {
                                Label("Forget device…", systemImage: "trash.slash")
                            }
                        })
                    .opacity(0.7)
                }
            }
        }
    }

    // MARK: Derived state (same expressions as DevicesContent)

    private func isLive(_ device: PairedDevice) -> Bool { device.status == .active && live.connected }

    private func bondRefused(_ device: PairedDevice) -> Bool { isLive(device) && live.pairingHint != nil }

    private func pill(_ device: PairedDevice) -> DevicePillState {
        DevicePillState.resolve(isArchived: device.status == .archived, isActive: device.status == .active,
                                 isReconnecting: device.status == .active && live.rebootInProgress && !live.connected,
                                 bondRefused: bondRefused(device), isLiveConnected: isLive(device))
    }

    private func canReboot(_ device: PairedDevice) -> Bool {
        isLive(device) && SourceCoordinator.isWhoop(device) && !model.ble.isWhoop4
    }

    private func liveBatteryPct(_ device: PairedDevice) -> Int? {
        guard isLive(device) else { return nil }
        return LiveConsoleReadout.batteryPercent(activeIsWhoop: SourceCoordinator.isWhoop(device),
                                                 whoopPct: live.batteryPct, ringPct: live.ouraBatteryPct)
    }

    private func firmware(for device: PairedDevice) -> String? {
        FirmwareAttribution.resolve(
            live: device.status == .active ? live.strapFirmware : nil,
            perDevice: SourceCoordinator.isWhoop(device)
                ? FirmwareAttribution.prefKey(peripheralId: device.peripheralId)
                    .flatMap { UserDefaults.standard.string(forKey: $0) } : nil,
            legacyGlobal: SourceCoordinator.isWhoop(device)
                ? UserDefaults.standard.string(forKey: "noop.lastFirmware") : nil,
            pairedCount: registry.devices.count)
    }

    private func lastSeen(_ device: PairedDevice) -> String {
        if bondRefused(device) { return String(localized: "Connected, but not paired") }
        if isLive(device) { return String(localized: "Connected now") }
        return String(localized: "Last seen \(relativeAgo(TimeInterval(device.lastSeenAt)))")
    }

    /// #987 clock state from the same ConnectionReadout parsers Devices and Test Centre bind.
    private var strapClockState: (line: String, warning: String?)? {
        guard live.connected else { return nil }
        let deviceClock = ConnectionReadout.clockCorrelatedDevice(logLines: live.log)
        guard deviceClock != nil || live.strapRange != nil || live.lastFrameAtUnix != nil else { return nil }
        let latched = ConnectionReadout.clockLatchedLabel(deviceClockUnix: deviceClock,
                                                          strapNewestUnix: live.strapRange?.newestUnix)
        let frame = ConnectionReadout.lastFrameLabel(lastFrameUnix: live.lastFrameAtUnix,
                                                     nowUnix: Int(Date().timeIntervalSince1970))
        let warning = ConnectionReadout.rtcWarning(deviceClockUnix: deviceClock,
                                                   strapNewestUnix: live.strapRange?.newestUnix,
                                                   batteryPct: live.batterySamples.last?.soc)
        return (String(localized: "Clock latched: \(latched) · last frame \(frame)"), warning)
    }
}

// MARK: - Header and tabs

private struct BroopAccountDeviceHeader: View {
    let device: PairedDevice?
    let onRename: (PairedDevice) -> Void
    @EnvironmentObject private var live: LiveState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                BroopCaps(statusText, size: 11.5, color: statusTint)
                if let device {
                    Button { onRename(device) } label: {
                        HStack(spacing: 8) {
                            BroopCaps(device.displayName, size: 17)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(BroopAccountStyle.icon)
                        }
                    }
                    .buttonStyle(BroopPressableStyle())
                    .accessibilityLabel(Text("Rename \(device.displayName)"))
                }
            }
            Spacer(minLength: 8)
            syncBlock
        }
    }

    private var pill: DevicePillState? {
        guard let device else { return nil }
        return DevicePillState.resolve(isArchived: false, isActive: true,
                                        isReconnecting: live.rebootInProgress && !live.connected,
                                        bondRefused: live.connected && live.pairingHint != nil,
                                        isLiveConnected: device.status == .active && live.connected)
    }

    private var statusText: String {
        guard let pill else { return String(localized: "No device paired") }
        switch pill.label {
        case "Active · Live": return String(localized: "Connected to")
        case "Connected · not paired": return String(localized: "Connected · not paired")
        case "Reconnecting…": return String(localized: "Reconnecting…")
        default: return String(localized: "Not connected")
        }
    }

    private var statusTint: Color {
        switch pill?.tone {
        case .positive?: return pill?.label == "Active · Live" ? BroopAccountStyle.connected : BroopAccountStyle.caption
        case .warning?: return BroopPalette.warning
        default: return BroopAccountStyle.caption
        }
    }

    @ViewBuilder private var syncBlock: some View {
        switch SyncChipState.resolve(live: live) {
        case .syncing(let chunks, _):
            syncView(title: String(localized: "Syncing"), value: chunks > 0 ? String(localized: "\(chunks) chunks") : "…",
                     symbol: "arrow.triangle.2.circlepath.icloud")
        case .synced:
            syncView(title: String(localized: "Last sync"),
                     value: live.lastSyncedAt.map { BroopFormat.time(Date(timeIntervalSince1970: $0)) } ?? "—",
                     symbol: "checkmark.icloud")
        case .experimentalLive:
            syncView(title: String(localized: "Live only"), value: String(localized: "History sync experimental"),
                     symbol: "icloud")
        case .hidden:
            EmptyView()
        }
    }

    private func syncView(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 5) {
                BroopCaps(title, size: 11, color: BroopAccountStyle.caption)
                Text(verbatim: value)
                    .font(BroopType.demi(14))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .lineLimit(1)
            }
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BroopAccountDeviceTabs: View {
    @Binding var selection: DeviceTab

    var body: some View {
        HStack(spacing: 34) {
            tab(.status, String(localized: "Status"))
            tab(.advanced, String(localized: "Advanced"))
            Spacer()
        }
    }

    private func tab(_ value: DeviceTab, _ title: String) -> some View {
        let on = selection == value
        return Button { withAnimation(.snappy) { selection = value } } label: {
            VStack(spacing: 8) {
                BroopCaps(title, size: 12, color: on ? BroopPalette.textPrimary : BroopAccountStyle.caption)
                Rectangle().fill(on ? BroopPalette.textPrimary : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Status pieces

/// The strap drawing bleeding off the left edge, with the battery column on the right.
private struct BroopAccountStrapHero: View {
    let device: PairedDevice
    let liveBatteryPct: Int?
    let liveBatteryMv: Int?
    let charging: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BroopAccountStrapArt(connected: liveBatteryPct != nil)
                .frame(width: 190, height: 330)
                .rotationEffect(.degrees(-16))
                .offset(x: -40, y: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .trailing, spacing: 4) {
                    if charging {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.system(size: 11))
                            BroopCaps(String(localized: "Charging"), size: 10)
                        }
                        .foregroundStyle(BroopAccountStyle.batteryFill)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        if let pct = liveBatteryPct {
                            Text(verbatim: "\(pct)")
                                .font(BroopType.number(54))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .broopNumeral(54)
                        } else {
                            Text(verbatim: "--")
                                .font(BroopType.number(54))
                                .foregroundStyle(BroopPalette.textSecondary)
                        }
                        Text(verbatim: "%").font(BroopType.number(22)).foregroundStyle(BroopPalette.textPrimary)
                    }
                    Text(verbatim: DeviceCapabilityProfile.make(for: device).displayModel)
                        .font(BroopType.medium(14))
                        .foregroundStyle(BroopAccountStyle.caption)
                    if let mv = liveBatteryMv {
                        Text(verbatim: String(format: "%.2f V", Double(mv) / 1000.0))
                            .font(BroopType.number(12))
                            .foregroundStyle(BroopPalette.textTertiary)
                    }
                }
                batteryBar
            }
            .padding(.trailing, 6)
            .padding(.bottom, 30)
        }
        .frame(height: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(liveBatteryPct.map { String(localized: "Battery \($0) percent") } ?? String(localized: "Battery unknown")))
    }

    private var batteryBar: some View {
        let frac = Double(liveBatteryPct ?? 0) / 100
        return ZStack(alignment: .bottom) {
            Capsule().fill(Color(broopHex: 0x2D3236))
            Capsule().fill(fill).frame(height: max(0, 118 * frac))
        }
        .frame(width: 6, height: 118)
    }

    private var fill: Color {
        guard let pct = liveBatteryPct else { return .clear }
        if pct < 15 { return BroopPalette.bandLow }
        if pct < 35 { return BroopPalette.warning }
        return BroopAccountStyle.batteryFill
    }
}

/// Strap-history sync state, resolved by the shared `SyncChipState` (Devices, Today).
private struct BroopAccountSyncStatusRow: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        switch SyncChipState.resolve(live: live) {
        case .syncing(let chunks, _):
            row("arrow.triangle.2.circlepath", chunks > 0 ? String(localized: "Syncing… \(chunks) chunks") : String(localized: "Syncing…"), BroopPalette.teal)
        case .synced(let agoText):
            row("checkmark.circle.fill", String(localized: "Synced \(agoText) ago"), BroopAccountStyle.connected)
        case .experimentalLive:
            row("checkmark.circle", String(localized: "Connected; strap history sync is experimental on this strap"), BroopAccountStyle.caption)
        case .hidden:
            EmptyView()
        }
    }

    private func row(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(String(localized: "Strap history"), size: 10.5, color: BroopAccountStyle.caption)
                Text(verbatim: text).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

/// WHOOP's BROADCAST HEART RATE card: the strap-side broadcast, the same key and BLE call the Data
/// Sources "Broadcast heart rate from the strap" switch uses.
struct BroopAccountBroadcastRow: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.broadcastHrKey) private var strapBroadcastHrEnabled = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(strapBroadcastHrEnabled ? BroopAccountStyle.broadcast : Color(broopHex: 0x3A3D40)))
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(String(localized: "Broadcast heart rate"), size: 12.5)
                    .lineLimit(1).minimumScaleFactor(0.7)
                BroopCaps(String(localized: "To compatible apps & devices"), size: 10, color: BroopAccountStyle.caption)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $strapBroadcastHrEnabled)
                .labelsHidden()
                .tint(BroopAccountStyle.broadcast)
                .accessibilityLabel(Text("Broadcast heart rate from the strap"))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        .onChange(of: strapBroadcastHrEnabled) { _, on in model.ble.setBroadcastHr(on) }
    }
}

/// One paired band: name, model, state, last seen, and the action menu.
private struct BroopAccountBandRow<MenuContent: View>: View {
    let device: PairedDevice
    let pill: DevicePillState
    let subtitle: String
    let onPrimary: (() -> Void)?
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 0) {
            Button { onPrimary?() } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(device.status == .active ? BroopPalette.textPrimary : BroopAccountStyle.icon)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            BroopCaps(device.displayName, size: 12.5).lineLimit(1)
                            if device.sourceKind == .oura { BroopAccountChip(text: String(localized: "Beta"), tint: BroopPalette.warning) }
                        }
                        Text(verbatim: "\(DeviceCapabilityProfile.make(for: device).displayModel) · \(subtitle)")
                            .font(BroopType.medium(12.5))
                            .foregroundStyle(BroopAccountStyle.caption)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    BroopAccountChip(text: pill.label, tint: tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BroopPressableStyle())
            .disabled(onPrimary == nil)
            Menu { menu() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BroopAccountStyle.icon)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Device actions for \(device.displayName)"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private var tint: Color {
        switch pill.tone {
        case .positive: return BroopAccountStyle.connected
        case .warning: return BroopPalette.warning
        default: return BroopAccountStyle.caption
        }
    }

    private var icon: String {
        if device.sourceKind == .ftms { return "figure.run.treadmill" }
        if device.sourceKind == .huami { return "waveform.path.ecg.rectangle" }
        if device.sourceKind == .liveAppleWatch { return "applewatch" }
        if device.sourceKind == .oura { return "circle.circle" }
        return SourceCoordinator.isWhoop(device) ? "applewatch.side.right" : "heart.circle"
    }
}

// MARK: - Strap comparison

/// #1300 tier 2: how the two straps' latest shared day lines up, with the same tolerances as the classic
/// Devices card. Read-only; never mixes into a score.
struct BroopAccountStrapCompare: Equatable {
    let aName: String
    let bName: String
    let day: String
    let rows: [StrapComparison.Row]

    @MainActor
    static func load(devices: [PairedDevice], repo: Repository) async -> BroopAccountStrapCompare? {
        let comparable = devices.filter { SourceCoordinator.isWhoop($0) || $0.id.hasPrefix("oura-") }
        guard comparable.count >= 2, let store = await repo.storeHandle() else { return nil }
        let a = comparable[0], b = comparable[1]
        async let aRaw = store.dailyMetrics(deviceId: a.id, from: "0000-01-01", to: "9999-12-31")
        async let bRaw = store.dailyMetrics(deviceId: b.id, from: "0000-01-01", to: "9999-12-31")
        let aDaily = (try? await aRaw) ?? []
        let bDaily = (try? await bRaw) ?? []
        let bByDay = Dictionary(bDaily.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        guard let shared = aDaily.sorted(by: { $0.day > $1.day }).first(where: { bByDay[$0.day] != nil }),
              let bShared = bByDay[shared.day] else { return nil }
        let rows = StrapComparison.compare(values(shared), values(bShared))
        return rows.isEmpty ? nil : BroopAccountStrapCompare(aName: a.displayName, bName: b.displayName, day: shared.day, rows: rows)
    }

    private static func values(_ d: DailyMetric) -> [MetricArbitrationPolicy.MetricKind: Double] {
        var out: [MetricArbitrationPolicy.MetricKind: Double] = [:]
        if let v = d.restingHr { out[.restingHR] = Double(v) }
        if let v = d.avgHrv { out[.hrv] = v }
        if let v = d.spo2Pct { out[.spo2] = v }
        if let v = d.skinTempDevC { out[.skinTemp] = v }
        if let v = d.steps { out[.steps] = Double(v) }
        if let v = d.totalSleepMin { out[.sleep] = v }
        if let v = d.activeKcalEst { out[.calories] = v }
        return out
    }
}

private struct BroopAccountStrapCompareCard: View {
    let data: BroopAccountStrapCompare

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopAccountSectionLabel(text: String(localized: "How your straps compare"))
            VStack(spacing: 10) {
                HStack {
                    Text(verbatim: data.aName).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(verbatim: data.bName).frame(width: 70, alignment: .trailing)
                    Spacer().frame(width: 74)
                }
                .font(BroopType.demi(11.5))
                .foregroundStyle(BroopAccountStyle.caption)
                ForEach(data.rows, id: \.metric) { row in
                    HStack(spacing: 10) {
                        Text(verbatim: label(row.metric)).font(BroopType.demi(14.5)).foregroundStyle(BroopPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: value(row.a)).font(BroopType.number(15)).foregroundStyle(BroopPalette.textPrimary)
                        Text(verbatim: value(row.b)).font(BroopType.number(15)).foregroundStyle(BroopPalette.textPrimary)
                            .frame(width: 70, alignment: .trailing)
                        agreement(row.agreement).frame(width: 74, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
            BroopAccountFootnote(text: String(localized: "A read-only look at your last shared day — not a combined score. Different devices read a little differently, so a difference isn't necessarily wrong."))
        }
    }

    private func value(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "—" }

    private func agreement(_ a: AgreementState) -> some View {
        switch a {
        case .agree: return BroopAccountChip(text: String(localized: "match"), tint: BroopAccountStyle.connected)
        case .minorDelta: return BroopAccountChip(text: String(localized: "close"), tint: BroopAccountStyle.caption)
        case .conflict: return BroopAccountChip(text: String(localized: "differs"), tint: BroopPalette.warning)
        case .single: return BroopAccountChip(text: String(localized: "one strap"), tint: BroopAccountStyle.caption)
        }
    }

    private func label(_ m: MetricArbitrationPolicy.MetricKind) -> String {
        switch m {
        case .restingHR: return String(localized: "Resting HR")
        case .heartRate: return String(localized: "Heart rate")
        case .hrv: return "HRV"
        case .spo2: return "SpO₂"
        case .skinTemp: return String(localized: "Skin temp")
        case .steps: return String(localized: "Steps")
        case .sleep: return String(localized: "Sleep")
        case .calories: return String(localized: "Calories")
        case .other: return ""
        }
    }
}

// MARK: - Dialogs

struct BroopAccountDeviceDialogState {
    var switchTarget: PairedDevice?
    var renameTarget: PairedDevice?
    var renameDraft = ""
    var removeTarget: PairedDevice?
    var deleteDataTarget: PairedDevice?
    var forgetTarget: PairedDevice?
    var rebootTarget: PairedDevice?
    var probeTarget: PairedDevice?
    var batteryProbeTarget: PairedDevice?
    var bodyLocationProbeTarget: PairedDevice?
    var featureFlagProbeTarget: PairedDevice?
    var ecgProbeTarget: PairedDevice?
    var ecgWristTarget: PairedDevice?
    var deviceConfigProbeTarget: PairedDevice?
    var pickNewActive = false
}

private func presented(_ binding: Binding<PairedDevice?>) -> Binding<Bool> {
    Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
}

/// Registry dialogs with the classic Devices copy and the same registry / BLE calls.
private struct BroopAccountDeviceDialogs: ViewModifier {
    @ObservedObject var registry: DeviceRegistry
    @Binding var state: BroopAccountDeviceDialogState
    let activatable: [PairedDevice]
    @EnvironmentObject private var model: AppModel

    private var currentActiveName: String {
        registry.devices.first(where: { $0.status == .active })?.displayName ?? String(localized: "Your current strap")
    }

    func body(content: Content) -> some View {
        content
            .alert("Make this your active strap?", isPresented: presented($state.switchTarget), presenting: state.switchTarget) { device in
                Button("Cancel", role: .cancel) { state.switchTarget = nil }
                Button("Make active") { registry.setActive(device.id); state.switchTarget = nil }
            } message: { device in
                Text("Make \(device.displayName) your active strap? From now on it provides your live data. \(currentActiveName)'s history stays exactly as it is. Only new days come from \(device.displayName).")
            }
            .alert("Rename device", isPresented: presented($state.renameTarget), presenting: state.renameTarget) { device in
                TextField("Name", text: $state.renameDraft)
                Button("Cancel", role: .cancel) { state.renameTarget = nil }
                Button("Save") { registry.rename(device.id, to: state.renameDraft); state.renameTarget = nil }
            } message: { device in
                Text("Give \(device.brand) \(device.model) a name you'll recognise.")
            }
            .modifier(RemoveDialogs(registry: registry, state: $state, activatable: activatable))
    }
}

private struct RemoveDialogs: ViewModifier {
    @ObservedObject var registry: DeviceRegistry
    @Binding var state: BroopAccountDeviceDialogState
    let activatable: [PairedDevice]
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Remove this device?", isPresented: presented($state.removeTarget), presenting: state.removeTarget) { device in
                Button("Cancel", role: .cancel) { state.removeTarget = nil }
                Button("Remove", role: .destructive) { confirmRemove(device) }
            } message: { device in
                Text("Remove \(device.displayName)? NOOP will stop connecting to it. Its recorded data is kept and you can re-add it any time.")
            }
            .alert("Delete all of this device's data?", isPresented: presented($state.deleteDataTarget), presenting: state.deleteDataTarget) { device in
                Button("Cancel", role: .cancel) { state.deleteDataTarget = nil }
                Button("Delete data", role: .destructive) {
                    let deviceId = device.id
                    Task {
                        guard let store = await model.repo.storeHandle() else { return }
                        await registry.deleteDeviceData(deviceId, store: store)
                    }
                    state.deleteDataTarget = nil
                }
            } message: { device in
                Text("This permanently deletes all data recorded from \(device.displayName). This can't be undone.")
            }
            .alert("Forget this device?", isPresented: presented($state.forgetTarget), presenting: state.forgetTarget) { device in
                Button("Cancel", role: .cancel) { state.forgetTarget = nil }
                Button("Forget device", role: .destructive) {
                    let deviceId = device.id
                    Task {
                        guard let store = await model.repo.storeHandle() else { return }
                        await registry.forget(deviceId, store: store)
                    }
                    state.forgetTarget = nil
                }
            } message: { _ in
                Text("NOOP removes this device from your list and deletes its recorded data here. You can re-pair the strap to pull its recent history back.")
            }
            .alert("Restart this strap?", isPresented: presented($state.rebootTarget), presenting: state.rebootTarget) { _ in
                Button("Cancel", role: .cancel) { state.rebootTarget = nil }
                Button("Restart") { model.rebootStrap(); state.rebootTarget = nil }
            } message: { device in
                Text("Restart \(device.displayName)? It disconnects for about 30 seconds while it reboots, then reconnects on its own. Your recorded data is kept.")
            }
            .confirmationDialog("Pick a new active strap", isPresented: $state.pickNewActive, titleVisibility: .visible) {
                ForEach(activatable) { device in
                    Button(device.displayName) { registry.setActive(device.id) }
                }
                Button("Leave none active", role: .cancel) { }
            } message: {
                Text("You removed your active strap. Choose which paired band provides your live data, or leave none active and pair one later.")
            }
    }

    /// Release the BLE link, archive the row, and offer a new active band if the active one went.
    private func confirmRemove(_ device: PairedDevice) {
        let wasActive = device.status == .active
        model.ble.forgetDevice(device.peripheralId)
        registry.archive(device.id)
        state.removeTarget = nil
        if wasActive {
            let remaining = activatable.filter { $0.id != device.id }
            if !remaining.isEmpty { state.pickNewActive = true }
        }
    }
}

/// The 4.0 reboot probe and the #592 battery probe (the other probes reuse the classic modifiers).
private struct BroopAccountDeviceProbeDialogs: ViewModifier {
    @Binding var state: BroopAccountDeviceDialogState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    func body(content: Content) -> some View {
        content
            .confirmationDialog("WHOOP 4.0 reboot probe", isPresented: presented($state.probeTarget),
                                titleVisibility: .visible, presenting: state.probeTarget) { _ in
                ForEach(RebootProbeVariant.allCases, id: \.self) { variant in
                    Button(variant.menuLabel) { model.rebootProbe(variant); state.probeTarget = nil }
                }
                Button("Cancel", role: .cancel) { state.probeTarget = nil }
            } message: { _ in
                Text("The WHOOP 4.0 reboot frame isn't confirmed — a normal Restart is ignored (#235). Send each candidate and watch BOTH the strap log and the strap itself. “no disconnect within 12s” means the strap ignored the frame. A “link dropped” line means the frame reached the strap — but a dropped link alone isn't a reboot: a real reboot also switches the strap's sensor light off for a few seconds, so if the light stayed on it was just a dropped connection, not a reboot. Non-destructive — your data is kept. Please share the log so we can pin the real frame.")
            }
            .confirmationDialog("Battery-info probe (#592 RE)", isPresented: presented($state.batteryProbeTarget),
                                titleVisibility: .visible, presenting: state.batteryProbeTarget) { _ in
                Button("Send probe (read-only)") { model.probeExtendedBatteryInfo(); state.batteryProbeTarget = nil }
                Button("Cancel", role: .cancel) { state.batteryProbeTarget = nil }
            } message: { _ in
                Text("Two independent protocol tables disagree on the extended-battery opcode (98 vs 87). This sends the curated read-only 98 and shows the strap's full raw reply. A battery-style payload confirms 98 on your firmware; a short stub means it stays ambiguous. Nothing is written to the strap.")
            }
            .sheet(isPresented: Binding(get: { live.extendedBatteryProbe != nil },
                                        set: { if !$0 { model.clearExtendedBatteryProbe() } })) {
                BroopAccountTextSheet(title: String(localized: "Battery-info probe result (#592)"),
                                      text: live.extendedBatteryProbe ?? "",
                                      waiting: live.extendedBatteryProbe == BLEManager.extendedBatteryProbeWaiting,
                                      onClose: { model.clearExtendedBatteryProbe() })
            }
    }
}

// MARK: - Strap drawing

/// A front view of a knit band with the sensor pod, drawn with shapes (no WHOOP artwork).
struct BroopAccountStrapArt: View {
    var connected = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bandW = w * 0.62
            ZStack {
                // Knit band.
                RoundedRectangle(cornerRadius: bandW * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0x1E2226), Color(broopHex: 0x0E1113)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: bandW, height: h)
                    .overlay(knit.clipShape(RoundedRectangle(cornerRadius: bandW * 0.18, style: .continuous)))
                    .overlay(RoundedRectangle(cornerRadius: bandW * 0.18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                // Sensor pod.
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0x4A5056), Color(broopHex: 0x23272B), Color(broopHex: 0x121417)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w * 0.70, height: h * 0.34)
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.04)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.6), radius: 14, x: 0, y: 10)
                // Clasp with the Broop mark.
                RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0x3A3F44), Color(broopHex: 0x1A1D20)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.78, height: h * 0.075)
                    .overlay(
                        BroopMark().fill(style: FillStyle(eoFill: true))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(width: h * 0.045, height: h * 0.045))
                    .offset(y: h * 0.17)
                if connected {
                    Circle().fill(BroopAccountStyle.connected)
                        .frame(width: 6, height: 6)
                        .offset(x: w * 0.27, y: -h * 0.15)
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }

    private var knit: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 5
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += step
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 1)
        }
    }
}
#endif
