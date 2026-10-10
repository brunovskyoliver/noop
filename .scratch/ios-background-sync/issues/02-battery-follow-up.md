# Battery and sync follow-up after the October 2 installation

## Report, October 4, 2026

The physical iPhone 16 Pro still runs Broop 11.8.0/415 on iOS 27.0.1. A read-only audit collected 403 available phone/Watch diagnostic reports and nine retained app log segments. The full report and raw evidence are in [the battery audit](/Users/oliver/agent-runs/2026-10-04-iphone-battery/REPORT.md).

The October 3–4 raw NOOP CPU counters average 33% below September 29–30, background energy counters average 40% lower, and GPU counters are nearly zero. These are observed, uncontrolled differences; private log units, charging, foreground activity, and workloads prevent an exact battery-saving claim. NOOP remains the largest CPU-counter app in both recent reports. No newer NOOP CPU-limit termination appears after September 28.

The retained October 4 trace covers about 04:55–21:56 and has 354 historical persistence events, 146,101 persisted sensor rows, and a largest nonempty-persistence gap of 10m 32s. It does not repeat ticket 01's 6h 41m sync gap. It contains 30 disconnects and recovery, with some weak RSSI periods. This is operational evidence, not a controlled locked-phone or force-quit test, and it does not cover both entire nights.

Remaining app costs are concrete: 67 short-budget scoring cancellations, 24 forced resumes, seven completed 21-night passes, about 2,641 live HR/RR flushes in 17 hours, and 300 GB of attributed file reads in the October 3 phone Analytics export. Most completed passes reuse 19–20/21 cached nights, but still probe 60 gravity windows and repeat change-detection and post-processing work. Five sync refresh wakes all expire without an in-window completed offload despite historical syncing continuing around them.

`WhoopStore.analysisFingerprint()` performs an unscoped `MAX(ts)` on a table keyed `(deviceId, ts)`. A synthetic host SQLite test with the repo's schema confirms the avoidable scan: one million HR rows take at least four million VM instructions; a hypothetical timestamp index returns the identical result in fewer than 1,000. This establishes query behavior, not its exact share of phone drain.

Instagram leads the latest recorded app-energy table at 6.23 times NOOP, followed by Spotify and Safari. Phone Analytics show persistent cellular use, historical hotspot activity on battery, and continued nonfatal Health CPU incidents. The previous WhatsApp Watch kill storm is absent. Battery Analytics retain 92% maximum capacity across the week; the live snapshot has 426 cycles. Display/AOD, notification energy, and exact system-component attribution remain unmeasured.

## Changes and verification

- Created the local audit/report, Apple primary-source research, capture manifest, parsers, and synthetic query check. No app implementation or phone settings changed. Existing unrelated source changes were preserved.
- The complete diagnostics pull succeeded. Parsed eight unique phone power windows; removed a duplicate September 28 export and separated phone from Watch reports.
- Independently checked latest energy totals, operational counts, resource actions, and memory-kill reasons. Hashed 412 raw diagnostic/log files.
- Ran `analyze_phone.py` and `check_query_work.py`; the query check asserts equal results and the scan/index behavior at 100,000 and 1,000,000 synthetic rows.
- No application build is claimed because no application code changed.

## Next work

1. Profile global/day fingerprint queries; implement bounded, revision-aware checks or an additive index with migration/parity tests. Preserve backfills, edits, deletion, source promotion, and registry invalidations.
2. Reduce repeated preparation after background cancellations. Preserve last-night publication and resume old history without restarting its expensive probes.
3. Test longer bounded HR/RR batches and a supported lower-traffic background policy, preserving overnight HRV input and data durability.
4. Give refresh preparation an explicit healthy/no-work outcome so rate-limited fresh links finish promptly. Keep real recovery bounded and logs truthful.
5. Capture matched unplugged on-device Power Profiler runs for actual battery savings. Prior force-quit reminder and out-of-range hardware checks from ticket 01 are still outstanding; this audit does not replace them.

The audit above preceded the implementation below.

## Implementation, October 4, 2026

The user authorized the follow-up fixes and then restricted development to Apple platforms. All Android edits made during this task were removed, and its build was stopped. Android is unchanged.

### Changes

- Replaced the Apple engine's global COUNT/MAX raw-history probes with the existing transactional daily revisions and registry identity. Day-scan checkpoints and the 60-day motion cache now check those small revision records instead of counting dense sensor streams. The legacy fingerprint APIs remain available. No scoring formula or database schema changed.
- Preserved cache invalidation for every tracked sensor stream, in-place corrections, deletions, owner/model changes, sleep payloads, WHOOP 4 skin anchors, RR source policy, and scoring settings. Deleting a source advances an integer cache epoch in the existing cursor table, in the deletion transaction, so replacement data cannot reuse equal counters from the deleted dataset. The epoch contains no source identity or health data.
- A short background opportunity publishes the recent three-night window and queues older history for BGProcessing or foreground execution. It no longer starts a second full-history pass immediately under another short assertion. Recent retry throttling and cancellation remain in place; the partial pass cannot advance the complete-history watermark. Foreground and extended processing still drain the debt.
- Standard live HR/RR persistence now flushes at 30 accepted readings, 30 seconds of batch age checked on ingress, or 256 buffered rows. Dense RR notifications no longer shorten the intended reading batch. Pending automatic flushes coalesce. Failure restores samples, reading counts and the original deadline, including readings received while the failed write was suspended. Lifecycle/disconnect flush paths remain active.
- Refresh preparation now distinguishes a healthy, recently completed link with nothing due from an outstanding offload or reconnection. Only a bonded, error-free link without pending history qualifies. A fresh wake returns successfully without polling or claiming an offload; real recovery still waits within the existing bound.
- Added local MetricKit capture. Apple metric and diagnostic payloads are saved unchanged to `Documents/Diagnostics/MetricKit`, preserving reporting windows, mixed-version flags, and original build/device metadata. A utility queue deduplicates and retains at most 32 reports within 8 MiB, ordered by reporting-window end. The directory is excluded from cloud backup and protected until the first unlock after reboot. The capture has no timer or network path.
- Incremented the iOS build number from 415 to 416. Existing unrelated encryption/privacy/tooling changes were preserved.

