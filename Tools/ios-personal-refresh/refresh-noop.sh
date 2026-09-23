#!/bin/bash

set -uo pipefail

readonly PROJECT_ROOT="${NOOP_PROJECT_ROOT:?NOOP_PROJECT_ROOT is required}"
readonly DEVICE_ID="${NOOP_DEVICE_ID:?NOOP_DEVICE_ID is required}"
readonly TEAM_ID="${NOOP_TEAM_ID:?NOOP_TEAM_ID is required}"
readonly BUNDLE_ID_PREFIX="${NOOP_BUNDLE_ID_PREFIX:?NOOP_BUNDLE_ID_PREFIX is required}"
readonly REFRESH_WINDOW_SECONDS="${NOOP_REFRESH_WINDOW_SECONDS:-172800}"
readonly STATE_ROOT="${NOOP_REFRESH_STATE_ROOT:-${HOME}/Library/Application Support/NOOP Personal Refresh}"
readonly DERIVED_DATA_ROOT="${NOOP_REFRESH_DERIVED_DATA:-${HOME}/Library/Caches/NOOPPersonalRefresh/DerivedData}"
readonly PROFILE_DIR_XCODE="${NOOP_PROFILE_DIR_XCODE:-${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles}"
readonly PROFILE_DIR_LEGACY="${NOOP_PROFILE_DIR_LEGACY:-${HOME}/Library/MobileDevice/Provisioning Profiles}"
readonly APP_PATH="${DERIVED_DATA_ROOT}/Build/Products/Release-iphoneos/NOOP Staging.app"
readonly LOCK_DIR="${STATE_ROOT}/refresh.lock"
readonly PENDING_INSTALL_FILE="${STATE_ROOT}/install-pending"
readonly -a EXPECTED_PROFILE_KINDS=('main' 'widgets' 'watch' 'complications')
LOCK_ACQUIRED=0

log() {
    printf '%s %s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

notify() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript -e "display notification \"${message}\" with title \"${title}\"" >/dev/null 2>&1 || true
}

iso_to_epoch() {
    /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null
}

profile_kind_for_app_id() {
    local app_identifier="$1"
    case "$app_identifier" in
        "${TEAM_ID}.${BUNDLE_ID_PREFIX}.noop") printf '%s\n' 'main' ;;
        "${TEAM_ID}.${BUNDLE_ID_PREFIX}.noop.widgets") printf '%s\n' 'widgets' ;;
        "${TEAM_ID}.${BUNDLE_ID_PREFIX}.noop.watch") printf '%s\n' 'watch' ;;
        "${TEAM_ID}.${BUNDLE_ID_PREFIX}.noop.watch.complications") printf '%s\n' 'complications' ;;
        *)
            return 1
            ;;
    esac
}

profile_matches_app_id() {
    profile_kind_for_app_id "$1" >/dev/null
}

read_profile_field() {
    local profile_path="$1"
    local field="$2"
    /usr/bin/security cms -D -i "$profile_path" 2>/dev/null \
        | /usr/bin/plutil -extract "$field" raw -o - - 2>/dev/null
}

