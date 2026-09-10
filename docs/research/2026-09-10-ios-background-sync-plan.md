# iPhone background strap sync and delayed sleep results

Research date: 2026-09-10. Source baseline: local commit `b3fe1f2f`. Scope: investigation and implementation plan; no app behavior changed.

## Findings from this phone

The selected strap family is WHOOP 5.0 / MG. The latest device reports identify iOS 27.0 build 24A435. Background Bluetooth is partly working: saved logs show restored connected peripherals at 07:29:27, 07:32:14 and 07:33:10, notification re-subscription, and historical download starts. The app also logged Bluetooth connection timeouts at 07:30:07 and 07:31:29. These observations rule out a completely absent restoration setup, but do not prove reliable overnight syncing.

At 07:29:27 iOS killed the current installed build for CPU use: 48 CPU seconds in 52 elapsed seconds, 93% average. A subsequent 08:54:36 report records 144 CPU seconds in 152 seconds, 94%, with no termination action for that report. Symbolication against the matching B93FEEFF-D5D1-3BCE-9058-630C0FBB23D6 binary identifies `IntelligenceEngine.analyzeRecent` -> `AnalyticsEngine.analyzeDay` -> `SleepStager.detectSleep`, including the stream fingerprint work around SleepStager.swift:1359. This is direct evidence of costly analytics, not proof that every Bluetooth timeout is caused by analytics.

The copied app preferences record `noop.rescoreOwed = true` and `noop.rescoreLastPassSeconds = 82.7626`. Saved logs repeatedly say an outstanding rescore prevented a background backstop pass. Thus the sleep delay has a concrete mechanism: expensive or interrupted analysis remains queued, and execution is deferred. There is not enough retained history to reconstruct the user's entire half-day delay precisely.

Private evidence remains under `.git/background-sync-investigation/`: preferences, crash inventory, morning CPU reports. Earlier CPU reports are under `.git/coach-crash-investigation/`. Do not commit these files; preferences contain private app settings. This note records only relevant operational facts.

## Code findings

| Area | Current behavior | Consequence |
| --- | --- | --- |
| Background configuration | `project.yml:260` declares bluetooth-central, fetch and processing; rescore identifier is permitted and registered in `StrandiOSApp.init` | Adding a background flag alone will not solve this |
| Bluetooth restoration | `BLEManager.swift:1328`, `:6054` create a restoring central and recover delegates, services and subscriptions | Preserve and test the existing mechanism |
| Automatic sync | `BLEManager.swift:4598` uses a main-queue DispatchSourceTimer, normally 900 seconds; connection and strap events also trigger sync | Timer cannot provide a wake from suspension; event coverage matters |
| Foreground entry | `StrandiOSApp.swift:294` explicitly requests sync and drains owed analysis | Explains why reopening helps both stages |
| Failed connection retry | `BackfillPolicy.swift:64` rate-limits connect/foreground for 90 seconds from the last attempt, not last successful transfer | Actual logs show restored connect attempts skipped at 54 seconds; after that there may be no immediate event to retry |
| Transfer durability | `Backfiller.swift:24` already has durable writes before trim acknowledgement; `BLEManager.swift:2913` already auto-continues backlog | Extend this design; do not invent a second cursor or remove safety guards |
| Completion dispatch | `AppModel.swift:362` debounces published lastSyncedAt for 2 seconds before refresh/analysis | A process suspension/death before the trailing callback can delay work; durable dirty state should be recorded at commit |
| Analysis | `IntelligenceEngine.swift:600` defaults to 21 days; per-day reuse cache is process memory; loops collect results before later persistence | Cold restoration repeats work and interruption loses progress. Iteration already starts with recent days, but results are not published per completed night |
| Scheduler | `RescoreBackgroundPolicy.swift` defers owed or measured-over-20-second work; `RescoreBackgroundScheduler.swift:174` cannot cancel detached analysis at assertion expiry | The observed 82.8-second pass does not fit this application's assumed short budget; expiry can leave CPU work running |
| Other analysis triggers | `AppModel.swift:601` active-device adoption calls analysis directly; forced rerun in `IntelligenceEngine.swift:703` also calls directly | Audit every entry point, since scheduler protection is not universal |
| Error reporting | `RescoreBackgroundScheduler.swift:237` uses try? for submission | Scheduling failure is invisible |
| Storage protection | `StorePaths.swift` and `RawHistoryArchive.swift` already use protection until first authentication | Verify all SQLite/WAL/SHM files on-device; no evidence yet that locking storage caused this incident |

