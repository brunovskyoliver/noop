import Foundation
import UserNotifications

/// The evening-review reminder: a local notification an hour before tonight's wind-down reminder
/// (`EveningReviewTiming`) inviting the person to look back at today and log their journal by voice. The text
/// is fixed until a sync shortly before it writes the review in the background (`writeAheadIfDue`), which
/// then becomes tonight's text. One one-off request per coming evening, re-armed whenever Home appears, so a
/// changed alarm or sleep plan moves it. Default off, like every NOOP automation. On-device only; nothing is
/// sent anywhere.
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

    /// How long before tonight's reminder a sync may write the review.
    static let writeAhead: TimeInterval = 45 * 60

    /// Called after every scoring pass: within `writeAhead` of tonight's reminder, write the review (`write`
    /// returns the stored one when it already exists) and put its headline and tonight's step in the
    /// reminder, at the same time. No-op when off, or when tonight's reminder is skipped or already shown.
    static func writeAheadIfDue(now: Date = Date(), write: () async -> AppleCoachBrief?) async {
        guard isEnabled else { return }
        let centre = UNUserNotificationCenter.current()
        let id = requestIdPrefix + Repository.localDayKey(now)
        guard let request = await centre.pendingNotificationRequests().first(where: { $0.identifier == id }),
              let fire = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
              fire.timeIntervalSince(now) <= writeAhead,
              let review = await write(), review.day == Repository.dayString(now) else { return }
        let body = [review.headline, review.tonight].compactMap { $0 }.joined(separator: "\n")
        guard !body.isEmpty, body != request.content.body,
              let content = request.content.mutableCopy() as? UNMutableNotificationContent else { return }
        content.body = body
        try? await centre.add(UNNotificationRequest(identifier: id, content: content, trigger: request.trigger))
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
