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

## Verification and remaining work

In progress. Final test counts, builds, screenshots, demo bedtime values and device installation are
recorded below when verified.

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
- B4 skipped: `HealthKitBridge.readTypes` and `collect` import weight and active/basal calories burned,
  but no `dietaryEnergyConsumed` or daily calorie intake. Burned energy cannot replace intake in
  `AdaptiveExpenditureEngine`. No food logging or Health permission added.
