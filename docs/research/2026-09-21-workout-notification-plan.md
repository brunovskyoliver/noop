# Background workout detection + post-workout notification: implementation plan

Research date: 2026-09-21. Builds on `2026-09-21-workout-auto-detection.md`. Scope: investigation + implementation plan; no app behavior changed. Calibrated against the local production store at `~/Library/Application Support/OpenWhoop/whoop.sqlite` (WHOOP 5.0/MG, "my-whoop").

## What the real data shows (calibration evidence)

The local store holds ~8.3 days of contiguous 1 Hz streams (2026-08-08 → 2026-08-16), ~520K rows each of `hrSample` / `gravitySample` / `stepSample`, plus 83 imported WHOOP workouts (`source="whoop"`, 2026-06-24 → 2026-08-07 — labels end one day before the streams begin). `stepSample.activityClass` is populated (377K still / 141K walk / 1.2K run ticks).

A faithful Python replica of `WorkoutDetector.detect` was run over this data (constants byte-identical: `hrMarginBPM=15`, `motionThreshold=0.20`, `mergeGapS=150`, `bridgeGapS=300`, `minIntensityZ2Plus=0.50`, `minDurS−smooth=290s`):

| Detector configuration | Result on real data |
| --- | --- |
| Production `WorkoutDetector`, per-day observed HRmax (~105-132) | 13 candidate windows kept — but the real pipeline never uses per-day HRmax |
| Production `WorkoutDetector`, realistic HRmax=185 (Tanaka/overrides feed `effMaxHR`, AnalyticsEngine.swift:859) | **0 kept, every day.** Runs form (longest 2.7-6.5 h/day) but all die at the ≥50%-zone-2 gate (`droppedLowIntensity`). This is why `exerciseCount=0` and zero `sport="detected"` rows exist despite 20K-48K steps/day. |
| `AutoWorkoutDetector` as-shipped (floor = rest+30, HR-only ≥12 min) | **Massively over-fires.** This user's resting HR is 42-49 on active days → floor 72-79 bpm → the whole waking day merges into one "workout" (Aug 9: a single 809-min window; Aug 15: eleven windows). Notification spam, useless. |
| Same scan, motion confirmation wired on (mean L2 gravity-delta ≥ 0.05) | Drops only the quietest windows; still 30+/day. Motion confirm alone doesn't fix a floor below daytime ambulation HR. |
| **Floor = rest + 40% HRR** (hrmax 185; ≈ 103-131 bpm for this user), ≥10 min, dips ≤90 s, merge <5 min, motion-confirmed | **21 windows / 8 days**, avg 100-123 bpm — multi-hour hikes split correctly, day-long ambulation excluded. |
| Floor = rest + 50% HRR | 8 windows, avg 112-129 — "real workout" grade. |

