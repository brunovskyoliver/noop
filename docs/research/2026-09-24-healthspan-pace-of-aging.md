# Body Age over 6 months, VO₂max, zone time and Pace of Aging

Status: implemented in `VitalityEngine` / `VitalityWindow` (Swift `Packages/StrandAnalytics`, Kotlin
`com.noop.analytics`), stored weekly as `vitality`, `body_age` and `pace_of_aging`. A wellness estimate,
not a clinical biological age.

## What WHOOP does

Source: *The WHOOP Healthspan Feature*, white paper rev. 4 Sep 2025.

- **WHOOP Age** is chronological age plus the sum of per-metric "Age Impacts". Each impact converts an
  all-cause-mortality hazard ratio into years ("effective age", Spiegelhalter 2016). The reference person
  meets WHOOP's recommendations, so a WHOOP Age equal to your age means "meeting the recommendations",
  not "average".
- **Inputs (9):** sleep duration, sleep consistency, steps, HR zone 1–3 time, HR zone 4–5 time, strength
  activity time, VO₂max, resting HR, and lean body mass % (optional; no effect unless entered).
- **Window:** the last 6 months. Updates weekly.
- **Zone time** counts only inside logged activities. Zones are %HRR (Karvonen). Recommendations for
  young adults: ≥100 min/week zone 1–3 and ≥10 min/week zone 4–5, falling with age.
- **VO₂max reference** (Figure 4, ml/kg/min, ages 20…100 in 5-year steps):
  - F 40 40 38 36 34 32 30 29 27 26 25 23 22 21 20 19 18
  - M 46 46 44 42 40 37 36 34 32 30 29 27 26 25 23 22 21
- **Overlap:** a structural equation model fitted on member data produces adjustment factors, so that
  RHR and VO₂max (for example) are not counted twice. The factors are not published.
- **Pace of Aging** (−1.0× to 3.0×): project WHOOP Age six months ahead assuming the last 30 days'
  averages hold, and compare the projected change with six months. 1.0× = aging at the calendar rate.

Other products, for contrast:
- **Garmin Fitness Age:** VO₂max vs age/sex norms, plus vigorous minutes, RHR and BMI/body fat.
- **Oura Cardiovascular Age:** pulse-wave shape and arterial stiffness from night-time PPG.
- **Apple:** Cardio Fitness (VO₂max) from outdoor walks and runs only; no biological age.
- **Ultrahuman Ultra Age:** combines pulse, sleep and optional blood markers.

## What NOOP does

The existing Vitality model already follows the same effective-age idea: a log-hazard sum ×0.75
overlap shrink ÷ (ln2/8) per year, clamped to a Body Age of 20–90. This change:

1. **Window: 7 days → 180 days** for Body Age, matching WHOOP. Aggregation:
   - resting HR and HRV are medians;
   - sleep, steps and VO₂max are means;
   - zone time is minutes per week over worn days (needs ≥7 worn days).
2. **VO₂max joins the model.**
   - Reference: WHOOP's table above, linear between anchors, flat outside 20–100. Sex values other
     than male/female use the mean of the two rows.
   - Hazard: 13% per MET (3.5 ml/kg/min), from Kodama 2009 (RR 0.87 per MET, 102,980 people). Capped
     at ±4 MET.
   - Source: a measured value (Apple Health import) is preferred for the whole window. Otherwise NOOP's
     weekly estimate (`vo2max_est`, Nes 2011 or Uth 2004) is used. The two are never averaged together.
3. **HR-zone time joins the model.**
   - Minutes come from each workout's stored `zonesJSON`, attributed to the workout's local start day.
     Detected bouts use the Edwards %HRR zones 50/60/70/80/90, which are close to WHOOP's %HRR zones.
     Workouts without stored zones add nothing.
   - Moderate-equivalent minutes = zone 1–3 + 2 × zone 4–5 (WHO's rule that one vigorous minute counts
     as two moderate ones).
   - Hazard curve: Arem 2015 (JAMA Intern Med, 661,137 people).
     - vs no activity, HR 0.80 below the guideline, 0.69 at 1–2×, 0.63 at 2–3×, 0.61 at 3–5×
       (plateau, no harm above);
     - piecewise-linear in ln(HR) at the bin midpoints: 0, 75, 225, 375 and 600 min/week;
     - zero point at the 150 min/week guideline.
