# Android Broop port

## Request

Rebuild the Android app to match the current Swift iOS Broop app, divide implementation between subagents, and verify the complete port.

## Implementation

- Broop is the default Android shell, with Home, Health, More, quick actions, matching dark design tokens, branding and launcher icon. The existing application IDs, local database and classic-screen access remain compatible. Demo builds carry a visible DEMO badge.
- Every `BroopScreen` destination in the Swift router has an Android route. Apple-only integrations have explicit Android equivalents. `Tools/test_android_broop_routes.py` checks the actual Swift enum against registered Android routes and emulator-test cases.
- Overview, sleep, score details, activity, strength training, Healthspan, Stress, Energy, Mind, Jet Lag, journal, insights, account settings and onboarding have Android implementations over local data. Native Android editors and integrations are retained where they supply the corresponding behavior.
- Coupled and Full Day Chart have dedicated Broop pages. The timeline shares the selected day, shows sleep/workout bands and Charge/Effort annotations, and supports hold-to-read, pinch, pan and reset. Coupled uses its own today-only state and the current Rest input for Charge attribution.
- Strength training includes program import/editing, set inputs and carry, start/complete/undo/rest, finish choices, session history, an app-wide running-session bar, crash restoration and rest notifications. Completed sets, program changes and the paired workout commit together without inventing HR or strain.
- Android launcher shortcuts perform Sync, Buzz and Mark a Moment through the existing actions, after the app's consent/setup gates. Intent payloads are consumed once. Health Connect supplies the Android health integration.
- Existing secondary screens use Broop's gradient and static ring/bar/HR visuals. The classic presentation retains its existing behavior.
- Added Kotlin twins for Stress Monitor v2, Rest v2, Sleep Regularity, effort targets, Energy, Mind and the current Healthspan model. Oracle tests use output from actual Swift source, with varying inputs rather than one matching example.
- Stress analysis uses every calendar day, all sleep blocks with imported local-wake-day precedence, the complete workout-source mask, and chronological baseline and Energy carry. Expired raw data preserves derived history; present but insufficient raw data clears stale derived values. Waking-only days persist independently of scored sleep nights. Scoring-window writes share one Room transaction.
- A scoring-mode change rearms and reruns the full-history Rest repair. Completion requires successful persistence and an unchanged preference. Live stress uses one packet window shared by the visible screens.
- Added English resources and German, Spanish, French and European Portuguese translations for the new UI.

## Work allocation

- Overview, sleep and score flows: [02-overview.md](02-overview.md).
- Health, activity, strength and body analytics: [03-body.md](03-body.md).
- More, account, onboarding, journal, insights and Healthspan: [04-account.md](04-account.md).
- Parent: shell, navigation, branding, Stress/Rest integration, raw/live HR funnel, transactional persistence, builds, cross-agent review and emulator verification.

## Verification completed

- Full, Demo and instrumentation APK builds passed with JDK 17 and the repository Gradle wrapper. Installable builds are `android/app/build/outputs/apk/full/debug/app-full-debug.apk` and `android/app/build/outputs/apk/demo/debug/app-demo-debug.apk`. Application IDs are `com.noop.whoop.debug` and `com.noop.whoop.demo.debug`; both are version 12.1.0 debug variants.
- The complete Android JVM run executed **6,791 tests: 6,784 passed, six skipped, one existing failure**. Every new port test passed. The strict instrumented scoring-method guard passed at 55,658 bytes against its unchanged 55,700-byte budget. Schema, transaction, restoration, notification, source-selection and oracle checks ran in this suite.
- All **six instrumentation tests passed** on the isolated API 35 ARM64 emulator. They rendered **68 distinct destinations**, covering all **40 Swift BroopScreen route kinds** and Android account/integration routes; navigated tabs and the Add Activity form; compared a historical displayed Rest score with its stored day; exercised chart hold-to-read/pinch/reset; logged, undid, finished and reopened strength training with SQLite assertions; and completed all eleven applicable onboarding pages. The paired-success page correctly stays absent without a bonded strap.
- A second device pass passed seven representative pages at **360 dp width and 130% text size**. Screenshots were inspected for the score rings, headings, cards and navigation. The final Demo APK was also installed and its Home, Sleep, Health and More navigation checked through MainActivity.
- Swift Stress/Rest/Sleep Regularity/effort test selection: **44 passed**. Native Swift Healthspan selection: **21 passed**. Kotlin fixtures contain output generated from actual Swift code. Healthspan covers 4,185 curve inputs plus scenarios and window boundaries at nine-decimal stdout precision; this is not a claim of raw floating-point bit identity for every input.
- Python Tools: **341 passed** on the final analytics inventory. The standalone source ledger and exact-base parity ratchet passed with zero errors. Existing paired functions, properties and constants were retained; new app/store adapters have individual reviewed dispositions. The stale task-start authority was regenerated through the guarded migration, which independently rescanned that exact base.
- `Tools/test_android_broop_routes.py`, `Tools/doc_comment_lint.py` and `git diff --check` passed. New Android text has no hardcoded-literal findings and complete German, Spanish, French and European Portuguese coverage. The overall i18n command still exits nonzero for inherited Apple locale debt and 45 existing Android Italian gaps.