### Verification

The original migrated-store regression failed at 400,200 SQLite VM instructions for change detection over 100,000 HR rows. The replacement passes the fewer-than-1,000-instruction bound. Correction, deletion, rollback, all 11 revision-tracked streams, source replacement, registry changes and checkpoint persistence are covered by real store tests. All 627 WhoopStore tests passed.

The collector regression first failed on premature writes and wrong batch sizes. The initial app checks passed 47 tests; the wider run passed 95 tests. The final collector run passed all 10 tests, including samples arriving during a failed write. Scoring integration compares all persisted daily metrics from reused checkpoints with a fresh scan after correction. Real engine tests verify recent publication, absence of a second full pass in a short wake, retry throttling, unchanged complete-history watermark after partial work, and full completion in foreground/extended processing. Refresh tests cover stale/future timestamps, failed syncs, unbonded/recovering links, pending history and expiration.

A final real-engine regression reproduced stale checkpoint reuse after correcting a re-added strap's model from 4.0 to 5.0. The day key now includes the canonical resolved family, even when the owner is not the legacy `my-whoop` alias and both families have no skin anchor. All 100 tests in the combined final macOS app run passed, including this regression and the local archive tests. The run compiled the shared app target and its tests. The machine-readable Xcode result summary is saved with the build logs.

The final signed iOS Release build succeeded with local MetricKit capture and the resolved-family cache fix. The original MetricKit payload APIs also type-checked against the installed Xcode 27 SDK with an iOS 17 deployment target. All three local metric archive tests passed, checking exact payload preservation, repeated delivery, delayed reporting windows, byte/count limits and unrelated-file preservation. `git diff --check` and the repository doc-comment gate passed. Build/test logs and primary-source research are retained in [the local run directory](/Users/oliver/agent-runs/2026-10-04-noop-battery-fixes).

The installable [Broop 11.8.0/416 app](/Users/oliver/agent-runs/2026-10-04-noop-battery-fixes/Broop.app) and matching debug symbols are saved outside the checkout. Strict deep signature verification passed. Bundle identity, App Group and keychain groups match the previously installed build; the profile provisions the paired iPhone and expires October 1, 2027. The app, widget, Watch app and complication all report build 416. `build-manifest.json` records the binary UUID/hash, source hashes and signing/version checks. The user selected option 1 to install and verify live sync; replacement installation succeeded on the paired physical iPhone.

### Device verification after installation

Apple's device tools confirm the installed Broop version is 11.8.0, build 416. The app launched successfully without a debugger/console attachment. The previous approximately 2.01 GiB database remains in place, and the retained logs continue across the upgrade. T3's Device panel did not expose this physical phone, so verification used CoreDevice's install/launch and read-only container access.

The new app restored the connected WHOOP 5/MG at 22:52:16 local time. At 22:52:24 its historical offload persisted 398 rows, including 135 motion and 135 skin-temperature rows, and ended with `HISTORY_COMPLETE`. A following continuation reached the end of available history and completed. The completed-sync preference advanced beyond the pre-install timestamp.

Two observed cadence flushes at 22:52:46 and 22:53:16 each offered 30 HR readings, with 10 and 9 RR intervals. They successfully inserted 26 and 29 HR rows and all 19 RR intervals. Offered and inserted counts are distinct; the store's conflict/deduplication policy remains active. The initial recent-window pass completed in 36.038 seconds, followed by the 21-night pass in 37.150 seconds. The latter logged 27.0 process CPU seconds, no assertion expiration, and a foreground state at completion. The preference snapshot then showed no pending analysis debt and the new revision-based complete-history watermark.

These are startup and foreground observations on the real strap, not an unplugged battery comparison or a sustained locked-phone test. They do not prove exact battery savings or MetricKit delivery. Raw device results, preference snapshots, log segments and an asserted machine-readable summary are saved under [phone-check](/Users/oliver/agent-runs/2026-10-04-noop-battery-fixes/phone-check/validation.json).

### Remaining work

Local implementation, signed installation and startup sync verification are complete. Sustained background behavior, MetricKit delivery and actual battery savings remain unverified for build 416. A matched unplugged Power Profiler trial remains the appropriate battery measurement; app MetricKit payloads are delayed, may span multiple app versions, and do not measure whole-phone battery attribution by themselves. The earlier locked-phone, reminder and out-of-range checks remain deferred at the user's request.

The change reduces database/persistence work without disabling the continuous standard HR/RR stream needed for overnight inputs. A lower-traffic BLE mode remains an experiment requiring a separate matched hardware trial. Whole-phone hotspot, cellular and third-party app usage remain measurements and usage recommendations from the audit, not settings changes made by this implementation.

The upgrade changes checkpoint and motion-cache keys. The first complete scoring pass rebuilds those caches; steady-state savings must be measured after that initial work.
