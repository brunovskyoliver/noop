# Android Broop account, insights and onboarding

## Implemented

- Added the Broop More profile summary, score-qualified streak and every iOS menu group. Rows navigate to real app destinations.
- Added App Settings with profile, heart-rate zones, units, appearance, Sleep, features, strap/sync, backup/export, storage, scoring, experimental and About pages.
- Existing settings cards are filtered into their actual sections. Their profile writes, BLE permission gates, import/export/restore handlers, diagnostics and confirmation dialogs are reused. The HR zones editor and database-storage readout use native Broop pages.
- Added an integrations hub. Health Connect replaces HealthKit. Mi Band opens its real Mi Fitness import. Apple Shortcuts/Siri pages explain the platform difference and link to the supported Health Connect, export and on-device automation actions. No unsupported button claims to run an Apple shortcut.
- Added the classic-interface switch and the Broop return switch in classic Appearance settings.
- Added a native journal page, including numeric answers, custom questions, renaming, grouping, question kinds, hiding/restoring, a bounded date picker, resume refresh and storage errors. Reading the page never copies yesterday's answers into today's database rows. Writes use the existing native journal source and leave imported rows alone.
- Kept lag-aware ranked effects, dose curves and forecasts in the existing InsightsHub model. Its Broop host uses the shared Broop page. Mover cards now open a detail dialog. Imported metricSeries take precedence over DailyMetric fallbacks as in Swift, and sleep efficiency is no longer substituted for the Rest score.
- Rebuilt onboarding's header, progress, welcome, typography and primary button for Broop. The same twelve actual steps still own Bluetooth/notification permissions, scanning, bonding, profile persistence, imports and appearance. Android skips the paired-success page when no strap bonded.

## Verification

- Read the Swift Broop router, More, account routes/settings, insights hub/journal and Final B onboarding against their Android counterparts.
- Parsed all XML resources and checked that every new R.string reference resolves.
- Parent owns the full Gradle build, unit suite and emulator verification. No independent Gradle process was started by this subagent.
- New UI uses BroopPalette/BroopMetrics/BroopType and the existing shared settings controls. No new BLE command, migration, network service or telemetry was added.

## BroopScreen route inventory

| iOS BroopScreen | Android destination |
| --- | --- |
| sleep | sleep |
| fullDayChart | full_day_chart |
| coupled | coupled_view |
| workouts | workouts |
| live | live |
| liftLog | lift_log |
| breathe | breathe |
| intervals | intervals |
| health | health_hub, with health monitor under health |
| stress | stress |
| labBook | lab_book |
| rhythm | rhythm |
| metricExplorer | explore |
| trends | trends |
| hydration | hydration |
| compare | compare |
| healthspan | healthspan |
| mind | mind |
| energy | energy |
| jetLag | jet_lag |
| metric(key, source) | vital_detail/{key}; source-specific rendering remains the existing Android metric screen |
| journal | insights, with journal_insights for experiments/activity costs/relationships |
| insightsHub | insights_hub |
| intelligence | intelligence |
| fusedRecord | fused_record |
| coach | coach |
| alarms | smart_alarm |
| settings | settings, account/{section} |
| devices | devices |
| appleHealth | apple_health (Health Connect integration and Apple Health file import) |
| miBand | account/mi_band, then the real Xiaomi Mi Band importer in data_sources |
| dataSources | data_sources |
| backupSync | backup_sync |
| shortcutsExport | account/shortcuts_export (Health Connect/CSV equivalent) |
| noopLimitations | noop_limitations |
| automations | automations |
| siriShortcuts | account/android_shortcuts (explicit Apple-only limitation, supported Android actions) |
| powerSaving | power_saving |
| testCentre | test_centre |
| classicToday | classic_today |

## Remaining limits

- Existing profile/appearance/scoring/export/diagnostics editors and several insights cards are reused under Broop design tokens. They retain Android control layouts rather than copying the Swift layouts pixel for pixel.
- Apple Shortcuts, Siri, HealthKit, Apple Intelligence and Live Activities have platform-specific implementations. Android uses its existing local coach/Health Connect/foreground-service paths; it does not claim Apple frameworks exist on Android.
- Android supports user-pinned launcher shortcuts for Sync, Buzz and Mark. Siri and Apple Shortcuts remain platform-specific.
- Strap connection, pairing, alarms and sync still require real-hardware verification. No hardware validation has been claimed.
- The `journal_insights` destination retains the existing full InsightsScreen for experiments, activity costs and metric relationships.

