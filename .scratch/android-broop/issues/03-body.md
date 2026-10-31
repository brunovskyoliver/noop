# Android Broop Health, Mind, Energy, Activity and strength

## Changes

- Added the Broop Health hub with real live heart rate, the canonical Healthspan snapshot, Health Monitor, shared live/latest Stress, Energy, Mind, HRV, fitness, body tools and trend/source destinations. Existing native workout, live activity, intervals and breathing flows remain reachable.
- Added Healthspan details using one `healthspanSnapshot` for the headline, trend, age delta, nine factor contributions, Sunday update and recovery-data gate. The account agent owns the exact nine-factor backend and its verification.
- Ported the current Swift Energy reservoir and Mind engines. Energy keeps the exact state rates, heart-zone activity drain, prior-day carry, calibration gate, projection cap, stored rounding and ten stored metric keys. Mind keeps the daytime-data gates, 14/31-day windows, trend, PSS-4/GAD-2/PHQ-2 scoring, 28-day check-in cadence and paired correlations.
- Home, Health and Energy use the same `rememberBroopEnergyDay` and reusable `BroopEnergyCard`. It reads selected-day resting HR from all merged history, carries the previous day's stored Energy with imported fallback, uses the shared Stress live sampler and invalidates after history sync. A retained historical summary never acquires a chart from a materially different recomputation. New dates and straps clear the previous load before rendering numbers.
- Added the Mind details, monthly eight-question check-in, batch save, retry, history/delete and correlations. Rest inputs use the same resolved-series source precedence as Home.
- Added the persisted Jet Lag planner with origin zone, travel date, 15-minute destination-offset picker and dated bright-light, dim-light, sleep and wake guidance. It calls the existing Circadian engine and never changes an alarm.
- Added the live Strain Coach to Activity, Live and the active workout overlay. It scores the raw day window only before the workout, adds the live workout TRIMP and applies the stored-day floor once, avoiding double counting. Target debt, RHR, Charge and alert inputs share the existing resolvers. Minutes-to-target uses actual heart rate and appears only for Edwards scoring; insufficient or failed reads remain absent.
- Added Activity summary and recent workout navigation from actual local sessions. Added native strength programs, program editing/reordering, target sets/reps/range/weight/RPE/rest/notes, exercise muscle assignment, confirmed archival, history, set edits/deletion, notes/session RPE, volume and fractional muscle-set summaries.
- Added bounded CSV/XLSX program import with native file selection, preview and warnings before writing. CSV header aliases, numeric parsing, grouping and muscles match Swift. XLSX handles workbook tab order, shared/rich/inline strings, sparse references and cached formula values. XML external entities are disabled. No new dependency or network service was introduced.
- Added the exact Swift Lift session state machine and finish/program rules. Planned sets form an editable sheet: any slot can start or redo, progression stays on the current exercise before returning to skipped work, set counts can change, new exercises can be added, and undo restores the whole stage/plan/record snapshot. Weight/reps carry from earlier session sets, prior sessions and program targets. Typed pending values and warmups survive minimising and process death.
- Added a ViewModel-lifetime Lift controller, shared mini bar and direct resume route. Rest uses absolute end seconds, native countdown notifications and durable AlarmManager warning/end alarms. The existing strap DOUBLE_TAP stream advances the same controller, with Swift's five-second knock filter and existing reversible haptic command. Warning claims are persisted and stale session/device/rest alarms are ignored. Exact-alarm grants are reused; Android's inexact idle alarm fallback is used when the grant is absent.
- Finishing explicitly asks whether to complete or discard unstarted slots and whether to keep added exercises/changed counts in the program. Completed sets preserve completion order and measured timing; unstarted sets have no invented timing. Heaviest performed working sets update the program's weight/reps by Swift's rule. Final sets, program changes, session and paired manual workout are written in one SQLite transaction. Discarding every unperformed slot writes no session or workout. Save failures retain the live state for retry.
- Added 344 body resources in English, German, Spanish, French and European Portuguese. UI uses shared Broop palette, typography and spacing tokens. Source IDs, preference keys, metric names and file MIME types remain stable protocol literals.

## Verification

