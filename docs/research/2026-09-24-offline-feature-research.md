# Research: eight offline features (HRV status, planners, strain target, reports, tests, cycle)

Research only; nothing here is implemented. Each section covers how WHOOP and others do it, the key
science, what NOOP already has, a recommended method, how to validate it, and the risks. Items marked
**[unverified]** come from secondary sources, vendor claims or memory.

Common rules for everything below (from AGENTS.md):
- Pure engines go in `Packages/StrandAnalytics`, with a Kotlin twin in `com.noop.analytics`.
- Swift and Kotlin must be pinned to identical output by an oracle test.
- Results are stored in `metricSeries`, so no schema migration is needed.
- New physiological signals ship default-off (Experimental) until they are shown to track changing
  input on several people.

## Bugs found during the scan (verified)

1. **Live workout Effort ignores the user's resting HR.** `StrainScorer.strain(...)` is called with
   no `restingHR` in `Strand/App/AppModel.swift:1146` (Android `AppViewModel.kt:1856`), so it uses the
   default of 60 bpm. The saved workout uses today's real resting HR, so the live and saved numbers can
   differ.
2. **Cycle next-period window without a logged period.** In `CyclePhaseEngine` (Swift and Kotlin),
   when no period start is logged, the anchor is the temperature-shift onset (around ovulation).
   `anchor + cycleLength ± 2` then lands near the *next ovulation*, about two weeks after the real next
   period. It should be `onset + luteal length` (about 12 days). No test pins this case.
3. **Training load is averaged on the log-compressed strain scale.** `TrainingLoadEngine` and the
   ACWR/monotony code in `ReadinessEngine` work on daily strain instead of TRIMP. A week with twice the
   TRIMP shows a ratio of about 1.1 instead of 2.0. `ReadinessEngine` also drops missing days
   (`compactMap`), which squeezes calendar gaps together. Edwards TRIMP can be recovered exactly as
   `7201^(S/100) − 1`.
4. **Three separate bedtimes.** The wind-down reminder (its own sleep need and wake time), the caffeine
   cutoff (`noop.caffeine.bedtimeMinutes`) and `CircadianEngine.idealSleepWindow` each define bedtime.
   A sleep planner must not add a fourth. The fix is one resolver that all of them read.
5. Possible: WHOOP 4.0 is labelled as electrical R-R ("chest strap") in `LiveView.swift:35` and
   `LiveScreen.kt:196`, but it is an optical sensor. [unverified that this is unintended]

## Suggested order

| # | Feature | Effort | Why this position |
|---|---|---|---|
| 1 | Fix bugs 1–3 | small | They distort features 3, 4 and 7 below |
| 2 | HRV status band | small | The engine exists (`HRVReadiness`) but only as an Experimental Test Centre item; promote and tighten it |
| 3 | Sleep planner + caffeine cutoff | medium | Needs the single bedtime resolver (bug 4); both share it |
| 4 | Live strain target | medium | Needs bug 1 and bug 3 fixed |
| 5 | Monthly performance report | medium | Reuses `RangeReport`/`TrendsReportSheet` and the TRIMP-based load from bug 3 |
| 6 | Hours until recovered | medium | New per-session model; must be backtested before it is shown |
| 7 | Jet-lag planner | medium | `CircadianEngine.planShift` exists but is unwired and anchored wrongly |
| 8 | Guided tests (orthostatic, 2 km walk) | large | New flows plus GPS and RR quality gates |
| 9 | Cycle predictions | medium | Fix bug 2 first; keep the "no fertile window" rule |

---

## 1. HRV status band (Garmin style)

**How others do it**
- **Garmin:** a 7-day average of overnight HRV compared with a personal baseline range. The status
  needs about 3 weeks of data. Labels are balanced, unbalanced (above or below the range), low, and
  poor (below the norm for your age). The formula is not published.
