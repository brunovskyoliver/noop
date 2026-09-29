#if os(iOS)
import SwiftUI
import AppIntents
import StrandAnalytics
import StrandDesign

// MARK: - Data Sources

/// Every import and data source as WHOOP-style integration cards. Imports run through the AppModel
/// pipeline (WHOOP, Apple Health, Mi Band) or `DataSourceImports` (the classic screen's own logic,
/// shared), so a file lands exactly as it does from the classic Data Sources screen.
struct BroopAccountDataSourcesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @State private var busy: DataSourceImports.Target?
    @State private var summaries: [String: DataSourceImports.Outcome] = [:]
    @State private var confirmDeleteAppleHealth = false
    @State private var appleHealthDeleting = false
    @State private var appleHealthDeletedSummary: String?
    #if OURA_CLOUD_IMPORT
    @StateObject private var oura = OuraConnectModel()
    #endif

    private var localBusy: Bool { busy != nil }

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountHeading(title: String(localized: "Data Sources"),
                                detail: String(localized: "Everything stays on \(Platform.deviceNounPhrase). Bring your history in once, then it's yours."))
            BroopAccountSection(title: String(localized: "Wearable history")) {
                VStack(spacing: 12) {
                    whoopCard
                    appleHealthCard
                    card(symbol: "figure.walk.motion", title: String(localized: "Xiaomi Mi Band"),
                         detail: String(localized: "Import your Mi Band history (steps, heart rate, resting HR, sleep stages, SpO₂, stress and sleep score) straight from the Mi Fitness app. On your iPhone: Files → On My iPhone → Mi Fitness, long-press the folder → Compress, then choose the .zip here. Fully offline; no Xiaomi account or Bluetooth needed. Smart Band 8/9/10."),
                         action: String(localized: "Choose Mi Fitness export"), target: .xiaomi,
                         importing: model.isImporting(.xiaomi),
                         summary: model.xiaomiImportSummary.map { .init(summary: $0, failed: model.xiaomiImportFailed) })
                    card(symbol: "figure.mind.and.body", title: String(localized: "Oura / Fitbit / Garmin export"),
                         detail: String(localized: "Import your own data export from Oura, Fitbit or Garmin: sleep, resting heart rate, HRV, steps and more, where the export has them. Download it from the brand's app (Oura: Account → Export Data; Fitbit: Google Takeout; Garmin: Export Your Data), then choose the file here. Fully offline; nothing leaves \(Platform.deviceNounPhrase). Each brand's own readiness or sleep score is kept for reference only. Your scores stay yours."),
                         action: String(localized: "Choose export"), target: .wearable,
                         importing: busy == .wearable, summary: summaries["wearable"])
                    #if OURA_CLOUD_IMPORT
                    ouraCloudCard
                    #endif
                }
            }
            BroopAccountSection(title: String(localized: "Training & nutrition")) {
                VStack(spacing: 12) {
                    card(symbol: "fork.knife", title: String(localized: "Nutrition (.csv)"),
                         detail: String(localized: "Import daily nutrition totals from a Cronometer or MacroFactor CSV export: calories in, protein, carbs, fat (and weight if present). Other trackers work too if the file has a date column and daily totals."),
                         action: String(localized: "Choose .csv"), target: .nutrition,
                         importing: busy == .nutrition, summary: summaries["nutrition"])
                    card(symbol: "dumbbell", title: String(localized: "Lifting log (Hevy / Liftosaur)"),
                         detail: String(localized: "Import your strength-training history from a Hevy CSV export or a Liftosaur JSON export. Each workout becomes a Strength session with a training-volume estimate (weight × reps). It's a volume figure, not a measured strain. It never changes your Effort."),
                         action: String(localized: "Choose export"), target: .lifting,
                         importing: busy == .lifting, summary: summaries["lifting"])
                    card(symbol: "point.topleft.down.curvedto.point.bottomright.up", title: String(localized: "Workout file (GPX / TCX / FIT)"),
                         detail: String(localized: "Import a single exported workout file from any brand (Garmin, Coros, Suunto, Wahoo, Polar, Strava, Apple) straight off your device. GPS route, distance, heart rate and calories come in where the file has them. Fully offline; nothing leaves \(Platform.deviceNounPhrase)."),
                         action: String(localized: "Choose .gpx / .tcx / .fit"), target: .activityFile,
                         importing: busy == .activityFile, summary: summaries["activityFile"])
                }
            }
            BroopAccountSection(title: String(localized: "Live Bluetooth")) {
                VStack(spacing: 12) {
                    BroopAccountPhoneBroadcastCard()
                    BroopAccountLiveStrapCard()
                }
            }
        }
        .refreshable { await repo.refresh() }
        .broopAccountChrome(String(localized: "Data Sources"))
        .alert("Remove Apple Health imported data?", isPresented: $confirmDeleteAppleHealth) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { deleteAppleHealthData() }
        } message: {
            Text("This permanently deletes everything imported from Apple Health: heart rate, HRV, sleep, steps, workouts and more. Your live strap data is untouched. This can't be undone.")
        }
    }

    private var whoopCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            card(symbol: "square.and.arrow.down", title: String(localized: "WHOOP Export"),
                 detail: String(localized: "Import your full WHOOP history (recovery, strain, sleep, workouts) from a data export (.zip). Works for WHOOP 4.0, 5.0 and MG. Get one at app.whoop.com → Data Management."),
                 action: String(localized: "Choose export"), target: .whoop,
                 importing: model.isImporting(.whoop),
                 summary: model.whoopImportSummary.map { .init(summary: $0, failed: model.whoopImportFailed) },
                 status: repo.days.isEmpty ? String(localized: "Nothing imported") : String(localized: "Imported"),
                 footnote: String(localized: "\(repo.days.count) days · \(repo.sleeps.count) sleeps stored"))
        }
    }

    private var appleHealthCard: some View {
        card(symbol: "heart", title: "Apple Health",
             detail: String(localized: "Import an Apple Health export (Health app → profile → Export All Health Data → export.zip). 7 years of HR, HRV, sleep, SpO₂, steps and more, streamed locally. Large exports take a minute or two."),
             action: String(localized: "Choose export.zip"), target: .appleHealth,
             importing: model.isImporting(.appleHealth),
             summary: model.appleHealthImportSummary.map { .init(summary: $0, failed: model.appleHealthImportFailed) },
             extraDisabled: appleHealthDeleting) {
            VStack(alignment: .leading, spacing: 8) {
                BroopAccountButton(title: appleHealthDeleting ? String(localized: "Removing…") : String(localized: "Remove imported data"),
                                   kind: .destructive, busy: appleHealthDeleting,
                                   enabled: !model.hasActiveImport && !appleHealthDeleting) {
                    confirmDeleteAppleHealth = true
                }
                .accessibilityLabel(Text("Remove Apple Health imported data"))
                if let s = appleHealthDeletedSummary {
                    Text(verbatim: s).font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.connected)
                }
            }
        }
    }

    #if OURA_CLOUD_IMPORT
    private var ouraCloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(symbol: "circle.circle", title: String(localized: "Oura history import"), status: nil)
            Text("A one-time import of your own Oura history over the Oura API. Runs only when you tap it.")
                .font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
            if oura.isConnected {
                BroopAccountButton(title: String(localized: "Import again"), enabled: !oura.busy) { oura.connectAndImport(repo: repo) }
                BroopAccountButton(title: String(localized: "Forget Oura access"), kind: .destructive, enabled: !oura.busy) { oura.disconnect(repo: repo) }
            } else {
                BroopAccountButton(title: oura.busy ? String(localized: "Working…") : String(localized: "Import your Oura history"),
                                   enabled: !oura.busy && oura.isConfigured) { oura.connectAndImport(repo: repo) }
                if !oura.isConfigured {
                    Text("Add your Oura app credentials to OuraSecrets.xcconfig to enable this.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopAccountStyle.caption)
                }
            }
            if let s = oura.statusText { Text(verbatim: s).font(BroopType.regular(12.5)).foregroundStyle(BroopAccountStyle.caption) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }
    #endif

    private func header(symbol: String, title: String, status: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(BroopAccountStyle.icon)
                .frame(width: 28)
            BroopCaps(title, size: 12.5).lineLimit(2)
            Spacer(minLength: 6)
            if let status { BroopAccountChip(text: status, tint: BroopAccountStyle.caption) }
        }
    }

    private func card(symbol: String, title: String, detail: String, action: String,
                      target: DataSourceImports.Target, importing: Bool,
                      summary: DataSourceImports.Outcome?, status: String? = nil, footnote: String? = nil,
                      extraDisabled: Bool = false) -> some View {
        card(symbol: symbol, title: title, detail: detail, action: action, target: target, importing: importing,
             summary: summary, status: status, footnote: footnote, extraDisabled: extraDisabled) { EmptyView() }
    }

    private func card<Extra: View>(symbol: String, title: String, detail: String, action: String,
                                   target: DataSourceImports.Target, importing: Bool,
                                   summary: DataSourceImports.Outcome?, status: String? = nil, footnote: String? = nil,
                                   extraDisabled: Bool = false, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(symbol: symbol, title: title, status: status)
            Text(verbatim: detail)
                .font(BroopType.regular(13.5))
                .foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
            BroopAccountButton(title: importing ? String(localized: "Importing…") : action, kind: .secondary, busy: importing,
                               enabled: !model.hasActiveImport && !localBusy && !extraDisabled) {
                presentImporter(target)
            }
            if let summary {
                Text(verbatim: summary.summary)
                    .font(BroopType.medium(13))
                    .foregroundStyle(summary.failed ? BroopPalette.warning : BroopAccountStyle.connected)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote {
                Text(verbatim: footnote).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
            }
            extra()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    /// iOS picks through `DocumentPicker` (asCopy, so an iCloud placeholder downloads first), as classic.
    private func presentImporter(_ target: DataSourceImports.Target) {
        Task {
            guard let url = await DocumentPicker.importFile(target.allowedContentTypes) else { return }
            handlePicked(url, target)
        }
    }

    private func handlePicked(_ url: URL, _ target: DataSourceImports.Target) {
        switch target {
        case .whoop: model.importWhoop(url: url)
        case .appleHealth: model.importAppleHealth(url: url)
        case .xiaomi: model.importXiaomi(url: url)
        case .nutrition: run(target, key: "nutrition") { await DataSourceImports.importNutrition(url: url, repo: repo, live: live) }
        case .lifting: run(target, key: "lifting") { await DataSourceImports.importLifting(url: url, repo: repo, live: live) }
        case .activityFile:
            run(target, key: "activityFile") { await DataSourceImports.importActivityFile(url: url, model: model, repo: repo, live: live) }
        case .wearable: run(target, key: "wearable") { await DataSourceImports.importWearable(url: url, repo: repo, live: live) }
        }
    }

    private func run(_ target: DataSourceImports.Target, key: String,
                     _ work: @escaping () async -> DataSourceImports.Outcome) {
        busy = target
        summaries[key] = nil
        Task {
            summaries[key] = await work()
            busy = nil
        }
    }

    private func deleteAppleHealthData() {
        guard !appleHealthDeleting else { return }
        appleHealthDeleting = true
        appleHealthDeletedSummary = nil
        Task {
            appleHealthDeletedSummary = await DataSourceImports.deleteAppleHealthData(model: model, repo: repo, live: live)
            appleHealthDeleting = false
        }
    }
}

/// "Broadcast HR from this phone": the screen-owned HrBroadcaster, started while the switch is on and
/// released when the screen goes away, exactly as on the classic Data Sources screen.
private struct BroopAccountPhoneBroadcastCard: View {
    @EnvironmentObject private var live: LiveState
    @AppStorage(HrBroadcaster.defaultsKey) private var broadcastHrEnabled = false

    private final class LogSink { weak var live: LiveState? }
    private let sink: LogSink
    @StateObject private var broadcaster: HrBroadcaster

    init() {
        let sink = LogSink()
        self.sink = sink
        _broadcaster = StateObject(wrappedValue: HrBroadcaster(log: { [weak sink] line in
            MainActor.assumeIsolated { sink?.live?.append(log: line) }
        }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 20, weight: .light)).foregroundStyle(BroopAccountStyle.icon).frame(width: 28)
                BroopCaps(String(localized: "Broadcast HR from this phone"), size: 12.5).lineLimit(2)
                Spacer(minLength: 6)
                Toggle("", isOn: $broadcastHrEnabled).labelsHidden().tint(BroopAccountStyle.broadcast)
                    .accessibilityLabel(Text("Broadcast heart rate as a Bluetooth sensor"))
            }
            Text("Re-share your live strap heart rate over Bluetooth as a standard heart-rate sensor, so a gym treadmill, bike, Zwift, Peloton or any fitness app nearby can read it. Local Bluetooth only. Nothing leaves \(Platform.deviceNounPhrase). Off by default.")
                .font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                generation("WHOOP 4.0", String(localized: "Broadcasts the strap's own live heart rate over Bluetooth."))
                generation("WHOOP 5.0 & MG", String(localized: "Broadcasts the live heart rate NOOP derives from the strap once connected."))
            }
            if broadcastHrEnabled { status }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        .onAppear {
            sink.live = live
            broadcaster.bind(to: live)
            if broadcastHrEnabled { broadcaster.start() }
        }
        .onDisappear { broadcaster.stop() }
        .onChange(of: broadcastHrEnabled) { _, on in if on { broadcaster.start() } else { broadcaster.stop() } }
    }

    @ViewBuilder private var status: some View {
        if let note = broadcaster.statusNote {
            Text(verbatim: note).font(BroopType.medium(13)).foregroundStyle(BroopPalette.warning)
        } else if broadcaster.subscriberCount > 0 {
            let n = broadcaster.subscriberCount
            Text(n == 1 ? "1 device reading your heart rate" : "\(n) devices reading your heart rate")
                .font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.connected)
        } else if let hr = live.heartRate {
            Text("Sharing \(hr) bpm. Waiting for a device to pair.").font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.caption)
        } else {
            Text("No live heart rate yet. Open Live to pair your strap.").font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.caption)
        }
        BroopAccountChip(text: broadcaster.advertising ? String(localized: "Broadcasting") : String(localized: "Starting…"),
                         tint: broadcaster.advertising ? BroopAccountStyle.connected : BroopPalette.warning)
    }

    private func generation(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(BroopAccountStyle.broadcast).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(BroopType.demi(12.5)).foregroundStyle(BroopPalette.textBody)
                Text(verbatim: detail).font(BroopType.regular(12.5)).foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The live strap row: three-state connection label (as classic) + the strap-side broadcast switch.
private struct BroopAccountLiveStrapCard: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .light)).foregroundStyle(BroopAccountStyle.icon).frame(width: 28)
                BroopCaps(String(localized: "WHOOP Strap (Live BLE)"), size: 12.5).lineLimit(2)
                Spacer(minLength: 6)
            }
            BroopCaps(label, size: 11, color: tint)
            Text("Pairs directly with your strap over Bluetooth: no WHOOP app, no cloud.")
                .font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
            BroopAccountBroadcastRow()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private var label: String {
        if live.encryptedBond { return String(localized: "Bonded, streaming.") }
        if live.bonded { return String(localized: "Live HR (not fully paired)") }
        if live.connected { return String(localized: "Connected.") }
        return String(localized: "Not connected. Open Live to pair.")
    }

    private var tint: Color {
        if live.encryptedBond { return BroopAccountStyle.connected }
        if live.bonded || live.connected { return BroopPalette.warning }
        return BroopAccountStyle.danger
    }
}

