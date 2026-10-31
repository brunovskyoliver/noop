import OuraProtocol
import StrandAnalytics   // ConnectionReadout - the #987 clock-latch / RTC-epoch readout parsers
import StrandDesign
import SwiftUI
import WhoopProtocol   // Whoop5Ecg.WristSelection — the MG ECG wrist-selection step
import WhoopStore

/// The device card's state-pill label/tone/pulsing, as a priority-ordered pure decision (#221): archived
/// beats everything; on the active card, reconnecting > bond-refused > live > plain active; a non-active
/// card is "Paired". Mirrors the Kotlin `devicePillState` in DevicesScreen.kt exactly (see
/// `DevicePillStateTests` / the Kotlin `DevicePillStateTest`), so a future edit to either side can't
/// silently reorder "Connected · not paired" vs "Active · Live" without a test catching it.
struct DevicePillState: Equatable {
    let label: String
    let tone: StrandTone
    var pulsing: Bool = false
    var showsDot: Bool = true

    static func resolve(isArchived: Bool, isActive: Bool, isReconnecting: Bool,
                         bondRefused: Bool, isLiveConnected: Bool) -> DevicePillState {
        if isArchived { return DevicePillState(label: "Removed", tone: .neutral, showsDot: false) }
        guard isActive else { return DevicePillState(label: "Paired", tone: .neutral) }
        if isReconnecting { return DevicePillState(label: "Reconnecting…", tone: .warning, pulsing: true) }
        if bondRefused { return DevicePillState(label: "Connected · not paired", tone: .warning) }
        if isLiveConnected { return DevicePillState(label: "Active · Live", tone: .positive, pulsing: true) }
        return DevicePillState(label: "Active", tone: .positive)
    }
}

/// Honest, per-model summary of what a device captures and what NOOP uses it for — shown on its card.
///
/// Derived from brand/model/sourceKind, NOT from the stored capability `Set`. The stored set is generic
/// across WHOOP models (it would render an identical "Heart rate · HRV · Blood oxygen · Skin temp · …"
/// line for a 4.0 and a 5/MG alike) and it mislabels: no SpO₂ **percentage** ever comes off any WHOOP
/// strap (raw red/IR only — a real % exists only from a WHOOP CSV / Apple Health import), skin temp is a
/// nightly ±°C sleep deviation rather than a live reading, steps are 5/MG-only and a raw motion count,
/// and Charge/Effort/Rest are NOOP-derived scores. Verdicts are source-verified against the decode +
/// scoring paths (the device-capability audit). `*` in a label = an on-device estimate, not a raw sensor.
struct DeviceCapabilityProfile {
    let displayModel: String   // clean card subtitle (replaces the redundant "WHOOP · WHOOP")
    let captures: String       // "·"-joined honest capture labels for THIS model
    let powers: String         // the NOOP scores / screens this device drives
    let footnote: String       // one short honest caveat line ("*" estimates + the SpO₂/steps notes)

