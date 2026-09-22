# Workout auto-detection and classification: what exists and what is feasible

Research date: 2026-09-21. Source baseline: working tree at `docs/research/` creation date; all paths relative to repo root. Scope: investigation only; no app behavior changed.

Question: can NOOP detect/predict workout sessions from captured data, like the WHOOP app's auto-detected activities? Short answer: yes at the coarse level, and most of it is already built. Detection runs in production today; classification exists but is dormant; the strap itself never sends a workout record.

## The two detectors (deliberately separate)

| Component | Status | Behavior |
| --- | --- | --- |
| `WorkoutDetector` (`Packages/StrandAnalytics/Sources/StrandAnalytics/WorkoutDetector.swift`) | **Production** | Retroactive dual-gate detector over stored 1 Hz HR + gravity. Runs inside `AnalyticsEngine.analyzeDay` (AnalyticsEngine.swift:868-898), called by `IntelligenceEngine` every ~15 min while connected. Persists `sport="detected"` rows under the computed `"<deviceId>-noop"` source. |
| `AutoWorkoutDetector` (`AutoWorkoutDetector.swift`) | **Shipped, default OFF** | Opt-in "did you just work out?" suggestion card. HR-only in practice, never writes a row; Save converts a suggestion to a manual `sport="Workout"` row. |
| `WorkoutTypeClassifier` (`WorkoutTypeClassifier.swift`) | **Dormant** | Heuristic 6-class scorer (walk/run/strength/cycle/ski/other) over a detected window. Zero production call sites on either platform; validated only on synthetic fixtures. |
| `ImuFeatureExtractor` (`ImuFeatureExtractor.swift`) | **Built, unwired** | 100 Hz raw-IMU feature vector (accel/gyro energy, jerk RMS, autocorrelation cadence) for WHOOP 5/MG. The designed upgrade path behind `WorkoutTypeClassifying`. |

### `WorkoutDetector` mechanics (WorkoutDetector.swift)

- Gates: per-sample smoothed gravity intensity > `motionThreshold = 0.20` AND nearest HR within ±5 s > resting + `hrMarginBPM = 15` (lines 460-471). Resting defaults to the day's 10th-percentile HR (lines 137-143); HRmax to `StrainScorer.estimateHRmax` (lines 445-453).
- Grouping: active runs split on gaps > `mergeGapS = 150` s (lines 475-484); `bridgeRuns` stitches runs across ≤ 300 s motion lulls only while mean gap HR stays above the floor — a genuine HR lull stays split (lines 336-377, 486-490).
- Qualification: duration ≥ `minExerciseMin − motionSmoothS` (290 s effective, lines 186-189, 499-504), non-empty HR core, ≥ 50 % of samples in Edwards zone ≥ 2 (`minIntensityZ2Plus`, lines 516-520). Warm-up back-dating via `backdatedStart` (lines 379-399, 522-526).
- Per bout: `ExerciseSession` with avg/peak HR, duration, zone-time %, mean %HRR, strain (`StrainScorer`), Keytel 2005 + Harris-Benedict calories, `hrCoveragePct` in 60 s buckets (lines 40-76, 215-234).
- Diagnostics: `DetectionFunnel` counted during the detector's own walk; always-on `detectionFunnelLine` per day and `boutCalibrationLine` per bout, byte-identical to Kotlin (lines 155-281).

### Persist and display path

- `IntelligenceEngine.swift:2139-2202`: emits funnel + per-bout calibration lines, drops bouts overlapping any real row while backfilling that row's missing avgHR/peakHR/kcal/strain (#510, lines 2165-2190), persists survivors as `WorkoutRow(sport: "detected", source: computedId)`; re-run idempotency via delete-then-reinsert under the computed id (lines 2751-2756).
- `Repository.workoutRows` unions registered WHOOP ids, their `-noop` siblings, `apple-health`, `lifting`, `activity-file` (Repository.swift:2619-2645).
- Display: `sport == "detected"` renders as "Activity" (`WorkoutSource.displaySport`, WorkoutSource.swift:44-50); "Detected" source badge (WorkoutsView.swift:1619-1626) / "AUTO" on Android. Row actions: relabel (11-sport quick menu, WorkoutsView.swift:466-470), dismiss, edit, merge.
- Stale doc note: `docs/ANALYTICS.md:44` still says "Not yet surfaced in the Workouts screen" — superseded; rows are surfaced today.

### `AutoWorkoutDetector` mechanics (AutoWorkoutDetector.swift)

