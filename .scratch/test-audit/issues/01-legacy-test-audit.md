# Legacy code and test audit

Date: 2026-10-18. Starting revision: `3cb48871` on `main`, initially clean.
Status: audit complete. Changes remain uncommitted. Recovery-driver parity,
parity-governance authority and translation gates remain red.

## Removal standard

Repository reference searches, target manifests, current replacement paths and reachable history were
checked before removal. Scanner findings were treated as leads. An API used only by tests was retained
when it served as an oracle, test fixture, documented manual entrypoint or future export boundary.
The checkout is shallow at `12c74680fb7a82719851f178553709213567f28a`; provenance older than that
boundary could not be reconstructed. Public package cleanup establishes absence of consumers in this
repository, not in unknown external projects.

## Changes and evidence

- Removed the fixed `0.1.0` marker APIs from StrandAnalytics, StrandImport and StrandDesign, and the
  Kotlin StrandAnalytics marker. No application, CLI, manifest or stored-data reader used them. App
  versions come from `project.yml` and Gradle. Only their three literal version tests were removed.
  StrandDesign's substantive chart, palette and compatibility code remains. The analytics index was
  corrected. The misleadingly named design `PlaceholderTests.swift` still contains meaningful tests.
- Removed WhoopStore's two initial scaffold tests. `SELECT 42` adds no database coverage beyond the
  integration suites that migrate, write and read real stores. The version assertion is still covered
  by `MetricsCacheTests`, `LabMarkerStoreTests`, `SleepMotionStateTests` and `MigrationTests`.
  `WhoopStoreInfo.schemaVersion` remains because backups and diagnostics use it.
- Removed the unused `SleepView.nightOnsetIndex` duplicate walk. All eight onset-walk cases now execute
  `SleepModel.nightOnsetTs` with stored-session fixtures, including the real segment-array regression.
  Added empty-group and hand-corrected-onset cases. `SleepModel.mergeDay` uses that same production
  resolver. The per-fragment boundary tests and decoder assertions remain.
- Removed `DataBackup.writtenBackupIsIntact`, an unused Boolean wrapper, and its redundant test.
  Every real writer uses `verifyWrittenBackup` and distinguishes intact, torn and unreadable files.
  All eight verdict tests remain, including the unreadable-file case that prevents deletion of a good
  backup. The Android comment now names the live Swift verifier.
- Replaced Android's unused `HistoryHeal` predicates and private test-only `applyDelete` mirror with
  repository tests executing the exact production DAO SQL through SQLite. Coverage includes every raw
  table, both owner namespaces, inclusive boundaries, imported history, scoped window deletion and
  idempotence. The live pruning SQL was preserved.
- Removed four uncalled Python helpers: `parse_properties`, `parse_constants`, `_symbol_names` and
  `words_u32le`. The snapshot content parsers, symbol-owner resolver and actual response decoder remain.
  Original and edited scanners produced byte-identical stdout and structured results against an
  immutable archive of the starting revision: 309 findings, including 253 test-only reachability leads,
  and four scan errors. CLI stdout SHA-256 was
  `7e401b5e8754a143a0e029c12365163f37840c0201e997315c87b8b58a0479e9`.
- Fixed four macOS source-reference test failures by resolving the fixture's temporary root, matching
  the checker's existing canonical-path behavior. Exact diagnostic assertions remain.
- Moved two premature `unittest.main()` guards to the ends of their files. Direct execution now finds
  all 83 i18n tests and all 52 SpO2-validator tests, previously 42 and 10 respectively.
- Registered 23 omitted parity arity/artifact tests in governance CI and the unfiltered Python job.
  The registration guard requires every parity module and the source-reading modules in the appropriate
  jobs. Count diagnostics now acknowledge intentional test removals.
- Updated the obsolete R-R source contract to follow the fresh-data path introduced by `fcf5c3d7`.
  It still forbids passing the protected persistence copy into downstream derivations. It now follows
  the fitness-age overlay and weekly Healthspan forwarding. Four mutations dropping or replacing
  those fresh-data handoffs were rejected.
