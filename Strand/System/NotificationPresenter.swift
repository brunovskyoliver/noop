import Foundation
import UserNotifications

/// Foreground presentation delegate for the app's local notifications (wind-down nudge, smart-alarm
/// backup, battery/illness alerts).
///
/// Without a `UNUserNotificationCenterDelegate`, iOS/macOS suppress a notification's banner while the
/// app is in the FOREGROUND (the default). A user testing a reminder with the app open would see
/// nothing and conclude notifications are broken. Returning banner + sound + list here makes them
/// visible whether the app is open or not — matching what the user expects from a reminder.
///
/// Cross-platform (iOS + macOS). Register once at launch:
/// `UNUserNotificationCenter.current().delegate = NotificationPresenter.shared`.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    private override init() { super.init() }

    /// K5: wired by the app root (`StrandApp` on macOS, `StrandiOSApp` on iOS) at launch to route a
    /// tapped scheduled morning-brief notification to the Coach screen via `NavRouter.openCoach()`. nil
    /// is a safe no-op (the tap is simply not routed) rather than a crash if this ever fires before the
    /// root has wired it.
    var onCoachBriefTapped: (() -> Void)?

    /// 2026-09-21 detected-workout notification actions, wired at launch beside `onCoachBriefTapped`.
    /// `onWorkoutDetectedReview` routes to the Workouts screen focusing the bout's row (.detail on a
    /// plain tap, .edit on the Edit action); `onWorkoutDetectedDismiss` runs the durable
    /// "not a workout" dismissal without navigating. The span arrives as (startTs, endTs) userInfo —
    /// the handlers re-resolve the row by overlap, so a re-detected drift can't strand the action.
    var onWorkoutDetectedReview: ((_ startTs: Int, _ endTs: Int, _ edit: Bool) -> Void)?
    var onWorkoutDetectedDismiss: ((_ startTs: Int, _ endTs: Int) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tap on a delivered notification. The scheduled morning-brief category (K5) routes to
    /// Coach; the detected-workout category routes to Workouts (tap/Edit) or dismisses the bout
    /// ("Not a workout"). Every other notification (wind-down, smart-alarm, battery/illness) just
    /// opens the app to wherever it was, matching the pre-K5 behaviour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        if category == CoachBriefScheduler.notificationCategoryId {
            onCoachBriefTapped?()
        } else if category == StandReminderNotifier.categoryId {
            if response.actionIdentifier == StandReminderNotifier.actionPauseId {
                Task { @MainActor in StandReminderNotifier.pauseToday() }
            }
        } else if category == WorkoutDetectedNotifier.categoryId {
            let info = response.notification.request.content.userInfo
            let startTs = info[WorkoutDetectedNotifier.infoStartTs] as? Int
            let endTs = info[WorkoutDetectedNotifier.infoEndTs] as? Int
            switch response.actionIdentifier {
            case WorkoutDetectedNotifier.actionDismissId:
                if let startTs, let endTs { onWorkoutDetectedDismiss?(startTs, endTs) }
            case WorkoutDetectedNotifier.actionEditId:
                if let startTs, let endTs { onWorkoutDetectedReview?(startTs, endTs, true) }
            default:
                // A plain tap on the body: open the row's detail. Missing/foreign userInfo still
                // routes to the list (0,0 resolves to no row — the list is the fallback).
                onWorkoutDetectedReview?(startTs ?? 0, endTs ?? 0, false)
            }
        }
        completionHandler()
    }
}
