#if os(iOS)
import SwiftUI
import UIKit
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - Notifications

/// Every notification switch the iPhone app has, in one list. the Notifications screen is
/// macOS-only (it picks Mac apps), so on iPhone these switches live on Automations and Features; this
/// page binds the same keys and runs the same authorisation requests, so the two places always agree.
struct BroopAccountNotificationsPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false
    @AppStorage(WorkoutDetectedNotifier.enabledDefaultsKey) private var workoutDetectedNotifyEnabled = false
    @AppStorage(SyncStallPolicy.enabledKey) private var syncStallReminderEnabled = true

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Wrist alerts")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Enable wrist alerts"),
                                       detail: String(localized: "The master switch for every wrist buzz (inactivity, stress, alerts). Off keeps the strap quiet no matter what else is on."),
                                       isOn: $wristAlertsMaster)
                }
            }
            BroopAccountSection(title: String(localized: "Phone notifications")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Sync stopped reminder"),
                                       detail: String(localized: "Asks you to reopen Broop after 30 minutes without a completed sync, or longer with power saving. It can arrive even if you swipe Broop away. Locking the phone is fine; swiping the app away stops background Bluetooth recovery."),
                                       isOn: $syncStallReminderEnabled)
                    BroopAccountToggle(title: String(localized: "Detected workouts"),
                                       detail: String(localized: "NOOP already saves sessions it detects on its own. With this on, it lets you know about ten minutes after one ends — one notification per sync at most. Open it to edit or relabel, or mark it not a workout. On \(Platform.deviceNounPhrase) only."),
                                       isOn: $workoutDetectedNotifyEnabled)
                    BroopAccountToggle(title: String(localized: "Low and full battery"),
                                       detail: String(localized: "A reminder to recharge before bed when the strap drops to 15%, and a heads-up when it reaches 100%, each at most once per charge cycle."),
                                       isOn: $behavior.batteryAlerts)
                    if behavior.batteryAlerts {
                        BroopAccountToggle(title: String(localized: "Predictive runtime warning"),
                                           detail: String(localized: "An early \"recharge tonight\" heads-up when the strap has about a day of estimated runtime left, at most once per discharge cycle. Turn off to keep only the 15% warning."),
                                           isOn: $behavior.batteryPredictiveAlerts)
                    }
                    BroopAccountToggle(title: String(localized: "Optimal strain reached"),
                                       detail: String(localized: "Posts after your strap syncs and NOOP scores the day — not the exact second you cross it. At most once per day."),
                                       isOn: $behavior.strainTargetNudge)
                    BroopAccountToggle(title: String(localized: "Above strain target"),
                                       detail: String(localized: "A heads-up when your Effort passes the top of today's target range, so you can ease off. At most once per day."),
                                       isOn: $behavior.strainTargetUpperNudge)
                    BroopAccountToggle(title: String(localized: "Early-illness signs"),
                                       detail: String(localized: "Needs at least 14 days of history. When two or more signals drift together you get a banner on the dashboard and a notification, at most once a day."),
                                       isOn: $behavior.illnessWatch)
                }
            }
            BroopAccountSection(title: String(localized: "Reminders")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountLink(value: BroopScreen.automations, symbol: "figure.stand",
                                     title: String(localized: "Inactivity & stand"),
                                     subtitle: String(localized: "Set up in Automations"))
                    BroopAccountLink(value: BroopScreen.alarms, symbol: "alarm",
                                     title: String(localized: "Alarms & wind-down"))
                }
            }
        }
        .broopAccountChrome(String(localized: "Notifications"))
        .onChange(of: syncStallReminderEnabled) { _, on in
            if on { SyncStallReminder.shared.requestAuthorizationIfNeeded() }
            SyncStallReminder.shared.refresh()
        }
        .onChange(of: workoutDetectedNotifyEnabled) { _, on in if on { WorkoutDetectedNotifier.requestAuthorization() } }
        .onChange(of: behavior.batteryAlerts) { _, on in if on { BatteryNotifier.requestAuthorization() } }
        .onChange(of: behavior.strainTargetNudge) { _, on in
            if on {
                StrainTargetNotifier.requestAuthorization()
                model.evaluateStrainTarget()
            }
        }
        .onChange(of: behavior.strainTargetUpperNudge) { _, on in
            if on {
                StrainTargetNotifier.requestAuthorization()
                model.evaluateStrainTarget()
            }
        }
        .onChange(of: behavior.illnessWatch) { _, on in
            model.reevaluateIllness()
            if on { IllnessNotifier.requestAuthorization() }
        }
    }
}

// MARK: - Coach & features

