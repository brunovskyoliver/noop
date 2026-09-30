import Foundation
import UserNotifications
import StrandAnalytics

/// The wind-down nudge (#207) — a gentle, NON-critical evening local notification suggesting it's
/// time to start winding down so the user can reach their usual wake time well-rested.
///
/// Cross-platform (macOS + iOS): a sideloaded backgrounded app can't fire a dependable LOUD wake
/// alarm (no critical-alert entitlement), but it CAN post a calm daily reminder. The nudge fires on a
/// repeating calendar trigger at a time DERIVED from the user's earliest wake time minus their usual
/// sleep need minus a short lead. State is its own UserDefaults-backed store so it doesn't couple to
/// the shared BehaviorStore. On-device only; nothing is sent anywhere.
@MainActor
enum WindDownNudge {

    private static let requestId = "wind-down-nudge"

    // MARK: - Persisted settings (own keys; default OFF, opt-in like every automation)

    private enum K {
        static let enabled = "windDown.enabled"
        static let sleepNeed = "windDown.sleepNeedMinutes"   // default 8h
        static let lead = "windDown.leadMinutes"             // default 30m
        static let wake = "windDown.wakeMinutes"             // earliest wake, minutes since midnight
        // PR#554 (MumiZed) — per-day wake overrides. A JSON map of {weekday(1=Sun…7=Sat): wakeMinutes}.
        // Empty / no entry for a day = that day uses the default `wakeMinutes`, so the feature is purely
        // additive (no override → exactly the old single-time behaviour).
        static let perDayWake = "windDown.perDayWakeMinutes"
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: K.enabled) }

    /// The bed-to-wake window's stored range. The upper bound IS the planner's own (`SleepPlanner.maxWindowMin`,
    /// 12 h plus rounding): the old 11 h clamp made a long plan and its reminder name different bedtimes. The
    /// planner is the only writer, so the lower bound only guards a corrupt stored value.
    static let minWindowMinutes = 0
    static let maxWindowMinutes = SleepPlanner.maxWindowMin

    static var sleepNeedMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.sleepNeed) as? Int ?? 8 * 60
        return min(max(v, minWindowMinutes), maxWindowMinutes)
    }

    static var leadMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.lead) as? Int ?? 30
        return min(max(v, 0), 120)
    }

    static var wakeMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.wake) as? Int ?? 7 * 60   // 07:00
        return min(max(v, 0), 24 * 60 - 1)
    }

    // MARK: - Per-day wake overrides (PR#554)

    /// The stored per-weekday wake overrides — {weekday(1=Sun…7=Sat): wakeMinutes}. Empty when the user
    /// hasn't set any (the common case), so every day falls back to the single `wakeMinutes`. Values are
    /// clamped to a valid minute-of-day on read so a corrupt blob can't schedule at a nonsense time.
    static var perDayWakeOverrides: [Int: Int] {
        guard let data = UserDefaults.standard.data(forKey: K.perDayWake),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        var out: [Int: Int] = [:]
        for (k, v) in raw {
            guard let day = Int(k), (1...7).contains(day) else { continue }
            out[day] = min(max(v, 0), 24 * 60 - 1)
        }
        return out
    }

    /// The wake time used for a given Calendar weekday (1=Sun…7=Sat) — the per-day override if set, else the
    /// default `wakeMinutes`. The single source of truth both the schedule and the UI read, so they agree.
    static func wakeMinutes(forWeekday weekday: Int) -> Int {
        perDayWakeOverrides[weekday] ?? wakeMinutes
    }

    /// Whether ANY per-day override is set — drives whether scheduling fans out to 7 per-weekday triggers
    /// (overrides present) or keeps the single daily trigger (none).
    static var hasPerDayOverrides: Bool { !perDayWakeOverrides.isEmpty }

    /// Set or clear a single weekday's wake override (pass nil to clear → that day reverts to the default),
    /// rescheduling if enabled. Clamps the minute-of-day so a bad value can't be stored.
    static func setWakeOverride(weekday: Int, minutes: Int?) {
        guard (1...7).contains(weekday) else { return }
        var map = perDayWakeOverrides
        if let m = minutes {
            map[weekday] = min(max(m, 0), 24 * 60 - 1)
        } else {
            map.removeValue(forKey: weekday)
        }
        let encodable = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: K.perDayWake)
        }
        if isEnabled { schedule() }
    }

    /// The nudge minute-of-day for a given weekday — that day's wake (override or default) minus sleep need
    /// minus lead, wrapped into [0, 1440). Pure; mirrors `nudgeMinuteOfDay()` per-day. (PR#554)
    static func nudgeMinuteOfDay(forWeekday weekday: Int) -> Int {
        let raw = wakeMinutes(forWeekday: weekday) - sleepNeedMinutes - leadMinutes
        let day = 24 * 60
        return ((raw % day) + day) % day
    }

    /// The day shift for a given weekday's nudge — 0 if the nudge lands on the same day as the wake,
    /// -1 if it wraps to the previous evening. The minute-of-day wrap in `nudgeMinuteOfDay` silently
    /// loses which day the nudge belongs to; this companion carries that information so the scheduler
    /// can pin the trigger to the nudge's day, not the wake's. (#1863)
    ///
    /// `raw` is always in [-842, 1439] given the clamped inputs (wake ≤ 1439, window ≤ 722, lead ≤ 120),
    /// so the shift is always 0 or -1 — but the formula is general floor-division for safety.
    static func nudgeDayShift(forWeekday weekday: Int) -> Int {
        let raw = wakeMinutes(forWeekday: weekday) - sleepNeedMinutes - leadMinutes
        let day = 24 * 60
        // Floor division (Swift's `/` truncates toward zero, so adjust for negatives).
        return raw < 0 ? -(((-raw - 1) / day) + 1) : raw / day
    }

    /// Shift a Calendar weekday (1=Sun…7=Sat) by a day count, wrapping through the week end. (#1863)
    /// `shiftedWeekday(weekday: 1, by: -1)` → 7 (Sunday's evening-before nudge fires on Saturday).
    static func shiftedWeekday(weekday: Int, by shift: Int) -> Int {
        let zeroBased = weekday - 1 + shift
        return ((zeroBased % 7) + 7) % 7 + 1
    }

    // MARK: - Tonight: one wake for the plan and the reminder

    /// Tonight's reminder, resolved from the SAME wake tonight's sleep plan uses (`AppModel.tonightWakeMinute`).
    ///
    /// The weekday schedule alone fired from the weekday's usual wake time, while the plan works back from
    /// the armed strap alarm (one-off overrides included) whenever it will ring. On a night the two differ
    /// the reminder and the planner named different bedtimes. This value is what the scheduler fires
    /// tonight and what the Alarms screen prints, so they cannot disagree.
    struct Tonight: Equatable, Sendable {
        /// When tonight's reminder fires. May already be in the past (the reminder has gone off).
        let fireDate: Date
        /// The wake it precedes: the strap alarm when `fromAlarm`, else the weekday's usual wake time.
        let wakeDate: Date
        /// Calendar weekday (1 = Sun … 7 = Sat) of that wake: the key of its repeating weekday trigger.
        let wakeWeekday: Int
        /// True when the armed strap alarm sets the wake.
        let fromAlarm: Bool
        /// Minutes from the reminder to the wake (window + lead), in wall-clock minutes. The copy that
        /// explains the reminder prints this number, so the text and the trigger share one value.
        let offsetMin: Int
    }

    /// The wake tonight's plan and reminder share: the strap alarm when it will ring within 24 h
    /// (`alarmFire` is nil when it is off or will not arm), else the first weekday wake after `now`.
    nonisolated static func tonightWake(now: Date, calendar: Calendar, alarmFire: Date?,
                                        wakeMinuteForWeekday: (Int) -> Int) -> (date: Date, fromAlarm: Bool) {
        if let fire = alarmFire, fire > now, fire.timeIntervalSince(now) < 24 * 3600 {
            return (fire, true)
        }
        let start = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let minute = wakeMinuteForWeekday(calendar.component(.weekday, from: day))
            if let fire = wallClock(minute, on: day, calendar: calendar), fire > now { return (fire, false) }
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let minute = wakeMinuteForWeekday(calendar.component(.weekday, from: tomorrow))
        return (wallClock(minute, on: tomorrow, calendar: calendar) ?? tomorrow, false)
    }

    /// Tonight's reminder: `windowMin` (the plan's bed-to-wake window) plus `leadMin` before the shared
    /// wake, counted on the WALL CLOCK. The planner's bedtime is a wall-clock minute, so on a DST night the
    /// reminder still lands `leadMin` before the bedtime the planner prints, not an hour off it.
    nonisolated static func tonight(now: Date, calendar: Calendar, alarmFire: Date?, windowMin: Int, leadMin: Int,
                                    wakeMinuteForWeekday: (Int) -> Int) -> Tonight {
        let wake = tonightWake(now: now, calendar: calendar, alarmFire: alarmFire,
                               wakeMinuteForWeekday: wakeMinuteForWeekday)
        let offset = windowMin + leadMin
        return Tonight(fireDate: nudgeDate(beforeWake: wake.date, offsetMin: offset, calendar: calendar),
                       wakeDate: wake.date,
                       wakeWeekday: calendar.component(.weekday, from: wake.date),
                       fromAlarm: wake.fromAlarm, offsetMin: offset)
    }

    /// What to hand the notification centre. `repeatingWakeWeekdays` get their usual weekday trigger;
    /// `oneOffs` are single-fire dates. On a night the alarm moves the wake, that wake weekday's repeating
    /// trigger is replaced by tonight's one-off plus a one-off at its usual time a week later, so the
    /// weekly pattern survives even if the app is not opened again before then (the next reschedule
    /// restores the repeating trigger).
    struct SchedulePlan: Equatable, Sendable {
        var repeatingWakeWeekdays: [Int]
        var oneOffs: [Date]
    }

    nonisolated static func schedulePlan(now: Date, calendar: Calendar, tonight: Tonight,
                                         wakeMinuteForWeekday: (Int) -> Int) -> SchedulePlan {
        let all = Array(1...7)
        guard tonight.fromAlarm else { return SchedulePlan(repeatingWakeWeekdays: all, oneOffs: []) }
        // The weekday schedule's own reminder for that wake day, at the weekday's usual wake time.
        let wakeDay = calendar.startOfDay(for: tonight.wakeDate)
        guard let usualWake = wallClock(wakeMinuteForWeekday(tonight.wakeWeekday), on: wakeDay, calendar: calendar)
        else { return SchedulePlan(repeatingWakeWeekdays: all, oneOffs: []) }
        let usual = nudgeDate(beforeWake: usualWake, offsetMin: tonight.offsetMin, calendar: calendar)
        guard usual != tonight.fireDate else { return SchedulePlan(repeatingWakeWeekdays: all, oneOffs: []) }
        var oneOffs: [Date] = []
        if tonight.fireDate > now { oneOffs.append(tonight.fireDate) }
        if let nextWeekWake = calendar.date(byAdding: .day, value: 7, to: wakeDay),
           let nextWake = wallClock(wakeMinuteForWeekday(tonight.wakeWeekday), on: nextWeekWake, calendar: calendar) {
            oneOffs.append(nudgeDate(beforeWake: nextWake, offsetMin: tonight.offsetMin, calendar: calendar))
        }
        return SchedulePlan(repeatingWakeWeekdays: all.filter { $0 != tonight.wakeWeekday }, oneOffs: oneOffs)
    }

    /// `minute` after local midnight on `day`, as a date (DST-safe: a skipped wall time moves forward).
    nonisolated static func wallClock(_ minute: Int, on day: Date, calendar: Calendar) -> Date? {
        let m = ((minute % 1440) + 1440) % 1440
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: calendar.startOfDay(for: day))
    }

    /// `offsetMin` wall-clock minutes before `wake`: the wake's minute of day minus the offset, with the day
    /// shifted back when it wraps past midnight.
    nonisolated static func nudgeDate(beforeWake wake: Date, offsetMin: Int, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: wake)
        let raw = (c.hour ?? 0) * 60 + (c.minute ?? 0) - offsetMin
        let shift = raw < 0 ? -(((-raw - 1) / 1440) + 1) : raw / 1440
        let day = calendar.date(byAdding: .day, value: shift, to: calendar.startOfDay(for: wake)) ?? wake
        return wallClock(raw, on: day, calendar: calendar) ?? wake
    }

    // MARK: - Public API

    /// The result of enabling the nudge — lets the UI react instead of silently persisting an "on" toggle
    /// that can never fire. `.denied` means the OS won't deliver (permission off), so the caller should
    /// revert the switch and point the user at Settings.
    enum EnableOutcome { case scheduled, denied, off }

    /// Enable/disable and (re)schedule. Enabling gates on notification authorization FIRST — mirroring the
    /// smart-alarm backup path in `AppModel.scheduleSmartAlarmBackupNotification`: if undetermined it asks
    /// once and schedules on grant; if already denied it reports back rather than persisting a dead toggle.
    ///
    /// Why this matters: the old version called `requestAuthorization` with an empty completion and then
    /// scheduled unconditionally. `requestAuthorization` only shows the system dialog when the status is
    /// `.notDetermined`; once a user (or a prior sideload install with the same bundle id) has denied, the
    /// dialog never returns and the app silently scheduled reminders the OS would never deliver — with
    /// nothing in the UI to explain it. Now denial surfaces.
    ///
    /// `completion` always runs on the main actor (the settings/authorization callbacks fire off-main).
    static func setEnabled(_ on: Bool, completion: (@MainActor (EnableOutcome) -> Void)? = nil) {
        guard on else {
            UserDefaults.standard.set(false, forKey: K.enabled)
            // Clear the single trigger AND any per-day triggers (PR#554) so disabling leaves nothing behind.
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [requestId] + perDayRequestIds + oneOffRequestIds)
            completion?(.off)
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    UserDefaults.standard.set(true, forKey: K.enabled)
                    schedule()
                    completion?(.scheduled)
                case .notDetermined:
                    // First ask — the system dialog appears now (a predictable moment), then we schedule on
                    // grant so the FIRST night is covered rather than only after some later re-arm.
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in
                            if granted {
                                UserDefaults.standard.set(true, forKey: K.enabled)
                                schedule()
                                completion?(.scheduled)
                            } else {
                                UserDefaults.standard.set(false, forKey: K.enabled)
                                completion?(.denied)
                            }
                        }
                    }
                default:
                    // .denied (or any future non-authorized case) — don't fake an enabled toggle. The caller
                    // surfaces a "notifications are off" prompt with a jump to Settings.
                    UserDefaults.standard.set(false, forKey: K.enabled)
                    completion?(.denied)
                }
            }
        }
    }

    /// The armed strap alarm tonight's plan wakes to (nil when off, not arming, or over 24 h away), as last
    /// handed over by `AppModel.refreshTonightPlan`. The scheduler fires tonight's reminder from it.
    private static var tonightAlarmFire: Date?

    /// Follow tonight's sleep plan: store the planned bed-to-wake window as the "sleep need" the nudge
    /// subtracts from the wake time, so the reminder fires `leadMinutes` before the planned bedtime, and
    /// take the alarm the plan wakes to. Reschedules only when either changed.
    static func syncPlan(windowMinutes: Int, alarmFire: Date?) {
        let v = min(max(windowMinutes, minWindowMinutes), maxWindowMinutes)
        let changed = v != sleepNeedMinutes || alarmFire != tonightAlarmFire
        UserDefaults.standard.set(v, forKey: K.sleepNeed)
        tonightAlarmFire = alarmFire
        if changed, isEnabled { schedule() }
    }

    /// Tonight's reminder from the stored settings and the alarm last synced (see `Tonight`).
    static func tonight(now: Date = Date(), alarmFire: Date?) -> Tonight {
        tonight(now: now, calendar: .current, alarmFire: alarmFire, windowMin: sleepNeedMinutes,
                leadMin: leadMinutes, wakeMinuteForWeekday: { wakeMinutes(forWeekday: $0) })
    }

    /// Update the earliest wake time the nudge is derived from, rescheduling if enabled.
    static func setWakeMinutes(_ minutes: Int) {
        UserDefaults.standard.set(min(max(minutes, 0), 24 * 60 - 1), forKey: K.wake)
        if isEnabled { schedule() }
    }

    /// The minute-of-day the nudge fires: wake − sleepNeed − lead, wrapped into [0, 1440).
    static func nudgeMinuteOfDay() -> Int {
        let raw = wakeMinutes - sleepNeedMinutes - leadMinutes
        let day = 24 * 60
        return ((raw % day) + day) % day
    }

    // MARK: - Scheduling

    /// Per-weekday request ids — cleared alongside the single id so toggling overrides on/off never leaves
    /// a stale trigger behind. The one-off ids cover tonight's alarm-driven reminder and its week-later
    /// stand-in (see `schedulePlan`).
    private static var perDayRequestIds: [String] { (1...7).map { "\(requestId)-wd\($0)" } }
    private static let oneOffRequestIds = ["\(requestId)-once0", "\(requestId)-once1"]

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        // Clear the single trigger, every per-day trigger and the one-offs, so switching modes (or editing
        // an override, or the alarm moving) never double-fires or leaves an orphaned reminder.
        center.removePendingNotificationRequests(withIdentifiers: [requestId] + perDayRequestIds + oneOffRequestIds)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to wind down")
        content.body = String(localized: "A calm hour now helps you hit your wake time well-rested.")
        content.sound = .default

        let now = Date()
        let cal = Calendar.current
        let plan = schedulePlan(now: now, calendar: cal, tonight: tonight(now: now, alarmFire: tonightAlarmFire),
                                wakeMinuteForWeekday: { wakeMinutes(forWeekday: $0) })

        // Seven weekday-pinned triggers, each at that wake day's own nudge time (PR#554). Without overrides
        // they are all the same minute, which is the old single daily trigger split per day, so tonight's
        // weekday can be swapped for a one-off when the strap alarm moves the wake.
        for weekday in plan.repeatingWakeWeekdays {
            let minute = nudgeMinuteOfDay(forWeekday: weekday)
            // #1863 — an early wake (e.g. 03:30) wraps the nudge minute to the previous evening
            // (19:00). The minute wrap alone loses which DAY that evening belongs to, so the trigger
            // was pinned to the wake's own weekday — firing 8+ hours AFTER the wake it precedes.
            // Derive the day shift and pin the trigger to the nudge's day, not the wake's.
            let shift = nudgeDayShift(forWeekday: weekday)
            var comps = DateComponents()
            comps.weekday = shiftedWeekday(weekday: weekday, by: shift)   // the nudge's day
            comps.hour = minute / 60
            comps.minute = minute % 60
            // repeats: true survives relaunch (it lives in the notification center, not the process).
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            // The request id stays keyed to the wake's weekday so toggling/clearing overrides
            // always matches the ids `perDayRequestIds` enumerates.
            center.add(UNNotificationRequest(identifier: "\(requestId)-wd\(weekday)",
                                             content: content, trigger: trigger))
        }
        for (id, date) in zip(oneOffRequestIds, plan.oneOffs) {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