    static func make(for d: PairedDevice) -> DeviceCapabilityProfile {
        // FTMS gym machine: a live machine + (when reported) HR session, recorded via the existing
        // live-workout path. Honest — we surface the machine's metrics + HR live; the session is
        // Effort-scored only when the machine actually reports heart rate.
        if d.sourceKind == .ftms {
            return DeviceCapabilityProfile(
                displayModel: String(localized: "Gym equipment (FTMS)"),
                captures: String(localized: "Speed · Cadence · Power · Distance · Energy · Heart rate (if the machine sends it)"),
                powers: String(localized: "Records a live machine workout, Effort-scored from HR when the machine reports it"),
                footnote: String(localized: "Live machine data over Bluetooth FTMS. No sleep, recovery, skin temp or SpO₂. Effort needs the machine's heart rate; without it the session logs the machine metrics only."))
        }
        // EXPERIMENTAL Huami device (Amazfit / Zepp / Mi Band): best-effort live HR only, honest about it.
        if d.sourceKind == .huami {
            return DeviceCapabilityProfile(
                displayModel: String(localized: "\(d.brand) (experimental)"),
                captures: String(localized: "Heart rate (live, best-effort)"),
                powers: String(localized: "Powers the live console + Effort. No Charge, Rest or Sleep"),
                footnote: String(localized: "Experimental: live heart rate where the band exposes it. Some bands need a pairing we can't do yet. NOOP will say so honestly and never show a made-up number. No sleep, recovery, skin temp, SpO₂ or steps."))
        }
        // EXPERIMENTAL locally-adopted Oura ring (gen 3/4/5). The gen is carried on `model` ("Oura Ring
        // 3/4/5") and recovered with OuraRingGen.from(model:). NOOP reads the ring's OWN raw signals + open
        // HRV/sleep-phase tags and computes its own Charge/Effort/Rest; it NEVER reads Oura's encrypted
        // Readiness/Sleep scores, and claims NO absolute SpO₂ %. Estimates carry "*"; a signal it can't read
        // stays "-". Per-gen copy and the canonical Beta caveat (spec
        // docs/superpowers/specs/2026-06-29-oura-onboarding-ux.md s3/s4).
        if d.sourceKind == .oura {
            let gen = OuraRingGen.from(model: d.model)
            // gen3/4 are verified-shape; gen5 ("newer") carries the least-proven caveat.
            let newer = (gen == .gen5)
            let captures = newer
                ? String(localized: "Heart rate* · HRV* · Sleep* · Resting HR* · Skin temp* · Battery*")
                : String(localized: "Heart rate · HRV* · Sleep · Resting HR · Skin temp* · Battery")
            let powers = newer
                ? String(localized: "Powers Effort now; Charge and Rest once enough nights and decode are confirmed")
                : String(localized: "Powers Charge, Effort, Rest and Sleep")
            return DeviceCapabilityProfile(
                displayModel: String(localized: "\(gen.displayName) (Beta)"),
                captures: captures,
                powers: powers,
                footnote: String(localized: "Beta. * is an on-device estimate. Skin temp is a trend versus your own baseline, and HRV needs you to be still. No Oura Readiness or SpO₂ percentage comes off the ring (import an Oura file for those)."))
        }
        // Apple Watch (live HealthKit source). UNLIKE the WHOOP/strap branches, the watch's stored
        // capability `Set` is already the honest per-model trim (AppleWatchDevice only adds a metric
        // once real data for it arrives), so we read the labels straight off it. An older watch with
        // no SpO₂/wrist-temp samples simply won't list them. Recovery is the calibrating-by-design
        // score (~a week of nights), so the footnote sets that expectation rather than over-promising.
        if d.sourceKind == .liveAppleWatch {
            let labels: [(Metric, String)] = [
                (.hr, String(localized: "Heart rate")), (.hrv, "HRV"), (.sleep, String(localized: "Sleep")),
                (.steps, String(localized: "Steps")), (.spo2, String(localized: "Blood oxygen")), (.skinTemp, String(localized: "Wrist temp")),
            ]
            let captures = labels.filter { d.capabilities.contains($0.0) }.map { $0.1 }.joined(separator: " · ")
            return DeviceCapabilityProfile(
                displayModel: "Apple Watch",
                captures: captures.isEmpty ? String(localized: "Calibrating, no data yet") : captures,
                powers: String(localized: "Powers Rest, Effort, Fitness Age and steps, plus Charge once recovery calibrates"),
                footnote: String(localized: "Computed live from your Apple Watch via Health. Recovery needs about a week of nights to calibrate, and every watch-derived score is labelled with its confidence. Only the metrics your watch actually records are listed above."))
        }
        // Generic heart-rate strap: live HR + R-R only; drives the live console + Effort, nothing nightly.
        // (Same WHOOP test as SourceCoordinator.isWhoop, inlined so this stays nonisolated.)
        let isWhoop = d.id == "my-whoop" || d.brand.caseInsensitiveCompare("WHOOP") == .orderedSame
        guard isWhoop else {
            return DeviceCapabilityProfile(
                displayModel: String(localized: "Heart-rate strap"),
                captures: String(localized: "Heart rate · HRV (live)* · Strain"),
                powers: String(localized: "Powers the live console + Effort. No Charge, Rest or Sleep"),
                footnote: String(localized: "Live HR + R-R only · no sleep, recovery, skin temp, SpO₂, steps or battery (those are WHOOP-only)."))
        }
        let whoopPowers = String(localized: "Powers Charge, Effort, Rest, Sleep + Health Monitor")
        let model = d.model.lowercased()
        // WHOOP 5.0 / MG — adds a (raw) step count the 4.0 can't read over BLE.
        if model.contains("5") || model.contains("mg") {
            return DeviceCapabilityProfile(
                displayModel: "WHOOP 5.0 / MG",
                captures: String(localized: "Heart rate · HRV · Skin temp* · Resp rate* · Steps* · Sleep · Strain · Battery"),
                powers: whoopPowers,
                footnote: String(localized: "* on-device estimate: skin temp is a nightly ±°C deviation, steps are a raw motion count (#78). No SpO₂ % off the strap; import a WHOOP CSV for a real %."))
        }
        // WHOOP 4.0 — NOOP's primary band; no steps over BLE.
        if model.contains("4") {
            return DeviceCapabilityProfile(
                displayModel: "WHOOP 4.0",
                captures: String(localized: "Heart rate · HRV · Skin temp* · Resp rate* · Sleep · Strain · Battery"),
                powers: whoopPowers,
                footnote: String(localized: "* on-device estimate: skin temp is a nightly ±°C deviation (firmware-dependent); no steps over BLE on a 4.0. No SpO₂ % off the strap; import a WHOOP CSV for a real %."))
        }
        // Legacy / unknown WHOOP (the seeded device, model just "WHOOP") — show only the common-to-all set.
        return DeviceCapabilityProfile(
            displayModel: "WHOOP",
            captures: String(localized: "Heart rate · HRV · Skin temp* · Resp rate* · Sleep · Strain · Battery"),
            powers: whoopPowers,
            footnote: String(localized: "Exact model unknown. Shows what every WHOOP can do. * on-device estimate · no SpO₂ % off the strap (import a WHOOP CSV for that)."))
    }
}