**Ground-truth anchor:** the imported WHOOP auto-detected rows (sport `"Activity"` — WHOOP's own auto-detect label) average **109-148 bpm**, matching the 40% HRR tier. WHOOP's published bar (launch-era): elevated HR + movement ≥ ~15 min accumulating strain; 2026: min duration lowered to 10 min. The `rest + 40% HRR` sustained-motion window is the honest local equivalent.

**Conclusions the design must respect:**
1. A fixed `rest + N bpm` floor cannot work across users — this user's 42-49 RHR makes +30 equivalent to "awake and moving." The floor must be **HRR-relative** (`rest + frac × (hrmax − rest)`), which self-scales with fitness.
2. The production detector's zone-2 qualification is calibrated for cardio sessions and silently drops this user's dominant activity pattern (long walks/hikes, avg 95-110). The fix is a second, lower-intensity "activity" tier — and because the user chose auto-save semantics, it must live inside `WorkoutDetector` (which owns persisted rows), not the suggestion path (see "Architecture constraint" below).
3. WHOOP semantics are "Activity" (auto-detected sustained effort) vs user-named sport. NOOP already renders `sport="detected"` as "Activity" — the vocabulary matches.

## Proposed design

Decisions locked with the user (2026-09-21): **Activity-tier sensitivity** (≈ rest + 40% HRR — WHOOP auto-"Activity" parity) and **auto-save + FYI notification** (the row persists immediately; the notification is informational with Edit/Dismiss actions — WHOOP's actual behavior).

**Architecture constraint that shapes everything:** `IntelligenceEngine` deletes and re-inserts all `sport="detected"` rows under the computed `"-noop"` source on every pass (IntelligenceEngine.swift:2751-2756). A row auto-saved by the suggestion path would be clobbered on the next analysis. Therefore the activity tier must live **inside `WorkoutDetector`** — the engine that already owns persisted detected rows — not in `AutoWorkoutDetector` (whose header contract is "never writes a row on its own").

### Phase 1 — activity tier in `WorkoutDetector` + post-workout notification (the deliverable)

**Detector change (pure, byte-parity both platforms):**
- `WorkoutDetector.detect` gains a second tier. Runs that fail the existing `minIntensityZ2Plus` gate are today dropped at `f.droppedLowIntensity`; instead, re-qualify them against the activity bar: window sustained ≥ `activityMinMin = 10` min AND ≥ `activityElevatedFrac = 0.5` of its HR samples above `rest + activityHRRFrac × (hrmax − rest)` with `activityHRRFrac = 0.40`. Rationale: the span-forming floor (rest+15 + motion) already produces these windows — the z2 gate just discards them. Re-qualifying at the higher floor reproduces the 21-window/8-day calibration above without touching what already passes.
  - Alternative formulation (equally valid, slightly deeper cut): run span formation twice at two floors. The re-qualify approach is the smaller diff and keeps one funnel.
- `ExerciseSession` gains a tier marker (e.g. `isActivityTier: Bool`, default false — additive, Codable-compatible). Persisted rows keep `sport="detected"` (renders "Activity" today — already WHOOP's vocabulary); the funnel gains `keptActivity` so `detectionFunnelLine` stays honest. Both changes byte-mirrored in `WorkoutDetector.kt` + `IntelligenceEngine.kt` persist loop.
- `AutoWorkoutDetector` adopts the same floor shape (`rest + max(30bpm, 0.40×HRR)`) so suggestion-card candidates and persisted rows stop disagreeing — the repo's own "a bout and its day scored by different recipes is worse than either being wrong" principle. Its motion-confirm path gets wired at the call site (`motionPoints(gravity)` — currently `motion: nil`, Repository.swift:3060).

**Notifier (app-target, `IllnessNotifier`/`BatteryNotifier` idiom):**
- New `Strand/System/WorkoutDetectedNotifier.swift`: `requestAuthorization()` on toggle-enable; `post(session)` checks `getNotificationSettings` status-only; dedup via UserDefaults span-token set `workouts.detectedNotified` (`"startTs:endTs"` tokens, 30-day prune + 200 cap — same shape as `autoDetectDismissedSpans`, byte-mirrored with Android prefs).
- `UNNotificationCategory` `workout.detected` with actions: **Edit** → open the workout detail/relabel (routes via `NotificationPresenter.didReceive` + NavRouter, same pattern as `CoachBriefScheduler.notificationCategoryId`, NotificationPresenter.swift:37-46); **Not a workout** → existing dismiss path (durable `dismissedDetected` span + delete, Repository.swift:2890-2901).
- Copy (i18n-gated): "Activity detected — 47 min · avg 104 bpm · peaked 140." Informational; the row is already saved.
- Android twin `com.noop.notif.WorkoutDetectedNotifier`: channel + `NotificationCompat` actions → PendingIntents to relabel/dismiss.

**Trigger point (background semantics):**
- The `IntelligenceEngine` persist loop already knows which rows it just wrote. After the pass, take newly persisted detected rows with `endTs ≤ now − notifySettleS` (`notifySettleS = 600` — only notify once the window has been over for ≥10 min, so it can't fire mid-workout and naturally lands ~15-20 min post-exercise on the offload cadence), diff against the notified set, post the newest.
- iOS background: BLE offload wake → backfill → analysis → post; no new scheduler. macOS: menu-bar extra keeps the process alive. Android: same hook in `IntelligenceEngine.kt`'s pass completion, called from `WhoopConnectionService`.
- Gate: new pref `workoutDetectedNotify` (default OFF), Settings row next to `noopAutoDetectWorkouts` with honest copy ("Saves a detected activity after it ends and notifies you. Approximate, on-device.").

### Phase 2 — suggested sport on the notification (classification)

- Wire the **dormant** `WorkoutTypeClassifier` behind its existing `WorkoutTypeClassifying` seam: on a notification candidate, build `WorkoutClassFeatures` via `WorkoutTypeFeatureExtractor` (HR shape + `activityClass` tick composition + gravity variance + duration/kcal) → notification reads "Looks like a walk" / save flow pre-selects the sport.
- **Ship rule per the repo's derived-signal standard:** the classifier is validated only on synthetic fixtures today. Before any label reaches UI, score it against labeled data — the 83 imported WHOOP rows give sport labels (no overlapping streams yet, so first pass = forward-looking: accumulate detected windows the user confirms/relabels as labels; `workouts.csv` re-imports provide more). The `scores` field already emits per-class raw scores for confusion-matrix evaluation. Until accuracy is proven, notifications stay generic ("Activity") and the label path is trace-only under the `.workouts` Test Centre domain.
- Never override a user's own sport selection; never gate a downstream score on a predicted class (classifier header contract).

### Phase 3 — richer accepted rows

- On Log/accept, run `WorkoutDetector`'s per-bout stats over just the accepted window (avg/peak/strain/zones/calories — `ExerciseSession`) and write them into the saved row's `avgHr`/`maxHr`/`strain`/`zonesJSON` via the existing `backfillWorkout` seam (WorkoutDetector.swift:557) instead of the bare `avgHr`-only manual row `saveDetectedWorkout` writes today (Repository.swift:3075).

### Phase 4 (stretch) — 100 Hz IMU classification

- `ImuFeatureExtractor` already produces cadence (1.2-3.5 Hz autocorrelation on genuine 100 Hz data — allowed by the derived-signal rule), jerk RMS, gyro energy. Wiring it behind `WorkoutTypeClassifying` separates run/cycle/strength properly. Blocked today: raw IMU is file-backed capture-session only (raw-data mode costs battery; the `rawImuSample` cache was dropped at migration v41). Evaluate only after Phase 2 proves value on stored streams; no persistent IMU table without a migration+test and a battery discussion.

## Repo-standard checklist for the PR

- **Byte parity:** every constant/branch mirrored in `AutoWorkoutDetector.kt` (+ tests); oracle-compile the Swift twin for expected outputs. `detectionFunnelLine`-style diagnostics stay byte-identical — add a `workout notify` trace line under the existing `.workouts` Test Centre domain (per-connect readouts gated; state transitions always-on, per the repo's diagnostic-attribution rule).
- **No spectral/frequency methods on 1 Hz streams** (the #194 rule); cadence only from the real 100 Hz IMU.
- **Migrations:** none needed — notified/dismissed sets live in UserDefaults/SharedPreferences like the existing span lists.
- **i18n:** new notification + Settings strings must satisfy `Tools/i18n_audit.py --ci`.
- **No default CI builds app targets** (`app-build.yml` disabled): verify with `xcodebuild -project Strand.xcodeproj -scheme Strand build` + `xcodebuild -scheme NOOPiOS build` locally, and `cd android && ./gradlew testFullDebugUnitTest`.
- **`doc_comment_lint`:** insert new declarations above neighbors' doc blocks, never between a doc block and its declaration.
- **Design system:** notification copy is system-rendered (no palette concerns); the in-app card path already uses design tokens.
- **Attribution discipline:** notification body must only claim what the detector measured ("Looks like a workout — 47 min, avg 104 bpm"), never a sport it didn't classify (existing `saveDetectedWorkout` writes generic `"Workout"` for exactly this reason).

## Risks / open questions

- **Notification chattiness:** at 40% HRR this user's data yields ~2-3 windows/day. Mitigations: notify only the newest unsettled candidate per pass, once-per-span dedup, optional per-day cap, and the dismiss path teaching the dismissed-set. Tune `hrrFraction` (0.40 vs 0.45) after field use — keep the constant public for the trace.
- **restingHR source:** `autoDetectCandidate` uses the most recent nightly RHR (Repository.swift:3043) or 60 — fine; but a low-RHR user + high HRR fraction means the floor rides high on days the strap misread RHR. Optional guard: also require `avgBpm` inside window ≥ absolute floor (~100 bpm) as a sanity clamp.
- **WHOOP 4.0:** no `activityClass` ticks and coarser gravity banking → motion confirm weaker; the detector still works HR+motion, classifier falls back to HR+motion scoring (`tickCoverage` gate already handles it).
- **False-positive classes:** sauna/hot weather HR elevation without motion — killed by motion confirm; long car rides — gravity micro-motion may pass confirm; classifier `stillFraction` helps Phase 2.