- **Oura:** HRV balance compares a 14-day average with a 3-month average.
- **Polar:** its nightly "ANS charge" compares against a 28-day baseline using the mean and multiples
  of the SD.
- **HRV4Training:** a 7-day average against a 60-day normal range, plus the coefficient of variation
  (CV).
- **WHOOP:** no separate band; HRV is folded into Recovery.

**Science**
- The 7-day average of ln RMSSD tracks performance change (r ≈ 0.72–0.76); a single day does not
  (Plews 2013, IJSPP, PMID 23479420).
- At least 3 valid nights a week are needed (Plews 2014, PMID 24334285).
- The normal band is mean ± 0.5 SD (Vesterinen 2016; Javaloyes 2019, PMID 29809080; Nuuttila 2022,
  PMC9473708). Kiviniemi 2007 used mean − 1 SD as the rest signal (PMID 17849143).
- HRV also rises during overreaching (Bellenger 2016 meta-analysis, PMID 26888648; Le Meur 2013), so
  "above range" must not be presented as good.
- The direction of the CV change is contested: Flatt & Esco 2016 (PMID 26200192) against Altini.

**NOOP already has** `HRVReadiness.swift` / `.kt`:
- ln RMSSD, the last 7 valid nights, a band of mean ± 0.5 SD over 60 nights, and a minimum of 14
  nights;
- states called primed, normal and suppressed, plus an `overreachingWatch` flag;
- shown only in the Test Centre, behind the `noopHrvReadiness` flag.

**Recommended method**
- **Short window:** the last 7 *calendar* days, needing ≥3 valid nights ("solid" at ≥5). Today the
  engine takes the last 7 *valid* nights, which can reach far back after a gap.
- **Baseline:** days t−67…t−7, so the 60 days before the short window. Excluding the short window stops
  a sustained drop from pulling its own baseline down.
  - Values winsorized at ±3 SD; SD floor 0.08 ln.
  - Needs ≥21 valid nights; until then show "calibrating n/21".
  - Stale after 3 days without a valid night.
- **Status:**
  - balanced: inside ±0.5 SD;
  - above usual: above +0.5 SD;
  - below usual: between −0.5 and −1.0 SD;
  - low: below −1.0 SD (a design choice modelled on Kiviniemi).
- **Hysteresis:** change status only after crossing a boundary by 0.1 SD, or after 2 days in a row.
- **Leave out for now:** Garmin's "poor" tier (age norms). NOOP's RMSSD comes from deep sleep only, so
  published norms don't apply.
- **Illness:** nights the illness heads-up flagged are left out of the baseline only. They stay in the
  7-day average, which gets a "may reflect illness" label.
- **Wording:** "7-night HRV vs your usual range". The existing Readiness driver uses last night only,
  so label the two readouts "last night" and "7-night trend" to keep them from appearing to disagree.

**Validation**
- Synthetic step changes of several sizes; the status must follow each one.
- On real history, the share of non-balanced status in steady weeks should be about 20–30%.
- "Low" should line up with illness flags and hard training blocks.

## 2. Sleep planner ("go to bed at X for Y% of your need")

**How others do it**
- **WHOOP:**
  - Need = baseline + strain + sleep debt − naps.
  - Goals are 100%, 85% and 70% of need.
  - Suggested time in bed is balanced against how consistent your recent bed and wake times have been.
  - The strain coefficient and how time in bed is converted to sleep are not published.
- **Oura:** bases its bedtime suggestion on the bedtimes of your best nights and the timing of your
  resting-HR drop. Needs about 2 weeks of data.
- **Samsung (One UI 8):** runs a two-process model over 3 days of sleep to suggest a bedtime.

**Science**
- Two-process model (Borbély 1982; 2016 reappraisal).
- Adults need at least 7 h (Watson 2015, PMID 26039963).
- 1 h of sleep debt took about 4 days of extended sleep to recover (Kitamura 2016, PMC5075948). Pay
  debt back partially, not in one night.