/// A four-bar Wi-Fi-style signal indicator derived from RSSI. RSSI is negative dBm: closer to 0 is
/// stronger. Buckets are coarse on purpose — a precise dBm readout would be noise to the user.
/// Internal (not private) so the Add-a-device wizard reuses the same indicator.
struct SignalBars: View {
    let rssi: Int

    static func level(for rssi: Int) -> Int {
        switch rssi {
        case (-55)...:    return 4   // very strong
        case (-67)...:    return 3
        case (-80)...:    return 2
        case (-90)...:    return 1
        default:          return 0
        }
    }

    var body: some View {
        let level = Self.level(for: rssi)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < level ? StrandPalette.accent : StrandPalette.hairlineStrong)
                    .frame(width: 3, height: 6 + CGFloat(i) * 3)
            }
        }
        .frame(width: 22, height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// #690: the body-location probe's confirm + result dialogs as one ViewModifier, so they're type-checked
/// in isolation instead of extending the DevicesView `.confirmationDialog`/`.sheet` chain (which is already
/// near the iOS Swift type-checker's budget). `model`/`live` auto-inject from the parent's environment.
struct BodyLocationProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Body-location probe (#690 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeBodyLocationAndStatus(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Sends the read-only GET_BODY_LOCATION_AND_STATUS (0x54) and shows the strap's full raw reply, decoding the body-location record (revision / location / confidence / status) on WHOOP 4.0. Nothing is written to the strap, and it never changes wear detection or scoring.")
            }
            .sheet(isPresented: Binding(get: { live.bodyLocationProbe != nil },
                                        set: { if !$0 { model.clearBodyLocationProbe() } })) {
                BodyLocationProbeResultView(
                    text: live.bodyLocationProbe ?? "",
                    onClose: { model.clearBodyLocationProbe() })
            }
    }
}