The installed app is a Debug build with `-Onone` in its build log. This may materially increase CPU cost. Measure an optimized build on the same input before estimating production performance; it does not remove the lifecycle and cancellation problems.

## Recommended implementation order

1. **Establish the device baseline and reduce immediate CPU risk.** Compare Debug and Release analytics on the same local input snapshot, retaining personal signing and bundle identity. Add bounded structured events for process launch reason, app state, sync trigger/skip reason, committed chunk counts, analysis start/checkpoint/finish, background expiration and scheduler submission errors. Record operational counters without raw health values. Measure without a debugger attached. Treat the existing CPU report as the baseline failure, not a completed end-to-end reproduction of overnight delay.

2. **Make analysis bounded and resumable.** Route every analysis entry point through one coordinator. Propagate cancellation to the actual worker and check it inside expensive loops, including sleep detection/fingerprinting where necessary. Persist dirty sleep windows, their input/configuration versions and completed checkpoints. Commit a completed recent night's detection promptly. Separate dependent recovery/baseline reconciliation from initial sleep availability, preserving source ownership, user edits and cross-midnight sessions. Resume remaining work after expiration instead of rescanning all 21 days. A complete dirty-night transaction must not mark new data that arrived during computation as processed.

3. **Persist useful caches and prioritize recent sleep.** Reuse unchanged nights across process restarts using input revisions, algorithm/config versions, source identity and timezone/window rules. Invalidate after edits, imports, baseline changes and adjacent-night input changes. Recent days are already iterated first; change the publication boundary so their results no longer wait for the complete window. Profile the observed SleepStager fingerprint hotspot and avoid repeatedly reading/hashing unchanged dense streams. Publish available sleep as provisional if later chunks can alter it; finalize only with adequate input coverage. Initial engineering target: typical recent-night update within 10 seconds of its required inputs being committed while execution is available, subject to measurement rather than an iOS timing promise.

4. **Make automatic transfer depend on real Bluetooth events.** Preserve one restoring manager and reconnect intent. When the restored/bonded transport becomes ready, reconcile its persisted cursor and pending work. Evaluate overdue sync on useful incoming characteristic events as well as strap prompts, with a cheap rate gate. Separate last attempt, retry eligibility and last successful data frontier so an interrupted attempt does not strand resumed work behind a periodic timer. Keep timers as opportunities while running. Preserve no-progress protection and durable-before-ack semantics; log continuation stop reasons and resume pending backlog on the next eligible event. Firmware that supplies no events while idle cannot support a promised fixed polling interval on suspended iOS.

5. **Separate ingestion, analysis and publication.** Mark impacted windows dirty in the same durable boundary as saved data, before acknowledging history. Coalesce analysis work without relying on a UI publisher's debounce for delivery. Keep BLE transfer free of whole-dashboard refresh and full-history compute. BGProcessing becomes the recovery/older-history path. Publish updated app state, widget snapshot and authorized HealthKit writeback after deferred results commit as well as immediate results; the current deferred method publishes only the widget explicitly.

6. **Support an explicit long catch-up operation.** For a user-started large transfer, evaluate iOS26+ BGContinuedProcessingTask and visible progress/Live Activity, with cancellation and checkpoints. Keep automatic background sync on the ordinary CoreBluetooth path. Check supported APIs and registration in the installed SDK, and validate actual Bluetooth behavior on the phone. Show connection, data saved through, backlog remaining, and sleep processing state separately; use measured progress rather than treating every completed slice as fully caught up.

## Verification before calling it fixed

Use automated tests at the real coordinator/store seams for restored connected/disconnected states; attempt interrupted within the 90-second floor; repeated chunks; durable write failure before ack; process restart with pending dirty windows; expiration during compute; new input arriving during an analysis snapshot; cache invalidation; and publishing the newest night while older work remains. Compare incremental results against a complete reference rescore, including edits, naps and cross-midnight windows.

