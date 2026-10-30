# Broop dashboard activity values

Reported on 2026-10-19. The iPhone Air dashboard showed HRV, resting heart rate,
restorative sleep and respiratory rate, but omitted Steps and Active Calories.
The user confirmed that Apple Health was connected and displayed steps and
active energy on its own integration screen.

## Cause

`BroopModel` resolved current steps/calories from Apple Health when available,
but its comparison helper read history only from the strap/import daily rows.
WHOOP export import leaves those daily activity fields empty. The helper then
returned nil for an empty historical series, and the dashboard dropped the whole
row even when its current Apple Health value was present.

The exact original helper reproduced this rule in a standalone Swift harness.
A stronger reproduction used the old installed simulator app with synthetic
WHOOP vitals and Apple Health activity. Its dashboard showed only four rows.
No data from either physical phone was copied or edited during diagnosis.

## Change

- Added one pure activity resolver for current values and comparison history.
  Each day uses the existing priorities: native steps, then Apple Health steps,
  then a step estimate; Apple Health active energy, then the native estimate.
  Duplicate Apple rows use per-field maxima, preserving the existing rule.
- Apple Health activity history now participates in the dashboard comparison.
  Comparisons include up to 30 preceding available days, excluding the selected
  day and future days.
- A present current activity value keeps its dashboard row even without a
  comparison. An unavailable baseline and trend are omitted, never invented.
- Missing activity on the selected day no longer borrows a different day's step
  estimate. A genuine zero remains a value.
- Existing design tokens/components and localized labels are reused. No BLE,
  health storage, analytics formula or migration changed. This repairs the iOS
  Broop dashboard; concurrent Android Broop work was left untouched.

## Verification

- Six retained XCTest cases exercise Apple-only values and history, missing
  history, source priority, duplicate rows, zero, missing selected-day data,
  future-day exclusion, estimates and the comparison limit.
- All six passed by compiling the actual helper and actual test file together
  with Xcode's macOS XCTest libraries. The helper is also included in the
  `StrandTests` target through `project.yml`; the full hosted app suite was not
  rerun for this iOS presentation repair.
- Regenerated the project from `project.yml`; iOS simulator Debug build passed.
- On the same synthetic simulator fixture, installing the fixed app restored
  both activity rows. Values were Steps 5005 / comparison 1200 and Active
  Calories 1628 / comparison 400, matching the Apple Health fixture exactly.
- Removing all earlier activity values from the synthetic fixture kept both
  current rows visible and removed their comparison figures. The accessibility
  snapshot and a visual screenshot confirmed this state.
- Signed iOS Release build passed. Deep/strict code signature verification
  passed, both iPhone provisioning profiles include both phones, and the built
  app carries its HealthKit entitlement.
- `doc_comment_lint.py` and `git diff --check` passed.

The signed update was installed and successfully launched on both the iPhone
Air and iPhone 16 Pro. CoreDevice returned success for both installations and
both launches. The user subsequently reported completion and requested cleanup.
Physical-phone dashboard values were not independently read back by the agent.
No installation blockers remain.

## Cleanup

Removed the isolated `build/sleep-buzz-fix` output, this session's temporary
build/debug/test files, and the two diagnostic files created by its simulator
interaction failures. All selected paths are confirmed absent: 36,066 files
with 4,813,062,144 allocated bytes. Available disk space increased by
4,366,151,680 bytes during cleanup; APFS sharing and concurrent activity mean
these measurements need not match.

Closed the simulator automation session and uninstalled only the disposable
Broop simulator app, which was absent before this task. The existing simulator,
physical-phone installations and their data, source changes, retained tests,
reports, generated Xcode project and dependency lockfile remain.

Preserved the installed build's four dSYM bundles in a compressed archive
(62,946,080 bytes), with build identity, source paths and a SHA-256/size manifest.
Every archived file/link was verified before and after deleting the build tree.
The archive, manifest and cleanup inventory are retained in
`/Users/oliver/agent-runs/2026-10-19-broop-device-symbols/` for crash symbolication.
Shared tool caches and unrelated work were not removed.
