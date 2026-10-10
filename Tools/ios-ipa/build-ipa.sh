#!/bin/bash
# Archives NOOPiOS and exports an ad-hoc .ipa that installs on every iPhone registered to the team
# (developer.apple.com → Devices). Register a new phone first, then rebuild: the ad-hoc profile
# only lists devices that existed when it was generated.
#
# Uses the team, bundle prefix and App Group from Config/BundleIdSecrets.xcconfig and the Apple
# Account signed into Xcode; automatic signing creates the Apple Distribution certificate and the
# ad-hoc profiles on first use.
#
# The build number is a UTC timestamp, so every build is unique without editing project.yml.
# Pass --testflight to upload to App Store Connect instead (needs the app record there).

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly BUILD_NUMBER="$(/bin/date -u '+%Y%m%d.%H%M')"
readonly WORK="${NOOP_TESTFLIGHT_DIR:-${TMPDIR:-/tmp}/noop-testflight}/${BUILD_NUMBER}"
readonly ARCHIVE="${WORK}/NOOP.xcarchive"
METHOD=release-testing
DESTINATION=export
if [ "${1:-}" = "--testflight" ]; then METHOD=app-store-connect; DESTINATION=upload; fi

cd "$PROJECT_ROOT"
/bin/mkdir -p "$WORK"
xcodegen generate --quiet

xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates archive CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

readonly TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:Team' "${ARCHIVE}/Info.plist")"
/usr/bin/plutil -create xml1 "${WORK}/ExportOptions.plist"
/usr/bin/plutil -insert method -string "$METHOD" "${WORK}/ExportOptions.plist"
/usr/bin/plutil -insert destination -string "$DESTINATION" "${WORK}/ExportOptions.plist"
/usr/bin/plutil -insert teamID -string "$TEAM_ID" "${WORK}/ExportOptions.plist"
/usr/bin/plutil -insert signingStyle -string automatic "${WORK}/ExportOptions.plist"
/usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool false "${WORK}/ExportOptions.plist"

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "${WORK}/export" \
    -exportOptionsPlist "${WORK}/ExportOptions.plist" -allowProvisioningUpdates

echo "Build ${BUILD_NUMBER} (${METHOD}): ${WORK}/export"
