import Foundation
import UserNotifications

/// The evening-review reminder: a local notification an hour before tonight's wind-down reminder
/// (`EveningReviewTiming`) inviting the person to look back at today and log their journal by voice. The text
/// is fixed; the review itself is written when the app opens, since the model does not run in the
/// background. One one-off request per coming evening, re-armed whenever Home appears, so a changed alarm or
/// sleep plan moves it. Default off, like every NOOP automation. On-device only; nothing is sent anywhere.
@MainActor
enum EveningReviewReminder {
    static let categoryId = "coach-evening"
    private static let requestIdPrefix = "coach-evening-"
    private static let enabledKey = "coachEvening.reminderEnabled"
    /// Evenings armed ahead, so the reminder still comes on days the app isn't opened.
    static let eveningsAhead = 7

    static var isEnabled: Bool {
        CoachBriefScheduler.coachMasterEnabled && UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var storedEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Turn the reminder on or off. Turning it on asks for notification permission once and reports a
    /// refusal so the toggle can turn itself back off. `windDownFires` are the coming wind-down reminders.
    static func setEnabled(_ on: Bool, windDownFires: [Date], skipTonight: Bool,
                           completion: @escaping @MainActor (Bool) -> Void) {
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            cancel()
            completion(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                UserDefaults.standard.set(granted, forKey: enabledKey)
                if granted { schedule(windDownFires: windDownFires, skipTonight: skipTonight) }
                completion(granted)
            }
        }
    }

    /// Replace the armed reminders with ones from these wind-down fires. No-op (after clearing) when off.
    static func schedule(windDownFires: [Date], skipTonight: Bool, now: Date = Date()) {
        let centre = UNUserNotificationCenter.current()
        centre.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            centre.removePendingNotificationRequests(withIdentifiers: old)
            Task { @MainActor in
                guard isEnabled else { return }
                let calendar = Calendar.current
                for date in EveningReviewTiming.reminderDates(windDownFires: windDownFires, now: now, skipTonight: skipTonight) {
                    let content = UNMutableNotificationContent()
                    content.title = String(localized: "How was your day?")
                    content.body = String(localized: "See today's evening review and log your journal by voice.")
                    content.sound = .default
                    content.categoryIdentifier = categoryId
                    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    let id = requestIdPrefix + Repository.localDayKey(date)
                    centre.add(UNNotificationRequest(identifier: id, content: content,
                                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
    }

    /// Remove every armed reminder (the toggle or the Coach master switch going off).
    static func cancel() {
        let centre = UNUserNotificationCenter.current()
        centre.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            if !ids.isEmpty { centre.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }
}