- Constants (lines 58-73): `elevatedMarginBPM = 30`, `minSustainedMin = 12.0`, `maxDipS = 90`, `mergeGapS = 300`, `motionConfirmMean = 0.05`, `defaultRestingHR = 60`. Deliberately conservative — a suggestion you can decline, not a row.
- `Repository.autoDetectCandidate(daysBack: 2)` (Repository.swift:3030-3068): unioned HR read, most-recent nightly RHR or 60, excludes saved + dismissed spans, returns newest candidate; `detectTrace` under the Workouts test mode.
- Gate: `PuffinExperiment.autoDetectWorkoutsKey = "noopAutoDetectWorkouts"`, default OFF (PuffinExperiment.swift:245-252; SettingsView.swift:1715-1727). Card: `AutoWorkoutCard.swift` mounted in TodayView; Android twin `AutoWorkoutNudge.kt` (same gates, `NoopPrefs.autoDetectWorkouts` default false).
- The motion-confirmation path exists in the detector but is unwired: the only caller passes `motion: nil` on both platforms.

## What data exists to detect from

| Signal | Source | Cadence | Role today |
| --- | --- | --- | --- |
| HR (`heart_rate@22`) | `Interpreter.swift` v18 decode; persisted `HistoricalStreams.swift:264-266` | nominal 1 Hz banked; ~30 s sparse live on 5/MG | Primary gate, both detectors |
| Gravity x/y/z (`@45/49/53`) + `dynamic_acceleration@41` | `Interpreter.swift:445-455`; persisted `HistoricalStreams.swift:306-314` | ~1 Hz, offload-only | Motion gate (`WorkoutDetector`); optional confirm (`AutoWorkoutDetector`, unwired) |
| `activity_class@63` (0 still/1 walk/2 run) | `Interpreter.swift:466-475`; persisted on `StepSample` (`HistoricalStreams.swift:284-289`) | 1 Hz, offload-only, 5/MG only | The strap's own per-tick gait label — classifier feature, not a detection gate. 4.0 never emits `StepSample`. |
| `step_motion_counter@57`, `step_cadence@59` | `Interpreter.swift:456-475` | 1 Hz, offload-only | Step totals; counter overcounts on 5/MG (`stepTicksPerStep`) |
| Raw 100 Hz 6-axis IMU | `Whoop5RawImu.swift` (1244-byte buffer, accel+gyro; Gen4 variant 1917 in whoop_protocol.json) | 100 Hz | **Not persisted as a stream** — file-backed capture sessions only (`ImuSessionFileStore`); the `rawImuSample` SQLite cache was dropped at migration v41. Requires START_RAW_DATA(81)+TOGGLE_IMU_MODE(106). |
| PPG waveform (v26, 24 samples/s) | persisted `HistoricalStreams.swift:236-263`; `PpgHr.estimate` → per-second HR | 24 Hz → 1/s | HR-gap filler upstream of detection only |
| `sleep_state@81`, quality fields | `Interpreter.swift:430-475` | 1 Hz | Not used by workout detectors |

Consequences:

- Both detectors are **retroactive by construction** — gravity/steps/activity-class only reach the app on offload (`backfillIntervalSeconds = 900`, docs/PROTOCOL.md:367). No real-time "in a workout now" detection is possible on this data.
- `StreamReadCap.swift:50-74` caps assume 1 Hz for HR and gravity over the 54 h analysis window.
- WHOOP 4.0: no step count, coarsely banked gravity — weaker motion gate, no `activityClass`.

## What the wire carries (no native workout record)

- Packet types (whoop_protocol.json:4-9): COMMAND/RESPONSE, REALTIME_DATA(40), REALTIME_RAW_DATA(43), HISTORICAL_DATA(47), EVENT(48), METADATA(49), CONSOLE_LOGS(50), REALTIME_IMU(51), HISTORICAL_IMU(52), puffin variants. **No workout/session packet type.**
- `EventNumber` enum (whoop_protocol.json:11-31): battery/charging/wrist/BLE/RTC/alarm/haptic — **no workout-start or activity event**.
- The only on-wire activity signal is `activity_class@63` — a gait label, not a session or sport ID.
- WHOOP sport labels exist only in the user's own `workouts.csv` export (`activity_name`, `activity_strain`, zone pcts, distance — `WhoopExportImporter.swift:344-382`): import-only ground truth, not a BLE feed.
- Conclusion: WHOOP's auto-detected activities are computed server-side; nothing to decode. NOOP must derive windows locally — which is what it does.

## Classification reality

- `WorkoutTypeClassifier.swift`: ramp scoring over `WorkoutClassFeatures` (HR profile incl. `hrCV`; `activityClass` tick fractions + `tickCoverage`; gravity-delta `motionVariance`/`motionCV`; duration; `kcalPerMin`) → walk/run/strength/cycle/ski/other + confidence. Gates: `minTickCoverage = 0.15`, `minPlausibleScore = 0.40`, `minMargin = 0.05` (lines 163-168). Explicitly broad-only and deliberately non-spectral on the 1 Hz stream (lines 17-29).
- **Dormant**: repo-wide grep for `WorkoutTypeClassifier.` / `WorkoutTypeFeatureExtractor` hits only implementation + test files — zero production call sites either platform.
- Header honesty (lines 31-39): "validated so far ONLY against synthetic fixtures … Real-world accuracy against labeled workouts … is an explicit follow-up." The `scores` field reports every class's raw score precisely so a later pass can compute accuracy/confusion without re-deriving features.
- `WorkoutCatalog.swift`: 84-entry manual sport picker — not classifier capability.
- `ImuFeatureExtractor.swift` (lines 4-46): the designed upgrade path — real cadence (1.2-3.5 Hz band, strength-gated autocorrelation on a genuine 100 Hz stream, allowed by the derived-signal rule), jerk, gyro energy. Wired to nothing yet; meant to slot behind `WorkoutTypeClassifying`.