### Reproduction commands

```bash
cd android
JAVA_HOME=/Users/oliver/.local/toolchains/jdk17/Contents/Home ./gradlew \
  :app:assembleFullDebug :app:assembleDemoDebug :app:assembleFullDebugAndroidTest
JAVA_HOME=/Users/oliver/.local/toolchains/jdk17/Contents/Home ./gradlew :app:testFullDebugUnitTest
```

With the Full app and test APK installed on an isolated emulator:

```bash
adb shell am instrument -w -r -e broop.seed true \
  -e class com.noop.ui.BroopPortSmokeTest,com.noop.ui.BroopLiftFlowTest,com.noop.ui.BroopOnboardingFlowTest \
  com.noop.whoop.debug.test/androidx.test.runner.AndroidJUnitRunner
```

The instrumentation seed and raw chart fixture are synthetic test data. The Full production path never invokes the seed.

The subsequent non-debuggable release APK build and signature verification are recorded in [05-release-apk.md](05-release-apk.md).

## Existing failing gate

`RecoveryDriversTest.originalHrvOnlyInputMatchesSwiftScoreAndDriverOracle` fails on the installed JDK 17. Its production scorer, driver and existing test are unchanged by this port. At the original fixture input, Darwin Swift's `exp` and Java's `exp` differ by one ULP: the neutral score is `404cf759b59ded46` versus `404cf759b59ded45`. That changes an exact negative half-point boundary into a value just inside it, so the displayed driver rounds to -1 in Swift and 0 in Java. The discrepancy was reproduced independently; the existing oracle and formula were preserved. The complete suite is therefore reported as failing this one test.

## Validation limits

- Emulator checks cannot establish real WHOOP connection, notification timing, haptics, or strap double-tap behavior. A real-strap test is still required. No new outbound BLE command or handshake behavior is introduced.
- Android uses native permissions, pickers, Compose charts and Health Connect. Siri/App Intents have local Android launcher actions; Apple-specific frameworks are not available on Android. The UI contract is feature parity with platform controls.
- The stress memo verifies actual raw arrays before reuse, including same-timestamp corrections. It saves repeated analysis, but still queries present raw data because the existing store has no durable revision covering all relevant corrections.
- Evidence and logs are stored outside the repository at `/Users/oliver/agent-runs/2026-10-19-android-broop/`: `android-apks-complete.log`, `android-presentation-final.log`, `android-unit-summary.json`, `python-final-validation.log`, `device-final-validation2.log`, `device-rendered-routes.log`, `device-small-font.log`, `broop-ratchet-final2.log`, `broop-ledger-final2.log`, `broop-i18n-final2.log`, and the `populated/` and `small-font/` screenshot sets. `apk-manifest.json` records sizes and SHA-256 digests.
- The temporary emulator, its AVD and the session's throwaway files were removed after verification. The later [cleanup](06-cleanup.md) stopped the remaining build/emulator helpers, removed generated output and retained only the release APK and its metadata in the project's ignored build directory. Final evidence remains in the path above.
