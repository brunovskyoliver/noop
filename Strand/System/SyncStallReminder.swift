import Foundation
#if os(iOS)
import Combine
import UserNotifications
#endif

/// A stale-sync reminder cannot attribute the silence to a force-quit, radio loss, or suspension.
enum SyncStallPolicy {
    static let enabledKey = "ios.syncStallReminder.enabled"
    static let monitoringSinceKey = "ios.syncStallReminder.monitoringSince"

    static func deadline(enabled: Bool, expectsSync: Bool, lastSyncAt: TimeInterval?,
                         monitoringSince: Date, now: Date, syncInterval: TimeInterval) -> Date? {
        guard enabled, expectsSync else { return nil }
        let last = lastSyncAt.flatMap { value -> Date? in
            guard value.isFinite, value > 0, value <= now.timeIntervalSince1970 else { return nil }
            return Date(timeIntervalSince1970: value)
        } ?? min(monitoringSince, now)
        let interval = syncInterval.isFinite && syncInterval > 0 ? syncInterval : 300
        // Hourly power saving must not generate a warning between healthy hourly syncs.
        let stale = last.addingTimeInterval(max(30 * 60, 2 * interval))
        // Give a reopened app a minute to finish reconnecting before an overdue reminder fires.
        return max(stale, now.addingTimeInterval(60))
    }
}

#if os(iOS)
/// Queued with iOS while the process is alive, so the reminder can fire after it stops.
/// Successful offloads replace the deadline; heart-rate packets and app opens do not reset it.
@MainActor
final class SyncStallReminder {
    static let shared = SyncStallReminder()
    private static let identifier = "strap-sync-stalled"

    private weak var live: LiveState?
    private var expectsSync: (() -> Bool)?
    private var syncInterval: (() -> TimeInterval)?
    private var subscriptions = Set<AnyCancellable>()
    private var revision = 0
    private var reconciliation: Task<Void, Never>?
    private var scheduledDeadline: Date?
    private var authorizationUnavailableLogged = false

    func attach(to live: LiveState, expectsSync: @escaping () -> Bool,
                syncInterval: @escaping () -> TimeInterval) {
        self.live = live
        self.expectsSync = expectsSync
        self.syncInterval = syncInterval
        subscriptions.removeAll()
        live.$lastSyncedAt.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        live.$connected.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        refresh()
    }

    func requestAuthorizationIfNeeded() {
        guard expectsSync?() == true else { return }
        guard UserDefaults.standard.object(forKey: SyncStallPolicy.enabledKey) as? Bool ?? true else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            refresh()
        }
    }

    func refresh() {
        revision += 1
        guard reconciliation == nil else { return }
        // Serialize add/remove operations so an older async authorization read or add cannot
        // reinstall a reminder after the user disables it or after a newer sync completes.
        reconciliation = Task { [weak self] in
            guard let self else { return }
            var processed: Int
            repeat {
                processed = self.revision
                await self.reconcile(revision: processed)
            } while processed != self.revision
            self.reconciliation = nil
        }
    }

    private func reconcile(revision: Int) async {
        guard let live else { return }
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        let expected = expectsSync?() == true
        let enabled = defaults.object(forKey: SyncStallPolicy.enabledKey) as? Bool ?? true
        let now = Date()
        let started = defaults.object(forKey: SyncStallPolicy.monitoringSinceKey) as? Double
        if expected, started == nil { defaults.set(now.timeIntervalSince1970, forKey: SyncStallPolicy.monitoringSinceKey) }
        guard let deadline = SyncStallPolicy.deadline(
            enabled: enabled, expectsSync: expected, lastSyncAt: live.lastSyncedAt,
            monitoringSince: started.map(Date.init(timeIntervalSince1970:)) ?? now,
            now: now, syncInterval: syncInterval?() ?? 300) else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
            scheduledDeadline = nil
            defaults.removeObject(forKey: SyncStallPolicy.monitoringSinceKey)
            return
        }
        guard deadline != scheduledDeadline else { return }
        let settings = await center.notificationSettings()
        guard self.revision == revision else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            if !authorizationUnavailableLogged {
                live.append(log: AppModel.stamped("Sync reminder: notifications are not authorized"))
                authorizationUnavailableLogged = true
            }
            return
        }
        authorizationUnavailableLogged = false
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Strap sync needs attention")
        content.body = String(localized: "Broop hasn't synced your strap recently. Open Broop to reconnect and catch up. Leave it in the app switcher for background sync.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
            scheduledDeadline = deadline
            if let last = live.lastSyncedAt, now.timeIntervalSince1970 - last < 60 {
                center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
            }
        } catch {
            live.append(log: AppModel.stamped("Sync reminder: scheduling failed: \(error.localizedDescription)"))
        }
    }
}
#endif
