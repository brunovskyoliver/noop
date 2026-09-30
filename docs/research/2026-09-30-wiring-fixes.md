# Broop wiring fixes, 2026-09-30

Base: `feature/broop-energy-strain-sri`, `d941f3c7`. Working tree was clean. Work is on
`feature/broop-wiring-fixes`; nothing is pushed. Android is intentionally outside this fork task.

## A. Bug verification

- A1 already fixed in `fc214d90` (Refs #983), `Strand/App/AppModel.swift`:
  `captureWorkoutSample` and saved workouts both pass `workoutRestingHR`.
- A2 already fixed, including the requested no-log test, in `95a90e20`:
  `CyclePhaseEngine.swift` uses `anchoredByLog ? len : lutealDays`.
  `testTemperatureOnlyWindowIsOneLutealPhaseAfterTheShift` pins onset + 12, not + 28.
  No code or duplicate test added.
- A3 already fixed in `2307a471`. `ReadinessEngine.calendarLoads`,
  `TrainingLoadEngine.dailyTrimp`, the paired readiness API, classic `TrainingLoadCard`, and
  Broop `BroopHealthTrendsView` use TRIMP. Readiness windows retain calendar boundaries;
  CTL/ATL require a contiguous observed suffix and break at an unobserved day.
  Added `testDoubledTrimpDoublesWeeklyLoadAndCtlAtlTsb`: doubling TRIMP doubles weekly load,
  CTL/ATL/TSB, while monotony stays unchanged. Four `TrainingLoadTrimpTests` pass.
  The coupled ACWR includes the hard week in the chronic denominator: three weeks at 200 plus
  one at 400 gives 400/250 = 1.6, not 2.0. The existing regression pins that definition.
- A4 stopped for a product decision. `SleepPlanner` is already the pure resolver for wind-down,
  caffeine and the planner (`AppModel+TonightPlan.swift`); it already applies median bedtime − 90 min.
  `BodyClockDialCard` and `BroopFinalABodyClockCard` intentionally compare last night's phase at
  last night's actual duration (`CircadianEngine.idealSleepWindow` documents this contract).
  Replacing that reference with tonight's full sleep need changes the meaning of the diagnostic.
  No explicit manual caffeine bedtime remains in current readers; they use `tonightPlan`, with a
  23:00 fallback while loading. Wind-down still subtracts the shared window from its own weekday
  wake time and clamps that window to 11 hours, so it can disagree with an armed alarm or a
  12-hour plan. Fixing the scheduling and display contract together exceeds a small wiring fix.
  Options: (1, recommended) keep the retrospective phase diagnostic clearly labelled, add a separate
  tonight-plan row, and decide which circadian edge limits the planner; (2) replace the diagnostic
  with tonight's plan everywhere. Both need a policy for plans that cannot meet sleep need and for
  weekday reminders versus one-off alarm overrides. No bedtime policy or notification changed here.
  The current planner's need also comes from `SleepModel.debtLedger`, rather than Rest v2's need.
  Switching that input changes the plan and the reminder schedule, not just their displayed copy.

- A5 fixed: both WHOOP generations now select `.opticalPPG` through
  `LiveView.hrvSnapshotSource(for:)`, used by classic and Broop snapshot presentations.
  `WhoopHRVSourceTests` failed on 4.0's old `.chestStrap` mapping before the correction.
  No BLE behavior changed. WHOOP's [4.0 sensor description](https://www.whoop.com/us/en/thelocker/chief-technology-officer-whoop-4-0-accuracy/)
  identifies its optical LEDs and photodiodes.

## B. Engine wiring

- B1 wired with `BroopHealthJetLagView`, reachable from the Sleep screen and both Body Clock cards.
  `Repository.jetLagPlan(trip:)` is the single resolver, off-main through `CancellableAnalysis`.
  `JetLagTrip` saves travel date, origin zone, destination UTC offset and the starting bed/wake window
  from `AppModel.tonightPlan` in `broop.jetLag.activeTrip.v1`. No migration or alarm change.
  Day dates precede travel, and all windows are explicitly on the origin clock. The origin offset is
  resolved for the travel date (DST); the user chooses the destination offset for that date.
  Date-line differences beyond 12 hours have no plan. The info sheet explains the engine's fixed
  one-hour steps and limits. Four `JetLagTripTests` plus the optical-source test pass on macOS.
  This reuses the already-shared SleepPlanner despite A4's deferred circadian policy.
  Visual verification also caught and corrected the starting-window label: an active trip now shows
  its captured window, rather than the next refresh's tonight plan. Editing date/offset hides the old
  plan until saved. The offset has a visible label; the page title is shown once.
- B4 skipped: `HealthKitBridge.readTypes` and `collect` import weight and active/basal calories burned,
  but no `dietaryEnergyConsumed` or daily calorie intake. Burned energy cannot replace intake in
  `AdaptiveExpenditureEngine`. No food logging or Health permission added.

- B2 wired as one merged readout using the better-founded `HRVStatus`, now labelled "HRV readiness"
  on Broop Health/Monitor, HRV Trend and Charge. It already implements the Plews/Altini SWC band in
  ln RMSSD, using calendar windows, a baseline excluding the recent week, density and stale-data
  gates, and neutral "above usual" wording. The older `HRVReadiness.evaluate` squeezes missing
  nights together, includes the short week in its baseline and labels high HRV "primed".
  It remains only an explicitly experimental Test Centre comparison. Production Broop views all
  call `Repository.hrvReadiness(asOf:flaggedDays:)` off-main and show no card without a status.
  The method sheet states the log-domain arithmetic, gates and limits. Values are shown in ms
  by exponentiating the mean ln RMSSD; this is distinct from last night's HRV in Charge.
  The promoted card now uses `BroopCard` and shared layout/font tokens, with the displayed value
  labelled geometric mean RMSSD. The info sheet explains the ln-domain calculation and SWC band.

- B3 wired: the Sleep screen now has Pre-sleep HR (default-off, Settings → Sleep) and Sleep
  heart-rate dip, each with 14/30-day observed-night trends and a shared method sheet.
  `Repository.sleepHeartRateHistory` selects primary sleep through the existing Sleep selector,
  reads raw pre-sleep samples only when enabled, and runs both engines off-main.
  Pre-sleep uses the 30 minutes before primary onset and prior observed nights; a card requires
  an observation and a usable comparison. Sleep dip compares complete five-minute epochs in primary
  sleep with the preceding primary-wake-to-bed interval, excluding every recorded nap. An interval
  over 24 hours has no contrast. Missing epochs stay nil; each side needs the engine's 30 valid epochs.
  The sleep window includes in-bed wake. Displayed coverage is observed epoch availability, not a claim
  about continuous recording. No diagnostic categories or scoring inputs added.
  Four `SleepHeartRateWindowsTests` pin missing epochs, partial boundaries, nap exclusion and short
  windows. Trend points are unconnected so gaps are never drawn as continuous observations.

## C. Loose ends

- C1 fixed: classic macOS `AutomationsView.strainTargetCard` now binds an "Above target" toggle to
  `BehaviorStore.strainTargetUpperNudge`. It requests notification permission and evaluates the
  target when enabled, matching the existing lower-target pattern. Section activity reflects either
  switch. Uses shared Strand design components and localized copy; no BLE commands changed.
- C3 checked: `338c282e`, already on the base, fixes the coach's mid-workout double count, zero lower
  strain target, past Energy summaries and SRI wake-label handling. The old report's remaining
  real-strap questions stay unverified. The legacy Rest formula (Rest v2 off) deliberately retains
  duration regularity; replacing that formula is a separate scoring change rather than a wiring fix.

- C2 partially completed, older backlog skipped for size under the small-item rule: translated this
  batch's 40 catalog keys (360 values) in all supported non-English locales: de, es, fr, it, pl,
  pt-PT, ru, zh-Hans, zh-Hant. This includes the upper-target toggle and method sheets. Preserved
  catalog ordering/formatting and printf argument signatures. The batch adds no un-extracted
  literals, focus-locale gaps, extra-locale gaps or English-only translation echoes.
  The previous branches still have about 230 missing catalog values per language, plus many
  un-extracted Broop strings. Translating roughly 2,000 locale values and reviewing physiology
  wording across nine languages is a dedicated localization batch, not a small wiring change.
  Options: (1, recommended) a separate translation pass scoped to those branches with native-speaker
  review of the longer method sheets; (2) translate one feature at a time. No translation baseline
  allowances were changed, and untouched watch/design catalogs were left alone.

## Bedtime readouts on demo data

These paths retain their base-branch arithmetic because A4 was deferred. Both columns use the same
captured synthetic fixture and the unchanged resolver paths; this is a code-verified comparison,
not a claim that two different app binaries were screenshotted. The screenshots are of this branch.

| Reader | Before | After | Meaning |
|---|---|---|---|
| Wind-down | 21:10 reminder, 07:00 wake | Same | 30 min before the planner bedtime on this fixture |
| Caffeine | 13:38 cutoff, 21:40 bedtime | Same | 95 mg reference coffee, shared tonight plan |
| Body clock | 22:04–05:20 | Same | Retrospective phase reference at last night's duration |
| Sleep screen planner | 21:40–07:00 | Same | Need 8:29, in-bed window 9:20, median-bedtime guard applied |
| Alarms planner | 21:40–07:00 | Same | Same published tonight plan |
| New jet-lag starting window | Hidden engine | 21:40–07:00 | Captured from that plan when the trip is saved |

The Body Clock also shows actual last-night timing, 23:21–06:37. That is a separate measured fact.
The old wind-down explanation truncates its window minutes: it says "9h 30m before" beside the
21:10 reminder, although the actual window plus lead is 9h 50m before 07:00. This inherited copy bug
is recorded with A4; the scheduled time was not changed. The loaded caffeine reader uses the plan,
but its 23:00 loading fallback remains another A4 follow-up.

## Verification

- `cd Packages/StrandAnalytics && swift test`: **2,192 tests, zero failures**. Includes the new
  doubled-TRIMP regression and the existing no-period-log luteal regression.
- `xcodegen generate` succeeded. Local Debug builds of **NOOPiOS** (iOS Simulator) and **Strand**
  (macOS) succeeded on the final code. Generated Xcode projects and build output are not committed.
- `xcodebuild ... -scheme Strand ... test` ran the nine new app tests: optical source (1), trip
  resolution/persistence (4), and sleep HR epoch windows (4). **Nine passed, zero failures**.
  The source regression was first run against the old mapping and failed before the fix.
- `Tools/doc_comment_lint.py`: passed, no new detached comments. `git diff d941f3c7 --check`: passed.
- `Tools/i18n_audit.py --ci d941f3c7`: **fails on inherited non-focus-locale gaps**. No new un-extracted
  literals, focus-locale gaps, format-signature regressions or English translation echoes from this
  batch. All 40 changed keys have translations in all nine non-English app locales (360 values).
- No Android/Kotlin, migrations or BLE command code changed. Production calculations run through
  Repository tasks and `CancellableAnalysis`; the live illness observation stays in an isolated
  equatable child. UI additions use existing Broop/Strand tokens and components.
- No live strap validation was performed. The last branch's hardware questions remain open.

Inherited audit failures are listed as missing values / allowance. The full log is in the artifact
folder. No allowance was raised to make this batch green.

| Catalog | it | pl | ru | zh-Hans | zh-Hant |
|---|---:|---:|---:|---:|---:|
| `NOOPWatch/Localizable.xcstrings` | 2 / 0 | 2 / 0 | 2 / 0 | 2 / 0 | 2 / 0 |
| `NOOPWatchComplications/Localizable.xcstrings` | 26 / 25 | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 |
| `Packages/StrandDesign/.../Localizable.xcstrings` | 58 / 32 | 26 / 0 | 27 / 1 | 26 / 0 | 26 / 0 |
| `Strand/Resources/Localizable.xcstrings` | 408 / 179 | 230 / 0 | 231 / 1 | 230 / 0 | 309 / 79 |

The requested older Healthspan/Stress/Mind and Energy/Strain/SRI translation work is therefore
**not complete**, and the repository-wide i18n gate does **not** pass. Watch and design catalogs
were not edited.

## Simulator and screenshots

Verification used a session-created iPhone 17 Pro simulator, `Broop-wiring-fixes`,
`3EF5ECD5-6B1C-47E4-B738-5DB40B40E8F1`. The existing "Broop iPhone 17 Pro" simulator was untouched.
The app was launched with `--demo-seed`; DEBUG screenshot entry points are stripped from Release.

The original demo contained no raw HR, and both new Sleep cards stayed hidden. The empty-store
seeder now adds 40 days of synthetic HR inputs, including pre-sleep samples, through `WhoopStore`.
It seeds no card result. Both production engines and the existing body-clock phase fit process
those inputs. This fixture gives pre-sleep HR 66 bpm (+0.7 versus prior nights) and sleep reduction
25.6% (wake 77, sleep 57). HRV readiness is 80 ms, usual band 72–86 ms.

Checked the 14/30-day switch and each method sheet, trip persistence across relaunch, and navigation
to the planner from the actual Sleep and Body Clock links. Settings → Sleep can disable Pre-sleep HR;
the card then disappears while Sleep dip remains. Missing-data cards were not replaced by a value.
The saved trip is Europe/Copenhagen → UTC+05:00 on 7 October; its three plan dates are 4–6 October.

macOS Automations was opened using the DEBUG `--demo-automations` entry point without seeding or
editing the Mac's data. Both target switches are visible. AeroSpace classified the existing main
window as `AXStandardWindow` under `TilingContainer`; window policy/configuration was unchanged.
Neighbor-frame resizing and close/reopen tiling acceptance were not measured in this content-only
change. The diagnostic and screenshot are saved.

Artifacts and logs are in `/Users/oliver/agent-runs/2026-09-30-wiring-fixes/`.

![Jet-lag planner](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/jet-lag-planner.png)

![HRV readiness](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/hrv-readiness.png)

![Both Sleep HR cards, 14 days](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/sleep-heart-rate-14-days.png)

![Sleep planner bedtime](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/bedtime-sleep-planner.png)

![Wind-down reminder](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/bedtime-wind-down.png)

![Caffeine and body-clock readouts](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/bedtime-caffeine-body-clock.png)

![macOS target toggles](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/mac-automations.png)

Additional evidence: [30-day trends](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/sleep-heart-rate-30-days.png),
[Sleep settings](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/settings-sleep.png),
[Pre-sleep disabled](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/sleep-pre-sleep-disabled.png),
[Alarms planner](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/bedtime-alarm-planner.png),
[Body clock on Sleep](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/bedtime-body-clock-on-sleep.png),
[jet-lag dates](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/jet-lag-days.png),
[jet-lag method](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/jet-lag-method.png),
[HRV method](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/hrv-readiness-method.png),
and [Sleep HR method](/Users/oliver/agent-runs/2026-09-30-wiring-fixes/sleep-heart-rate-method.png).
No TDEE screenshot exists because B4 was skipped for missing intake data.

## Commits and iPhone delivery

Each change is in its own commit; the planner/HRV visual corrections and DEBUG fixtures are separate
follow-ups. Every commit carries the requested iOS-only parity exception and co-author trailer.
The code ends at `f2f271a2`; a final documentation commit records this report. Nothing is pushed.

The final signed **Release** build succeeded for iPhone `00008140-001203D12402201C` using
`-allowProvisioningUpdates`. `xcrun devicectl device install app` succeeded, installing
`com.oliverbrunovsky.noop`. The install log and JSON result are in the artifact folder. The app was
not launched on the physical phone, and no real-data or strap behavior is claimed verified there.
The session-created simulator and temporary build directories were removed after evidence capture.