struct BroopAccountFeaturesPage: View {
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectWorkoutsEnabled = false
    @AppStorage(PuffinExperiment.journalReminderKey) private var journalReminderEnabled = true
    @AppStorage("workoutKeepScreenOn") private var workoutKeepScreenOn = false

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Coach")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "AI Coach"),
                                       detail: String(localized: "Turns the Coach, its Home entry and the daily brief on or off. Your saved provider key is kept, so turning it back on needs no setup."),
                                       isOn: $coachEnabled)
                }
            }
            BroopAccountSection(title: String(localized: "Trackers"),
                                footer: String(localized: "Optional trackers, off by default. Everything stays on \(Platform.deviceNounPhrase).")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Hydration tracking"),
                                       detail: String(localized: "Adds a simple fluid log with a daily goal that adjusts to your effort. Tap to add a sip, cup or bottle and watch a progress ring fill. On \(Platform.deviceNounPhrase) only. Nothing is synced."),
                                       isOn: $hydrationEnabled)
                    BroopAccountToggle(title: String(localized: "Auto-detect workouts"),
                                       detail: String(localized: "After a sync, NOOP looks over your recent heart rate for a sustained, raised stretch that looks like exercise and offers to save it. It only ever suggests. Nothing is saved until you tap Save, and you can dismiss any suggestion. Turning this off stops future suggestions but keeps your existing workout history. Deliberately conservative, so the odd workout may be missed. On \(Platform.deviceNounPhrase) only."),
                                       isOn: $autoDetectWorkoutsEnabled)
                    BroopAccountToggle(title: String(localized: "Journal reminder"),
                                       detail: String(localized: "Show a Today card reminding you to log your journal"),
                                       isOn: $journalReminderEnabled)
                    BroopAccountToggle(title: String(localized: "Keep screen on during a workout"),
                                       detail: String(localized: "Holds the screen awake while you're recording a workout, so your live heart rate stays visible without the device dimming. Only applies during a recording. The screen sleeps normally the rest of the time. Leaving it on does use a bit more battery, and means your unlocked screen stays visible for the whole workout, so flip it off if that's a concern."),
                                       isOn: $workoutKeepScreenOn)
                }
            }
        }
        .broopAccountChrome(String(localized: "Coach & Features"))
        .onChange(of: coachEnabled) { _, on in CoachBriefScheduler.applyMasterSwitch(on) }
    }
}

// MARK: - Strap & sync

struct BroopAccountStrapPage: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivityEnabled = true
    @AppStorage(UnitPrefs.syncLiveActivityKey) private var syncLiveActivityEnabled = true
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepScreenOn = false

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountStrapConnectionCard()
            BroopAccountSection(title: String(localized: "Live Activities")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Live heart rate in Dynamic Island"),
                                       detail: String(localized: "Shows your live heart rate on the Lock Screen and in the Dynamic Island while the strap is connected. Turn it off to keep your live HR out of the Dynamic Island. (Any one already showing clears within a moment.)"),
                                       isOn: $liveActivityEnabled)
                    BroopAccountToggle(title: String(localized: "Strap sync in Dynamic Island"),
                                       detail: String(localized: "Shows Connecting… / Syncing… with the chunk count and elapsed time while NOOP pulls history from your strap, including a sync started by the Sync Strap shortcut. Independent of the live heart rate switch above."),
                                       isOn: $syncLiveActivityEnabled)
                }
            }
            BroopAccountSection(title: String(localized: "Sync")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Keep screen on while syncing"),
                                       detail: String(localized: "Holds the screen awake while NOOP pulls stored history from your strap, so you can watch a long sync finish without the phone locking. Only applies while a sync is running and NOOP is open. The screen sleeps normally the rest of the time. It uses a bit more battery while the screen stays on."),
                                       isOn: $syncKeepScreenOn)
                }
            }
            BroopAccountSection(title: String(localized: "Strap log"),
                                footer: String(localized: "Grab this when you report a bug. It tells me what the app saw. (The full live log is also on the Live screen.)")) {
                BroopAccountStrapLogRow()
            }
            BroopAccountLink(value: BroopScreen.devices, symbol: "applewatch.side.right",
                             title: String(localized: "Device Settings"),
                             subtitle: String(localized: "Pair, switch, restart or remove straps"))
        }
        .broopAccountChrome(String(localized: "Strap & Sync"))
    }
}

