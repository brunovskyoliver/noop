#!/bin/bash

set -euo pipefail

export NOOP_PROJECT_ROOT='/tmp/noop-test-project'
export NOOP_DEVICE_ID='test-device'
export NOOP_TEAM_ID='TEAM123'
export NOOP_BUNDLE_ID_PREFIX='com.example'
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/noop-personal-refresh-test.XXXXXX")"
export NOOP_REFRESH_STATE_ROOT="${TEST_ROOT}/state"
export NOOP_REFRESH_DERIVED_DATA="${TEST_ROOT}/derived-data"
export NOOP_PROFILE_DIR_XCODE="${TEST_ROOT}/profiles-xcode"
export NOOP_PROFILE_DIR_LEGACY="${TEST_ROOT}/profiles-legacy"

source "$(dirname "$0")/refresh-noop.sh"

assert_success() {
    local description="$1"
    shift
    if ! "$@"; then
        echo "FAIL: ${description}" >&2
        exit 1
    fi
}

assert_failure() {
    local description="$1"
    shift
    if "$@"; then
        echo "FAIL: ${description}" >&2
        exit 1
    fi
}

assert_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: ${description}: expected '${expected}', got '${actual}'" >&2
        exit 1
    fi
}

assert_success 'main app profile matches' profile_matches_app_id 'TEAM123.com.example.noop'
assert_success 'widget profile matches' profile_matches_app_id 'TEAM123.com.example.noop.widgets'
assert_success 'watch profile matches' profile_matches_app_id 'TEAM123.com.example.noop.watch'
assert_success 'watch complication profile matches' profile_matches_app_id 'TEAM123.com.example.noop.watch.complications'
assert_failure 'another app profile does not match' profile_matches_app_id 'TEAM123.com.example.other'
assert_failure 'another team does not match' profile_matches_app_id 'OTHER.com.example.noop'

assert_success 'missing profiles require refresh' refresh_is_due 3 2000 1000 100
assert_success 'profile inside refresh window requires refresh' refresh_is_due 4 1099 1000 100
assert_failure 'profile outside refresh window does not require refresh' refresh_is_due 4 1101 1000 100
assert_success 'pending installation retries despite fresh profiles' refresh_is_due 4 9999 1000 100 1

assert_equal 'ISO timestamp parsing is UTC-stable' '1789586787' "$(iso_to_epoch '2026-09-16T19:26:27Z')"

mkdir -p "$NOOP_PROFILE_DIR_XCODE" "$NOOP_PROFILE_DIR_LEGACY"
touch \
    "$NOOP_PROFILE_DIR_XCODE/main-old.mobileprovision" \
    "$NOOP_PROFILE_DIR_XCODE/main-new.mobileprovision" \
    "$NOOP_PROFILE_DIR_XCODE/widgets.mobileprovision" \
    "$NOOP_PROFILE_DIR_XCODE/watch.mobileprovision" \
    "$NOOP_PROFILE_DIR_LEGACY/main-duplicate.mobileprovision" \
    "$NOOP_PROFILE_DIR_LEGACY/complications.mobileprovision"

read_profile_field() {
    local profile_name="$(basename "$1")"
    local field="$2"
    if [ "$field" = 'Entitlements.application-identifier' ]; then
        case "$profile_name" in
            main-*) printf '%s\n' 'TEAM123.com.example.noop' ;;
            widgets.*) printf '%s\n' 'TEAM123.com.example.noop.widgets' ;;
            watch.*) printf '%s\n' 'TEAM123.com.example.noop.watch' ;;
            complications.*) printf '%s\n' 'TEAM123.com.example.noop.watch.complications' ;;
        esac
    else
        case "$profile_name" in
            main-old.*) printf '%s\n' '2026-09-17T00:00:00Z' ;;
            main-new.*|main-duplicate.*) printf '%s\n' '2026-09-23T00:00:00Z' ;;
            widgets.*) printf '%s\n' '2026-09-22T00:00:00Z' ;;
            watch.*) printf '%s\n' '2026-09-21T00:00:00Z' ;;
            complications.*) printf '%s\n' '2026-09-20T00:00:00Z' ;;
        esac
    fi
}

find_profile_state
assert_equal 'duplicates still produce four distinct profiles' '4' "$PROFILE_COUNT"
assert_equal 'newest duplicate is selected and earliest distinct expiry wins' \
    "$(iso_to_epoch '2026-09-20T00:00:00Z')" "$EARLIEST_EXPIRY_EPOCH"
mv "$NOOP_PROFILE_DIR_XCODE/watch.mobileprovision" "${TEST_ROOT}/watch.disabled"
find_profile_state
assert_equal 'a missing required identifier reduces profile count' '3' "$PROFILE_COUNT"

BACKUP_ROOT="${TEST_ROOT}/backup"
archive_matching_profiles "$BACKUP_ROOT"
find_profile_state
assert_equal 'archiving moves every NOOP profile aside' '0' "$PROFILE_COUNT"
touch "$NOOP_PROFILE_DIR_XCODE/widgets.mobileprovision"
restore_archived_profiles "$BACKUP_ROOT"
find_profile_state
assert_equal 'a failed renewal restores the archived profiles' '3' "$PROFILE_COUNT"
assert_success 'a profile already present is not overwritten' \
    test -f "${BACKUP_ROOT}/xcode-userdata/widgets.mobileprovision"

mkdir -p "$LOCK_DIR"
assert_failure 'a newly created incomplete lock is treated as active' acquire_lock
rmdir "$LOCK_DIR"

mkdir -p "$LOCK_DIR"
printf '%s\n' '999999' > "${LOCK_DIR}/pid"
printf '%s\n' 'dead process start' > "${LOCK_DIR}/process-start"
assert_success 'a stale lock is reclaimed' acquire_lock
assert_equal 'the reclaimed lock belongs to this process' "$$" "$(cat "${LOCK_DIR}/pid")"
release_lock
assert_failure 'release removes the owned lock directory' test -d "$LOCK_DIR"

mkdir -p "$LOCK_DIR"
printf '%s\n' "$$" > "${LOCK_DIR}/pid"
printf '%s\n' 'reused pid with another start time' > "${LOCK_DIR}/process-start"
assert_success 'a reused live PID does not preserve a stale lock' acquire_lock
release_lock

mkdir -p "$LOCK_DIR"
printf '%s\n' "$$" > "${LOCK_DIR}/pid"
process_start_marker "$$" > "${LOCK_DIR}/process-start"
assert_failure 'a matching live owner keeps its lock' acquire_lock
rm -f "${LOCK_DIR}/pid" "${LOCK_DIR}/process-start"
rmdir "$LOCK_DIR"

echo 'PASS: personal refresh policy tests'