- Sleep Regularity Index (Phillips 2017).
- Chronotype from mid-sleep on free days (MSFsc, Roenneberg).
- It is hard to fall asleep about 2–3 h before your habitual bedtime (the "forbidden zone"), so
  bedtime can't be pulled much earlier in one night.

**NOOP already has**
- `personalizedNeedHours`: the 75th percentile of recent nights, with an age floor, capped at 9.5 h.
  No strain term.
- `SleepDebt` (14-night ledger).
- `RecoveryForecast`, the wind-down reminder (which uses its own need), the smart alarm and
  `CircadianEngine.idealSleepWindow`.

**Recommended method** (one pure resolver, "tonight's plan", read by the wind-down reminder, the
caffeine cutoff and the planner card)

```
need = base + min(0.33·debt, 90 min) + strainAdd(0…20 min, default off) − todayNapSleep
goal = need × {1.00, 0.85, 0.70}
SE   = median sleep efficiency of last 14 nights, clamped 0.75–0.97 (default 0.88)
TIB  = goal / SE + latency (15 min default, user-editable)
wake = strap alarm > wind-down weekday wake > 14-night median wake
bed  = wake − TIB, but no earlier than median bedtime − 90 min (otherwise: "not reachable tonight")
```

- **Regularity hint:** stay within ±30 min of your median bedtime.
- **Social-jetlag warning:** weekends more than 1 h later than weekdays.
- **Circadian check:** flag a wake time more than 1.5 h before `idealSleepWindow`.
- **Labels:** NOOP's own tier names, not WHOOP's Peak/Perform/Get By.
- **Show the arithmetic:** "8 h 20 = 8 h base + 20 min debt".

**Validation**
- Backtest the predicted sleep (time in bed × personal efficiency) against actual sleep; target a
  median error under 20 min.
- Unit tests for DST, wake after midnight, and fewer than 7 nights.

**Risks**
- The strain term has no solid evidence behind it.
- Ever-earlier bedtime suggestions can feed insomnia worry.

## 3. Caffeine cutoff

**Now:** `CaffeineLog.swift` sits in the app target, not the package. It uses a half-life of 5.5 h and
a cutoff of bedtime − 11 h *whatever the dose*, with its own bedtime setting.

**Science**
- Drake 2013 (PMID 24235903): 400 mg taken 6 h before bed cut total sleep by more than 1 h.
- Gardiner 2023 meta-analysis (PMID 36870101): caffeine cost 45 min of sleep. Cutoffs: coffee
  (107 mg) at least 8.8 h before bed, pre-workout (217.5 mg) at least 13.2 h.
- Gardiner 2025, SLEEP: 100 mg even 4 h before bed had no significant effect; 400 mg disrupted sleep
  up to 12 h out.
- Clearance is mostly by the CYP1A2 enzyme. Oral contraceptives and pregnancy slow it, smoking speeds
  it up (Nehlig 2018).

**Recommended method** (move into `StrandAnalytics`)
- Remaining caffeine: `residual(t) = Σ dose·0.5^((t−tᵢ)/h)`.
- Cutoff for a drink of D mg: `bedtime − h·log2(D/R)`, clamped to 4–16 h before bed.
- Defaults: h = 4.3 h and R = 26 mg. This fit is our own back-derivation: it reproduces both Gardiner
  cutoffs (107 mg → 8.8 h, 217.5 mg → 13.2 h). Default drink = 95 mg.
- User-chosen presets for sensitivity multiply the half-life: ×0.7 / ×1 / ×2 / ×3. Never inferred.
- Bedtime comes from the sleep planner's resolver.