/// Connection status, Re-scan / Disconnect and the WHOOP 4.0 rename, the Strap card's controls.
/// Observes `LiveState` on its own so the rest of the page does not re-render on every strap tick.
struct BroopAccountStrapConnectionCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    @State private var strapNameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(live.connectionStatusLabel, size: 11.5, color: statusTint)
                    Text(verbatim: statusDetail)
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopAccountStyle.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if let pct = live.batteryPct {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: "\(Int(pct.rounded()))%")
                            .font(BroopType.number(24))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .broopNumeral(24)
                        BroopCaps(live.charging == true ? String(localized: "Charging") : String(localized: "Battery"),
                                  size: 9, color: BroopAccountStyle.caption)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 10) {
                BroopAccountButton(title: String(localized: "Re-scan")) { model.scan() }
                BroopAccountButton(title: String(localized: "Disconnect"), kind: .secondary,
                                   enabled: live.connected || live.bonded) { model.disconnect() }
            }
            if live.connected && selectedWhoopModelRaw == WhoopModel.whoop4.rawValue {
                BroopHairline()
                renameControl
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private var statusTint: Color {
        if live.connectionStatusIsActive { return BroopAccountStyle.connected }
        if live.connectionStatusIsIdle { return BroopPalette.warning }
        return BroopAccountStyle.danger
    }

    /// Same priority as the Strap card (see SettingsView.strapStatusDetail).
    private var statusDetail: String {
        if live.encryptedBond && live.connected {
            return String(localized: "Your strap is paired and sending data. Open Live for a real-time heart rate.")
        }
        if live.connected, let hint = live.pairingHint { return hint }
        if live.bonded && live.connected {
            return String(localized: "Live heart rate is streaming, but your strap is not fully paired. The encrypted pairing is what carries motion, skin temperature, SpO₂ and respiratory rate — without it, sleep is staged from heart rate alone. Buzz, alarms and history sync need it too.")
        }
        if live.connected { return String(localized: "Connected. Finishing the secure pairing handshake…") }
        if live.bonded { return String(localized: "Previously paired but not currently connected. Re-scan to reconnect.") }
        return String(localized: "No strap connected. Put your WHOOP nearby and tap Re-scan to pair.")
    }

    /// WHOOP 4.0 only: rename the BLE advertising name; the strap reboots to apply.
    private var renameControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "Strap name"), size: 10.5, color: BroopAccountStyle.caption)
            Text("Current: \(live.advertisingName ?? "—")")
                .font(BroopType.medium(14))
                .foregroundStyle(BroopPalette.textBody)
            HStack(spacing: 10) {
                TextField(String(localized: "New strap name"), text: $strapNameDraft)
                    .textFieldStyle(.plain)
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopAccountStyle.field))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BroopAccountStyle.fieldBorder, lineWidth: 1))
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("New strap name"))
                Button { model.ble.renameStrap(strapNameDraft) } label: {
                    BroopCaps(String(localized: "Rename"), size: 11.5, color: .black)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BroopPressableStyle())
                .disabled(strapNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(strapNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            if let status = live.renameStatus {
                Text(verbatim: status).font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
            }
            Text("Changes the Bluetooth name your WHOOP 4.0 advertises (what you see when pairing). The strap reboots to apply, so the new name appears the next time it connects. WHOOP 4.0 only.")
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Copy / Save the strap log, the same text the Strap card and Live screen export.
struct BroopAccountStrapLogRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var copied = false

    var body: some View {
        BroopAccountGroup {
            BroopAccountButtonRow(title: String(localized: "Copy strap log"),
                                  value: copied ? String(localized: "Copied") : nil, showsChevron: false) {
                PlatformPasteboard.copy(live.exportableLogText())
                copied = true
            }
            BroopAccountButtonRow(title: String(localized: "Save strap log…"), showsChevron: false) {
                Task {
                    let extra = await DebugDataDiagnostics.dynamicLines(repo: model.repo)
                    FileExport.exportText(live.exportableLogText(extraHeaderLines: extra),
                                          suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
                }
            }
        }
    }
}

// MARK: - Backup & export

struct BroopAccountDataPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy = false
    @State private var alert: (title: String, message: String)?
    @State private var showOversizeRestoreConfirm = false
    @State private var oversizeRestoreMessage = ""

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountHeading(title: String(localized: "Backup & Export"),
                                detail: String(localized: "Move all your NOOP data to another device. Export saves everything (history, sleeps, workouts, settings) to a single file you can copy across; import replaces \(Platform.deviceNounPhrase)'s data with a backup."))
            VStack(spacing: 12) {
                BroopAccountButton(title: String(localized: "Export backup"), busy: busy) { runExport() }
                BroopAccountButton(title: String(localized: "Import backup"), kind: .secondary, enabled: !busy) { runImport() }
                BroopAccountButton(title: String(localized: "Export CSV"), kind: .secondary, enabled: !busy) { runCsvExport() }
            }
            BroopAccountNotice(symbol: "info.circle.fill",
                               text: String(localized: "Importing overwrites everything currently on \(Platform.deviceNounPhrase). Your old data is kept in a side file just in case. NOOP needs a relaunch for an import to take effect. Export CSV writes a WHOOP-format zip of your days, sleeps, workouts and journal that re-imports into NOOP on Mac, iPhone, or Android. On-device computed rows are marked APPROXIMATE in its Source column; the full backup stays the lossless restore path."),
                               tint: BroopAccountStyle.icon)
            BroopAccountNotice(text: String(localized: "This is a plain, unencrypted archive — anyone who gets the file can open it with any zip tool. Store it somewhere you trust."))
            BroopAccountLink(value: BroopScreen.backupSync, symbol: "externaldrive.badge.icloud",
                             title: String(localized: "Backup & Sync to a folder"),
                             subtitle: String(localized: "Daily backups to iCloud Drive or any folder"))
        }
        .broopAccountChrome(String(localized: "Backup & Export"))
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(verbatim: alert?.message ?? "")
        }
        .alert("Backup problem", isPresented: $showOversizeRestoreConfirm) {
            Button("Restore") { runImport(allowOversize: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(verbatim: oversizeRestoreMessage)
        }
    }

    private func runExport() {
        busy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }

    private func runImport(allowOversize: Bool = false) {
        busy = true
        Task {
            let result = await DataBackup.runImport(allowOversize: allowOversize)
            handleBackup(result)
        }
    }

    private func runCsvExport() {
        busy = true
        Task {
            let result = await CsvExport.run(repo: model.repo)
            busy = false
            switch result {
            case .cancelled:
                return
            case .exported(let url):
                alert = (String(localized: "CSV exported"),
                         String(localized: "Saved to \(url.lastPathComponent). The zip re-imports into NOOP (Data Sources → WHOOP Export) on any Mac, iPhone, or Android device."))
            case .failure(let message):
                alert = (String(localized: "Export problem"), message)
            }
        }
    }

    /// Same outcomes and copy as the Backup & restore card.
    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        busy = false
        switch result {
        case .cancelled:
            return
        case .exported(let url):
            alert = (String(localized: "Backup exported"),
                     String(localized: "Saved to \(url.lastPathComponent). Copy this file to your other \(Platform.deviceNoun) and use Import there to restore everything."))
        case .exportedOversize(let url, let bytes, let limit):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            alert = (String(localized: "Backup exported"),
                     String(localized: "Saved to \(url.lastPathComponent). Your database is \(size), over the \(cap) NOOP restores without asking — the backup is complete and valid, and restoring it will ask you to confirm once."))
        case .restoreTooLarge(let name, let limit):
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            oversizeRestoreMessage = String(localized: "\(name) is larger than the \(cap) NOOP restores without asking. That limit guards against a malicious archive expanding to fill this \(Platform.deviceNoun) — a backup you exported yourself is not that. Restoring it needs the space the database will take. You'll be asked to choose the file again.")
            showOversizeRestoreConfirm = true
        case .imported:
            alert = (String(localized: "Backup imported"),
                     String(localized: "Your data has been restored. Quit and reopen NOOP for it to take effect."))
        case .failure(let message):
            alert = (String(localized: "Backup problem"), message)
        }
    }
}