- Fixed three live Broop motion-gating defects without changing the census assertions. The voice orb
  removes its timeline outside active thinking and uses a static frame under the shared motion gate.
  Both pairing pulses now respect Reduce Motion, Low Power Mode and the app's quiet-motion setting.
  Changed UI uses existing tokens. The same five motion census tests now also compile into StrandTests,
  so the app workflow checks app-only changes to every scanned UI root. Independent review found that
  the old census accepted a file-wide monitor token without checking each branch. Four additional
  scoped source tests now pin the three repaired branches and the static voice renderer, rejecting
  ten in-memory guard/monitor/timeline mutations. These checks establish source wiring, not runtime
  rendering or power consumption.

## Genuine timestamp-healing bug

The new repository tests exposed an Android/Swift disagreement. Android derived the minimum day in the
phone's local zone, while Swift uses UTC. `1700000000` falls on November 14 in UTC and November 15 in
Tokyo. The old Android path could delete a computed November 14 row that Swift retains.

A regression exercises the live Android repository across time zones. Expected vectors came verbatim
from a standalone Swift oracle, with matching Swift store integration tests and literal vectors. The
Swift tests were also run in separate UTC+14 and UTC-11 processes. Android now derives only the
minimum sentinel day in UTC; the upper `today` bound stays local. The live regression catches both
eastward over-deletion and westward retention. All six new repository regressions pass after the fix.

## Additional failures investigated

Two Android recovery-driver tests assumed a particular HRV-only fixture produced an exact `-0.5`
marginal on both runtimes. Darwin and JVM produced neutral scores one ULP apart; the JVM marginal was
`-0.4999999999999929`. A bounded differential search found a common, moderate-score fixture. Both
platforms now assert full `68.855940620972248`, neutral `69.355940620972248`, exact marginal `-0.5`,
and driver points `-1`. Below/above brackets, full HRV/RHR driver fields, unchanged score, and the
omitted eighth argument are preserved. No epsilon, widened tolerance, scorer change or new rounding
helper was introduced. This repairs the exact-tie fixture, but does not resolve the original input's
cross-platform defect: Swift emits a `-1` HRV driver while JDK 17 emits `0`. The original input is
retained in a separate Swift regression and an unignored Kotlin test against the Swift oracle. That
test must stay red until the scorer produces the same result. No platform-specific expectation,
assertion suppression or score-changing epsilon was added. A deterministic cross-platform numerical
fix remains a blocker; changing physiological scoring needs broader input validation.

An ordinary incremental Android build then lost Room's schema export. A one-second reproduction made
a harmless comment edit to a non-entity source, ran main KSP alone, and found zero schema JSON files
despite task success. The main processor skipped the unchanged database after its declared export was
cleared. This independently rules out a unit-test KSP race as the cause of this instance.