**Validation**
- Pin the dose → lead-time table in both test suites.
- Personal effect (caffeine left at bedtime vs next night's sleep) goes through the existing
  `DoseResponseEngine` as instrumentation only.

**Risk**
- Existing users' cutoffs will change; call this out in the changelog.

## 4. Live strain target during a workout

**How others do it**
- **WHOOP Strain Target (formerly Strain Coach):**
  - A daily target from recovery, sleep and "training state".
  - Bands called restoring, optimal and overreaching.
  - Live "keep going / you hit the goal / you're overdoing it" during an activity.
  - The formula is not published.
- **Garmin/Firstbeat:** acute load (7-day weighted EPOC) against a personal optimal range; load ratio
  green at 0.8–1.3.
- **Polar:** strain ÷ tolerance (7 vs 28 days).

**Science**
- HRV-guided training: Kiviniemi 2007, Vesterinen 2016, Javaloyes 2019.
- The acute:chronic ratio (Gabbett 2016) is heavily criticised (Impellizzeri 2020, Lolli 2019). Use it
  only as a ramp limit, never as injury prediction.
- Foster 1998: monotony ≥ 2 went with illness.

**NOOP already has**
- Fixed bands in `CoupledView` (recovery ≥67 → 14–18, 34–66 → 10–14, below 34 → 4–10).
- `StrainTargetNotifier`, `LiveSessionEngine` (an HR-band coach), `LiveWorkoutView` and
  `TrainingLoadEngine` (CTL 42 / ATL 7).
- On NOOP's scale the top of the fixed band barely fits: strain 18 needs about 2,024 TRIMP, which is
  roughly 405 min above 90% HRR.

**Recommended method** (`StrainTargetEngine`)
1. Work in TRIMP (additive), not strain (log scale).
2. Chronic load C = exponential average of daily TRIMP, τ = 28 d; acute A, τ = 7 d. Contiguous days
   only.
3. Recovery multiplier `m = clamp(0.5 + 0.9·R/100, 0.5, 1.4)`.
4. Cap m at 0.8 if the 7-day ln RMSSD is below baseline − 0.5 SD, or resting HR is 1 SD or more above
   baseline.
5. Ramp cap: the target must keep tomorrow's acute load ≤ 1.3 × chronic.
6. Monotony nudge: if monotony over 6 days is ≥ 2.0 and yesterday was in the band or above, lower today
   by 15%.
7. Band = 0.85–1.15 × m·C, shown in strain units.
8. Cold start:
   - with fewer than 14 contiguous days, use the existing fixed bands;
   - between 14 and 28 days, blend personal and fixed bands.
9. Live display:
   - remaining TRIMP = band_low − today's TRIMP so far;
   - minutes = remaining ÷ Edwards weight (1–5) per %HRR zone, plus "about N min at your current
     pace";
   - the on-screen zones are %HRmax and must be converted to Edwards %HRR zones.
10. The band is fixed once when the morning recovery arrives and never moves mid-workout.
11. One resolver shared by the ring, the notification and the live screen.

**Validation**
- On imported WHOOP history:
  - the band should be reachable on about 50–70% of training days;
  - next-day recovery should fall in order: restoring > optimal > overreaching.
- Compare against the fixed bands behind an Experimental toggle first.

## 5. Monthly performance report (1–6 months)

**How others do it**
- **WHOOP Monthly Performance Assessment:**
  - sleep vs the previous month;
  - sleep debt against restorative sleep;
  - strain and zone time per sport;
  - strain by day of the week.
- **Garmin Training Status:** detraining, recovery, maintaining, productive, peaking, overreaching,
  unproductive or strained, from the VO₂max trend, acute load and HRV status.
- **TrainingPeaks:** CTL, ATL and TSB with 42- and 7-day constants.

**Science**
- The Banister fitness–fatigue model is fine for describing load but unstable for predicting it
  (Hellard 2006).
- Adaptation markers: resting HR down, HRV stable or up with CV down, faster heart-rate recovery
  (Buchheit 2014; Plews 2013).
- Overreaching can't be diagnosed from wearables (Meeusen 2013), and HRV can rise when overreached
  (Le Meur 2013).
- NOOP's VO₂max estimate is derived from resting HR, so it is not independent evidence.

**NOOP already has**
- `WeeklyDigest`, `RangeReport` + `TrendsReportSheet` (offline PDF), `ComparisonEngine.monthOverMonth`,
  `TrainingLoadEngine` and `HeartRateRecovery`.

**Recommended method** (`PerformanceReportEngine`, rendered through the existing PDF sheet)
- **Windows:** 28 days vs the previous 28, plus 3- and 6-month views.
- **Load:**
  - TRIMP totals;
  - CTL at the start and end, ramp per week, TSB as a % of CTL;
  - monotony and Foster strain;
  - zone minutes;
  - load by weekday and by sport.
- **Balance:**
  - recovery distribution;
  - days in each target band;
  - mismatches (overreaching on a red day, restoring on a green day);
  - sleep debt trend.
- **Adaptation:**
  - resting HR, ln RMSSD and HR recovery against their smallest worthwhile change (0.5 × SD over
    60 days; resting HR floor 1 bpm);
  - VO₂max shown, but not counted as independent.
- **Verdicts:**
  - Improved: at least 2 independent markers better, none worse, CTL steady or up.
  - Maintained.
  - Detraining: CTL down more than 20% plus a marker worse.
  - Strained: sustained deeply negative TSB or ACWR, plus resting HR up and HRV down for at least 7
    days.
  - Unproductive.
  - Mixed.
  - Never say "overtraining".
- **Gates:**
  - at least 21 of 28 days worn and 20 HRV nights;
  - CTL marked "building" until 42 contiguous days;
  - days not worn are shown as gaps, not zeros.

## 6. Readiness for tomorrow and hours until recovered

**How others do it**
- **Garmin/Firstbeat Recovery Time:** EPOC-based and updated with sleep and stress. The model is
  proprietary and has never been validated publicly.
- **COROS:** a recovery timer capped at 96 h with an exponential-like shape.
- **Polar:** strain ÷ tolerance.
- **WHOOP and Oura:** no countdown.

**Science**
- Parasympathetic recovery takes up to 24 h after low-intensity work, 24–48 h after threshold work and
  ≥48 h after high-intensity work. Fitter people recover faster, and duration matters less than
  intensity (Stanley 2013, PMID 23912805).
- Below the first ventilatory threshold, recovery is minimal (Seiler 2007).
- One session barely moves nightly HRV; nightly HR is more sensitive (Myllymäki 2012; Nuuttila 2024).
  HRV alone can't certify "recovered".

**NOOP already has**
- `RecoveryForecast`: tomorrow's Charge from strain debt, sleep adequacy and mean reversion. Its
  "planned sleep" is just the average of past nights.
- `DoseResponseEngine`: per-user slopes shrunk toward a prior.

**Recommended method**
- **Per session:**
  - Intensity class: high if at least 10 min ≥80% HRR; threshold if at least 20 min ≥70%; otherwise
    low.
  - Base hours: 12 / 36 / 60.
  - Dose: `sqrt(TRIMP / personal median TRIMP for that class)`, clamped 0.5–1.6.
  - Session hours `Rᵢ` = base × dose, capped at 96 h.
- **Stacking:** `F(t) = Σ exp((Rᵢ − (t−tᵢ))/24 h)`, remaining = `24 h·ln F`.
- **Morning adjustment:**
  - HRV and resting HR normal: ×0.75;
  - either clearly off: +12 h;
  - short sleep: +6 h;
  - never set the countdown to 0 from HRV alone.
- **Tomorrow's Charge:**
  - use F at tomorrow's wake time instead of today's strain debt;
  - learn the Effort→Charge slope per user;
  - use the planned sleep from the sleep planner.
- **Show:** "about 30 h before another hard session (estimate)", in 6 h steps, naming the session type
  that drove it.

**Validation** (offline on stored history)
- **Forecast backtest:** error against "same as today" and "14-day mean". If it doesn't beat them, say
  so in the UI.
- **Recovery hours:** nights until HRV and resting HR are back within ±0.5 SD, compared with the
  prediction.
  - Include a shuffled-timing control, which should do clearly worse.
  - The low < threshold < high ordering must hold across several people.
- Experimental first.

## 7. Jet-lag planner

**How others do it**
- **Timeshifter:** light, sleep, caffeine and melatonin timing. The model is not public.
- **Entrain (Walch 2016):** model-based light schedules.

**Science**
- Light phase-response curve: light before the body-temperature minimum (CBTmin) delays the clock,
  after it advances (Khalsa 2003). A single pulse shifts it by up to about 2 h (St Hilaire 2012).
- Pre-flight shifting of 1 h/day with morning light works; 2 h/day doesn't (Burgess 2003, Eastman
  2005).
