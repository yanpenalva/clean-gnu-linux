#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1090
source <(awk '/^[a-z_]+\(\) \{/ {printing=1} printing {print} /^}/ {printing=0}' "$script_dir/cleaning.sh")

sandbox=$(mktemp -d /tmp/opencode/cleaning-test.XXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
LOG_FILE="$sandbox/cleaner.log"
ERROR_LOG="$sandbox/errors.log"
DRY_RUN=0
QUIET=1
VERBOSE=0
IS_TTY=0
FAILURES=0
COLOR_YELLOW=""
COLOR_RED=""
COLOR_RESET=""
MAX_LOG_SIZE=0
BACKUP_LOGS=0

target="$sandbox/Code Cache"
mkdir -p "$target/old directory" "$target/nested/keep-dir/empty" "$target/empty"
touch "$target/old directory/old" "$target/old directory/new" \
    "$target/nested/keep.log" "$target/nested/keep-dir/preserved" \
    "$target/"$'old\nfile'
touch -d '40 days ago' "$target/old directory/old" "$target/nested/keep.log" \
    "$target/nested/keep-dir/preserved" "$target/"$'old\nfile' "$target/old directory"
touch "$sandbox/outside"
ln -s "$sandbox/outside" "$target/link"

clean_directory "$target" 30 'keep*,*.log'
[[ ! -e "$target/old directory/old" && ! -e "$target/"$'old\nfile' ]]
[[ -f "$target/old directory/new" && -f "$target/nested/keep.log" ]]
[[ -f "$target/nested/keep-dir/preserved" && -d "$target/nested/keep-dir/empty" ]]
[[ ! -d "$target/empty" && -L "$target/link" && -f "$sandbox/outside" ]]
[[ $FAILURES -eq 0 ]]

DRY_RUN=1
QUIET=0
printf 'unchanged\n' >"$LOG_FILE"
printf 'unchanged\n' >"$ERROR_LOG"
before=$(find "$sandbox" -printf '%P %y %T@ %s\n' | sort)
output=$(clean_directory "$target" 0 'keep*,*.log')
[[ "$output" == *"Would clean 1 files"* && "$output" == *estimate* ]]
clean_directory "$target" 0 'keep*,*.log' >/dev/null
rotate_logs
log_message "must not be written" >/dev/null
error_message "must not be written" 2>/dev/null
after=$(find "$sandbox" -printf '%P %y %T@ %s\n' | sort)
[[ "$before" == "$after" ]]
[[ $(<"$LOG_FILE") == unchanged && $(<"$ERROR_LOG") == unchanged ]]

QUIET=1
(exit 7) &
status=0
show_spinner $! || status=$?
[[ $status -eq 7 ]]
QUIET=0
(exit 9) &
status=0
show_spinner $! || status=$?
[[ $status -eq 9 ]]

printf 'cleaning tests passed\n'
