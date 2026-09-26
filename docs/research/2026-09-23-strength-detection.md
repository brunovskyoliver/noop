# Detecting weight training: what the real data shows

Research date: 2026-09-23. Builds on `2026-09-21-workout-auto-detection.md` and `2026-09-21-workout-notification-plan.md`, both of which predate commit `db53a8f9`, which wired the classifier and the activity tier into production.

Data: the iPhone production store (WHOOP 5.0/MG, streams 2026-08-08 → 2026-09-23), copied read-only with `devicectl`. Profile: age 19 (Tanaka HRmax ≈ 195), resting HR 42–49. The labels come from 3 Apple Watch "Strength Training" sessions that overlap the strap streams (09-16, 09-20, 09-21), 1 manual walk (09-22), and 83 older imported WHOOP rows (06-24 → 08-07) that have no overlapping streams. The real `WorkoutDetector.detect` + `WorkoutTypeClassifier` were run over 45 days of phone data with a scratch SwiftPM harness.

## Findings

1. **The motion gate is not what misses lifts.** The expected failure was that a gripped bar barely rotates the wrist, so the gravity-delta gate (`motionThreshold = 0.20`) would not fire. On real lifts, however, the 10 s-smoothed gravity delta clears 0.20 on 58–70% of seconds, against 34–53% for walks. `dynAccel` (`dynamic_acceleration@41`, stored on 99.99% of `gravitySample` rows and read by nothing in analytics) tracks the gravity delta closely: lifts 0.24–0.25 median, walks 0.12–0.20. Swapping the gate to `dynAccel` would buy nothing for detection on this data, so it was not done.
2. **Lifts were being lost to dilution, not to intensity.** Runs form at the span floor (rest + 15 ≈ 63 bpm), which nearly any waking movement clears, and are then qualified against the activity floor (rest + 40% HRR ≈ 106 bpm), which is much higher. On 09-21 the 40 min lift bridged into a 142 min afternoon run that sat only 41% above the activity floor, under the 50% bar, so the whole run, lift included, was dropped as `lowIntensity`. The same merging is why the 09-16 and 09-20 bouts swallow the walk to and from the gym.
3. **The persisted lift rows were missing for a different reason.** The persist loop drops any detected bout that overlaps an existing row (`IntelligenceEngine` #510 overlap rule), and all three lifts overlap their Apple Health rows. `dailyMetric.exerciseCount` shows that 09-16 and 09-20 were detected.
4. **Classification of lifts: not solved, and the data to solve it doesn't exist yet.** Every detected lift was classified **walk** (strength scored 0.30–0.46). Contributing causes:
   - the bouts include the walks to and from the gym (gait streaks of 380–500 s);
   - `motionVariance` on lifts reads 0.08–0.13, not the 0.25–0.36 the `strengthScore` comment cites, so the `variableMotion` plateau (0.12→0.22) barely fires;
   - the strap's own `activityClass` marks about 45% of lifting seconds as walk, the same fraction as a real walk, so gait-tick composition does not separate the two.

   With 3 labelled lifts and 1 labelled walk, any retuning would be overfitting. Per the repo's derived-signal rule, this needs more labels first.
5. **WHOOP does not auto-detect these lifts either.** All 13 imported WHOOP "Weightlifting" rows have seconds-precision starts (manually started), while all 70 auto rows (Walking 39, Activity 10, Cycling 8, Swimming 8, Other 3, Soccer, Volleyball) start on a whole minute. WHOOP's auto rows come to about 1.6 a day, with walks as short as 12 min and avg HR as low as 91.

## Change made: elevated-core split (Swift only)

`WorkoutDetector.detect` now tries once more before dropping a run that fails both the zone-2 bar and the activity tier. It splits the run into **elevated cores**: maximal stretches where HR is above the activity floor, with consecutive above-floor samples at most `bridgeGapS` (300 s) apart, so rests between sets stay inside a core. Each core then goes through the same qualification. Cores are never back-dated over the warm-up (the motion before a core is the pottering it was cut from) and are never split again. The funnel gains `splitRuns` / `splitKept`, and the `workout detect` line appends `split=N splitKept=M`. The accounting invariant becomes `bridged == short + noHR + lowIntensity + split + (kept − splitKept)`.

The Android twin was deliberately not changed; this build targets iPhone only.

Harness result over the same 45 days:

| | Before | After |
| --- | --- | --- |
| Detected bouts | 30 (0.7/day) | 89 (2.0/day) |
| Labelled lifts found | 2 of 3 | 3 of 3 |
| Lifts classified as strength | 0 | 0 |

Most of the new bouts are 10–30 min walks at 104–120 bpm, which is WHOOP's auto-"Activity"/Walking territory. The daily rate moves toward WHOOP's ~1.6/day. Watch notification volume in the field: `activityMinMin` (10) and `activityHRRFraction` (0.40) are the knobs.

## Next steps (not done)

1. **Collect labels.** Log each lift in NOOP (or keep the Apple Watch workout) for ~10 sessions, plus walks and runs, then rerun the harness and build a confusion matrix from the stored per-class `scores`.
2. **Split bout edges on gait streaks.** Trimming a contiguous gait streak of 5 min or more off the start or end of a bout would separate the commute from the lift, and it is the most likely single fix for the walk label. Validate on the labels from step 1.
3. **Retune `strengthScore`** only after step 1: its `motionVariance` plateau does not match real lifts, and candidate features are HR set-peak count and `dynAccel` during still-class ticks (lifts 0.24–0.30 vs walk 0.11, though two unlabelled bouts also read ≥ 0.23).
4. A 100 Hz IMU capture (`ImuFeatureExtractor`) remains the only path to rep-level signal. It fits a manual "start lifting" action, not auto-detection.

## Update 2026-09-26: gait tags in the motion gate, and cutting the walk off the lift

The user logged a lift from about 15:25 for an hour and a one-hour walk from about 17:00 on 09-26, with no watch. The detector saved a 14:34–16:14 "walk" (pottering, the walk to the gym and the lift in one bout) and caught the 17:00 walk only as 17:04–17:20 and 17:43–17:54.

1. **The walk was lost at the motion gate.** From 17:15 to 18:02 the strap tagged 58–60 of every 60 seconds as walk, but the 10 s gravity delta cleared 0.20 on 0–13 of them: a quiet arm on a steady walk. `detect` now takes the step stream and lets any second tagged walk or run (class 1 or 2) through the motion gate. `AnalyticsEngine` passes the day's steps.
2. **Next steps item 2 is done: bouts are cut at walking streaks.** A walking minute has at least 45 gait-tagged seconds. A streak is at least 5 such minutes, with a single missing minute bridged. Streaks less than 10 min apart are joined. A streak only counts when under half its HR is in zone 2+, because the strap tags sprinting in a field sport as walk (08-22: 177–184 bpm, class 2 never set) and such a streak belongs to the session. A qualified bout is cut at its streaks' edges when at least 10 min of something else sits beside one. Each piece is then qualified on its own, and a non-walking piece needs only 25% of its HR over the activity floor: its parent already qualified, lifts read about 40% (09-20: 42%), and pottering reads near 0%.

The harness was rerun over 42 days (08-16 → 09-26), with Tanaka HRmax and the stored daily resting HR:

| Label | Before | After |
| --- | --- | --- |
| Lift 09-16 18:59–19:52 | walk 18:27–19:22, walk 19:29–20:54 | other 18:58–19:22, **strength** 19:29–19:50, walk 19:50–20:04 |
| Lift 09-20 19:48–20:44 | walk 19:57–20:58 | walk 19:57–20:43, walk 20:43–20:57 |
| Lift 09-21 17:08–17:48 | walk 17:11–18:13 | other 17:11–17:48, walk 17:48–17:59 |
| Lift 09-24 19:01–20:08 | strength 19:16–19:39, strength 19:47–20:10 | same, with a walk 20:06–20:18 cut off the end |
| Lift 09-26 ~15:25–16:25 | walk 14:34–16:14, walk 16:21–16:57 | **strength** 15:20–16:14 |
| Walk 09-26 ~17:00–18:00 | walk 17:04–17:20, walk 17:43–17:54 | walk 17:11–18:01 |
| Walks 09-22, 09-25 (manual) | all found | all found; 09-22 loses its last 15 min to an "other" piece, and two 09-25 walks 6 min apart become one |

Lifts classified as strength went from 1 of 5 to 3 of 5, and each lift is now separated from its walk. Volume rose from 86 bouts (2.0 a day) to 125 (3.0 a day), with total minutes down from 3,895 to 3,638. The extra bouts are long days on foot that now come back as several pieces (08-31: one 327 min walk became six pieces). The detected-workout notification posts at most one bout per analysis pass, so this raises notification volume on such days without firing one per piece. The Android twin was left unchanged, as before.