- Large eastward trips risk shifting the clock the wrong way (Revell & Eastman 2005).
- Delays are easier than advances. [1.5 h/day delay rate unverified]
- The ODE models (Forger 1999, Hannay 2019) need light-sensor input, which WHOOP doesn't have.

**NOOP already has** `CircadianEngine.planShift`: 1 h/day with light windows, and never melatonin. It
isn't wired into production. It anchors to clock wake time instead of CBTmin, treats advance and delay
alike, and has no itinerary input.

**Recommended method** (rule-based, anchored on CBTmin)
- Inputs: home and destination IANA timezones, dates, 0–3 pre-flight days, habitual sleep, and the
  CBTmin estimate (or wake − 2.5 h).
- Shift wrapped to ±12 h. More than 9 h east is planned as a delay the other way.
- Rates: advance 1 h/day, delay 1.5 h/day.
- Each day:
  - Advance: seek light CBTmin…+3 h and avoid light −3 h…CBTmin.
  - Delay: seek light −4…−1 h and avoid light CBTmin…+3 h.
- Remove windows that overlap sleep.
- Pre-flight days are shown in home time, later days in destination time.
- Widen windows when the phase estimate is uncertain.
- Never recommend melatonin.
- Also needed: store a timezone per night. History is re-rendered in the phone's current zone after
  travel.