/// #761: the READ-ONLY feature-flag enumeration probe's confirm + result dialogs, isolated into a
/// ViewModifier for the same reason `BodyLocationProbeSheets` is — keeping the DevicesView
/// `.confirmationDialog`/`.sheet` chain inside the iOS Swift type-checker's budget.
struct FeatureFlagProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Feature-flag probe (#761 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeFeatureFlags(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Asks the strap to list the feature-flag NAMES its own firmware knows: START_FF_KEY_EXCHANGE (0x75) then SEND_NEXT_FF (0x76) until the strap says it's done. Read-only — no flag value is written, and the SET commands are never sent from this probe. The list is shown here and written to the strap log.")
            }
            .sheet(isPresented: Binding(get: { live.featureFlagProbe != nil },
                                        set: { if !$0 { model.clearFeatureFlagProbe() } })) {
                FeatureFlagProbeResultView(
                    text: live.featureFlagProbe ?? "",
                    onClose: { model.clearFeatureFlagProbe() })
            }
    }
}

/// The MG ECG probe's dialogs as one ViewModifier — the action sheet, the SEPARATE wrist confirm, and
/// the result sheet — isolated for the same iOS type-checker reason as `BodyLocationProbeSheets`.
///
/// The wrist selection is deliberately a second, independent confirmation rather than a button inside
/// the start flow: `SELECT_WRIST` writes strap state that survives a disconnect. The right/left mapping
/// is no longer a guess (right=1/left=2, from the official parser and the firmware constructor), but a
/// persistent write NOOP has not verified on its own hardware still costs a deliberate extra tap.
/// Internal, not private: the Broop device screen presents the same sheets.
struct EcgProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?
    @Binding var wristTarget: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("WHOOP MG ECG capture (experimental)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { device in
                Button("Start ECG capture") { model.ecgStartCapture(); target = nil }
                Button("Stop ECG capture") { model.ecgStopCapture(); target = nil }
                Button("Set which wrist you wear it on…") { target = nil; wristTarget = device }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("NOOP is not a medical device and this is not an ECG test. It asks your MG to start its ECG subsystem and logs whatever comes back — unvalidated instrumentation for protocol research, never a measurement or a diagnosis, including any heart-rhythm classification the strap happens to send. Don't use it to make a health decision; see a doctor if you have symptoms.\n\nHold the two indents on the clasp with the fingers of your other hand for the whole capture. The MG measures across your wrist AND that clasp, so until you hold it the circuit is open, the strap has nothing to record, and you would see zero packets whatever the firmware did.\n\nNobody has confirmed a strap honours these commands, so the likely outcome is that nothing happens. Everything here is reversible: “Stop” turns the streams back off. Results land in the strap log.")
            }
            // Wrist selection: its own step, with its own confirmation and its own warning.
            //
            // A SHEET rather than a second confirmationDialog for two reasons: presenting one dialog from
            // another in the same runloop tick races (the first is still dismissing, and the second can be
            // dropped), and a dialog's message truncates on iOS — while the persistence warning here is
            // the whole point of the step and has to be readable in full.
            .sheet(isPresented: Binding(get: { wristTarget != nil },
                                        set: { if !$0 { wristTarget = nil } })) {
                EcgWristSheet(onPick: { wrist in model.ecgSelectWrist(wrist); wristTarget = nil },
                              onCancel: { wristTarget = nil })
            }
            .sheet(isPresented: Binding(get: { live.ecgProbe != nil },
                                        set: { if !$0 { model.clearEcgProbe() } })) {
                EcgProbeResultView(text: live.ecgProbe ?? "",
                                   onClose: { model.clearEcgProbe() })
            }
    }
}

