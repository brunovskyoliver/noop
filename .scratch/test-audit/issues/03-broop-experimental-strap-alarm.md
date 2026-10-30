# Broop experimental strap alarm control

Requested on 2026-10-19. The sleep planner said a WHOOP 5/MG alarm required
Experimental mode, but the Broop Experimental page did not expose that setting.
The user requested the fix and opt-in on both the iPhone Air and iPhone 16 Pro.

## Cause and change

The existing firmware alarm gate reads `PuffinExperiment.isEnabled`, backed by
`noopPuffinExperiments`. Test Centre exposed that preference as Protocol probes;
the redesigned Broop Experimental page omitted it while the planner still sent
users there.

- Added the existing Protocol probes switch under Strap wake-alarm in the Broop
  Experimental page. It uses the same default-off preference as Test Centre.
- Added a direct Experimental link beside the blocked 5/MG alarm explanation.
- The planner observes the preference with `@AppStorage`, so its warning updates
  when the setting changes.
- Opting in reapplies an already-enabled 5/MG alarm through the existing
  `AppModel.applySmartAlarm()` path. The callback is gated on the alarm being
  enabled and a 5/MG being selected; it does not disarm an unrelated alarm when
  someone only enables protocol probes.
- Reused existing translated strings and shared Broop components/design tokens.
  No protocol command, decoder, stored health value or analytics formula changed.
  This is an iOS screen wiring repair; Android and shared BLE code were not edited.

## Verification

A bounded source reproduction failed on the original page because no control
bound the actual gate. After the repair it passed. Runtime verification uses the
existing iPhone 18 Pro simulator, with synthetic demo data only.

- The iOS simulator Debug build passed.
- UI navigation reached App Settings > Experimental and found the new switch off
  by default. Tapping it wrote the existing preference as true.
- After terminating and reopening the app, UI navigation found the switch still
  on. The simulator's stored preference was also true.
- `doc_comment_lint.py` passed with no new detached comments.
- All labels and the switch description already have entries in the existing
  string catalog; no new localization keys were introduced.

- Final simulator Debug and signed device Release builds passed after the last
  source change. Deep/strict signature verification passed; the main app and
  widget provisioning profiles include both phones.
- The final Release app was installed on the iPhone Air and iPhone 16 Pro.
  Initial launch attempts encountered auto-locked phones; both subsequently
  launched successfully after the user unlocked them.
- Remote debugger attempts did not verify writing the preference. The user
  instead enabled the visible switch and explicitly confirmed it was enabled on
  both phones. This is user confirmation, not a successful debugger readback.

A scheduled wake on a physical strap has not been tested; the existing
experimental and backup-alarm guidance remains. The alarm warning's direct link
was compiled, but its complete navigation/arming flow was not exercised.

## Cleanup

The temporary build and debugging output was retained briefly for the immediately
following dashboard repair, recorded in `04-broop-dashboard-activity.md`. That
report records the final cleanup of the shared disposable output.