**Validation**
- Reproduce the Burgess 2003 schedule.
- Timezone edge cases: +5:30 and +5:45 zones, the date line, DST in the middle of a trip, and ±12 h.
- Optionally watch the heart-rate daily-rhythm peak move after a trip (instrumentation only).

## 8. Guided tests

### Orthostatic HRV test (Polar style)

**How Polar does it**
- 2 min lying then 2 min standing (older watches used 3 + 3).
- Metrics:
  - resting HR and RMSSD;
  - peak HR after standing;
  - standing HR and RMSSD.
- Baseline: 6 tests over 2 weeks. Normal range = 28-day mean ± SD once at least 4 tests exist in
  28 days.
- HRV4Training now prefers lying and then sitting up.

**Science**
- Standing triggers a heart-rate peak after about 15–20 beats. Overtrained athletes show a blunted
  response in both postures (Gronwald 2024).
- The effects are small and within day-to-day noise, so other symptoms are needed too (Bosquet 2008).
- Lying and standing can move in opposite directions with fatigue (Schmitt 2013/2015).
- A 60 s ln RMSSD is valid (Esco & Flatt 2014).

**Recommended protocol**
- 3 min lying, then a cue, then 3 min standing, within 1 h of waking.
- HR peak = maximum of a 3-beat median in the first 30 s after the cue.
- Windows analysed: 60–180 s of each phase.
- Quality gates:
  - at least 50 clean beats;
  - at most 20% rejected;
  - a stand must be detected (HR up at least 5 bpm within 30 s).
- One out-of-range result is just noted; 2 of the last 3 out of range in the same direction is a
  trend.
- Descriptive labels only, never "overtrained".

