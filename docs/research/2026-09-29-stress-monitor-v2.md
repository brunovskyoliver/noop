# Broop Stress Monitor v2 implementation report

## Delivered

The iOS Stress screen, Home tile and Health card read `Repository.stressDayAnalysis` and the shared live-reading resolver. The screen shows the 0–3 gauge, five-minute day chart with sleep/activity shading, waking band minutes and Sleep Stress. Breathing remains reachable. Advanced HRV and longer history remain in the classic stress sheet, explicitly labelled as classic analysis.

`StressDaySummary` persists waking mean, low/medium/high minutes, coverage and main-sleep high-stress percentage. `Repository.stressDaySummaries(days:)` supplies Mind. Waking totals require 30 measured minutes; Sleep Stress requires at least one hour and coverage of half the main sleep. Missing values stay absent. Exercise, detected movement and the post-exercise elevated-pulse window are excluded from waking scores and exercise is excluded from the baseline.

The live child views receive actual HR packets and fresh R-R packets converted to pulse. They require 60 observations, keep a five-minute window, and discard the reading after 15 seconds without a packet. They do not repeatedly count a stale HR property. Tracked workouts and elevated pulse following a workout are masked. Reference changes, source changes, midnight and final view detachment clear the relevant state. No BLE commands changed.

Rest v2 is enabled by default in Scoring. The inherited Rest resolver is shared by the updated app readouts. Imported sleep performance remains authoritative when present; computed Rest v2 applies to on-device scoring. Restorative sleep remains a separate displayed statistic. Full-history completion is recorded only after a successful analysis pass, and stored stress summaries survive raw-data retention expiry. Such retained days cannot be recalculated without their original samples.

The debug demo seeds 120 days of stress summaries from synthetic inputs passed through the production engine. The demo day chart uses the same generator. The seeder logs `Broop demo Rest comparison` with legacy and v2 values from the same daily row, using an explicit eight-hour need and 80% consistency; it does not replace imported demo sleep performance.

## Formula and sources

The public WHOOP description establishes the 14-day personal reference, HR/HRV inputs, movement handling and 0–3 bands. It does not publish the scoring transform. Sources were captured in the feature-gap research:

- [WHOOP Stress Monitor launch](https://www.whoop.com/us/en/thelocker/introducing-stress-monitor-a-new-way-to-monitor-manage-stress/)
- [WHOOP Stress Monitor discussion](https://www.whoop.com/us/en/thelocker/podcast-215-introducing-stress-monitor-a-new-way-to-measure-manage-stress/)
- [WHOOP Sleep Performance components](https://www.whoop.com/us/en/thelocker/how-well-whoop-measures-sleep/)

The fork's waking transform is `3 / (1 + exp(-ln(2) * (2 * deltaHR / 15 - 1)))`. It maps the calm floor to 1, +7.5 bpm to 1.5 and +15 bpm to 2. Sleeping HR and log-RMSSD use robust personal deviations, averaged across prior nights. Their combined deviation maps to 0.4 at reference and 2 at three robust standard deviations. Sleep Stress is the percentage of scored main-sleep epochs at or above 2.

Rest v2 weights sufficiency at 55%, consistency at 15%, efficiency at 15%, and sleep-stress credit at 15%. Sleep-stress credit is `clamp(1 - percentHigh / 30, 0, 1)`. Missing optional inputs are removed and the remaining weights renormalized. These weights, thresholds and transforms are local approximations, not WHOOP's unpublished formula.

## Verification

`swift test --package-path Packages/StrandAnalytics --filter 'StressMonitorTests|RestV2Tests'` passed 28 tests on 2026-09-29. Tests cover multiple injected stress shares, level anchors, cold start, HRV suppression, workout/post-workout masking, sleep coverage, exercise-only baseline rejection, missing Rest components and consistency shifts. `git diff --check` passed, and XcodeGen generated the app project.

Integrated verification passed the full 2,168-test analytics suite, iOS simulator and macOS app builds, 10 targeted app tests and the signed Release build. Simulator screenshots cover Stress, Sleep and Home, including matching imported Rest and Sleep Stress readouts. Release was installed and launched on the owner’s iPhone on 2026-09-29. Real-strap live behavior remains unverified. Evidence is in `~/agent-runs/2026-09-29-healthspan-stress-mind/`.

The matched demo daily row scored 86.06 with legacy Rest and 83.30 with v2, using an eight-hour need, 80% consistency and 5.21% Sleep Stress. Imported demo Rest remains 89 on both Home and Sleep.

## Limits

Daytime RMSSD does not contribute to stress because the existing daytime analysis explicitly excludes unreliable wrist measurements. Fresh live R-R supplies pulse; it is not a validated daytime HRV stress model. No motion channel is available to the live subscriber, so unlogged movement below the elevated-pulse cutoff can still resemble stress. Real-strap live behavior needs device verification.

The scoring method is an estimate of physiological load, not a mental-health assessment. Whole-night coverage below 50% is withheld. No Android code changed, as explicitly requested for this fork.

## Live dial follow-up, 2026-09-29

The revised iOS dial now uses a rolling 60-second pulse window with at least 30 measured seconds. Fresh packets update the shared reading as they arrive, rounded to one decimal place. Home and Health consume that same reading. The Canvas needle interpolates between values using the shared gauge animation, with system Reduce Motion, the app's quiet-motion setting and Low Power Mode respected.

WHOOP's standard and native realtime readers now emit readable heart-rate packet events even when BPM is unchanged. The existing UI value deduplication remains in place. This fixes a sampling gap in the previous subscriber: a steady pulse without R-R packets could fail to accumulate enough observations. No outbound BLE commands, stored scores, day analysis, or baseline formulas changed. This remains the fork's local HR estimate, not WHOOP's unpublished HR/HRV/motion scoring algorithm. Android remains outside this fork's requested scope.

The tested packet window counts one observation per second across channels, rejects invalid pulse values, drops stale samples after 15 seconds and starts fresh after a packet gap or backwards clock adjustment. Disconnects and off-wrist clears invalidate the live reading immediately. Workout masking requires fresh packets; final view detachment clears workout state and cancels the sampler without a trailing timer update.

Verification: all 25 `StressMonitorTests` passed, including a rising/falling-pulse regression that failed against the original five-minute window. The macOS app compiled and all 24 targeted `FrameIntegrityGateTests` and `LiveHeartRateReadabilityTests` passed. The packet regression passes 60 identical valid realtime frames through the production router, observes 60 packet events and only one HR value publication, and confirms a corrupt frame emits nothing. The iOS simulator app build passed. The new build was installed in the Broop-healthspan simulator and the Stress screen was checked with demo history. Its gauge, fallback label and timeline rendered correctly; the simulator check does not verify a connected strap or live animation. UI changes use existing palette, typography and motion tokens. `git diff --check` and `Tools/doc_comment_lint.py` passed.

`Tools/i18n_audit.py --ci HEAD` reports no new UI-copy or focus-language gaps. Its full result remains failing on existing extra-language coverage allowances in the unchanged string catalogs. Real-strap packet cadence, connection behavior and the live needle on the owner's iPhone remain unverified.

Phone deployment: the updated signed Release build passed on 2026-09-29. Its bundle signature passed `codesign --verify --deep --strict`. CoreDevice installed `com.oliverbrunovsky.noop` over the existing Broop app on Oliver's iPhone 16 Pro and successfully launched it. No demo launch arguments were used. This verifies deployment and launch; connected-WHOOP behavior still needs an on-device check.