## Healthspan backend parity

- Ported the current Swift nine-factor Healthspan model to Kotlin: the 10-year logarithmic hazard scale, overlap adjustments, 18–100 age bounds, measured VO₂ preference, lean-mass source precedence and carry window, 180/30-day windows, Sunday updates and 21-of-31 recovery gate. HRV is not a factor in this model.
- Added shared repository reads for finished Lift Log sessions and Healthspan history, snapshots and weekly metric rows. The snapshot serves the headline, age delta, factor breakdown and trend with one result and one age clock; old Saturday rows are omitted from the Sunday trend.
- The source reader uses real workout zones, strength duration, natural-key lift/workout deduplication, the shared steps resolver, imported sleep consistency or seven-day SRI, and dated body measurements. Health Connect supplies Android body measurements alongside existing Apple Health imports.
- Replaced obsolete v1 Android tests with v2 expectations. `HealthspanV2ParityTest` compares literal stdout, formatted to nine decimal places, from the current compiled Swift sources across 4,185 curve cases, result scenarios, window/gate/carry boundaries, Sunday keys, strength names and zone JSON. The durable Swift driver is checked in under Android test resources. Swift has a matching curve-oracle test so the contract is pinned in both directions.
- Standalone Kotlin/JUnit validation passed all 11 Healthspan tests against production Engine/Window code. Standalone native XCTest validation passed all 21 Swift HealthspanV2Tests against the production Swift twins. These were focused standalone builds, not a claim that the full Swift package or app suite ran.
- Swift production changes in this scope are comments removing the now-obsolete claim of intentional Android divergence and splitting two comma-separated StrainTarget constant declarations for complete inventory. The existing Swift formula and values were not altered.

## Scoring settings and history refresh

- Added the exact `noop.strainTargetGoal` restore/maintain/build choices, default-on `noop.restV2Enabled`, and default-on `noop.showEnergy` presentation toggle to Scoring. Each has translated German, Spanish, French and European Portuguese copy.
- Changing Rest mode now synchronously rearms the one-shot backfill flag and recomputes up to 4,000 history days with the same scoring preferences as ordinary edits. Cached-only days remain protected. A changed mode, failed pass or cancellation cannot mark the history complete; the next launch can retry. Startup repair also checks the captured mode before completing the flag.
- Four focused JVM tests passed for persistence ordering, mode changes during a pass, failed/skipped work and cancellation. The parent owns final whole-app Gradle validation.

## Localization verification

- Extracted all new account, More, onboarding, shared shell/back semantics and Stress Monitor copy. All 150 account/shell strings have German, Spanish, French and European Portuguese resources. Format-placeholder checks passed. Also supplied 77 body-feature translations per focus locale to the body-screen owner.
- `python3 Tools/i18n_audit.py --ci HEAD` reports no new Android literals, all focus-locale coverage passing, no new English-only translations and no resource whitespace or concatenation violations. The command remains red only for pre-existing out-of-focus Apple locale debt (it/pl/ru/zh-Hans/zh-Hant) and 45 existing Android Italian gaps; these unrelated catalogues were not changed.
- `git diff --check` passed. The parent records final APK, emulator and whole-suite results in the shared port report.

## Final review and governance

- Reviewed the Broop route shell, account destinations, theme, metric-only persistence and scoring-job cancellation against Swift. Parent corrected Back tab highlighting and the HRmax editor's upper bound. Account platform-equivalence pages disclose unsupported Apple Shortcuts/Siri instead of presenting inactive actions.
- Exact attached twin claims now name the current Swift selectors for the new shared analytics and repository helpers. Corrected the stale WorkoutEditing label reference and moved the Healthspan reader claim to the real repository helper. Removed an unused Result convenience lookup and reused the existing canonical date formatter.
- Added 68 individually reviewed typed dispositions for Android Room/cache/serialization adapters and role twins in excluded Swift app-layer files. No disposition waives shared math, stored values, an existing twin removal or a test-only feature. The live Activity strain coach now uses the target-zone and time-to-target helpers.
- The numeric-constant scanner resolves declared literal references without executing source. Cycles and ambiguity remain unverifiable. Exact excluded Swift extension filenames containing `+` now validate, while traversal and missing files remain rejected. All 77 focused scanner/disposition tests pass.
- No existing function, property or constant twin pair was removed in the refreshed semantic inventory. Final guarded regeneration and whole-suite results are recorded below when complete.

