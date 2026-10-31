# Broop-only iOS app and iOS-only build

## What changed
- The iOS app has one interface: Broop. The Classic toggle, Classic Today, the classic stress sheet, the
  onboarding appearance step and the Motion and Custom background settings that only classic screens read
  are gone.
- 93 classic-only files are excluded from `NOOPiOS` in `project.yml`. They stay on disk because the macOS
  app and `StrandTests` still compile them. `Strand/System/ProjectInfo.swift` had no references and was
  deleted.
- Logic hosted on classic views moved to neutral types in `Strand/Data` (`TodayRules`, `SleepRules`,
  `InsightsRules`, `WorkoutRules`, and others). No formula was changed.
- `Tools/ios.sh` and `project.ios.yml` build and test the iPhone app without the macOS app, Watch app or
  widgets.
- `DetectedWorkoutReconciliationTests` was stale against `09baea0b`, which stopped publishing detected bouts.
- `RootTabView` was rewritten and the root view no longer wraps its shell in `AnyView`.

## Measurements (Debug simulator, arm64)
| | Before | Full `NOOPiOS` now | `Tools/ios.sh build` |
|---|---|---|---|
| Clean build | 2:43 | 1:29 | 1:10 |
| NOOP.app | 434 MB | 171 MB | 133 MB |

Single runs on one machine. Release iOS-only build: 78 MB.

## Verified
- `Tools/ios.sh test`: 2,216 run, 2,214 passed, 2 skipped, 0 failed. 33 test files that need macOS-only
  screens are excluded and 6 host-dependent tests are skipped, all listed in `project.ios.yml`.
- macOS `StrandTests`: 2,479 run, 2 skipped, 0 failed.
- Debug and Release iOS-only builds succeed. Full-spec `NOOPiOS` Debug succeeds; its Release was not built.
- Simlock iPhone 18 Pro: terms, 11-step onboarding, Home, Health and More opened with no strap.
- `doc_comment_lint` passes. Android `compileFullDebugKotlin` passes.

## Not verified
- No real strap, no physical iPhone, no Watch. BLE behaviour is untested by this work.
- No launch-time or memory profiling on a device.

## Open
- Tools: 2 parity governance tests fail. Parity Governance CI was already failing on `fork/main`; refreshing
  needs issue-bound authority decisions because the fork removed paired Swift and Kotlin functions.
- `i18n_audit --ci` fails on missing translations, the same way against `origin/main` and `fork/main`.
- `StrandiOSApp` owns `AppModel` as `@StateObject`, so app-level body evaluation follows each published change.
  Not measured and not changed.
- Classic sources can only be deleted when the macOS app is removed or moved to Broop.
