#!/bin/bash

set -euo pipefail

readonly LABEL="com.noopapp.personal-refresh"
readonly LAUNCH_AGENT="${HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly USER_DOMAIN="gui/$(/usr/bin/id -u)"
readonly RETIRED_ROOT="${HOME}/Library/Application Support/NOOP Personal Refresh Retired $(/bin/date -u '+%Y%m%dT%H%M%SZ')"

/bin/launchctl bootout "$USER_DOMAIN" "$LAUNCH_AGENT" >/dev/null 2>&1 || true

if [ -f "$LAUNCH_AGENT" ]; then
    /bin/mkdir -p "$RETIRED_ROOT"
    /bin/mv "$LAUNCH_AGENT" "$RETIRED_ROOT/"
fi

if [ -d "${HOME}/Library/Application Support/NOOP Personal Refresh" ]; then
    /bin/mkdir -p "$RETIRED_ROOT"
    /bin/mv "${HOME}/Library/Application Support/NOOP Personal Refresh" "$RETIRED_ROOT/"
fi

echo "Disabled ${LABEL}. Its files were moved to: ${RETIRED_ROOT}"