Run a physical-device overnight trial without debugger or repeated devicectl usage assertions: open once, leave phone locked near strap, check next morning. Also test lock during a deep download, out-of-range/reconnect, Bluetooth toggle, restart followed by first unlock, Low Power Mode, background refresh disabled, and force-quit as a separate expected-limitation case. Record data-frontier lag, completed-night publication lag, reconnect delay, duplicate transfers, CPU terminations and battery use. Passing means progress resumes without manual foregrounding when the OS supplies eligible events, completed work survives interruption, and the CPU-kill signature no longer recurs. Exact unattended timing remains OS- and firmware-dependent.

## Apple platform research

# Apple background sync research — 2026-09-10

## What the platform supports

CoreBluetooth `bluetooth-central` lets iOS wake a suspended app for connections, disconnections and subscribed characteristic changes. Restoration preserves pending connections, subscriptions and scans and can relaunch an app for an event. Reconnect requests do not time out. Background scans are slower and coalesce duplicates. Bluetooth wakes offer brief execution; they do not grant an always-running process. Practical inference: drive strap sync from connection/readiness/data events, keep a pending reconnect and restore the same manager promptly on launch. Do not make polling timers the only trigger. [Apple Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)

There is no general API for guaranteed recurring background execution. App-refresh and processing tasks are opportunistic. Force-quitting should not be expected to preserve automatic operation; exceptions exist and change. [Apple DTS background execution limits, updated Jan 2026](https://developer.apple.com/forums/thread/685525)

Restoration requires a pending Bluetooth operation or subscription and its corresponding event. Apple's archived iOS11 matrix explicitly excludes force-quit and Bluetooth power toggle, and allows restoration after restart only after first unlock. This is useful baseline guidance, not a promise about every iOS27 case. [QA1962](https://developer.apple.com/library/archive/qa/qa1962/_index.html)

`earliestBeginDate` is only a lower bound, not a scheduled launch time. A request for 15 minutes later can execute much later. Use BGProcessing as recovery/maintenance, never the only path to display last night's sleep. [BGTaskRequest.earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)

## Long user-started sync

`BGContinuedProcessingTask` (iOS26+) is for work begun by an explicit user action in the foreground, continuing after the user leaves. It reports progress through a Live Activity, supports cancellation and can still be terminated under resource pressure. Suitable candidate: a user-started large historical download followed by sleep processing. It is not an automatic reconnect scheduler. [Apple long-running tasks guide](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados), [task documentation](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)

Documented resources cover default CPU/network and optional GPU. There is no documented Bluetooth-specific BGContinuedProcessing resource flag; use CoreBluetooth's own modes/restoration for the transport and validate combined behavior on hardware. [Resources](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/resources), [default resources](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequestresources/bgcontinuedprocessingtaskrequestresourcesdefault)

Current CoreBluetooth docs explicitly say that on iOS26+, an instantiated CBManager with a Live Activity started before backgrounding retains foreground Bluetooth privileges, including scan behavior. This is relevant to a visible finite catch-up sync; do not start permanent fake Live Activities as a background keepalive. [CoreBluetooth overview](https://developer.apple.com/documentation/corebluetooth)

## Locked-phone storage and HealthKit

HealthKit reads may be unavailable while locked; writes can be cached by the system until unlock. Distinguish temporarily inaccessible input from no sleep/data, and retry blocked enrichment after unlock. [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)

For local sync storage, audit protection on the SQLite file, WAL/SHM, raw chunks and any credentials. `completeUntilFirstUserAuthentication` remains encrypted but allows later locked access after first unlock; select protection deliberately for health data rather than disabling protection. This is a proposed audit, not a diagnosed issue in NOOP. [File protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication)

## iOS27 specifics and evidence limits

Current Apple release notes are titled iOS & iPadOS27 RC. The CoreBluetooth section documents a Channel Sounding fix, not a general background strap-sync regression. No background-task regression matching these symptoms was found. iOS27 adds restricted Neural Engine background access, relevant only if NOOP uses that engine for sleep inference; don't infer that from CPU analysis code. HealthKit permissions can now limit history, so inspect granted coverage if NOOP relies on historical HealthKit input. [iOS27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)

The device previously ran a 27 beta. Record its exact installed build and test behavior there; current release-note silence cannot rule out a beta defect. Most proposed fixes use longstanding CoreBluetooth APIs plus optional iOS26 continued processing; a new SDK alone will not repair an application lifecycle or analysis scheduling bug.

## Proposed design and validation (inferences)

1. Retain one process-wide sync coordinator initialized for background Bluetooth launches. Restore peripheral/delegate/subscriptions, reconnect known strap, and request missing chunks when transport is ready.
2. Persist transfer cursor after durable chunk commits; resume after disconnection, expiration or termination without replaying the entire history. Trigger bounded incremental sync on real strap events. If firmware offers no event while idle, fixed polling freshness cannot be guaranteed on iOS.
3. Separate durable ingestion from analysis. Mark impacted sleep windows dirty on each committed batch; process newest complete overnight window first. Publish completed recent results promptly, then work backward. Make CPU work bounded, cancellable, idempotent and checkpointed.
4. Use BGProcessing for deferred backlog/recovery; use continued processing for explicit long catch-up with real progress and cancellation. Do not silently shift automatic BLE wakes into hours of unrelated analysis.
5. Log last Bluetooth event, saved sample time, transfer cursor, backlog, sleep-input coverage, analysis start/end/cancellation and last result commit. Display these stages separately so 'synced' does not imply 'analysis finished'.
6. On the phone, without debugger attached: background/lock mid-transfer; move strap out/in range; suspend/relaunch through restoration; reboot then unlock; test user force-quit separately; measure CPU, battery, newest-data lag, and newest-sleep-result lag. Test throttled/expired analysis recovery and idempotent resume. Do not promise exact background timing.

## Implementation and validation

Implemented in the local device branch on 2026-09-10:

- Incoming Bluetooth notifications now provide a rate-limited opportunity to sync. A device-scoped interrupted-attempt marker allows a 15-second retry cooldown on restoration rather than treating the attempt as a successful transfer. Existing adaptive intervals, safe trim acknowledgements and continuation limits remain in effect.
- Every analysis entry point uses the background execution policy. Cancellation reaches detached CPU tasks; short background passes have a 20-second budget and no longer launch unrestricted forced reruns after expiration.
- Recent three-day passes can publish before the full 21-day pass and skip weekly fitness/60-day step calibration. Background recent attempts are limited to once per five minutes; iOS still chooses when an eligible wake occurs.
- Per-day scans are checkpointed in SQLite. Keys include raw-input revisions, stored sleep and legacy band state, owner and configuration. Revision triggers cover insert/update/delete in the raw scoring tables, so same-count corrections invalidate caches. Checkpoints survive restart, retain at most 64 recent days, and are removed with their device's data. Checkpoint schemas are explicitly iOS-only in both shared schema-oracle copies.
- Newly saved history records analysis debt before acknowledgement. The raw-input revision ledger commits transactionally with ingestion. Failed primary score/sleep saves do not advance the completed-analysis watermark.
- Health's Sync now starts a finite catch-up operation with chunk progress and Pause. On supported iOS it requests continued processing; unavailable grants fall back with a keep-open message. Catch-up has a 15-minute limit, preserves saved data, and does not report success while known backlog or analysis debt remains. Deferred analysis now also invokes authorized HealthKit writeback.

Validation passed: 1,957 StrandAnalytics package tests; 531 WhoopStore package tests; 49 targeted app tests covering the integrated checkpoint path, actual detached cancellation, retry policy and scheduler behavior. Signed Release build succeeded with the existing personal bundle ID/team and HTTP provider settings. Installed and launched successfully on the connected iPhone.

Initial device log after launch at 14:58:39 records a three-night recent pass completing in 5,176 ms (scan preparation 1,969 ms; scoring 1,096 ms). This is evidence for early recent-result publication on this device, not a full-history benchmark or an overnight reliability result. The full locked-phone overnight, range-loss and system-expiration matrix remains to be exercised on hardware. No fixed background timing guarantee is made.

A follow-up capture at 15:00:13 records a full 21-night pass completing in 52,516 ms. Additional input arrived during that pass, so the pending-work token correctly remained set. The crash inventory contained no new NOOP crash report since this installation; the newest listed fatal CPU report was from 13:25, before the update. This short startup check does not replace the overnight trial.
