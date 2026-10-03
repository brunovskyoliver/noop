# Overnight iPhone sync stops after a bond-loop pause

## Report

On 2026-10-02, the installed Broop app had not caught up with overnight strap data until it was opened around 08:30. The phone stayed near the strap. The requested behavior is automatic sync with the phone locked or the app backgrounded, plus a reminder to reopen the app if sync stops after it is closed.

## Evidence and cause

The paired physical iPhone runs iOS 27.0.1 (24A446), with Broop 11.8.0, build 415, bundle identifier `com.oliverbrunovsky.noop`.

Saved logs record regular overnight offloads, then short post-bond disconnects at 01:43:19, 01:43:29 and 01:43:51. The latter two are CoreBluetooth connection timeouts. At 01:43:51, the post-bond detector pauses active reconnecting. The last recorded offload attempt is 01:43:44; the next is 08:25:14, after the morning open. The captured-trace check fails on this 6h 41m 30s gap.

`didDisconnectPeripheral` invokes the pause recovery before clearing `LiveState.connected`. The recovery's connected guard rejects the first request. Later in the same callback, the paused branch runs after the state reset, but its ten-minute floor rejects the second request. No standing connect remains with CoreBluetooth. The recovery helper tests reproduce this exact two-call sequence, with four failed assertions before the fix and zero afterward.

Background processing was also running: an extended scoring pass completed in 163 seconds with a reported 43% CPU share. This does not establish a CPU termination. The reconnect pause has direct evidence and is the repaired cause.

## Changes

- Retain the first passive recovery request across the disconnect-state reset. Consume it only when a standing connect is submitted; preserve it if the Bluetooth radio or target is unavailable. Keep the cooldown for subsequent attempts and clear pending recovery on successful bonding, manual reconnect, disconnect, or removal.
- Replace the disconnect message that blamed every pause on a pairing refusal with wording that also accounts for observed short post-bond timeouts.
- Register a bundle-derived `.strapsync` BGAppRefresh task at app launch and permit it in both the XcodeGen source and iOS plist. Each delivery requests another opportunity, repairs an eligible missing reconnect, or uses the existing adaptive sync gate on a connected link. Waiting is bounded to 25 seconds; an outstanding connection is not reported as a completed offload. Submission and expiration failures are recorded.
- Pre-schedule a local sync-stopped reminder with iOS. Each completed offload moves its deadline; live heart rate and app opens do not reset freshness. Default warning threshold is 30 minutes, extended to twice the selected sync interval for power saving. Explicit Disconnect, removal, source changes, and disabling the setting cancel monitoring. The reminder remains queued if the process is killed or swiped away.
- Add the reminder switch to Broop's existing Notifications page using the shared toggle and design tokens. Add all nine shipped non-English translations for the four new strings.

No protocol bytes, stored health values, database schemas, analytics formulas, or Android behavior changed. Android already posts its paused-recovery work to the handler, after disconnect cleanup, so the synchronous Apple callback-order bug does not apply there. BGAppRefresh and the queued force-quit fallback are iOS mechanisms.

## Verification

- Standalone recovery loop: observed four assertion failures before the fix; zero after.
- macOS application compiled and 39 targeted app tests passed, covering pause recovery, radio-unavailable recovery, user teardown, cooldowns, existing bond-loop/reconnect policies, bounded refresh completion/expiration, and reminder deadlines.
- Signed iOS Release build succeeded with the existing personal bundle identity, team, and extensions. The signed bundle declares `bluetooth-central`, `fetch`, and `processing`; its `.strapsync` identifier expands to its actual bundle identifier. Deep signature verification passed.
- `git diff --check` and detached doc-comment lint pass.
- New strings pass the translation audit's extraction, focus-locale, and English-echo checks. The full audit remains red on pre-existing non-focus-locale allowance overflows. Comparing all shipped locales against HEAD finds zero new missing translations. Those existing failures were not changed or baselined away.

## Remaining

The final incremental signed Release build and all 39 targeted tests passed after lifecycle wiring and translation updates. The verified app is saved at `~/agent-runs/2026-10-02-ios-background-sync/Broop.app`. Its provisioning profile has a 365-day lifetime, expires on 2027-10-01, and provisions HealthKit background delivery and the App Group. The user approved installation. The replacement was installed successfully on the paired iPhone under the same bundle identity. After the user unlocked and opened it, the strap connected at 16:14:31 and the first historical offload committed 1,170 rows at 16:14:35. The recent three-night scoring pass completed in 9,074 ms. A later captured preference snapshot showed no outstanding analysis debt, and sync-reminder monitoring was initialized.

The first locked-phone interval began at 16:17:15. CoreDevice reported that a passcode was required and the device had been unlocked since boot. The debugger was detached and no device commands ran during the wait. However, the app recorded a foreground sync at 16:20:29, before the five-minute interval ended. The capture therefore does not validate an unattended background offload. The strict trace validator rejects it for that foreground transition. The phone no longer required a passcode at the final check. A six-minute repeat was proposed; the user explicitly chose to skip the remaining phone test, and device testing stopped.

Outstanding hardware checks: a completed historical offload throughout a locked-phone interval, queued reminder delivery after sync stops, out-of-range recovery, and an unattended overnight trial. These are deferred at the user's request. Startup behavior is verified on the real strap; sustained background reliability is not yet verified. No app or device changes beyond the authorized installation were made.

Apple does not guarantee BGAppRefresh delivery times. Bluetooth restoration normally does not relaunch an app after a user force-quit, and there is no reliable force-quit callback. Therefore the queued notification names stale sync rather than claiming the app was closed. Locking the phone is compatible with Bluetooth background sync; automatic sync cannot be guaranteed in every phone state.

Sources: [Bluetooth relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules), [background task earliest start](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate), [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
