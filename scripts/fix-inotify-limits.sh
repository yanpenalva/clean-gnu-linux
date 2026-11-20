#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/sysctl.d/60-inotify.conf"
MAX_USER_INSTANCES=512
MAX_USER_WATCHES=262144

if (( EUID != 0 )); then
    printf 'Error: run this script as root.\n' >&2
    exit 1
fi

conflicting_files=()
assignment_pattern='^[[:space:]]*-?fs[./]inotify[./]max_user_(instances|watches)[[:space:]]*='
for file in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
    [[ "$file" == "$CONFIG_FILE" || ! -f "$file" ]] && continue
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $assignment_pattern ]]; then
            conflicting_files+=("$file")
            break
        fi
    done < "$file"
done

if (( ${#conflicting_files[@]} > 0 )); then
    printf 'Error: conflicting inotify assignments in:\n' >&2
    printf '%s\n' "${conflicting_files[@]}" >&2
    exit 1
fi

printf 'fs.inotify.max_user_instances = %s\nfs.inotify.max_user_watches = %s\n' \
    "$MAX_USER_INSTANCES" "$MAX_USER_WATCHES" > "$CONFIG_FILE"

sysctl -p "$CONFIG_FILE" >/dev/null

live_instances=$(sysctl -n fs.inotify.max_user_instances)
live_watches=$(sysctl -n fs.inotify.max_user_watches)
if [[ "$live_instances" != "$MAX_USER_INSTANCES" || "$live_watches" != "$MAX_USER_WATCHES" ]]; then
    printf 'Error: inotify verification failed: max_user_instances=%s, max_user_watches=%s.\n' \
        "$live_instances" "$live_watches" >&2
    exit 1
fi

printf 'Applied fs.inotify.max_user_instances=%s and fs.inotify.max_user_watches=%s.\n' \
    "$MAX_USER_INSTANCES" "$MAX_USER_WATCHES"