/// #103: the READ-ONLY device-config read probe's confirm + result dialogs, isolated into a
/// ViewModifier for the same reason `FeatureFlagProbeSheets` is — keeping the DevicesView
/// `.confirmationDialog`/`.sheet` chain inside the iOS Swift type-checker's budget.
struct DeviceConfigProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Device-config read probe (#103 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeDeviceConfigValues(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Asks the strap for config VALUES: GET_DEVICE_CONFIG_VALUE (0x79) and GET_FF_VALUE (0x80), one key per round-trip. Both commands may simply not exist in this firmware — finding that out is the point. Read-only — no value is written, and the SET commands are never sent from this probe. The result is shown here and written to the strap log.")
            }
            .sheet(isPresented: Binding(get: { live.deviceConfigProbe != nil },
                                        set: { if !$0 { model.clearDeviceConfigProbe() } })) {
                DeviceConfigProbeResultView(
                    text: live.deviceConfigProbe ?? "",
                    onClose: { model.clearDeviceConfigProbe() })
            }
    }
}

/// The #690 body-location probe reply (raw hex + decoded record + capture diff), or a "waiting…" state
/// while in flight. Read-only; selectable text + a Copy button. Twin of the Android BodyLocationProbe
/// result dialog and structurally identical to ExtendedBatteryProbeResultView.
private struct BodyLocationProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.bodyLocationProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Body-location probe result (#690)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// The #761 enumeration report (the strap's own flag-name list + the exchange trace), or a "waiting…"
/// state while the walk runs. Selectable text + a Copy button, structurally identical to the #592/#690
/// result views. Twin of the Android feature-flag probe result dialog.
private struct FeatureFlagProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.featureFlagProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Feature-flag probe result (#761)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                // Reuses the #592/#690 waiting copy — the walk sends one 118 per reply, so at any moment
                // it is waiting on exactly one strap reply, and the catalog keeps a single translation.
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// The wrist-selection step: the one ECG command that writes strap state outliving the session, so it
/// gets its own screen, its own warning, and its own confirmation rather than a button inside the start
/// flow. The copy names both facts plainly — that the value persists on the strap, and where the
/// left/right mapping comes from.
private struct EcgWristSheet: View {
    let onPick: (Whoop5Ecg.WristSelection) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which wrist do you wear it on?")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("This one is different from the other ECG controls: it is a setting written to the strap, and it stays there after you disconnect until you change it again.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
            Text("Which value means “left” and which means “right” comes from WHOOP's own app and the strap firmware, not from a strap NOOP has tested. You can send it again with the other choice at any time, and it changes nothing about your recorded data.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NoopMetrics.space3) {
                Button("Left wrist") { onPick(.left) }
                Button("Right wrist") { onPick(.right) }
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 220)
        .background(NoopChromeSurface())
    }
}

/// The MG ECG probe's report (verdict + per-command outcomes + candidate packet lines), or a "waiting…"
/// state while the listen window is open. Read-only, selectable, copyable — structurally identical to
/// `BodyLocationProbeResultView`, with the non-medical framing pinned above the text so it is read first.
private struct EcgProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.ecgProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ECG capture probe result")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Unvalidated instrumentation, not a medical measurement and not a diagnosis.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
            if waiting {
                Text("Listening for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// The #103 read report (per-verb verdict, the values read, the exchange transcript), or a "waiting…"
/// state while the plan runs. Selectable text + a Copy button, structurally identical to the #592/#690/
/// #761 result views. Twin of the Android device-config probe result dialog.
private struct DeviceConfigProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.deviceConfigProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device-config read probe result (#103)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                // Reuses the #592/#690/#761 waiting copy — the plan sends one read per reply, so at any
                // moment it is waiting on exactly one strap reply, and the catalog keeps one translation.
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}
