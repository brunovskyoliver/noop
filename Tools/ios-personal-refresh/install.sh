#!/bin/bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 DEVICE_ID TEAM_ID BUNDLE_ID_PREFIX" >&2
    exit 64
fi

readonly DEVICE_ID="$1"
readonly TEAM_ID="$2"
readonly BUNDLE_ID_PREFIX="$3"
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LABEL="com.noopapp.personal-refresh"
readonly INSTALL_ROOT="${HOME}/Library/Application Support/NOOP Personal Refresh"
readonly INSTALLED_SCRIPT="${INSTALL_ROOT}/refresh-noop.sh"
readonly LOG_ROOT="${HOME}/Library/Logs/NOOPPersonalRefresh"
readonly LAUNCH_AGENT="${HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly USER_DOMAIN="gui/$(/usr/bin/id -u)"

/bin/mkdir -p "$INSTALL_ROOT" "$LOG_ROOT" "${HOME}/Library/LaunchAgents"
/usr/bin/install -m 0755 "${PROJECT_ROOT}/Tools/ios-personal-refresh/refresh-noop.sh" "$INSTALLED_SCRIPT"

/usr/bin/plutil -create xml1 "$LAUNCH_AGENT"
/usr/bin/plutil -insert Label -string "$LABEL" "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments -array "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments.0 -string "$INSTALLED_SCRIPT" "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables.NOOP_PROJECT_ROOT -string "$PROJECT_ROOT" "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables.NOOP_DEVICE_ID -string "$DEVICE_ID" "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables.NOOP_TEAM_ID -string "$TEAM_ID" "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables.NOOP_BUNDLE_ID_PREFIX -string "$BUNDLE_ID_PREFIX" "$LAUNCH_AGENT"
/usr/bin/plutil -insert EnvironmentVariables.NOOP_REFRESH_WINDOW_SECONDS -string '172800' "$LAUNCH_AGENT"
/usr/bin/plutil -insert RunAtLoad -bool true "$LAUNCH_AGENT"
/usr/bin/plutil -insert StartInterval -integer 3600 "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProcessType -string Background "$LAUNCH_AGENT"
/usr/bin/plutil -insert LowPriorityIO -bool true "$LAUNCH_AGENT"
/usr/bin/plutil -insert Nice -integer 10 "$LAUNCH_AGENT"
/usr/bin/plutil -insert ThrottleInterval -integer 300 "$LAUNCH_AGENT"
/usr/bin/plutil -insert StandardOutPath -string "${LOG_ROOT}/refresh.log" "$LAUNCH_AGENT"
/usr/bin/plutil -insert StandardErrorPath -string "${LOG_ROOT}/refresh-error.log" "$LAUNCH_AGENT"

/bin/launchctl bootout "$USER_DOMAIN" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "$USER_DOMAIN" "$LAUNCH_AGENT"
/bin/launchctl enable "${USER_DOMAIN}/${LABEL}"

echo "Installed ${LABEL}"
echo "The lightweight check runs at login and hourly."
echo "Logs: ${LOG_ROOT}/refresh.log"