- Compiled and ran the actual Swift Energy, Mind, check-in, Correlation and Circadian sources standalone with `swiftc -O`; Kotlin tests contain the literal stdout across Energy state/rate/clamp cases, a full day, stored values, live cap, all 625 PSS-4 answer combinations, Mind gates/windows/trends/correlations and travel/DST cases.
- Compiled the actual Swift CSV program importer and compared its literal output for grouping, aliases, numeric rounding, muscle normalization and warnings. Added XLSX and size/empty-input coverage.
- Compiled the actual current Swift LiftSessionEngine and extracted pure controller finish/program/gesture/timer methods with `swiftc -O`. `LiftSessionParityOracleTest` contains verbatim stdout for occupied-machine progression, carry, edit/redo/undo, measured rest, finish, program updates, knock boundaries and rest event times. The reproducible driver is `android/app/src/test/resources/broop_lift_session_oracle.py`.
- Added real in-memory Room tests for session/set persistence, isolated straps, immutable muscle snapshots, paired workout keys, deletion ordering, program import/archive, final slot order, discarded-slot timing, heaviest-set program updates and no-workout empty finish.
- Added snapshot and native-notification tests for process restart, absolute rest timing, pending values/warmups, empty free warmup, corrupt input, future stage fallback, stale alarm rejection and a rest-ready receiver with no controller process.
- Independently reviewed the parent's metric-only scoring persistence. Added three real Room integration tests covering preservation of daily scores/provenance/unrelated metrics, clearing invalidated Stress/Energy keys on an explicit empty day and rollback of earlier writes when a later waking-only write fails. All three passed in the parent's Gradle run.
- Parent Gradle runs passed the Energy/Mind/travel oracle tests 2/2, importer tests 3/3, Lift state/finish oracle tests 3/3, expanded real Room Lift store tests 6/6 and scoring persistence tests 3/3. All four snapshot/receiver tests passed after enabling Gradle Android test resources; the receiver assertion uses the actual localized notification resources. The expanded Lift store suite now also covers prior-set carry beyond the UI history cap and discarded-set/source isolation. The parent owns the final whole-app compile, full unit suite and device-flow results.
- Body resource XML parses, all 344 focus-locale key sets and positional format arguments agree, the hardcoded-UI-text scan reports zero body findings, and `git diff --check` passes. No concurrent Gradle process was started by this subagent.

## Platform limits and final checks

- This work adds no destructive BLE command. Physical strap gestures, haptic timing, pairing and background BLE behavior require real-hardware validation; this subagent has not claimed a strap test.
- Android's OS can delay inexact alarms when exact-alarm access is absent. Running-process countdowns retain their absolute end time; the durable receiver validates the same stored rest when it is delivered. Force-stop behavior follows Android's alarm rules.
- Active-session snapshot JSON uses the Swift plan/stage/set/pending-input field shape plus Android-local session/device identity and a durable warning claim. It is not added to the cross-platform backup settings whitelist. Canonical completed Lift tables and paired workout records use the existing shared schema.
- Native Compose controls/charts differ visually from SwiftUI; behavior and source data are the parity boundary. Parent device verification should exercise a free session, planned out-of-order session, pending numeric edits, rest/undo, resume, finish choices, and import preview in addition to all new routes.

## Instrumented strength flow

- Added `BroopLiftFlowTest` using the real `NoopApplication`, `AppViewModel`, Broop router and canonical SQLite store. It follows the existing optional `broop.seed=true` fixture setup.
- The test starts a free session through the UI, adds an exercise, edits weight/reps, starts and completes a set, undoes completion, edits again and completes into rest. It adds an unstarted slot, chooses to discard that slot in the finish sheet, saves session RPE/notes and reopens the history entry.
- Assertions inspect the actual stored session and both set rows, including the performed numbers, measured timestamps/rest and the discarded slot's zero values with absent timing. The paired manual workout must occur exactly once before and after reopening, with no invented strain or heart rate.
- Added stable semantics tags only where nested dialogs otherwise share button labels. Removed the unused coroutine scope from the active-session view; the finish sheet retains its used scope.
- `git diff --check` passed. The parent owns compilation and emulator execution of this new instrumentation test; this subagent did not start Gradle or an emulator.


## Strength device-test follow-up

- The parent device run completed the UI save and passed every SQLite assertion, including exact performed/discarded values and one paired workout. History reopening then failed its text selector.
- History exercise names render through `BroopCaps`, so the UI contains uppercase text. Fixed the selector to ignore case and wait for the actual exercise row rather than the static Logged sets heading. Added an explicit visible assertion for the saved 42.5 kg × 8 value after reopening.
- No history rendering change was needed. `git diff --check` passed; the parent owns the device rerun.


## Populated-route presentation follow-up

- The parent's populated route run exposed the classic liquid vessel frame loop in the reused workout hero. Broop now renders `LiquidVessel` as a static shared-token ring, `LiquidTube` as a static shared-token bar and `LiquidThread` as the existing curve at a fixed phase. Broop takes these branches before motion acquisition or frame-clock setup.
- Explicit vessel tap callbacks remain clickable; a vessel with no callback leaves its parent click target available. Classic mode retains the existing animated and reduced-motion branches.
- Broop's shared screen backdrop slot and full-bleed resolver now always select the Broop gradient, including direct LiquidScreenSky hosts. Legacy custom images and day-cycle skies keep their existing precedence in classic mode.
- `git diff --check` passed. The parent owns rebuilding and rerunning the populated route pass; no test animation setting was changed.

## Final parent integration

Full and Demo APK builds passed. The final complete JVM suite has 6,784 passing tests, six skipped and one unchanged RecoveryDrivers oracle failure; all new port tests pass. All six emulator tests passed, rendering 68 destinations and completing historical score navigation, chart gestures, strength persistence/history and unpaired onboarding. Seven representative pages also passed at 360 dp with 130% text. See [01-port.md](01-port.md) for commands, evidence and hardware limits.
