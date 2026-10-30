# Broop live-data audit

Requested 2026-10-28. Audit the wearer's physical iPhone, the reported strength-session splitting around 16:00–17:00, a family member's early-wake report and runtime reliability. The follow-up requested a separate Apple Watch comparison and an independent Sol review. Apple Health remains disconnected from Broop.

## What changed

Created a private capture, read-only analysis scripts, production Swift helper replays, independent Watch comparison, evidence checks and an interactive daily chart. Located `/Users/oliver/Downloads/export.zip`, exported October 28 at 21:05:20, and streamed its relevant source-filtered records without importing them into Broop. Completed one independent `gpt-6.1-sol` review and corrected the report and acceptance assertions in response. Preserved original report/harness/output files so the corrections are visible.

No product source, phone settings, Health permissions or strap state changed. Existing working-tree work was preserved. No fix, app build, installation or deployment was performed.

Artifacts under `/Users/oliver/agent-runs/2026-10-28-broop-data-audit/`:

- `REPORT.md`, corrected main audit.
- `WATCH-COMPARISON.md` and `watch-comparison.json`, methods and daily values.
- `SOL-REVIEW.md`, unchanged independent objections and source evidence.
- `watch-comparison-chart.html`, interactive daily comparison.
- `capture-manifest.json` and `supplemental-manifest.json`, provenance and hashes.

## Findings after review

1. Confirmed semantic defect: total energy reaches the Active calories fallback. The rest-only helper case produces 0 active kcal but a 70.022-kcal fallback input. Today's recorded local-day replay has about 694 active kcal; Watch has about 495 active kcal. The published native fallback contains about 2,103 total kcal. Different calculation/publication states prevent exact decomposition of that saved value.
2. The Watch logs an October 25 strength workout from 09:24:29 to 10:22:49 during a captured strap-data gap. Broop has no overlapping workout and zero strap HR readings during it. The wearer subsequently confirmed WHOOP was not worn during this workout. This is expected non-wear and is excluded from detection/collection-failure evidence; unrelated gaps remain unattributed.
3. Eleven paired nights show median Broop-minus-Watch differences of +11.07 minutes asleep, +73.57 deep minutes and +51.47 REM minutes. Median paired deep-plus-REM share difference is +25.69 percentage points. This is disagreement between estimators on one wearer, not clinical accuracy evidence.
4. Today's five gait-derived pieces reproduce, but the true workout bounds remain unlabelled. The export contains no Watch workout today. October 23 and 24 Watch workouts each align with one central Broop bout over 97.67% of the interval, narrowing the original fragmentation claim.
5. Synthetic quiet-wake behavior reaches 05:56:59 after an assigned 04:00 wake. This does not diagnose the father. The review and a follow-up replay show that downstream main-night grouping can retain the late tail even when the detector separates sessions. Lowering one merge threshold is not an established repair.
6. Coverage and CPU measurements survive independent checking. Actual-calendar coverage differs from the engine's historical fixed-offset windows. The `solid` density rule does not establish day completeness, and no dashboard badge was verified. Logged CPU is process-wide; phase durations are elapsed time; background state is sampled at completion. No collection-gap or OS-kill cause is established.

## Verification

- Original capture quick-check passed; independent reviewer verified matching DB/WAL and listed-source hashes using private copies. The live multi-file capture is not atomic, and the partial source manifest does not establish installed-binary identity.
- Built `StrandAnalytics` and compiled replays against its existing products. Last-night boundaries reproduce exactly, and all 15 main-night totals / 17 session timelines pass consistency checks.
- Independently source-filtered the 2,186,165-record Health archive, verified its hash, preserved explicit offsets through the DST change and left missing Watch nights unavailable.
- Replayed production active-energy estimation for 15 actual local-calendar days. These windows are not claimed to reproduce every historical engine window.
- Sol independently re-queried workout overlaps, sleep medians, coverage and runtime statistics and compiled an additional whole-pipeline sleep sensitivity driver. Parent reproduced that sensitivity and the fixed-offset coverage counts.
- Removed the provisional one-session and synthetic five-minute accuracy acceptance assertions. Revised replay intentionally exits 1 only for the confirmed active/total semantic mismatch. Evidence checks pass.

## What remains

Product fixes are not implemented. Priorities: correct energy semantics while preserving historical storage/backup meaning; investigate missing inputs and expose collection coverage/freshness; validate staging, early wake and automatic session grouping against independent labels; profile the costly history/stress span and existing cache invalidations.

Father/brother records, today's true workout boundaries, causal attribution of collection gaps and independent physiological validation remain unavailable. Scoring changes require the repository validation protocol, temporal holdout and Swift/Kotlin parity. The requested export comparison and independent review are complete.

## Standing-reminder follow-up, 2026-10-28

The October 25 interpretation was corrected using the wearer's non-wear label. Accuracy priorities and the standing-reminder audit are recorded in `/Users/oliver/agent-runs/2026-10-28-broop-standing-reminder/STANDING-AND-ACCURACY.md`.

