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