4. **Overlap domains.**
   - {resting HR, VO₂max}: NOOP's VO₂max estimate is itself built from resting HR.
   - {steps, zone time}: step intensity stops predicting mortality once total steps are adjusted for
     (Saint-Maurice 2020, Paluch 2022).
   - Inside a domain the larger factor counts in full and the other at half. This is on top of the global
     0.75 shrink.
   - Sleep duration and regularity stay independent (Windred 2024 adjusted for both).
   - This is a transparent stand-in for WHOOP's unpublished SEM factors.
5. **Pace of Aging.**
   - Formula: pace = 1 + 2 · (BodyAge₃₀ − BodyAge₁₈₀), clamped to −1…3. This follows directly from
     WHOOP's definition: (Δ₃₀ + 0.5 y − Δ₁₈₀) / 0.5 y.
   - The recent window starts from the 180-day inputs and replaces each factor it measured, so a
     factor missing from the last 30 days reads as unchanged.
   - Needs ≥60 worn days in 180 and ≥14 in 30.
   - Bands:
     - reversing: < 0
     - slowing: < 0.95
     - steady: < 1.05 (prints as 1.0×)
     - accelerating: otherwise

The Swift and Kotlin versions are pinned to the same output by an oracle test:
`VitalityWindowTests.testOracleScenario` and `VitalityWindowTest.oracleScenario`, which compare exact
doubles.

## Known limits and next steps

- **Hazard ratios are observational** and come from cohorts unlike the user. The Gompertz slope
  (ln2/8 ≈ 0.087 per year) is a population average. WHOOP uses 0.1 per year; Levine's PhenoAge uses
  0.092 per year.
- **No uncertainty band is shown yet.** Wearable VO₂max alone carries ±3–6 ml/kg/min, which is about
  ±1–2 years. The Doherty (2025) critique of WHOOP makes the same point.
- **Estimated VO₂max is mostly resting HR in disguise**, so the domain halving matters. A measured
  VO₂max breaks that loop.
- **Still missing from WHOOP's input list:**
  - strength time: logged strength workouts, 30–60 min/week, J-shaped (Momma 2022);
  - lean mass %: optional, from Apple Health `lean_mass` / `body_fat`;
  - a timing-based Sleep Regularity Index: the current regularity input is a duration-CV proxy.
- **Short sleep only in WHOOP.** WHOOP gives long sleep (>9 h) no penalty because of reverse
  causation. NOOP's sleep curve still penalises both sides.

## References

- WHOOP Healthspan white paper (rev. Sep 2025):
  https://assets.ctfassets.net/rbzqg6pelgqa/3ONehqJslbqxI7CQlwGjfT/36429d6f66940e1fd866a772ed5bfc93/WHOOP_2025_White_Paper_Healthspan__6_.pdf
- Spiegelhalter 2016, BMC Med Inform Decis Mak (effective age): https://pubmed.ncbi.nlm.nih.gov/27496144/
- Kodama 2009, JAMA (CRF and mortality): https://pubmed.ncbi.nlm.nih.gov/19454641/
- Mandsager 2018, JAMA Netw Open: https://pubmed.ncbi.nlm.nih.gov/30646252/
- Arem 2015, JAMA Intern Med (activity dose-response): https://pubmed.ncbi.nlm.nih.gov/25844730/
- Lee 2022, Circulation (moderate vs vigorous, mutually adjusted): https://pubmed.ncbi.nlm.nih.gov/35876019/
- Paluch 2022, Lancet Public Health (steps): https://pubmed.ncbi.nlm.nih.gov/35247352/
- Saint-Maurice 2020, JAMA (steps, intensity): https://pubmed.ncbi.nlm.nih.gov/32207799/
- Zhang 2016, CMAJ (resting HR): https://pubmed.ncbi.nlm.nih.gov/26598376/
- Jensen 2013, Heart (RHR adjusted for VO₂max): https://pubmed.ncbi.nlm.nih.gov/23595657/
- Windred 2024, Sleep (sleep regularity): https://pubmed.ncbi.nlm.nih.gov/37738616/
- Cappuccio 2010, Sleep (sleep duration): https://pubmed.ncbi.nlm.nih.gov/20469800/
- Momma 2022, BJSM (muscle strengthening): https://pubmed.ncbi.nlm.nih.gov/35228201/
- Nes 2011, MSSE (non-exercise VO₂max): https://pubmed.ncbi.nlm.nih.gov/21502897/
- Uth 2004, EJAP (HRmax/HRrest VO₂max): https://pubmed.ncbi.nlm.nih.gov/14624296/
- Levine 2018, Aging (PhenoAge): https://pubmed.ncbi.nlm.nih.gov/29676998/
- Doherty 2025 critique: https://medium.com/@cailbhe/is-whoop-really-able-to-measure-your-healthspan-728b88e69175