// MARK: - Backup & Sync

struct BroopAccountBackupSyncView: View {
    @EnvironmentObject private var model: AppModel
    @State private var auto = FolderBackup.autoEnabled
    @State private var folderLabel = FolderBackup.folderLabel()
    @State private var lastMs = FolderBackup.lastBackupMs
    @State private var keep = FolderBackup.keepCount
    @State private var busy = false
    @State private var alert: (title: String, message: String)?
    @State private var showRestoreSheet = false
    @State private var snapshots: [FolderBackup.Snapshot] = []
    @State private var pendingRestore: FolderBackup.Snapshot?
    @State private var confirmRestore = false

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountHeading(title: String(localized: "Backup & Sync"),
                                detail: String(localized: "Save a full backup to a folder you choose - point it at Google Drive, iCloud or Dropbox for off-device sync."))
            BroopAccountSection(title: String(localized: "Backup folder")) {
                VStack(alignment: .leading, spacing: 12) {
                    BroopAccountGroup {
                        BroopAccountButtonRow(title: folderLabel == nil ? String(localized: "Choose folder") : String(localized: "Change folder"),
                                              value: folderLabel,
                                              detail: folderLabel == nil ? String(localized: "No folder chosen yet. Pick one your cloud app already syncs, or any local folder.") : nil) {
                            chooseFolder()
                        }
                        .disabled(busy)
                        if !FolderBackup.useInternalFolder {
                            BroopAccountButtonRow(title: String(localized: "Use NOOP's own folder"),
                                                  detail: String(localized: "Browse it in Files → On My iPhone → NOOP → Backups.")) {
                                useNoopFolder()
                            }
                            .disabled(busy)
                        }
                    }
                    BroopAccountFootnote(text: String(localized: "Tip: choose a folder in iCloud Drive and your backups sync to all your Apple devices automatically, no account setup needed."))
                    BroopAccountNotice(text: String(localized: "These backups are unencrypted too. If this folder syncs to Drive, Dropbox or iCloud, the readable file goes there as well — only point it at a service you trust."))
                }
            }
            BroopAccountSection(title: String(localized: "Automatic backups")) {
                VStack(alignment: .leading, spacing: 12) {
                    BroopAccountGroup {
                        BroopAccountToggle(title: String(localized: "Daily auto-backup"),
                                           detail: String(localized: "Backs up to your folder about once a day and keeps the latest \(keep). On this platform it runs when you next open NOOP."),
                                           isOn: $auto, enabled: folderLabel != nil)
                        BroopAccountPicker(title: String(localized: "Keep last snapshots"),
                                           detail: String(localized: "Older backups beyond this many are pruned, oldest first (≈ that many days). If data ever corrupts, restore the newest."),
                                           selection: $keep, options: FolderBackup.keepOptions.map { ($0, "\($0)") })
                    }
                    Text(verbatim: lastMs > 0 ? String(localized: "Last backup: \(relativeTime(lastMs))") : String(localized: "No backup yet."))
                        .font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.caption)
                    if auto, folderLabel != nil, lastMs > 0,
                       BackupSync.isBackupStale(lastBackupMs: lastMs, nowMs: Int(Date().timeIntervalSince1970 * 1000.0)) {
                        BroopAccountNotice(text: String(localized: "Auto-backup hasn't run in a few days. Check the backup folder is still available — a moved or disconnected cloud folder stops backups silently."))
                    }
                    BroopAccountButton(title: busy ? String(localized: "Working…") : String(localized: "Back up now"), busy: busy,
                                       enabled: folderLabel != nil) { backupNow() }
                }
            }
            BroopAccountSection(title: String(localized: "Restore"),
                                footer: String(localized: "Replace this device's data with one of the backups in your folder. This overwrites current data, so back up first if you're unsure.")) {
                BroopAccountButton(title: String(localized: "Restore from a backup"), kind: .secondary,
                                   enabled: folderLabel != nil && !busy) { openRestorePicker() }
            }
        }
        .broopAccountChrome(String(localized: "Backup & Sync"))
        .onChange(of: auto) { _, on in FolderBackup.autoEnabled = on }
        .onChange(of: keep) { _, n in FolderBackup.keepCount = n }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(verbatim: alert?.message ?? "") }
        .sheet(isPresented: $showRestoreSheet) {
            BroopAccountRestorePicker(snapshots: snapshots) { chosen in
                showRestoreSheet = false
                pendingRestore = chosen
                if chosen != nil { confirmRestore = true }
            }
        }
        .alert("Restore this backup?", isPresented: $confirmRestore, presenting: pendingRestore) { snap in
            Button("Replace all data", role: .destructive) { runRestore(snap) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { snap in
            Text(snap.timeMs > 0
                 ? "Replace all current data with the backup from \(Self.absoluteTime(snap.timeMs))? This cannot be undone."
                 : "Replace all current data with the backup \(snap.name)? This cannot be undone.")
        }
    }

    private func chooseFolder() {
        busy = true
        Task {
            defer { busy = false }
            let picked = await FolderBackup.pickFolder()
            if picked != nil {
                folderLabel = FolderBackup.folderLabel()
            } else if !FolderBackup.useInternalFolder {
                alert = (String(localized: "No folder selected"),
                         String(localized: "NOOP didn't get a folder back from the picker. If the Open button won't do anything, tap \"Use NOOP's own folder\" below to back up inside NOOP instead — you can read those backups from the Files app."))
            }
        }
    }

    private func useNoopFolder() {
        FolderBackup.useNoopFolder()
        folderLabel = FolderBackup.folderLabel()
        alert = (String(localized: "Using NOOP's folder"),
                 String(localized: "Backups will be saved inside NOOP. Open the Files app → On My iPhone → NOOP → Backups to see them, or drag that folder into iCloud Drive to read it on your Mac. To use a different folder later, tap Change folder."))
    }

    private func backupNow() {
        busy = true
        Task {
            defer { busy = false }
            let ok = await FolderBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() })
            lastMs = FolderBackup.lastBackupMs
            alert = ok ? (String(localized: "Backed up"), String(localized: "Saved a backup to your folder."))
                       : (String(localized: "Backup problem"), String(localized: "Backup failed - re-pick the folder and try again."))
        }
    }

    private func openRestorePicker() {
        snapshots = FolderBackup.listSnapshots()
        if snapshots.isEmpty {
            alert = (String(localized: "No backups found"), String(localized: "There are no NOOP backups in your folder yet. Use Back up now first."))
        } else {
            showRestoreSheet = true
        }
    }

    private func runRestore(_ snap: FolderBackup.Snapshot) {
        pendingRestore = nil
        busy = true
        Task {
            defer { busy = false }
            let result = await Task.detached(priority: .userInitiated) { FolderBackup.restore(snapshotNamed: snap.name) }.value
            switch result {
            case .imported:
                alert = (String(localized: "Restored"), String(localized: "Fully quit and reopen NOOP to load it."))
            case .failure(let m):
                alert = (String(localized: "Restore problem"), m)
            case .restoreTooLarge(let name, let limit):
                let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
                alert = (String(localized: "Backup problem"),
                         String(localized: "\(name) is larger than the \(cap) NOOP restores without asking. You can still restore it from Settings → Backup & restore → Import, which will ask you to confirm."))
            case .cancelled, .exported, .exportedOversize:
                alert = (String(localized: "Restore problem"), String(localized: "Couldn't restore that backup."))
            }
        }
    }

    private func relativeTime(_ ms: Int) -> String {
        RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: Double(ms) / 1000.0), relativeTo: Date())
    }

    static func absoluteTime(_ ms: Int) -> String {
        let f = DateFormatter()
        f.locale = AppClock.formattingLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }
}