// MARK: - Scoring & recovery

struct BroopAccountScoringPage: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuousHrvEnabled = false
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var continuousHrvOvernightOnly = true
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindowRaw = HrvWindow.whole.rawValue
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var experimentalSleepV2Enabled = true
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionAwareWakeEnabled = false
    @AppStorage(RestScoringPrefs.v2Key) private var restV2Enabled = true
    @AppStorage(StrainTargetPrefs.goalKey) private var strainGoalRaw = StrainTarget.Goal.maintain.rawValue
    @AppStorage(EnergyPrefs.showKey) private var showEnergy = true
    @State private var showRecalibrateConfirm = false
    @State private var showRecalibrated = false

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Charge baseline"),
                                footer: String(localized: "Your Charge score learns a personal baseline from your heart-rate variability, resting heart rate and more over time. If a bad first week set it off, you can re-learn it from tonight. Your history stays.")) {
                BroopAccountGroup {
                    BroopAccountButtonRow(title: String(localized: "Recalibrate Charge baseline"),
                                          detail: String(localized: "Restarts the roughly 4-night build-up for Charge and your HRV baseline from tonight.")) {
                        showRecalibrateConfirm = true
                    }
                }
            }
            BroopAccountSection(title: String(localized: "Rest"),
                                footer: String(localized: "Changing this re-scores your whole history in the background, so Rest and the Charge that reads it move together.")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Sleep Performance (4 parts)"),
                                       detail: String(localized: "Scores Rest like WHOOP's 2025 Sleep Performance: hours vs. needed 55%, sleep consistency 15%, sleep efficiency 15% and sleep stress 15%. Restorative sleep is still shown, just not scored. A part that could not be measured for a night is left out and the rest are re-weighted. Off uses the older formula (hours, efficiency, restorative sleep and consistency)."),
                                       isOn: $restV2Enabled)
                }
            }
            BroopAccountSection(title: String(localized: "Effort target"),
                                footer: String(localized: "Your daily Effort target comes from today's Charge, lowered when you carry sleep debt or an illness heads-up is showing. The goal shifts the whole range.")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "Goal"),
                                       detail: String(localized: "Restore lowers the range by 3 on the 21-point scale (about 14 of 100), Build raises it by 2 (about 10 of 100)."),
                                       selection: $strainGoalRaw, options: [
                        (StrainTarget.Goal.restore.rawValue, String(localized: "Restore")),
                        (StrainTarget.Goal.maintain.rawValue, String(localized: "Maintain")),
                        (StrainTarget.Goal.build.rawValue, String(localized: "Build")),
                    ])
                }
            }
            BroopAccountSection(title: String(localized: "Energy")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Show Energy"),
                                       detail: String(localized: "A 0–100 estimate of your reserves, charged by restful sleep and drained by stress and exercise. Shown on Home and in Health. It does not change any score."),
                                       isOn: $showEnergy)
                }
            }
            BroopAccountSection(title: String(localized: "HRV")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Continuous HRV capture"),
                                       detail: String(localized: "Keeps the detailed beat-to-beat heart-rate stream running all day and night, not just while a live screen is open, so NOOP captures much more for overnight HRV, recovery and sleep. Uses more battery: your strap streams heart rate continuously while connected."),
                                       isOn: $continuousHrvEnabled)
                    if continuousHrvEnabled {
                        BroopAccountToggle(title: String(localized: "Overnight only"),
                                           detail: String(localized: "Runs the continuous HRV stream only during your quiet hours window (22:00–07:00 by default), roughly halving the battery cost. Daytime Stress readings will be sparser. Note: continuous background HRV capture (including daytime naps) is paused outside this window. For on-demand daytime HRV readings (including naps), use the \"Take an HRV reading\" button on the Live screen."),
                                           isOn: $continuousHrvOvernightOnly)
                    }
                    BroopAccountPicker(title: String(localized: "HRV window"),
                                       detail: String(localized: "Whole night is NOOP's default measure; Deep sleep pools HRV over slow-wave sleep only, reading lower and matching WHOOP. Switching re-scores your recent nights over the new window and takes effect right away once you have a few nights of data."),
                                       selection: $hrvWindowRaw, options: [
                        (HrvWindow.whole.rawValue, String(localized: "Night")),
                        (HrvWindow.deep.rawValue, String(localized: "Deep sleep")),
                    ])
                }
            }
            BroopAccountSection(title: String(localized: "Sleep staging")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Sleep staging (V2)"),
                                       detail: String(localized: "A transparent cardiorespiratory recipe that recovers deep and REM better than the older V1 staging, and is now the default. It only changes how already-detected nights are split into stages (detection and scores are unchanged); turn it off to fall back to V1. Takes effect on the next nights staged."),
                                       isOn: $experimentalSleepV2Enabled)
                    BroopAccountToggle(title: String(localized: "Motion-aware wake refinement"),
                                       detail: String(localized: "Reviews each scored wake block for real evidence of getting up (walking cadence, a change in body position) instead of just a heart-rate rise. A wake block with no locomotion and a stable posture — a hot night, a brief turn-over — is folded back into light sleep; a real get-up is left alone. Self-checks how much motion detail your strap actually recorded and stays off on a night that's too sparse to trust (older WHOOP 4.0 firmware, mainly). Off by default; takes effect on the next nights staged."),
                                       isOn: $motionAwareWakeEnabled)
                }
            }
        }
        .broopAccountChrome(String(localized: "Scoring & Recovery"))
        .onChange(of: continuousHrvEnabled) { _, on in model.ble.setKeepRealtimeForData(on) }
        .onChange(of: continuousHrvOvernightOnly) { _, _ in
            model.ble.setKeepRealtimeForData(PuffinExperiment.keepRealtimeForDataEnabled)
        }
        .onChange(of: strainGoalRaw) { _, _ in
            StrainTargetContext.shared.goal = StrainTargetPrefs.goal
            model.evaluateStrainTarget()
        }
        .onChange(of: hrvWindowRaw) { _, _ in
            Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
        }
        .onChange(of: restV2Enabled) { _, _ in
            // Every stored sleep_performance and the Charge that reads it are re-derived over the whole
            // history (days whose raw heart rate is still on the device).
            Task { await model.intelligence.rescoreForRestModeChange(); await model.repo.refresh() }
        }
        .confirmationDialog("Recalibrate your Charge baseline?", isPresented: $showRecalibrateConfirm, titleVisibility: .visible) {
            Button("Recalibrate") { recalibrate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restarts the roughly 4-night build-up for Charge and your HRV baseline. Your history stays. Use it if a bad first week, like wearing it while sick, set your baseline off.")
        }
        .alert("Charge baseline recalibrating", isPresented: $showRecalibrated) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("NOOP will re-learn your baseline from tonight's data onward. Your history is kept, and it takes a few nights to settle.")
        }
    }

    private func recalibrate() {
        Baselines.recalibrateRecoveryBaselines()
        Task {
            await model.intelligence.analyzeRecent()
            await model.repo.refresh()
        }
        showRecalibrated = true
    }
}

