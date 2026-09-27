# Hourly stand reminder: how other apps do it, and what NOOP learns

Research date: 2026-09-26. Data: the iPhone production store (WHOOP 5.0/MG, 1 Hz gravity and step/activity-class samples, 2026-08-08 → 2026-09-26), copied read-only with `devicectl`. Calibration used the last 21 days; the replay used the last 35.

## What other apps do

| App | Goal | When it nudges | Who sets the hours |
| --- | --- | --- | --- |
| Apple Watch ([MacRumors](https://www.macrumors.com/how-to/turn-off-time-to-stand-reminders-apple-watch/), [Apple Community](https://discussions.apple.com/thread/250923213)) | Stand and move for 1 min in the hour; 12 such hours close the ring | :50 if the hour has no stand yet, leaving 10 min | Fixed; reminders can only be turned off |
| Fitbit ([help article](https://support.google.com/fitbit/answer/14225534?hl=en)) | 250 steps per hour | :50 if under 250 steps | User picks start/end time and days; off while asleep |
| Garmin Move Bar ([manual](https://www8.garmin.com/manuals/webhelp/vivoactive3/EN-US/GUID-55E4ED28-E438-4F65-A526-690F8FD5FF31.html)) | Reset by walking a couple of minutes | After 1 h idle, then every 15 min | Not configurable beyond on/off |

None of them learns the user's day. They all use a fixed window, or one the user types in.

The research on prompts matters more than any product. In the HeartSteps micro-randomized trial ([Klasnja et al. 2019](https://academic.oup.com/abm/article/53/6/573/5091257)), activity suggestions raised the next 30 minutes' step count at first, but the effect "largely disappeared after 1 month". Participants said the prompts had become boring after 2–4 weeks. So a reminder that goes on firing in an hour the user can't or won't break (a lecture, a commute, a meeting) doesn't just miss that hour. It teaches the user to ignore every other reminder as well.

## Design

The pure engine is `StandReminder` (`Packages/StrandAnalytics`). The app side is `StandReminderNotifier` plus `BLEManager.maybeRemindStand`, which runs on every history offload (about every 15 min), on the same hook as the inactivity reminder.

1. **Up minutes.** A wrist strap can't see posture, so a "stand" minute is an upright minute with movement in it. That means ≥ 10 walk/run activity-class ticks in the minute (5/MG only), or a mean per-sample gravity delta ≥ 0.20 g (any strap).
2. **The hourly rule is the same as Fitbit's and Apple's.** If the hour has fewer than the goal (default **5 min**) at the reminder minute (default **:50**), NOOP sends one notification, and a strap buzz if the strap is worn and connected. Because motion only arrives with each sync, the notification is handed to iOS in advance for :50. Any later sync that shows the goal met withdraws it. This way it fires on time even while the app is suspended.
3. **Learned day.** Each finished hour is saved with its covered, up, and still minute counts; 35 days are kept. An hour counts as *awake and worn* when it has ≥ 45 covered minutes and fewer than half of them are dead still. The reminder window is the longest run of hours awake on ≥ 80% of days, learned separately for weekdays and weekends. Each day type's hourly share is shrunk toward the other day type's with 2 pseudo-days, so a thin weekend history can't cut the window. Hours with too few observations bridge the run rather than breaking it. The last hour of the run is dropped and left for winding down. Until 5 days have been seen, the window is 09:00–18:00. When the feature is first turned on, it learns from the last 28 days of stored motion, so the learned window is available right away.
4. **Learned muting.** Each reminder is marked answered if ≥ 2 up minutes follow within 15 min. When a weekday or weekend hour's last three reminders were all ignored, that hour is muted for 7 days. After that it gets one probe reminder: answering it unmutes the hour, and ignoring it mutes the hour for another week.
5. **Guards.** No reminder when the strap is not worn, when the newest motion is over 20 min old, when the last 30 min are ≥ 90% dead still (asleep, or strap on a table), when the user is walking right now, when the daily cap (default 8) is reached, or when the user tapped **Pause for today**.

Everything is user-adjustable in Automations → Stand reminder: goal, reminder minute, learned vs manual hours, daily cap, muting (with "Unmute all"), and the strap buzz. The notification goes through the same wrist-alert path as the smart-alarm mirror (`AppModel.postWristAlert`), so it needs the **Wrist alerts** master switch on.

## Calibration on real data

Per-minute mean gravity delta (g):

| Minutes | n | p10 | p50 | p90 |
| --- | --- | --- | --- | --- |
| Sleep (inside a sleep session) | 9,043 | 0.001 | 0.001 | 0.021 |
| Awake, no gait ticks | 15,957 | 0.014 | 0.059 | 0.171 |
| ≥ 10 gait ticks | 4,161 | 0.094 | 0.281 | 0.469 |

The awake/still proxy against recorded sleep sessions, on hours with ≥ 45 covered minutes: 328 awake hours called awake, 3 called asleep; 145 sleep hours called asleep, 5 called awake (98% agreement).

Learned windows on this user's data: weekdays 07:00–21:00, weekends 08:00–21:00. So reminders run from 07:50 to 20:50.

## Replay

The engine was replayed every 15 min over the last 21 days, after warming its history on the 14 days before. The replay can't include any reaction to the reminders themselves, so "answered" here only means the user happened to move anyway.

- 1–8 reminders a day, about 4.4 on a typical weekday; the cap of 8 was reached twice.
- 95 reminders, 43 of them followed by movement.
- Five weekday hours (08, 14, 15, 18, 20) ended up muted.
- Most decisions: outside window (1008), goal met (466), reminder standing (192).

## Limits

- Posture is not observable. Standing still at a counter without moving the wrist doesn't count, and wrist-heavy seated activity above 0.20 g does.
- Notification timing is exact, but the data is up to one sync old. Walking done after the last sync and before :50 can still get a reminder.
- Android parity was left out on purpose (this build targets iPhone only).