`ksp.incremental=false` makes a KSP execution process the full symbol set and regenerate the real
export. The same probe then produced its JSON in three seconds. Gradle caching, task up-to-date checks
and normal Kotlin incremental compilation remain enabled. This trades annotation-processing speed
for a reliable schema oracle; a future Room export integration could restore incremental KSP after
proving this scenario. The probe restored source bytes in `finally` and left no debug tags.
See [KSP's documented switch](https://kotlinlang.org/docs/ksp-incremental.html) and
[Room's schema argument guidance](https://developer.android.com/training/data-storage/room/migrating-db-versions#export-schemas).

## Verification

Results below preserve the completed runs. Raw logs, detailed sub-audits and probe scripts were
removed at the user's subsequent cleanup request. Log filenames below identify historical runs;
they are no longer retained files. Regression inputs and expected values remain in repository tests.

- macOS application: final regenerated-project run passed 2,448 tests, with 2 skipped and no failures.
  The sleep-onset migration, backup-wrapper removal and all 9 motion checks were included.
  Skips cover iOS-only file protection and an unavailable real Xiaomi database.
- Swift packages and tools: all passed. WhoopProtocol 816 tests (1 corpus skip), OuraProtocol 267,
  PolarProtocol 25, WhoopStore 648, StrandAnalytics 2,280, StrandImport 332 (1 real-database skip),
  StrandDesign 138, NoopLocalAccess 14, SleepBench 13 and SleepPSG 33. Total: 4,566 tests across
  the eight package suites and two tool suites. Backfill builds successfully. TimestampHeal's 9 tests
  also passed in both UTC+14 and UTC-11 processes. The focused motion check reproduced 2 failures
  before repair and passed afterward. One initial store build used a plan made before scaffold deletion
  and failed on that missing input file; the final stable-source run passed all 648 tests.
  The full Analytics run preceded the final fixture edits and added parity regression; afterward,
  all 20 current `ChargeDriversTests` passed, including the original-input Swift oracle regression.
- Python core: 153 passed, preserving the pre-fix count. Capture: 234 tests, 1 real-database skip.
  The 23 omitted parity tests pass. The repaired R-R contract passes both tests and rejects four
  fresh-data-flow mutations. Final governance: 185 tests, 2 existing source/authority failures.
- `python3 Tools/doc_comment_lint.py`: passed.
- `git diff --check`: passed on the final changes.
- iOS: `NOOPiOS` simulator build passed for arm64 and x86_64 with signing disabled.
- Android: current JDK 17 command,
  `./gradlew testFullDebugUnitTest compileFullDebugKotlin --no-build-cache`, compiled successfully
  and ran 6,731 tests: 1 failure, 0 errors and 6 optional-fixture skips. The sole failure is
  `originalHrvOnlyInputMatchesSwiftScoreAndDriverOracle`. SchemaOracle 4/4, repository pruning 6/6,
  local-day 8/8 and the other 17 recovery tests pass. Both the schema export and oracle snapshot
  retained their real JSON. Logs: `android-final-visible-parity.log` and
  `android-final-test-summary.json`.
  Before adding that dedicated parity regression, the 6,730-test run passed in 18 seconds; its
  unchanged repeat passed in 507 ms with KSP, schema sync and tests up-to-date. These historical
  checks establish the export repair, not final suite success. The initial forced full run had
  3 failures: the new timezone regression and two original recovery assertions. The timestamp bug
  and exact-tie fixtures were repaired; the original numerical disagreement remains visible.

## Existing blockers

- The original recovery input (`hrvMs = 29.99117725828923`, RHR 60, HRV baseline 30/spread 0.55,
  no RHR baseline) produces different HRV driver points: Swift `-1`, JDK 17 `0`. The inputs and
  production scorer are unchanged from the starting revision. A separate, unignored Kotlin oracle
  regression preserves this failure; a portable exact-tie fixture also preserves the rounding tests.
  Swift's full score is `57.432425214874954` and neutral is `57.932425214874954`. JVM full matches,
  but neutral is one ULP lower, changing the marginal from `-0.5` to `-0.4999999999999929` and the
  displayed driver from `-1`/limiting to `0`/at baseline. The linked package oracle and complete row
  expectation remain in the regression tests. Swift full/neutral/marginal bits are respectively
  `404cb759b59ded46`, `404cf759b59ded46` and `bfe0000000000000`. A deterministic numerical implementation and broader
  cross-platform score validation are still needed.
- The original scanner against immutable starting HEAD returns four stale twin-reference errors:
  `WorkoutEditing.suggestedClassRes`, two former `Repository.vitalityDays` signatures, and
  `VitalityWindowTests`. The original recorded inventory is also stale: files 510 versus 525,
  functions 4538 versus 4730, properties 488 versus 518, constants 2001 versus 2203.
  `python3 Tools/parity_ledger.py --refresh-derived --base HEAD` rejects the scan and leaves both
  snapshots unchanged. No authority migration, baseline waiver or assertion suppression was used.
  A final ordinary scanner run still reports exactly those four twin errors.
- `python3 Tools/i18n_audit.py --ci HEAD` reports existing missing-translation allowances across Apple
  catalogs and Android Italian strings. The flagged catalogs are byte-identical to starting HEAD;
  that comparison was recorded before the raw cleanup. No translation baseline was raised.
- Native Windows, real-strap behavior and real-database optional integrations were not exercised.
  No connection or command-sending behavior changed. Android Emulator is unavailable on this host;
  JVM checks do not require it. Live iOS motion toggles and power consumption were not measured;
  the motion fixes were verified through source regression checks and both app builds.

## Retained candidates and follow-up work

- `WhoopStoreInfo.schemaVersion` exports 18 although migrations extend beyond that. This is documented
  existing provenance debt with live backup and diagnostic readers. Changing the exported contract
  requires a separate storage/provenance change; it is not dead code.
- `primarySessionRestingHR` and `primarySessionRestingHRCoverage` look superseded by the combined
  `primarySessionRestingHRWithCoverage`; migrate their useful cases on both platforms before removal.
- `AnalyzeRecentDayCache.cacheKey` and `StepsMotionCache.cacheKey` appear superseded by revision-based
  app keys. Their containing types still have live APIs; compare old invalidation tests with
  `IntelligenceCheckpointIntegrationTests` before changing them.
- Android `WorkoutEditing.sameActivity` feeds a 2,000-input naive oracle for the optimized dedup walk.
  It was retained. Classic Today, Liquid Today, migrations, legacy import compatibility, RawOutbox's
  export support, parser fixtures and documented manual research tools were also retained.
- Other test-only helpers, including launch-day and journal catalog wrappers, need replacement-path
  coverage analysis before removal. A reference count alone does not establish obsolescence.

## Cleanup after the audit

The user requested removal of disposable audit artifacts on 2026-10-18. Removed the audit's
`~/agent-runs/2026-10-18-noop-test-audit/` directory, raw logs, probes, generated Xcode project
contents, NOOP DerivedData, Android app build output, all eleven package/tool `.build` directories
created by this audit, four Python bytecode directories and the audit Gradle daemon log.

Also removed six synthetic NoopLocalAccess database directories, 26 Python database fixture
directories, four CSV fixture directories, two synthetic ZIPs, two PacketLogger fixtures, four
SQLite sidecars, 23 project-specific Swift package locks, four oracle linker temporary directories,
9,022 generated Swift source files and two staging-app window-state/scratch directories. Test
fixture contents and creation times were matched to the test sources and completed audit runs.
The audit's Gradle and Kotlin daemons were stopped. No other project process was stopped.

The selected files accounted for 10,261,553,152 allocated bytes. Available space increased from
568,666,080 KiB to 576,806,560 KiB, an observed gain of 8,335,851,520 bytes (8.34 GB). File allocation
and filesystem free-space changes differ because of shared storage and concurrent system activity.

Verification preserved the complete tracked source diff and the new SQLite regression source by
SHA-256 comparison. The generated Xcode project contained one tracked exception,
`Strand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; verification caught
its removal and it was restored byte-for-byte from the unchanged index. Its parent directories
remain solely to hold that lockfile. No dependency lockfile changes remain.

The audit ticket, implementation, regression expectations, older project Gradle cache, installed
toolchains, pre-existing Xcode package user settings, unrelated worktrees and shared caches remain.
The prior `/tmp/agents/01a14f24-5bf5-7403-91ba-ccd79fec48da/` session had already been removed.
The cleanup's own temporary manifest was also deleted. All selected disposable paths were verified
absent, apart from the restored lockfile's parent directory. No builds were rerun after cleanup,
so verification did not recreate their output.

## iPhone redeployment

Requested after cleanup on 2026-10-18. The current source was built with `NOOPiOS`, Release,
`generic/platform=iOS`, the existing local signing configuration and automatic provisioning.
The ordinary diagnostic build completed with `BUILD SUCCEEDED`. Main app, widgets, watch app and
watch complications are included. `codesign --verify --deep --strict` passes, and the embedded
provisioning profile includes the paired iPhone and expires on 2027-10-01.

Redeployment completed over paired Wi-Fi. Broop / NOOP 12.1.0 (436), bundle ID
`com.oliverbrunovsky.noop`, was installed from `build/iphone-deploy/NOOP.app` over the existing app.
CoreDevice initially returned error 4016 while the iPhone 16 Pro was unavailable. After the user
confirmed that the phone was unlocked on the same Wi-Fi, discovery succeeded and installation
completed without uninstalling the app or resetting its data.

`devicectl device process launch` succeeded. The post-install app query confirms version 12.1.0,
build 436. A subsequent process query found the main app (PID 19435) and widget (PID 19428) running
from the new installation's bundle path. This verifies installation and launch, not live strap
behavior or the complete UI flows.

Build intermediates, temporary deployment logs, generated Swift source files and the prepared app
bundle were removed after verification. The generated Xcode project remains for the existing
personal refresh job. The tracked source diff is unchanged; no application source, dependency
lockfile or signing configuration was changed during deployment. No deployment work remains.