find_profile_state() {
    local profile_dir
    local profile_path
    local app_identifier
    local expiry_iso
    local expiry_epoch
    local profile_kind

    PROFILE_MAIN_EXPIRY=0
    PROFILE_WIDGET_EXPIRY=0
    PROFILE_WATCH_EXPIRY=0
    PROFILE_COMPLICATION_EXPIRY=0

    for profile_dir in "$PROFILE_DIR_XCODE" "$PROFILE_DIR_LEGACY"; do
        [ -d "$profile_dir" ] || continue
        for profile_path in "$profile_dir"/*.mobileprovision; do
            [ -f "$profile_path" ] || continue
            app_identifier="$(read_profile_field "$profile_path" 'Entitlements.application-identifier')"
            profile_kind="$(profile_kind_for_app_id "$app_identifier")" || continue
            expiry_iso="$(read_profile_field "$profile_path" 'ExpirationDate')"
            expiry_epoch="$(iso_to_epoch "$expiry_iso")" || continue
            case "$profile_kind" in
                main)
                    [ "$expiry_epoch" -gt "$PROFILE_MAIN_EXPIRY" ] && PROFILE_MAIN_EXPIRY="$expiry_epoch"
                    ;;
                widgets)
                    [ "$expiry_epoch" -gt "$PROFILE_WIDGET_EXPIRY" ] && PROFILE_WIDGET_EXPIRY="$expiry_epoch"
                    ;;
                watch)
                    [ "$expiry_epoch" -gt "$PROFILE_WATCH_EXPIRY" ] && PROFILE_WATCH_EXPIRY="$expiry_epoch"
                    ;;
                complications)
                    [ "$expiry_epoch" -gt "$PROFILE_COMPLICATION_EXPIRY" ] && PROFILE_COMPLICATION_EXPIRY="$expiry_epoch"
                    ;;
            esac
        done
    done

    PROFILE_COUNT=0
    EARLIEST_EXPIRY_EPOCH=0
    for expiry_epoch in \
        "$PROFILE_MAIN_EXPIRY" \
        "$PROFILE_WIDGET_EXPIRY" \
        "$PROFILE_WATCH_EXPIRY" \
        "$PROFILE_COMPLICATION_EXPIRY"; do
        [ "$expiry_epoch" -gt 0 ] || continue
        PROFILE_COUNT=$((PROFILE_COUNT + 1))
        if [ "$EARLIEST_EXPIRY_EPOCH" -eq 0 ] || [ "$expiry_epoch" -lt "$EARLIEST_EXPIRY_EPOCH" ]; then
            EARLIEST_EXPIRY_EPOCH="$expiry_epoch"
        fi
    done
}

refresh_is_due() {
    local profile_count="$1"
    local earliest_expiry="$2"
    local current_epoch="$3"
    local refresh_window="$4"
    local install_pending="${5:-0}"

    [ "$install_pending" -eq 1 ] && return 0
    [ "$profile_count" -lt "${#EXPECTED_PROFILE_KINDS[@]}" ] && return 0
    [ "$earliest_expiry" -le $((current_epoch + refresh_window)) ]
}

phone_is_reachable() {
    local destinations
    destinations="$(/usr/bin/xcodebuild \
        -project "${PROJECT_ROOT}/Strand.xcodeproj" \
        -scheme NOOPiOS \
        -showdestinations 2>&1)" || return 1
    printf '%s\n' "$destinations" | /usr/bin/grep -Fq "platform:iOS, arch:arm64, id:${DEVICE_ID},"
}

acquire_lock() {
    local holder_pid=''
    local holder_start=''
    local live_start=''
    local lock_mtime=0
    local current_epoch=0
    local stale_lock_root="${STATE_ROOT}/stale-locks"
    local stale_lock_path

    if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "${LOCK_DIR}/pid"
        process_start_marker "$$" > "${LOCK_DIR}/process-start"
        LOCK_ACQUIRED=1
        return 0
    fi

    if [ ! -f "${LOCK_DIR}/pid" ] || [ ! -f "${LOCK_DIR}/process-start" ]; then
        lock_mtime="$(/usr/bin/stat -f '%m' "$LOCK_DIR" 2>/dev/null || printf '%s' 0)"
        current_epoch="$(/bin/date -u '+%s')"
        if [ "$lock_mtime" -gt 0 ] && [ $((current_epoch - lock_mtime)) -lt 30 ]; then
            return 1
        fi
    fi

    [ -f "${LOCK_DIR}/pid" ] && holder_pid="$(/bin/cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
    [ -f "${LOCK_DIR}/process-start" ] && holder_start="$(/bin/cat "${LOCK_DIR}/process-start" 2>/dev/null || true)"
    case "$holder_pid" in
        ''|*[!0-9]*) ;;
        *)
            if /bin/kill -0 "$holder_pid" 2>/dev/null; then
                live_start="$(process_start_marker "$holder_pid")"
                [ -n "$holder_start" ] && [ "$live_start" = "$holder_start" ] && return 1
            fi
            ;;
    esac

    /bin/mkdir -p "$stale_lock_root"
    stale_lock_path="${stale_lock_root}/refresh.lock.$(/bin/date -u '+%Y%m%dT%H%M%SZ').$$"
    /bin/mv "$LOCK_DIR" "$stale_lock_path" 2>/dev/null || return 1
    /bin/mkdir "$LOCK_DIR" 2>/dev/null || return 1
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
    process_start_marker "$$" > "${LOCK_DIR}/process-start"
    LOCK_ACQUIRED=1
}

process_start_marker() {
    /bin/ps -p "$1" -o lstart= 2>/dev/null
}

release_lock() {
    local holder_pid=''
    [ "$LOCK_ACQUIRED" -eq 1 ] || return 0
    [ -f "${LOCK_DIR}/pid" ] && holder_pid="$(/bin/cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
    [ "$holder_pid" = "$$" ] || return 0
    /bin/rm -f "${LOCK_DIR}/pid" "${LOCK_DIR}/process-start"
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_ACQUIRED=0
}

archive_matching_profiles() {
    local backup_root="$1"
    local profile_dir
    local profile_path
    local app_identifier
    local directory_label

    for profile_dir in "$PROFILE_DIR_XCODE" "$PROFILE_DIR_LEGACY"; do
        [ -d "$profile_dir" ] || continue
        if [ "$profile_dir" = "$PROFILE_DIR_XCODE" ]; then
            directory_label='xcode-userdata'
        else
            directory_label='mobiledevice'
        fi
        /bin/mkdir -p "${backup_root}/${directory_label}"

        for profile_path in "$profile_dir"/*.mobileprovision; do
            [ -f "$profile_path" ] || continue
            app_identifier="$(read_profile_field "$profile_path" 'Entitlements.application-identifier')"
            profile_matches_app_id "$app_identifier" || continue
            /bin/mv "$profile_path" "${backup_root}/${directory_label}/"
        done
    done
}

run_refresh() {
    local backup_root
    local current_epoch
    local expiry_remaining
    local install_pending=0
    local profiles_need_renewal=0

    /bin/mkdir -p "$STATE_ROOT" "$DERIVED_DATA_ROOT"
    if ! acquire_lock; then
        log 'Another refresh process is already running; exiting.'
        return 0
    fi
    trap 'release_lock' EXIT

    find_profile_state
    current_epoch="$(/bin/date -u '+%s')"
    [ -f "$PENDING_INSTALL_FILE" ] && install_pending=1
    if refresh_is_due "$PROFILE_COUNT" "$EARLIEST_EXPIRY_EPOCH" "$current_epoch" "$REFRESH_WINDOW_SECONDS" 0; then
        profiles_need_renewal=1
    fi

    if [ "${1:-}" != '--force' ] && ! refresh_is_due "$PROFILE_COUNT" "$EARLIEST_EXPIRY_EPOCH" "$current_epoch" "$REFRESH_WINDOW_SECONDS" "$install_pending"; then
        expiry_remaining=$((EARLIEST_EXPIRY_EPOCH - current_epoch))
        log "Profiles remain valid for $((expiry_remaining / 3600)) hours; no work needed."
        return 0
    fi

    log 'A signing refresh is due; checking for the paired iPhone.'
    if ! phone_is_reachable; then
        log 'The paired iPhone is not reachable by USB or the paired local network; will retry later.'
        return 0
    fi

    if [ "${1:-}" = '--force' ] || [ "$profiles_need_renewal" -eq 1 ]; then
        backup_root="${STATE_ROOT}/profile-backups/$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
        /bin/mkdir -p "$backup_root"
        archive_matching_profiles "$backup_root"
    fi
    /usr/bin/touch "$PENDING_INSTALL_FILE"

    log 'Renewing profiles and building NOOP with command-line Xcode tools.'
    if ! /usr/bin/xcodebuild \
        -project "${PROJECT_ROOT}/Strand.xcodeproj" \
        -scheme NOOPiOS \
        -configuration Release \
        -destination "platform=iOS,id=${DEVICE_ID}" \
        -derivedDataPath "$DERIVED_DATA_ROOT" \
        -allowProvisioningUpdates \
        -quiet \
        COMPILER_INDEX_STORE_ENABLE=NO \
        build; then
        log 'Build or signing failed. The existing phone installation was not removed.'
        notify 'NOOP refresh failed' 'The signed build failed. Check the refresh log on the Mac.'
        return 1
    fi

    if [ ! -d "$APP_PATH" ]; then
        log "Build succeeded, but the expected app bundle is missing: ${APP_PATH}"
        notify 'NOOP refresh failed' 'The built app bundle could not be found.'
        return 1
    fi

    log 'Installing the refreshed app on the paired iPhone.'
    if ! /usr/bin/xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
        log 'Installation failed; the job will retry on its next scheduled run.'
        notify 'NOOP refresh failed' 'The iPhone was found, but installation failed. Keep it unlocked for the next retry.'
        return 1
    fi

    /bin/date -u '+%Y-%m-%dT%H:%M:%SZ' > "${STATE_ROOT}/last-success.txt"
    /bin/rm -f "$PENDING_INSTALL_FILE"
    log 'NOOP was re-signed and installed successfully. Xcode.app was not launched.'
    notify 'NOOP refreshed' 'The seven-day development signature was renewed.'
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_refresh "${1:-}"
fi