**Strap limits**
- Both WHOOP models use an optical sensor, so standing RMSSD (often under 20 ms) is noisy. Present HR
  metrics normally, standing RMSSD as experimental, and offer a Polar H10 as the precise option.

**Safety**
- If the heart-rate rise after standing is ≥30 bpm on repeated tests, show neutral "talk to a
  clinician if you have symptoms" text. Never name a condition.

### Walk test for VO₂max

**How others do it**
- **Oura:** a 6-min brisk walk with GPS and ring HR. The equation is not published.
- **Apple:** from outdoor walks and runs; underestimates by about 6 ml/kg/min (Lambe 2025/2026).
- **Polar:** a resting test with about 13.7% error (Neudorfer 2025).

**Equations**
- **UKK 2 km walk** (Laukkanen 2000, PMID 10727071), total error 4.1–4.5 and validated for detecting
  change: [coefficients from a secondary source]
  - men: `184.9 − 4.65·t − 0.22·HR − 0.26·age − 1.05·BMI`
  - women: `116.2 − 2.98·t − 0.11·HR − 0.14·age − 0.39·BMI`
- **Rockport 1 mile** (Kline 1987), SEE about 5.
- **6-minute walk equations** (Burr 2011, Mänttäri 2018) were fitted on short indoor tracks with turns,
  so a straight outdoor GPS walk would bias them.

**Recommendation:** use the UKK 2 km walk (Rockport as the shorter alternative).
- Stop automatically at 2,000 m of GPS distance.
- HR = median over the final 15 s.
- Quality gates:
  - GPS accuracy ≤20 m and ascent ≤20 m;
  - no stops;
  - no running (speed ≤2.5 m/s or cadence ≤150 steps/min);
  - end HR ≥65% of max;
  - ages 20–65; ask about HR-limiting medication.
- Not offered on macOS.
- Blend with the Nes/Uth estimate by inverse variance. The test's error grows with its age, so it
  counts most for about 2–3 months.
- Show the ±4–5 ml/kg/min band and a safety screen.

## 9. Cycle predictions

**How others do it**
- **Apple:** retrospective ovulation estimate from wrist temperature. Error 1.2–1.6 days;
  next-period error 1.65 days (Wang 2025).
- **Oura:** temperature-based period predictions and a fertile window marketed for conception. Its
  Natural Cycles integration is FDA-cleared; Oura detected 96% of ovulations with about 1.3 days of
  error (Thigpen 2025).
- **WHOOP:** uses bleeding logs only, with no conception or contraception claims.
- **Natural Cycles:** FDA Class II contraception software (product code PYT).

**Science**
- Cycles average 29.3 ± 5.2 days, and the same woman varies by about 2.6 days. The luteal phase is
  12.4 ± 2.4 days; length differences come mostly from the follicular phase (Bull 2019, 612k cycles).
- 42.5% of women vary by more than 7 days (Fehring 2006).
- Conception happens only in the 6 days ending on ovulation (Wilcox 1995).
- Luteal temperature is about +0.3 °C (Maijala 2019).
- Sleeping pulse is +2–4 bpm in the luteal phase (Shilaih 2017).

**NOOP already has** `CyclePhaseEngine`:
- combines temperature, resting HR and HRV;
- needs at least 42 nights;
- period log stored as `noop-cycle/period_start`;
- explicitly bans "fertile window" and "safe days" wording.

It also has bug 2 above.

**Recommended method**
- **A. Calendar prior:**
  - median of the last 6 logged cycle lengths;
  - drop implausible cycles and probable missed logs;
  - window ±max(2, ⌈1.28·SD⌉) days;
  - with fewer than 3 cycles, 29 days ± about 5.
- **B. Ovulation confirmation:**
  - the "3-over-6" temperature rule: 3 nights above the maximum of the previous 6, with the 3-night
    mean ≥ +0.2 °C (≥2 SD on WHOOP 4.0, whose temperature scale is provisional);
  - ovulation = shift day − 1;
  - a resting-HR rise corroborates only.