Current source replays confirm a movement-goal/posture limitation, a stale scheduled alert when movement is not re-evaluated before :45, and an asynchronous callback that can re-add an already cleared reminder. Existing 15 core reminder tests pass. Controlled adapter/notification-path replays deliberately fail the no-stale-alert assertions. Actual observed alert delivery and the cause of the wearer's specific incidents remain unverified because no timestamps were recalled. No product code or phone settings changed.

Follow-up verification: `python3 /Users/oliver/agent-runs/2026-10-28-broop-standing-reminder/run_audit.py` checks the fresh-data cancellation control and both deliberately failing obsolete-alert reproductions. Raw-data reconstruction finds two of five saved reminder attempts already meet the five-minute goal by the scheduled time; those saved entries infer delivery and do not prove an OS alert was shown. No changes were installed.

## Five-item implementation follow-up, 2026-10-28

This section supersedes the earlier statement that product fixes are not implemented. The approved five-item pass is recorded in `/Users/oliver/agent-runs/2026-10-28-broop-accuracy-fixes/REPORT.md`.

Implemented separate active-only energy storage and reads while retaining legacy total-energy history; calendar-aware scoring/calibration windows and DST energy caps; confirmed wake boundaries through core analysis, aggregation and display; explicit confirmation for detected workout fragments; exact-span workout backfills; and recorded-HR coverage/confidence on Swift and Android. Existing saved workouts and unrelated workspace changes were preserved. No Apple Health connection or permission was enabled.

Independent V2 validation is complete on all 31 sleep-accel subjects / 26,773 PSG-labelled epochs, with all 93 required input files checksum-verified. Four-stage agreement is 61.14%, kappa 0.371; pooled deep bias is +1.32 percentage points and REM bias +4.46. Wake recall is 0.308. No classifier thresholds were changed and no automatic early-wake improvement is claimed from these stage-window results.

Verification: final Swift analytics suite 2,291 passed; iOS simulator build passed; macOS build plus 21 targeted app tests passed; final focused Android run 37 passed, including raw-bit Swift/Kotlin energy/coverage oracles and the unchanged method-size guard. Broader Android run has one untouched recovery-rounding oracle failure and five skipped tests among 2,495. Source hygiene and diff checks pass. New copy is fully translated; the full translation gate retains pre-existing non-focus-locale failures. Simulator visual verification was blocked by another project's device lease. Hardware was not tested.

Remaining: family-labelled wake traces, precise labels for today's workout, independent WHOOP-relevant stage calibration, the unrelated recovery oracle discrepancy and the separate standing-reminder remediation. Changes are local, uncommitted and not installed or deployed. The independent Sol review from the audit remains in the original audit evidence; no additional reviewer was started for this implementation.


## iPhone redeployment, 2026-10-28

The user authorized installing the current fixes and persisting signing. Built `NOOPiOS` in Release with Xcode 27.0 and installed Broop 12.1.0 (436), `com.oliverbrunovsky.noop`, on Oliver's iPhone 16 Pro without uninstalling it. CoreDevice launch succeeded; the new installed executable was subsequently running as PID 5323. No family phone was updated.

The existing gitignored `Config/BundleIdSecrets.xcconfig` already retained the paid development team, bundle prefix and App Group. Regenerating the project preserved those settings. All four embedded bundles passed signing/profile checks, and deep strict codesign verification passed. Main/widget profiles expire in October 2027.

The existing signing-renewal LaunchAgent pointed to a missing installed script and failed with EX_CONFIG. Restored that script, preserved its device/team settings, moved its future build output to ignored `build/personal-refresh`, and reloaded the job. Its normal profile check completed with exit code 0; renewal was not due.

The existing database, WAL and all pre-install Application Support paths remain present. The App Group container is unchanged; iOS relocated the application data container during the update. The full standing-reminder JSON is semantically unchanged, including 775 history entries and 76 outcomes. Database writes resumed with the new app; no full database byte comparison was performed. The working source and local signing config were unchanged during build/installation, and `git diff --check` passed.

Deployment has no remaining blocker on the wearer's iPhone. Verification covers signed build, installation, initial launch and retained state. Automatic early-wake accuracy, stage calibration, standing-reminder fixes and strap behavior remain as described in the prior audit and implementation reports; they were not newly validated on hardware. No commit, merge or published release was made.

Deployment report and evidence: `/Users/oliver/agent-runs/2026-10-28-broop-iphone-redeploy/REPORT.md`. Signed output remains under ignored `build/iphone-redeploy`. Session temporary state copies and query files were removed.


## Cleanup requested after deployment

Removed the session-owned ignored output directories `build/iphone-redeploy`, `build/accuracy-ios`, `build/accuracy-macos`, `build/data-audit` and the empty `build/personal-refresh`. Their files occupied approximately 8.25 GiB of allocated space. Both session temporary directories were already absent. The generated Xcode project, local signing config, Keychain identities, profiles, restored renewal script/LaunchAgent, source changes and reports remain. The renewal job recreates its build directory when needed. No phone data or installed app was removed. Details: `cleanup.json` in the deployment evidence directory.
