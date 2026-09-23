# Personal iOS refresh job

This private macOS LaunchAgent keeps a free-Apple-ID NOOP installation signed without leaving the Xcode GUI open.

The agent wakes at login and once an hour. It normally reads the four NOOP provisioning profiles and exits in under a second. When the earliest profile has less than 48 hours remaining, it checks whether the paired iPhone is reachable over USB or the local network. Only then does it archive the old NOOP profiles, run the command-line Xcode build with automatic signing, and install the new app bundle. A failed installation remains pending and is retried within an hour when the phone is reachable. It never launches `Xcode.app` and does not launch NOOP after a background refresh.

Install for one device:

```sh
Tools/ios-personal-refresh/install.sh DEVICE_ID TEAM_ID BUNDLE_ID_PREFIX
```

The Mac must be awake and logged in. Xcode must remain signed into the Apple Account, and the iPhone must be unlocked when iOS requires it. Wireless installation requires the already-paired phone to be reachable on the same local network.

Useful commands:

```sh
# Inspect the job
launchctl print gui/$(id -u)/com.noopapp.personal-refresh

# Follow its normal log
tail -f "$HOME/Library/Logs/NOOPPersonalRefresh/refresh.log"

# Force a renewal while the phone is reachable
NOOP_PROJECT_ROOT="$PWD" \
NOOP_DEVICE_ID="DEVICE_ID" \
NOOP_TEAM_ID="TEAM_ID" \
NOOP_BUNDLE_ID_PREFIX="BUNDLE_ID_PREFIX" \
Tools/ios-personal-refresh/refresh-noop.sh --force

# Disable it without deleting its state or profile backups
Tools/ios-personal-refresh/uninstall.sh
```

The generated app uses the Release configuration (a Debug `-Onone` build measured ~21% more CPU on device) and the Personal Team. It is not archived, uploaded, or distributed.