private struct BroopAccountRestorePicker: View {
    let snapshots: [FolderBackup.Snapshot]
    let onChoose: (FolderBackup.Snapshot?) -> Void

    var body: some View {
        NavigationStack {
            BroopAccountPage(spacing: 10) {
                ForEach(snapshots) { snap in
                    Button { onChoose(snap) } label: {
                        BroopAccountMenuRow(symbol: "clock.arrow.circlepath",
                                            title: snap.timeMs > 0 ? BroopAccountBackupSyncView.absoluteTime(snap.timeMs) : snap.name,
                                            subtitle: snap.timeMs > 0 ? snap.name : nil)
                    }
                    .buttonStyle(BroopPressableStyle())
                }
            }
            .background(BroopBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BroopCaps(String(localized: "Choose a backup"), size: 13) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onChoose(nil) } }
            }
            .tint(BroopPalette.textPrimary)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shortcuts Export

struct BroopAccountShortcutsExportView: View {
    @AppStorage(ShortcutHealthExport.enabledKey) private var enabled = false

    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountLinkIllustration(symbols: ["heart", "waveform.path.ecg", "figure.walk"]) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(broopHex: 0xE0457B), Color(broopHex: 0x5B4BD6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 32)).foregroundStyle(.white))
            }
            Text("Strap data into Apple Health without HealthKit, for sideloaded installs.")
                .font(BroopType.medium(17)).foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            BroopAccountGroup {
                BroopAccountToggle(title: String(localized: "Export for Shortcuts (Apple Health)"), isOn: $enabled)
            }
            BroopAccountFootnote(text: String(localized: "When this is on, NOOP rewrites a plain-text file (On My iPhone › NOOP › noop_sync.txt) each time you leave the app: one line per 15 minutes of heart rate, HRV and steps, read straight from your strap. Pair it with the Siri Shortcut that reads the file and logs everything into Apple Health (no HealthKit entitlement needed), so it works on sideloaded installs. The setup guide and the pre-built Shortcut live in the project wiki on GitHub."))
        }
        .broopAccountChrome(String(localized: "Shortcuts Export"))
    }
}

