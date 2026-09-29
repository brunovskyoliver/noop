# Sleep Regularity Index, continuous strain target and Energy (2026-09-29)

Branch `feature/broop-energy-strain-sri`, cut from `feature/broop-healthspan-stress-mind`. iOS-only fork
change; the Android twin was intentionally not updated.

Commits:

| Commit | What |
|---|---|
| `6c663843` | The live-stress work that was already in the tree (committed on request before branching) |
| `5d04797c` | §1 Replace the bedtime-spread proxy with a true Sleep Regularity Index |
| `2301b667` | §2 Continuous strain target and a live Strain Coach |
| `5b50834e` | §3 Energy reservoir engine |
| `93e51b1c` | §3 Store and show Energy on Home, Health and a new Energy screen |
| `d7e0edd4` | Strain Coach day Effort floored at the stored row (found while taking screenshots) |
| `ff83ae70` | DEBUG screenshot harness cases for the Broop screens |

## §1 Sleep Regularity Index

### What changed

- New `SleepRegularity` engine (`Packages/StrandAnalytics`). It is the only regularity code. It feeds:
  - the Sleep screen statistic, "Sleep regularity, 7 days"
  - the Healthspan / Broop Age regularity factor
  - Rest v2's consistency part, which uses a 4-day window and keeps the label "Consistency"
- `SleepConsistency.swift` (the bedtime-SD proxy) is deleted, along with Rest v2's old main-sleep-only
  comparison. Its tests went with it.
- An imported WHOOP `sleep_consistency` still wins when it covers the newest day
  (`SleepRegularity.resolve`). The UI then shows WHOOP's label ("Sleep Consistency").
- History is rescored by bumping two one-shot backfill flags:
  - `intelligence.stressRestV2.sri.backfill.done` covers Rest v2 and Charge
  - `intelligence.healthspanV2.sri.backfill.done` covers weekly Healthspan

### Formula

Phillips et al. 2017 (Sci Rep 7:1629, doi:10.1038/s41598-017-03171-4):

    SRI = 200 · P(same sleep/wake state at t and t + 24 h) − 100

- **Epochs:** 1 minute (`epochSeconds = 60`) over each night's 18:00→18:00 local window. Every recorded
  sleep session counts, naps included. Wake segments inside a session's stages count as wake (WASO).
- **Unknown data:** a window with under 2 h of recorded sleep is unknown, not "awake all day". Only pairs
  where both epochs are known count.
- **Validity:** the 7-day SRI needs ≥ 120 h of paired epochs, the rule in Windred et al. 2024 (Sleep 47:
  zsad253, doi:10.1093/sleep/zsad253).
- **Percentage:** `consistencyPercent(sri:)` clamps the SRI to 0…100. That is the one documented mapping.
  Negative SRI (worse than random) shows as 0.
- **Rest v2 consistency:** the same pairing between tonight's window and each of the previous 4 days. The
  credit is 2A − 1, clamped to 0…1 and averaged. At least 2 prior days are needed, each with ≥ 12 h of
  pairs.
- **Healthspan knots:** re-anchored on Windred 2024's verified quintiles.
  - Cut-offs: 71.6 / 78.6 / 83.2 / 87.3. Hazard ratios against the least regular quintile: 0.80, 0.75,
    0.72, 0.70.
  - Knots sit at quintile midpoints: (70, 0), (75.1, ln 0.80), (80.9, ln 0.75), (85.25, ln 0.72),
    (90, ln 0.70).
  - Below 70 the first slope is extrapolated for 10 points, then held flat.
  - The previous comment cited SRI percentiles (median 60, 95th percentile 75) that do not match Windred's
    median of 81.0, so those anchors were dropped.

### Tests

`SleepRegularityTests`, 7 tests:

- a regular schedule gives 100
- random 5-minute blocks give ≈ 0 (± 8)
- a schedule shifted by δ gives 100 − 200·2δ/24 for δ = 0.5, 1, 2 and 3 h
- Rest with a 1 h shift gives 1 − 4/24
- naps and WASO count
- missing days, strap-off days and a cold start give nil
- resolve precedence and clamping

## §2 Strain target and Strain Coach

### What changed

- New `StrainTarget` engine. Every reader goes through `StrainTargetContext.band(charge:isToday:)`:
  - the Home dial marker ("X to target", "In target", "Above target")
  - the score detail coach copy
  - Coupled / Outlook
  - the notifier
  - the live workout coach

  `CoupledView.optimalStrainRange` and its static band functions are deleted.