## Android parity

Byte-parity twins with mirrored tests on both sides: `AutoWorkoutDetector.kt`, `WorkoutDetector.kt` (constants, funnel, coverage, calibration lines), `WorkoutTypeClassifier.kt`, `AutoWorkoutNudge.kt`, `AutoWorkoutPrefs.kt`, `IntelligenceEngine.kt:1757-1824` (persist/dedup/backfill). The `round0`/`round1` magnitude formatters exist specifically so diagnostic lines compare byte-identical across platforms.

## Validation state

- Mechanics covered by unit tests: `AutoWorkoutDetectorTests.swift`, `WorkoutDetectorTests.swift`, `WorkoutDetectorBackfillTests.swift`, `DetectionFunnelTests.swift`, `AutoWorkoutDetectorTraceTests.swift`, plus the Kotlin mirrors.
- Classifier/IMU tests follow the derived-signal rule — multiple distinct injected patterns per class (`ImuFeatureExtractorTests.swift:21-30` recovers 1.4/1.8/2.4/3.0 Hz injected cadences).
- **No labeled real-workout benchmark exists.** `Tools/SleepBench`, `Tools/SleepPSG` are sleep-only; `Tools/linux-capture/correlate_ground_truth.py` correlates captures vs WHOOP CSV **nightly aggregates** — not workouts.
- Capture infrastructure for building one exists: `RawDataSessionStore` (bounded sessions + marker events), `ImuSessionFileStore`, Android `GroundTruthCollector.kt`; `docs/RAW_DATA_CAPTURE.md:6-17` names "labelled activity datasets" as a use.
- Field-data caveat: the #845 v18 census was "a single subject, one night … no ambulation, no workout" (`BLE_REVERSE_ENGINEERING.md:464`) — activity-side behavior is barely exercised in existing captures.

## Gap vs. the WHOOP app

| Axis | WHOOP | NOOP today |
| --- | --- | --- |
| Detection | Elevated HR + motion ≥ ~10-15 min (min duration lowered 15 → 10 min in 2026), cloud-side ML, finalizes ~20 min post-exercise | `WorkoutDetector` ≥ ~5 min dual-gate persists rows; `AutoWorkoutDetector` ≥ 12 min HR-only suggests. Both bracket WHOOP's bar. |
| Classification | Auto-classifies into named sports; >140-entry manual catalogue | Generic "Activity"/"Workout" only; dormant 6-class heuristic; 84-entry manual picker. |
| Timeliness | ~20 min post-exercise | Offload-bound (15 min cadence) + sparse 5/MG live HR — similar latency, but no in-progress indicator. |
| Signal ceiling | Full-rate IMU + cloud models | 1 Hz gravity-delta cannot resolve cadence; 100 Hz IMU exists but capture-only/unwired. 4.0 loses `activityClass`. Strength work under-elevates HR — `hrCoveragePct` exists partly to explain these misses. |

## What an extension would take

1. **Validate on labeled real data before trusting labels.** WHOOP-export workouts and Oura `workout.sport` rows are the ground truth already in the store; score the classifier's existing `scores` output for accuracy/top-k/confusion. Per the repo's derived-signal rule, a single matching session is not validation.
2. **Wire `ImuFeatureExtractor` behind `WorkoutTypeClassifying`** on 5/MG — real cadence + jerk separates run/cycle/strength far better than 1 Hz gravity. Requires persisting or session-capturing the raw IMU stream (dropped at migration v41; currently file-backed capture only).
3. **Graduate the suggestion flow** — `AutoWorkoutDetector` is built and mirrored but default-off; enabling it broadly wants field evidence its HR-only precision is acceptable.
4. **Keep the contracts**: Swift↔Kotlin byte-parity with oracle-tested constants; no spectral methods on ~1 Hz streams; detected rows stay mergeable/relabelable user data, never overwriting a user's own sport choice.

## External references

- WHOOP activity auto-detection launch post (Medium): elevated HR + movement ≥ 15 min, Strain ≥ 8.0, ~20 min post-exercise finalization.
- WHOOP "What's New" 2026: auto-detect minimum 15 → 10 min; "Workout Auto-Detect and Auto-Classify" improvements; >140-entry activity library (the loggable catalogue — WHOOP does not claim all are auto-classified).