// MARK: - Experimental

struct BroopAccountExperimentalPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(PuffinExperiment.defaultsKey) private var puffinExperiments = false
    @AppStorage("noop.liquidTodayEnabled") private var liquidTodayEnabled = true
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2CandidateDisplayEnabled = false
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    @State private var rawCsvBusy = false
    @State private var exportError: String?

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountNotice(symbol: "flask.fill",
                               text: String(localized: "Experimental features are unfinished. They never feed a score you rely on unless their own description says so."),
                               tint: BroopPalette.warning)
            BroopAccountSection(title: String(localized: "Strap wake-alarm")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Protocol probes"),
                                       detail: String(localized: "Sends experimental protocol queries and records replies in the strap log. Also enables the experimental 5/MG strap alarm."),
                                       isOn: $puffinExperiments)
                }
            }
            BroopAccountSection(title: String(localized: "Screens")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Liquid Today (prototype)"),
                                       detail: String(localized: "Replaces the classic Today tab with the prototype redesign. Turn it off any time to return to the classic dashboard. Reads the same live data from your strap."),
                                       isOn: $liquidTodayEnabled)
                    BroopAccountToggle(title: String(localized: "Live Sessions (beta)"),
                                       detail: String(localized: "A one-tap guarded workout: the strap watches your heart rate against a band gated on today's Charge, and only ever buzzes to correct course. Silence means you're on track."),
                                       isOn: $liveSessionsBeta)
                }
            }
            if selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue || model.repo.activeDeviceIsOura {
                BroopAccountSection(title: String(localized: "Blood oxygen")) {
                    BroopAccountGroup {
                        BroopAccountToggle(title: String(localized: "Blood Oxygen: strap estimate (WHOOP 5/MG, Oura)"),
                                           detail: String(localized: "Your WHOOP 5.0/MG sends a strap-computed SpO₂ percentage (the @82 candidate byte) every second — an 8-night independent validation tracked it at corr +0.99 against the WHOOP app, but two nights on the original test device moved the OPPOSITE direction, so device/firmware variance is unresolved. An Oura ring's own SpO₂ reading runs high on the wire (over 100% on a fifth to a half of samples on a clean night); this instead surfaces the ring's mean with each sample capped at 100% first, which has matched the Oura app's own displayed value on every full night checked against it so far, though only a few nights. Turning this on surfaces whichever applies to your device as \"strap estimate (unverified)\" in the Blood Oxygen tile when no calibrated import exists. It never feeds recovery or illness scoring. WHOOP 4.0 has no @82 stream, so this does nothing there."),
                                           isOn: $spo2CandidateDisplayEnabled)
                    }
                }
            }
            BroopAccountSection(title: String(localized: "Diagnostics"),
                                footer: String(localized: "Dumps the last 24 hours of decoded per-sample sensor streams (heart rate, R-R, motion, steps, SpO₂, skin temperature, respiration, events) to a single CSV. All on \(Platform.deviceNounPhrase), nothing uploaded. Share it to help prototype and test sleep, activity and strength algorithms.")) {
                BroopAccountButton(title: rawCsvBusy ? String(localized: "Exporting…") : String(localized: "Export raw sensor data (CSV)"),
                                   kind: .secondary, busy: rawCsvBusy) { exportRawSensorCSV() }
            }
        }
        .broopAccountChrome(String(localized: "Experimental"))
        .onChange(of: puffinExperiments) { _, enabled in
            // Apply an already-saved wake time as soon as the user opts in.
            if enabled && behavior.smartAlarmEnabled && model.whoop5Detected {
                model.applySmartAlarm()
            }
        }
        .onChange(of: spo2CandidateDisplayEnabled) { _, _ in
            Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(verbatim: exportError ?? "")
        }
    }

    /// the raw CSV export: the ACTIVE strap id (`repo.deviceId`), last 24 h, shared via the sheet.
    private func exportRawSensorCSV() {
        rawCsvBusy = true
        let strapId = model.repo.deviceId
        Task {
            let since = Date().timeIntervalSince1970 - 24 * 60 * 60
            guard let store = await model.repo.storeHandle() else {
                rawCsvBusy = false
                exportError = String(localized: "Couldn't open the local store.")
                return
            }
            do {
                let url = try await store.exportRawCSV(deviceId: strapId, since: since)
                rawCsvBusy = false
                FileExport.exportFile(at: url)
            } catch {
                rawCsvBusy = false
                exportError = error.localizedDescription
            }
        }
    }
}

