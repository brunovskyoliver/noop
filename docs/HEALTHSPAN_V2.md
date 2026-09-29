# Broop Healthspan v2

This Apple-only fork replaces the previous Body Age computation with Broop Age. Android remains on the previous model by explicit scope. Stored keys remain `body_age`, `pace_of_aging`, and `vitality`; Vitality is derived from the same age difference.

Broop uses the nine contributors described in the WHOOP Healthspan white paper and the effective-age transform `age + sum(10 * log(hazard ratio) * overlap weight)`. It cannot reproduce WHOOP Age exactly. WHOOP's fitted curves and overlap coefficients are unpublished. Each curve's source and Broop's interpolation, clipping and reference assumptions are documented in `VitalityEngine.swift`. The UI calls the result an independent approximation.

Broop-specific choices include a 0.7 weight for the smaller absolute contribution within the VO2/RHR and steps/moderate-activity pairs; linear age ramps for activity, steps and lean-mass targets; a bedtime-spread proxy for sleep consistency; and a 180-day approximation of six months. Sleep of seven hours or more is neutral, as requested. HRV is not an age input. Missing lean mass and unlogged strength have no effect. Strength sessions represented by an identically keyed workout count once.

The model requires 21 scored recoveries in the previous 31 days and updates on Sunday. The recent 30-day averages project six months ahead at age + 0.5. Pace is the projected age change divided by 0.5 and limited to -1 through 3. A recent missing factor carries its longer-window value. Imported Apple Health VO2 measurements take precedence over estimates independently in each averaging window; later measurements cannot rewrite earlier windows.

The repository resolves imported and computed recoveries, steps, workout zones, Lift Log sessions, sleep consistency, and body composition. The Health tab, detail screen, weekly writer and history backfill share this resolver. Each contributor opens its weekly six-month-average trend. Body composition can come from Lab Book body fat, Apple Health body fat, or paired same-day lean mass and weight. A body-composition reading can carry for up to a year; this assumption is not a WHOOP rule.

The first successful run replaces old Saturday history with recomputed Sunday values in one database transaction. Failed writes preserve the original history and remain retryable. The completion flag is device-specific and is not set before a profile age and history exist. No schema migrations or BLE commands change.

## Completion report

Continued the previous thread's committed engine and unfinished reader/UI work. Fixed strap-only recovery coverage, missing-strength handling, future VO2 measurements affecting earlier history, atomic replacement and retry behavior. Removed the temporary scroll argument and decorative glow. Added numeric targets and contributor trends, and disclosed method differences in the screen's information text.

Verification: 20 Healthspan engine tests and 3 shared sleep-consistency tests pass. The 15 metric-series store tests pass, including replacement rollback and preservation of unrelated sources and metrics. Changed Swift source parses successfully. Integrated app verification and phone installation are recorded below.

No claim of clinical validity or numerical equivalence with WHOOP is made. Local physiological scoring and imported source accuracy remain upstream limitations. The old demo seed used fabricated Body Age values, so comparing those numbers with the new computed demo would not measure an algorithm change.

A compiled comparison using the original v1 source and current v2 source on matched synthetic inputs produced `v1 Body Age 37.8692` and `v2 Broop Age 36.6386`. Inputs: male, age 40, RHR 58, VO2 42 (reference 40), sleep 7.5 hours, consistency 75%, 9,000 steps/day, 140/14 minutes per week in zones 1–3/4–5. V1 also received HRV 33 ms against a 33 ms norm (zero impact); v2 received 60 strength minutes/week and 80% lean mass. This is a reproducible synthetic comparison, not an observed result for the phone owner or the seeded demo.

## Integrated verification

The completed feature passed the full 2,168-test StrandAnalytics run, the additional 4-test consistency run, 16 metric-series store tests and 10 targeted macOS app tests. XcodeGen, NOOPiOS simulator, Strand macOS and signed NOOPiOS Release builds passed. Simulator checks covered Healthspan contributor navigation, Stress, Mind, Home and Sleep. The Mind questionnaire save and confirmed-delete flow passed with expected totals. The Release was installed and launched on the owner's iPhone on 2026-09-29. No real-strap stress validation was performed.

The local completion report, screenshots and logs are in `~/agent-runs/2026-09-29-healthspan-stress-mind/`. The demo shows Broop Age 23.9 against calendar age 30.0 and Pace -0.3x. No changes were pushed.
