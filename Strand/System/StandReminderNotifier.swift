import Foundation
import StrandAnalytics
import WhoopProtocol
import UserNotifications

/// The hourly stand reminder (2026-09-26): settings, persisted learning state, and the OS side of the
/// pure `StandReminder` engine.
///
/// Rides the same offload hook as the inactivity reminder (`BLEManager.maybeRemindStand`, on each
/// HISTORY_COMPLETE, ~15 min). Because the strap's motion only lands every sync, the reminder for an
/// hour is handed to the notification center ahead of time for :50 and withdrawn by any later sync
/// that shows the goal met, so it fires on time even while the app is suspended. Posting goes through
/// the wrist-alert path the smart-alarm mirror uses (`AppModel.postWristAlert`), gated on the same
/// master switch. On-device only.
@MainActor
enum StandReminderNotifier {

    nonisolated static let requestId = "stand-reminder"
    nonisolated static let categoryId = "stand.reminder"
    nonisolated static let actionPauseId = "stand.reminder.pause"

    // MARK: - Settings (UserDefaults; the Automations card binds the same keys)

    enum K {
        static let enabled = "stand.enabled"
        static let goalMinutes = "stand.goalMinutes"
        static let remindAtMinute = "stand.remindAtMinute"
        static let learnWindow = "stand.learnWindow"
        static let manualStartHour = "stand.manualStartHour"
        static let manualEndHour = "stand.manualEndHour"
        static let maxPerDay = "stand.maxPerDay"
        static let learnMuting = "stand.learnMuting"
        static let buzz = "stand.buzz"
        static let lastBackfillDay = "stand.lastBackfillDay"
    }

    static func loadConfig(_ d: UserDefaults = .standard) -> StandReminder.Config {
        let def = StandReminder.Config()
        func int(_ k: String, _ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(d.object(forKey: k) as? Int ?? v, r.lowerBound), r.upperBound) }
        let startHour = int(K.manualStartHour, def.manualWindow.startHour, 0...23)
        // An end at or before the start is an empty window that would never remind; read it as one hour.
        let endHour = max(int(K.manualEndHour, def.manualWindow.endHour, 1...24), startHour + 1)
        return StandReminder.Config(
            enabled: d.bool(forKey: K.enabled),
            goalMinutes: int(K.goalMinutes, def.goalMinutes, 1...30),
            remindAtMinute: int(K.remindAtMinute, def.remindAtMinute, 30...55),
            learnWindow: d.object(forKey: K.learnWindow) as? Bool ?? def.learnWindow,
            manualWindow: StandReminder.Window(startHour: startHour, endHour: endHour),
            maxPerDay: int(K.maxPerDay, def.maxPerDay, 1...18),
            learnMuting: d.object(forKey: K.learnMuting) as? Bool ?? def.learnMuting)
    }

    static var buzzEnabled: Bool { UserDefaults.standard.object(forKey: K.buzz) as? Bool ?? true }

    // MARK: - Learning state (a JSON file: rewritten every sync, so kept out of UserDefaults)

    private static var stateURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("stand-reminder.json")
    }

    static func loadState() -> StandReminder.State {
        guard let url = stateURL, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(StandReminder.State.self, from: data) else { return StandReminder.State() }
        return s
    }

    static func saveState(_ s: StandReminder.State) {
        guard let url = stateURL, let data = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func tzOffsetSec(_ ts: Int) -> Int {
        TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: - Evaluation

    /// Run the engine on fresh minutes and apply its action to the notification center. Returns the
    /// decision so the caller can buzz the strap and log.
    static func evaluate(minutes: [StandReminder.Minute], worn: Bool, nowSec: Int) -> StandReminder.Decision {
        let config = loadConfig()
        let decision = StandReminder.evaluate(nowSec: nowSec, tzOffsetSec: tzOffsetSec(nowSec), minutes: minutes,
                                              worn: worn, config: config, state: loadState())
        saveState(decision.nextState)
        switch decision.action {
        case .keep: break
        case .clear: clearPending()
        case .schedule(let fireAt):
            AppModel.postStandReminder(goal: config.goalMinutes, at: Date(timeIntervalSince1970: TimeInterval(fireAt)))
        case .remindNow:
            AppModel.postStandReminder(goal: config.goalMinutes, at: nil)
        }
        return decision
    }

    static func clearPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
    }

    /// Turning the feature off withdraws anything already handed to the OS.
    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: K.enabled)
        if on {
            // Ask once; postWristAlert only delivers once authorized and never prompts itself.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        } else {
            clearPending()
            var s = loadState(); s.scheduledFireAt = 0; saveState(s)
        }
    }

    /// "Pause for today": no reminders until local midnight.
    static func pauseToday(now: Date = Date()) {
        var s = loadState()
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        s.pausedUntil = Int(midnight.timeIntervalSince1970)
        s.scheduledFireAt = 0
        saveState(s)
        clearPending()
    }

    /// Forget muted hours (the learned day is kept: it describes the user, not their reactions).
    static func resetMuting() {
        var s = loadState(); s.outcomes = []; saveState(s)
    }

    // MARK: - History backfill

    /// Days of history to learn the day from when the feature is first turned on.
    static let backfillDays = 28

    /// Fold any of the last `backfillDays` days missing from the history, at most once per local day, so
    /// the learned window works from the first day instead of after a week of syncs. `read` returns one
    /// day's gravity and steps; folding runs off the main actor.
    static func backfillIfDue(nowSec: Int,
                              read: @escaping (_ from: Int, _ to: Int) async -> ([GravitySample], [StepSample])) async -> Int {
        let tz = tzOffsetSec(nowSec)
        let today = StandReminder.localDay(nowSec, tzOffsetSec: tz)
        guard UserDefaults.standard.integer(forKey: K.lastBackfillDay) != today else { return 0 }
        UserDefaults.standard.set(today, forKey: K.lastBackfillDay)
        let have = Set(loadState().history.map(\.day))
        var fresh: [StandReminder.HourRecord] = []
        for day in (today - backfillDays)..<today where !have.contains(day) {
            let from = StandReminder.hourStart(day: day, hour: 0, tzOffsetSec: tz)
            let (g, s) = await read(from, from + 86_400 - 1)
            guard !g.isEmpty else { continue }
            fresh += await Task.detached(priority: .utility) {
                StandReminder.hourRecords(StandReminder.minutes(gravity: g, steps: s), tzOffsetSec: tz)
            }.value
        }
        guard !fresh.isEmpty else { return 0 }
        // Reload: a sync may have saved while the reads were in flight.
        var s = loadState()
        s.history = StandReminder.merged(fresh, with: s.history, today: today)
        saveState(s)
        return Set(fresh.map(\.day)).count
    }

    // MARK: - Notification category

    nonisolated static var category: UNNotificationCategory {
        let pause = UNNotificationAction(identifier: actionPauseId,
                                         title: String(localized: "Pause for today"), options: [])
        return UNNotificationCategory(identifier: categoryId, actions: [pause], intentIdentifiers: [])
    }
}