// MARK: - Siri & Shortcuts

struct BroopAccountSiriView: View {
    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountHeading(title: String(localized: "Siri & Shortcuts"),
                                detail: String(localized: "Sync your strap, buzz it or mark a moment from Siri, Spotlight, the Shortcuts app, or a Back-Tap / automation. No setup needed."))
            VStack(spacing: 10) {
                SiriTipView(intent: SyncStrapIntent(), isVisible: .constant(true)).siriTipViewStyle(.dark)
                SiriTipView(intent: BuzzStrapIntent(), isVisible: .constant(true)).siriTipViewStyle(.dark)
                SiriTipView(intent: MarkMomentIntent(), isVisible: .constant(true)).siriTipViewStyle(.dark)
            }
            BroopAccountSection(title: String(localized: "Build your own"),
                                footer: String(localized: "Wire NOOP's actions into a Back-Tap, a focus automation, or a longer Shortcut. For example, double-tap the back of your iPhone to buzz the strap.")) {
                ShortcutsLink()
            }
        }
        .broopAccountChrome(String(localized: "Siri & Shortcuts"))
    }
}

// MARK: - What your strap reads

struct BroopAccountLimitationsView: View {
    private enum Mark { case full, partial, none }
    private struct Row: Identifiable { let feature: String; let w4: Mark; let w5: Mark; var id: String { feature } }