## Final verification results

- `python3 Tools/parity_ledger.py --refresh-derived --migrate-authority --base HEAD` passed and published the compact v3 source inventory/baseline with 280 known findings. The exact task-start HEAD already had stale authority; migration independently rescanned that tree and still required all new identities to be paired or individually dispositioned. Existing counters did not increase relative to the freshly derived base.
- `python3 -m unittest discover -s Tools -p 'test*.py'` passed all 341 tests in 78.914 seconds, including repository source-authority acceptance.
- `python3 Tools/doc_comment_lint.py` passed (no new detached doc comments) and `git diff --check` passed.
- Final APK, Android unit and emulator checks remain owned by the parent agent. The unrelated existing RecoveryDrivers test has a diagnosed Swift Darwin libm versus Java exp one-ULP boundary discrepancy; no production formula was changed to mask it in this scope.

## Android launcher actions

- Replaced the limitation-only Android shortcuts page with three real `ShortcutManager` pin actions for Sync, Buzz and Mark. Each uses a stable id and explicit MainActivity intent. The launcher asks the user to confirm pinning; creating a shortcut never executes it. Unsupported launchers get a direct explanation and disabled pin controls.
- MainActivity consumes each payload before posting it to a process-local queue, both on cold launch and onNewIntent. Rotation/recomposition cannot replay the same payload. The shared root consumes after terms/onboarding, so actions also work in classic mode. Sync/Buzz use the existing connected-strap funnels; Mark uses the existing timestamped strap-log marker and confirming cue. No BLE command, receiver, manifest permission, dependency or network integration was added.
- Added four focused Robolectric tests for explicit intent/stable id/flag mapping, one-shot consumption, unknown intent rejection and exact action dispatch. Parent owns their Gradle execution. All 15 new visible strings have German, Spanish, French and European Portuguese translations.
- Followed the official [Android pinned-shortcut API guidance](https://developer.android.com/develop/ui/compose/system/shortcuts/creating-shortcuts). No Google Shortcuts integration library is used.

- Final `python3 Tools/parity_ledger.py --base HEAD` passed with 280 baselined findings, all 1,256 declared references resolved, 771 constant pairs and unchanged freshly derived counters (dayString 15, resting-HR 1, Android UI Pearson 4).
- Final `python3 Tools/parity_ratchet.py --base HEAD --offline --migrate-authority` passed with zero errors. Its remaining warnings explain the already-stale task-start base and two inherited dispositions rendered obsolete by the completed twins; they cannot authorize future reintroduction.
- Repeated the complete Python Tools suite after the final row adapters: 341 tests passed in 78.914 seconds. Final native Android checks, including the four shortcut tests and parent-authored eleven-step unpaired onboarding flow, are recorded by the parent.

- After the final overview format extraction, the i18n gate reports no new Android literals, no focus-locale gaps, no new English-only translations, and no whitespace/concatenation violations. Its only failures remain the inherited out-of-focus Apple catalogues and 45 Android Italian gaps.
- Oracle precision is explicit: Healthspan comparison pins the Swift-generated nine-decimal output, not every raw Double bit. The pre-existing RecoveryDrivers boundary demonstrates an independent native libm portability difference; no exhaustive bitwise-parity claim is made.

## Final parent integration

Full and Demo APK builds passed. The final complete JVM suite has 6,784 passing tests, six skipped and one unchanged RecoveryDrivers oracle failure; all new port tests pass. All six emulator tests passed, rendering 68 destinations and completing historical score navigation, chart gestures, strength persistence/history and unpaired onboarding. Seven representative pages also passed at 360 dp with 130% text. See [01-port.md](01-port.md) for commands, evidence and hardware limits.