// MARK: - About

struct BroopAccountAboutPage: View {
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage(UpdateWatch.Keys.enabled) private var autoCheckUpdates = UpdateAvailability.defaultEnabled
    @Environment(\.openURL) private var openURL
    @State private var showWhatsNew = false
    @State private var showScoringGuide = false
    @State private var showHowNoopWorks = false
    @State private var showAppleWatchSetup = false
    @State private var showDiagnostics = false

    var body: some View {
        BroopAccountPage(spacing: 30) {
            VStack(spacing: 14) {
                BroopBadge(size: 64)
                BroopWordmark(size: 20)
                Text(verbatim: "NOOP v\(UpdateWatch.installedVersion)")
                    .font(BroopType.medium(14))
                    .foregroundStyle(BroopAccountStyle.caption)
                Text("A standalone companion for your WHOOP. Everything stays on this device: your history, your live stream, your numbers. Nothing is uploaded. NOOP is an independent, experimental project, not the WHOOP app.")
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopPalette.textBody)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(spacing: BroopAccountStyle.rowGap) {
                button("sparkles", String(localized: "What's New")) { showWhatsNew = true }
                button("questionmark.circle", String(localized: "How NOOP Works"),
                       String(localized: "Sleep sorting, scores, recording, and where your numbers come from.")) { showHowNoopWorks = true }
                button("gauge.with.needle", String(localized: "How Your Scores Work"),
                       String(localized: "Charge, Effort and Rest (and how they differ from WHOOP).")) { showScoringGuide = true }
                BroopAccountPageLink(symbol: "applewatch", title: String(localized: "About Apple Watch Data"),
                                     subtitle: String(localized: "Use NOOP with just an Apple Watch.")) {
                    BroopFinalAAppleWatchAboutPage(onStartSetup: { showAppleWatchSetup = true })
                }
                BroopAccountPageLink(symbol: "internaldrive", title: String(localized: "Storage"),
                                     subtitle: String(localized: "Where NOOP's on-device space is going, and a one-tap clean-up.")) {
                    BroopFinalAStoragePage()
                }
                button("stethoscope", String(localized: "Diagnostics"),
                       String(localized: "Device, iOS build, Data Protection and sideload status, for bug reports.")) { showDiagnostics = true }
            }

            BroopAccountSection(title: String(localized: "Updates"),
                                footer: String(localized: "Checks the project's home (GitHub) for the latest version when you tap. Nothing else is sent.")) {
                VStack(alignment: .leading, spacing: 12) {
                    BroopAccountGroup {
                        BroopAccountButtonRow(title: String(localized: "Check for updates"), value: updateStatus,
                                              showsChevron: updateChecker.state != .checking) {
                            updateChecker.check(currentVersion: UpdateWatch.installedVersion)
                        }
                        .disabled(updateChecker.state == .checking)
                        BroopAccountToggle(title: String(localized: "Check automatically"),
                                           detail: String(localized: "Once a day, NOOP asks GitHub for the latest version number and puts a note in Updates if there's a newer one. Nothing about you is sent, and it never installs anything."),
                                           isOn: $autoCheckUpdates)
                    }
                    if case .available(let v, let url, let notes) = updateChecker.state {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Version \(v) is available").font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                            if !notes.isEmpty {
                                ScrollView {
                                    Text(verbatim: notes).font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 150)
                            }
                            BroopAccountButton(title: String(localized: "Download")) { openURL(url) }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
                    }
                }
            }

            iphoneExpectations

            BroopAccountNotice(text: String(localized: "NOOP is not a medical device. It is for informational and personal-insight purposes only and is not intended to diagnose, treat, cure or prevent any condition. Talk to a clinician for medical advice."))

            BroopAccountSection(title: String(localized: "Built on"),
                                footer: String(localized: "Open-source BLE reverse-engineering work. Thank you.")) {
                BroopAccountGroup {
                    credit("johnmiddleton12/my-whoop", String(localized: "WHOOP 4.0 protocol"))
                    credit("b-nnett/goose", String(localized: "WHOOP 5.0 protocol"))
                    Link(destination: URL(string: "https://github.com/ryanbr/noop")!) {
                        BroopAccountRow(title: String(localized: "Project home & source"),
                                        detail: String(localized: "GitHub: code, releases, issues and the wiki.")) {
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BroopAccountStyle.icon)
                        }
                    }
                }
            }
        }
        .broopAccountChrome(String(localized: "About"))
        .sheet(isPresented: $showWhatsNew) { WhatsNewView(onClose: { showWhatsNew = false }) }
        .sheet(isPresented: $showScoringGuide) { BroopOverviewScoreGuide(onClose: { showScoringGuide = false }) }
        .sheet(isPresented: $showHowNoopWorks) { HowNoopWorksView(onClose: { showHowNoopWorks = false }) }
        .sheet(isPresented: $showAppleWatchSetup) { BroopFinalAAppleWatchSetup(onClose: { showAppleWatchSetup = false }) }
        .sheet(isPresented: $showDiagnostics) {
            let lines = IOSDiagnostics.capture().summaryLines()
            BroopAccountTextSheet(title: String(localized: "Diagnostics"),
                                  text: lines.isEmpty ? String(localized: "No iOS diagnostics available.") : lines.joined(separator: "\n"),
                                  onClose: { showDiagnostics = false })
        }
    }

    private var updateStatus: String? {
        switch updateChecker.state {
        case .checking: return String(localized: "Checking…")
        case .upToDate(let v): return String(localized: "You're on the latest (\(v)).")
        case .failed: return String(localized: "Couldn't check. Try again.")
        case .available(let v, _, _): return v
        case .idle: return nil
        }
    }

    private func button(_ symbol: String, _ title: String, _ subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopAccountMenuRow(symbol: symbol, title: title, subtitle: subtitle)
        }
        .buttonStyle(BroopPressableStyle())
    }

    private func credit(_ repo: String, _ note: String) -> some View {
        BroopAccountRow(title: repo, detail: note) { EmptyView() }
    }

    /// The honest sideload expectations, with the certificate expiry when it can be read.
    private var iphoneExpectations: some View {
        let diag = IOSDiagnostics.capture()
        let expiry = diag.expiryDaysRemaining()
        return BroopAccountSection(title: String(localized: "Using NOOP on iPhone")) {
            VStack(alignment: .leading, spacing: 10) {
                bullet(String(localized: "This is a sideloaded build, installed outside the App Store. It needs re-signing periodically: roughly every 7 days on a free Apple ID, about a year on a paid developer account."))
                bullet(String(localized: "After your iPhone reboots, unlock it once. Until you do, iOS keeps NOOP's files locked (Data Protection), so new history can't be written or synced."))
                bullet(String(localized: "Background Bluetooth has OS limits: iOS may pause NOOP when it's not in the foreground, so keep it open while syncing a fresh strap."))
                bullet(String(localized: "On a beta version of iOS, things can break that work on the release build."))
                if let days = expiry {
                    let warning = days <= 3
                    Text(verbatim: Self.expiryMessage(days))
                        .font(BroopType.demi(13))
                        .foregroundStyle(warning ? BroopPalette.warning : BroopAccountStyle.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(BroopAccountStyle.icon).frame(width: 4, height: 4).padding(.top, 7)
            Text(verbatim: text)
                .font(BroopType.regular(13.5))
                .foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func expiryMessage(_ days: Int) -> String {
        if days < 0 {
            let expired = -days
            return expired == 1
                ? String(localized: "This sideloaded build expired 1 day ago. Re-sign it to keep it running.")
                : String(localized: "This sideloaded build expired \(expired) days ago. Re-sign it to keep it running.")
        }
        return days == 1
            ? String(localized: "This sideloaded build expires in 1 day. Re-sign to keep it running.")
            : String(localized: "This sideloaded build expires in \(days) days. Re-sign to keep it running.")
    }
}
#endif