- **C. After confirmation:** next period = ovulation + personal luteal median (10–16 days, default 12),
  ±2 days.
- **D. No prospective fertile window.** Temperature only confirms ovulation afterwards, and a
  calendar-only window is wrong too often (Fehring). Keep the existing ban and use Apple-style
  wording: "ovulation likely occurred around X (estimate)".
- **Regulation:** contraception or fertility claims make the app a medical device in the US and EU.
  Stay with wellness wording.

**Validation**
- Leave-last-cycle-out backtest, reported separately for WHOOP 4.0 and 5.0.
- Volunteers with LH tests for ovulation; target a mean error ≤1.6 days.

---

## Sources

- **HRV:** Plews 2012, 2013 and 2014 (PMID 22367011, 23479420, 23852425, 24334285); Kiviniemi 2007
  (17849143); Vesterinen 2016 (26909534); Javaloyes 2019 (29809080); Nuuttila 2022 (PMC9473708) and
  2024 (PMC11235883); Bellenger 2016 (26888648); Flatt & Esco 2016 (26200192); Buchheit 2014
  (PMC3936188); Manresa-Rocamora 2021 (PMC8507742).
  - Vendors: Garmin HRV Status manual, Oura readiness contributors, Polar Nightly Recharge white paper,
    HRV4Training blog.
- **Recovery:** Stanley 2013 (23912805); Seiler 2007 (17762370); Hautala 2001 (11318832); Myllymäki
  2012 (21667290); Clarke & Skiba 2013 (23728131).
  - Vendors: COROS recovery timer, Polar Training Load Pro white paper.
- **Sleep:** Watson 2015 (26039963); Kitamura 2016 (PMC5075948); Phillips 2017 (Sci Rep); Roenneberg
  MCTQ.
  - Vendors: WHOOP sleep planner, Oura bedtime guidance, Samsung One UI 8 Watch.
- **Circadian and jet lag:** Khalsa 2003; St Hilaire 2012 (22547633); Burgess 2003 (12932084) and 2010
  (20410229); Eastman 2005 (15700719); Revell & Eastman 2005; Walch 2016; Hannay 2019 (31617438); CDC
  Yellow Book 2026.
- **Caffeine:** Drake 2013 (24235903); Gardiner 2023 (36870101) and 2025 (SLEEP zsae230); Nehlig 2018.
- **Load:** Foster 1998 (9662690); Gabbett 2016 (26758673); Impellizzeri 2020; Lolli 2019 (29101104);
  Williams 2017; Murray 2017 (28003238); Busso 2003 (12840641); Hellard 2006 (PMC1974899); Meeusen
  2013 (23247672); Le Meur 2013 (24136138).
  - Vendors: WHOOP Strain Target and Monthly Performance Assessment, Garmin Training Status,
    TrainingPeaks PMC.
- **Tests:** Gronwald 2024 (39259398); Bosquet 2008 (18308872); Schmitt 2013 (PMC3741143) and 2015;
  Esco & Flatt 2014 (25177179); Munoz 2015 (26414314); Laukkanen 2000 (10727071); Burr 2011
  (21673494); Mänttäri 2018 (29851229); Uth 2004 (14624296); Lambe 2025 (PMC12080799) and 2026
  (PMC13141568); Neudorfer 2025 (PMC12473405).
  - Vendors: Polar orthostatic test, Oura Cardio Capacity.
- **Cycle:** Bull 2019 (PMC6710244); Fehring 2006 (16700687); Wilcox 1995 (7477165); Maijala 2019
  (PMC6883568); Shilaih 2017 (PMC5431053); Alzueta 2024 (PMC11416332); Wang 2025 (PMC11879225); Thigpen
  2025 (PMC11829181); Natural Cycles FDA DEN170052 and K202897.