- Settings → Scoring → Effort target → Goal: Restore / Maintain / Build.
- Settings → Notifications gets "Above strain target", a separate toggle that defaults to off. It fires at
  most once a day.
- The Strain Coach card appears on the live workout screen and on the Live Sessions card while a workout
  runs. It shows:
  - the day's Effort, including this workout
  - the target band and a zone label
  - "~N min at this pace" from the inverted scorer (Edwards method only)
  - a zone-2 hint when the current pace is below zone 1

### Formula

The band is a straight-line fit through the old three bands at their Charge midpoints, on the 0–21 axis:

    lower21 = 1.75 + 0.15 · Charge
    upper21 = 8.00 + 0.12 · Charge

- **Sleep debt:** past 60 min, both bounds drop 0.5 per hour, at most 2.
- **Illness heads-up:** both bounds are capped at 4–10.
- **Goal:** Restore −3, Build +2.
- **Output:** clamped to 0…21 with a minimum width of 1, then returned on the 0–100 axis.
- **Unknown Charge:** no band.
- **Scope:** debt and illness only move today's band. Past days use Charge and the goal only.
- **Minutes to target:** (D^(target/100) − D^(current/100)) / TRIMP-per-minute, with D = 7201 (the
  scorer's denominator).

WHOOP publishes its Strain Coach idea but not the curve, so these are NOOP's numbers.

### Bugs checked

- **Live vs stored Effort mismatch: confirmed and fixed.** The live day ring, the workout and the saved
  workout scored with Tanaka HRmax. The stored daily pass used the Settings override. All of them now use
  `StrainScorer.effortMaxHR`. Test: `testEffortMaxHRFunnel`.
- **Resting-HR-60 bug: already fixed by #983.** Live and stored both use the same `?? 60` fallback. No
  change made.
- **Coach day Effort read 0 on a day without raw heart rate: fixed.** Home showed 45.2 on the same day. The
  coach now floors at the stored row through `StrainScorer.effectiveEffort`, Home's own funnel.

### Tests

- `StrainTargetTests`, 6 tests:
  - the band is monotone in Charge
  - it reproduces the old bands at their midpoints
  - nil Charge gives no band
  - debt, illness and goal shifts
  - zone edges
  - minutes-to-target recovers known session lengths at 5 heart-rate levels
  - the HRmax funnel
- `StrainTargetPolicyTests` (app target) updated. 7 pass under `xcodebuild test`.

## §3 Energy

### What changed

- **Engine:** `EnergyReservoir`, a 0–100 level integrated over the Stress Monitor's 5-minute epochs. It
  carries across days with no daily reset.
- **Per-day output:**
  - the series, each point tagged sleep / rest / awake / stress / activity / gap
  - start and end level, the level at wake, peak and low
  - charged, and drained split into stress, activity and being awake (the "top drains")
  - a `seeded` flag
- **Stored contract:** keys on the computed ("-noop") source. These are stored keys, not a migration:
  `energy_start`, `energy_end`, `energy_wake`, `energy_peak`, `energy_low`, `energy_charged`,
  `energy_drain_stress`, `energy_drain_activity`, `energy_drain_baseline`, `energy_seeded`.
- **Analysis pass:** runs in the stress loop, oldest to newest. Each day starts from the previous day's
  stored end.
  - A day keeps its stored summary when its stress inputs, start level and heart profile are unchanged
    (cache key `intelligence.energy.dayKeys.v1`).
  - A strap-off day is still integrated from its empty analysis, so the level holds flat instead of
    breaking the chain.
- **Resolver:** `Repository.energyDayAnalysis(dayKey:)` is the one resolver, the same shape as
  `stressDayAnalysis`. `EnergyNow.resolve` handles today's live level: the last integrated level carried
  over the minutes since the last epoch with the live stress reading (at most 30 min). Both the Home card
  and the Energy screen headline read it.
- **UI:**
  - a Home card with a battery gauge, the level, a band word and "+charged / −drained" for today
  - a new `BroopScreen.energy` screen:
    - the day chart with sleep / rest / activity shading and gaps breaking the line
    - the breakdown and top drains
    - 7- and 30-day averages of the level at wake and the daily low, with a 30-day chart
    - a "How it works" sheet
  - an Energy card on the Health tab after Stress and Mind
- **Setting:** Settings → Scoring → Show Energy, default on.
- **Isolation:** Energy feeds nothing. Charge, Rest, Effort, Healthspan and Mind do not read it.

### Formula

Per 5-minute epoch, with E the current level and dt in hours:

| Epoch | Change |
|---|---|
| Sleep, level L | E += 0.25 · q · (100 − E) · dt, with q = clamp((2 − L)/(2 − 0.4), 0, 1) |
| Waking, level L | E −= (2.0 + 6.0 · max(0, L − 1)) · dt |
| Waking calm run (≥ 2 epochs in a row below level 1, i.e. ≥ 10 min calm and still) | additionally E += 0.08 · (100 − E) · dt |
| Activity | E −= 2.0 · dt + 0.10 · (Edwards zone weight of the epoch's mean HR) · 5 min |
| No data, or sleep without HR | held flat |

- **Clamping:** the level is clamped to 0…100 after every epoch. Charged and drained book the actual
  change, so a clamped drain is not overstated.
- **Sleep anchors:** 0.4 is the typical sleeping level and 2.0 the high floor. A calm epoch charges fully
  and a stressed one not at all.
- **No double counting:** the Stress Monitor masks stress during activity, so exercise is costed only
  through TRIMP.
- **Activity TRIMP inputs:** the day's resting HR and the Effort HRmax funnel (override, else Tanaka).
  This is `Repository.energyHeart`.
- **Calibration gate:** both of the Stress Monitor's references (waking and sleeping) must be personal,
  which needs 4 days of heart rate. Until then the result is nil, shown as "calibrating". The first
  calibrated day with nothing to carry starts at 50 and is flagged.
- **Calibration targets, pinned by `testTypicalDayAndNightRoughlyBalance`:**
  - 8 calm hours from 40 → ≈ 92 (+52)
  - a typical waking day drains ≈ 55: 9 h at level 1.0, 3 h at 1.5, 30 min at 2.3, 1 h of zone 2 and
    1.5 h of calm rest

Garmin's Body Battery comes from Firstbeat, whose model is proprietary and unpublished. The structure
here follows the public description (charge by rest and sleep, drain by stress and activity), but the
constants are NOOP's own and are documented in the engine header.

### Tests

`EnergyReservoirTests`, 10 tests:

- a calm night recovers 5 injected start levels exactly, and inverting it gives them back
- a quiet day recovers 4 injected stress levels from the drain
- a restless night charges less than a calm one
- a typical day and night roughly balance
- high stress drains faster than low
- exercise drains through TRIMP only: zone 4 costs twice zone 2, and below zone 1 only the baseline
- gaps hold the level flat
- carry-over across midnight: a split night equals the same night in one piece, and the level at wake is
  correct
- the level is clamped to 0…100, and the drain is booked only as far as the level actually fell
- a cold start returns nil
- rest recharge needs a 10-minute calm, still run
- stored round-trip, plus the live projection

## Before / after on demo data

The demo seeder feeds SRI and Energy through the production engines (`--demo-seed`, 120 days). The old
numbers come from a throwaway tool in `$TMPDIR`. It runs the pre-change code from git (`6c663843`)
against the sleep sessions in the simulator's database.

### SD proxy vs SRI

Last 30 days:

| | Old: bedtime SD proxy | New: SRI, 7 days |
|---|---|---|
| Mean | 86.1 | 84.8 |

Last 7 nights:

| Night | SD proxy | SRI |
|---|---|---|
| 09-23 | 86.1 | 84.0 |
| 09-24 | 87.8 | 84.0 |
| 09-25 | 88.3 | 83.2 |
| 09-26 | 88.9 | 83.8 |
| 09-27 | 89.8 | 83.9 |
| 09-28 | 89.0 | 85.2 |
| 09-29 | 86.6 | 86.9 |

The SRI runs a little lower. It also penalises the demo's afternoon naps (a third of days) and wake times,
which a bedtime SD never saw.

### Old Rest vs new

Rest v2's consistency part averaged 89.6 % under the old main-sleep-only comparison and 84.5 % under the
4-day SRI. With a 15 % weight and all four parts measured, that moves Rest by about −0.8 points. The Sleep
screen shows 89 % Sleep Performance with Consistency 85 %.

### Old Healthspan age vs new

Regularity is not in an overlap pair, so its years are additive:
10 × (hazard(value) − hazard(target 70)).

| | Value | Knots | Years |
|---|---|---|---|
| Old | SD proxy 86.1 | Old | −1.05 |
| New | SRI 84.8 | Windred | −3.24 |

- **Net:** Δ −2.19 years. The knot change accounts for almost all of it: the same SRI through the old
  knots gives −1.04.
- **Result:** the demo's Broop Age is 21.3 now (the app says "Sleep Regularity helps the most: −3.3
  years"). Under the old code it would have been ≈ 23.5.
- **WHOOP median case in `HealthspanV2Tests`:** now −1.47 (male) / −1.92 (female), previously
  −2.11 / −2.34. WHOOP's own figure is −1.6.
- **Caveat:** before this branch the demo seeded an imported `sleep_consistency` (N(80, 8)). That import
  won over the proxy, so the demo's pre-change Broop Age actually used that synthetic import. The table
  shows what a strap-only user would have seen.

### Old 3-band target vs new band

On the 0–21 scale. "New, 3 h debt" means both bounds after 3 h of sleep debt.

| Charge | Old | New | New, 3 h debt |
|---|---|---|---|
| 8.8 (today) | 4–10 | 3.1–9.1 | 2.1–8.1 |
| 27.2 | 4–10 | 5.8–11.3 | 4.8–10.3 |
| 33.0 | 4–10 | 6.7–12.0 | 5.7–11.0 |
| 37.4 | 10–14 | 7.4–12.5 | 6.4–11.5 |
| 45.1 | 10–14 | 8.5–13.4 | 7.5–12.4 |
| 64.1 | 10–14 | 11.4–15.7 | 10.4–14.7 |
| 17 / 50 / 83 (old midpoints) | 4–10 / 10–14 / 14–18 | 4.3–10.0 / 9.2–14.0 / 14.2–18.0 | |
| 95 | 14–18 | 16.0–19.4 | |

The old bands jumped by 6 at Charge 34 and 67. The new band moves smoothly and matches the old one where
each old band was centred.

### Energy

Across the 120 seeded days:

| Measure | Mean per day |
|---|---|
| Charged | 62.3 |
| Drained | 62.3 (stress 32.1, being awake 24.2, activity 6.0) |
| Level at wake | 90.2 |
| Daily low | 27.9 |

Today: 47 at 23:04, +64 charged, −52 drained, 89 at wake, low 36. The demo's stress share is on the high
side. Its day is synthetic, the same every day apart from small offsets.

## Screenshots

In `~/agent-runs/2026-09-29-energy-strain-sri/`, from simulator "Broop-energy-sri" (iPhone 17 Pro,
iOS 26.4) with `--demo-seed`:

- `home.png`: Energy card below the monitors; Effort "Above target"
- `sleep.png`: Sleep Performance with Consistency (SRI, 4 days)
- `healthspan.png`: Broop Age with "Sleep Regularity helps the most"
- `workout-coach.png`: live workout with the Strain Coach (45.2 day Effort, target 14.6–43.1 on the 0–100 scale, "Overreaching")
- `energy.png`: Energy screen, day chart and breakdown
- `energy-info.png`: "How it works"

The Sleep screen's "Sleep regularity, 7 days" statistics row sits below the fold and is not in the
screenshot.

## Verification

- `swift test` in `Packages/StrandAnalytics`: 2,191 tests, 0 failures.
- `xcodegen generate`, then NOOPiOS (iOS Simulator) and Strand (macOS) both build after every section.
  StrainTargetPolicyTests: 7 passed under `xcodebuild test`.
- `Tools/doc_comment_lint.py`: OK. `git diff --check`: OK.
- `Tools/i18n_audit.py --ci 6c663843 --platform ios` fails on locale gaps in files this branch never
  touched, such as the watch catalogs. That gate was already failing on the base. New strings go through
  `String(localized:)` or `LocalizedStringKey` and have not been translated.

## Still needs real-strap checking

- **SRI:**
  - real nights with imported WHOOP consistency vs the computed SRI on the same days
  - that the 2 h minimum-sleep rule does not blank legitimate short nights
  - Healthspan history after the one-shot backfill
- **Strain Coach:**
  - minutes-to-target against a real workout. The "~N min" estimate assumes the current HR holds
  - the upper nudge fires once, and only above the band
  - the coach's day Effort vs Home's ring during a long workout. Both read raw HR plus the stored floor,
    but the stored row can include part of the running workout after a mid-workout pass
- **Energy:**
  - calibration of every constant against real days. The target is an average day draining 50–60 and a
    night recharging a similar amount; the demo's synthetic day drains ~62
  - how often a real night's sleeping stress level sits near 2 (which stops charging)
  - the live projection's jump when a new epoch lands
  - Energy's heart profile reads resting HR from `repo.days` during the pass, which can lag a fresh
    night's row by one pass
- **Not done:**
  - the classic macOS Automations view has no "Above strain target" toggle
  - legacy Rest (Rest v2 off) still uses the 1 − CV duration regularity
  - there is no Android twin for any of this