    // Mirrors NoopLimitationsView row for row (see its notes on why respiratory rate is partial on both).
    private let rows: [Row] = [
        Row(feature: String(localized: "Live heart rate"), w4: .full, w5: .full),
        Row(feature: String(localized: "HRV (rMSSD)"), w4: .full, w5: .full),
        Row(feature: String(localized: "Sleep staging"), w4: .full, w5: .full),
        Row(feature: String(localized: "Recovery & strain"), w4: .full, w5: .full),
        Row(feature: String(localized: "Respiratory rate"), w4: .partial, w5: .partial),
        Row(feature: String(localized: "Stress (on-device)"), w4: .full, w5: .full),
        Row(feature: String(localized: "Workout detection"), w4: .full, w5: .full),
        Row(feature: String(localized: "Skin temperature"), w4: .partial, w5: .full),
        Row(feature: String(localized: "Steps"), w4: .partial, w5: .full),
        Row(feature: String(localized: "Blood oxygen (SpO₂ %)"), w4: .none, w5: .none),
        Row(feature: String(localized: "ECG"), w4: .none, w5: .partial),
        Row(feature: String(localized: "Blood pressure"), w4: .none, w5: .none),
    ]

    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountHeading(title: String(localized: "What your strap reads"),
                                detail: String(localized: "What NOOP can read off each WHOOP, live and on this device."))
            VStack(spacing: 0) {
                HStack {
                    BroopCaps(String(localized: "Feature"), size: 10, color: BroopAccountStyle.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BroopCaps("4.0", size: 10, color: BroopAccountStyle.caption).frame(width: 60)
                    BroopCaps("5.0/MG", size: 10, color: BroopAccountStyle.caption).frame(width: 60)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                ForEach(rows) { row in
                    BroopHairline()
                    HStack {
                        Text(verbatim: row.feature).font(BroopType.demi(15)).foregroundStyle(BroopPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        cell(row.w4)
                        cell(row.w5)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(row.feature): WHOOP 4.0 \(spoken(row.w4)), 5.0/MG \(spoken(row.w5))"))
                }
            }
            .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
            BroopAccountSection(title: String(localized: "Legend")) {
                VStack(alignment: .leading, spacing: 12) {
                    legend(.full, String(localized: "Read live off the strap"))
                    legend(.partial, String(localized: "On-device estimate, or experimental / firmware-gated"))
                    legend(.none, String(localized: "Not from the strap. SpO₂ can be filled by importing a WHOOP or Health export."))
                }
            }
        }
        .broopAccountChrome(String(localized: "What Your Strap Reads"))
    }

    private func cell(_ m: Mark) -> some View {
        let (symbol, tint): (String, Color) = {
            switch m {
            case .full: return ("checkmark", BroopAccountStyle.connected)
            case .partial: return ("minus", BroopPalette.warning)
            case .none: return ("xmark", BroopPalette.textTertiary)
            }
        }()
        return Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 60)
            .accessibilityHidden(true)
    }

    private func spoken(_ m: Mark) -> String {
        switch m {
        case .full: return String(localized: "yes")
        case .partial: return String(localized: "partly")
        case .none: return String(localized: "no")
        }
    }

    private func legend(_ m: Mark, _ text: String) -> some View {
        HStack(spacing: 6) {
            cell(m).frame(width: 30)
            Text(verbatim: text).font(BroopType.regular(13.5)).foregroundStyle(BroopAccountStyle.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Power saving

struct BroopAccountPowerSavingView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var powerSavingPct = 20
    @AppStorage(PuffinExperiment.pauseHrvDisabledKey) private var pauseHrvDisabled = false
    @AppStorage(PuffinExperiment.lowRefreshKey) private var lowRefreshEnabled = false

    var body: some View {
        BroopAccountPage(spacing: 26) {
            BroopAccountHeading(title: String(localized: "Power Saving"),
                                detail: String(localized: "The strap keeps banking data on its own, so nothing is lost — NOOP just talks to it less often to help it last until you can charge it."))
            BroopAccountGroup {
                BroopAccountToggle(title: String(localized: "Power saving mode"),
                                   detail: String(localized: "Slows background strap-sync (every 45 min instead of 15) while your strap's battery is low. No data loss — the strap banks everything, so sync just batches into larger, less frequent pulls."),
                                   isOn: $powerSavingEnabled)
                if powerSavingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Kick in at (strap battery)").font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                            Spacer()
                            Text(verbatim: "\(powerSavingPct)%").font(BroopType.number(17)).foregroundStyle(BroopPalette.teal)
                        }
                        Slider(value: Binding(get: { Double(powerSavingPct) }, set: { powerSavingPct = Int($0) }),
                               in: 10...35, step: 5,
                               onEditingChanged: { editing in if !editing { model.applyPowerSaving() } })
                            .tint(BroopPalette.teal)
                    }
                    .padding(16)
                    BroopAccountToggle(title: String(localized: "Pause HRV capture"),
                                       detail: String(localized: "While your strap's battery is low, stop the always-on background HRV stream — the biggest continuous drain on the strap. A Live screen still shows heart rate, and it re-arms automatically once the strap is charged."),
                                       isOn: Binding(get: { !pauseHrvDisabled }, set: { pauseHrvDisabled = !$0 }))
                    BroopAccountToggle(title: String(localized: "Low refresh"),
                                       detail: String(localized: "Sync in the background every hour instead of every 15 minutes, whatever the strap's charge — fewer reconnections is the biggest saving on a WHOOP 4.0. Nothing is lost: the strap banks everything and hands it over in larger batches. Pull to sync still runs straight away, and live heart rate is untouched."),
                                       isOn: $lowRefreshEnabled)
                }
            }
        }
        .broopAccountChrome(String(localized: "Power Saving"))
        .onChange(of: powerSavingEnabled) { _, _ in model.applyPowerSaving() }
        .onChange(of: pauseHrvDisabled) { _, _ in model.applyPowerSaving() }
        .onChange(of: lowRefreshEnabled) { _, _ in model.applyPowerSaving() }
    }
}
#endif
