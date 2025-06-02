#!/usr/bin/env bash

set -e

unalias rm 2>/dev/null || true
unset -f rm 2>/dev/null || true

trap 'echo "An error occurred. Exiting..." >&2; exit 1' ERR

VERSION="1.1.0"

[[ $EUID -eq 0 ]] || {
    echo "This script must be run as root." >&2
    exit 1
}

LOG_FILE="/var/log/system_cleaner.log"
ERROR_LOG="/var/log/system_cleaner_errors.log"
SLEEP_TIME=1
DRY_RUN=0
SKIP_DOCKER=0
SKIP_JOURNAL=0
VERBOSE=1
MAX_LOG_SIZE=100
BACKUP_LOGS=0

log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "----------[ $(whoami) ${timestamp} ]---------- $1" >>"${LOG_FILE}"
    [[ $VERBOSE -eq 1 ]] && echo "$1"
}

error_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "ERROR [${timestamp}]: $1" >>"${ERROR_LOG}"
    echo -e "\e[31mERROR: $1\e[0m" >&2
}

rotate_logs() {
    for logfile in "${LOG_FILE}" "${ERROR_LOG}"; do
        if [[ -f "$logfile" ]]; then
            local size=$(du -m "$logfile" | cut -f1)
            if [[ $size -gt $MAX_LOG_SIZE ]]; then
                if [[ $BACKUP_LOGS -eq 1 ]]; then
                    mv "$logfile" "${logfile}.$(date +%Y%m%d%H%M%S).old"
                else
                    >"$logfile"
                    log_message "Log file $logfile rotated (truncated)"
                fi
            fi
        fi
    done
}

clean_directory() {
    local dir=$1
    local days=${2:-0}
    local exclude=${3:-""}

    if [[ -n "$dir" && -d "$dir" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            if [[ $days -gt 0 ]]; then
                echo "Dry-run: Would clean files older than $days days in $dir"
            else
                echo "Dry-run: Would clean all files in $dir"
            fi
        else
            log_message "Cleaning $dir..."
            echo "Cleaning $dir..."

            local find_cmd="find \"$dir\" -mindepth 1"

            if [[ $days -gt 0 ]]; then
                find_cmd+=" -mtime +$days"
            fi

            if [[ -n "$exclude" ]]; then
                for pattern in $(echo "$exclude" | tr "," " "); do
                    find_cmd+=" -not -name \"$pattern\""
                done
            fi

            local before_size=$(du -sh "$dir" 2>/dev/null | cut -f1)

            if [[ $VERBOSE -eq 1 ]]; then
                echo "Size before cleaning: $before_size"
                if [[ $days -gt 0 ]]; then
                    echo "Finding files older than $days days in $dir..."
                    eval "$find_cmd -type f -ls"
                fi
            fi

            find_cmd+=" -exec /bin/rm -rf {} \; 2>/dev/null || true"

            eval "$find_cmd"

            local after_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_message "Directory $dir: Before=$before_size, After=$after_size"

            if [[ $VERBOSE -eq 1 ]]; then
                echo "Size after cleaning: $after_size"
            fi
        fi
    else
        error_message "Directory $dir not found, skipping."
    fi
    sleep "${SLEEP_TIME}"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
    local status=$?
    if [ $status -ne 0 ]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would install $1"
        else
            echo "Installing $1..."
            apt update -qq && apt install -y "$1"
            if command -v "$1" >/dev/null 2>&1; then
                echo "$1 installed successfully."
                return 0
            else
                error_message "Failed to install $1."
                return 1
            fi
        fi
    fi
    return 0
}

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n "Processing "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    echo "Done!"
}

print_help() {
    echo "System Cleaner Script v${VERSION}"
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --dry-run         Simulate actions without making changes"
    echo "  --skip-docker     Skip Docker cleanup"
    echo "  --skip-journal    Skip systemd journal cleanup"
    echo "  --no-verbose      Disable verbose output (verbose is ON by default)"
    echo "  --backup-logs     Backup log files instead of truncating them"
    echo "  --help            Show this help message"
    echo
    echo "Example: $0 --skip-docker"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --dry-run) DRY_RUN=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-journal) SKIP_JOURNAL=1 ;;
    --no-verbose) VERBOSE=0 ;;
    --backup-logs) BACKUP_LOGS=1 ;;
    --help) print_help ;;
    *)
        echo "Unknown parameter: $1" >&2
        echo "Use --help for usage information."
        exit 1
        ;;
    esac
    shift
done

perform_package_cleanup() {
    log_message "Performing package cache cleanup"

    if check_command apt-get; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would clean package caches"
        else
            echo "Cleaning package caches..."
            if [[ $VERBOSE -eq 1 ]]; then
                apt clean -y
            else
                apt clean -y &
                show_spinner $!
            fi
        fi
    fi

    if check_command flatpak; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would clean Flatpak unused packages"
        else
            echo "Cleaning Flatpak unused runtimes and packages..."
            if [[ $VERBOSE -eq 1 ]]; then
                flatpak uninstall --unused -y
            else
                flatpak uninstall --unused -y &>/dev/null &
                show_spinner $!
            fi
        fi
    fi

    # Uncomment this block if you use Snap packages
    # if check_command snap; then
    #     if [[ "$DRY_RUN" -eq 1 ]]; then
    #         echo "Dry-run: Would clean Snap caches"
    #     else
    #         echo "Cleaning Snap caches..."
    #         set +e
    #         snap set system refresh.retain=2 &>/dev/null
    #         if [[ $VERBOSE -eq 1 ]]; then
    #             echo "Listing disabled snaps to remove:"
    #             snap list --all | awk '/disabled/{print $1, $3}'
    #         fi
    #         snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    #             if [[ $VERBOSE -eq 1 ]]; then
    #                 echo "Removing snap: $snapname (revision $revision)"
    #                 snap remove "$snapname" --revision="$revision"
    #             else
    #                 snap remove "$snapname" --revision="$revision" &>/dev/null
    #             fi
    #         done
    #         set -e
    #     fi
    # fi
}

perform_cleanup() {
    log_message "Starting filesystem cleanup"

    clean_directory "/home/*/.cache/thumbnails" 0
    clean_directory "/root/.cache/pip" 30
    clean_directory "/root/.npm" 30
    clean_directory "/root/.composer/cache" 30
    for user_home in /home/*; do
        clean_directory "$user_home/.cache/pip" 30
        clean_directory "$user_home/.npm" 30
        clean_directory "$user_home/.composer/cache" 30
    done

    echo "Removing orphaned packages..."
    if ! check_command deborphan; then
        echo "Installing deborphan..."
        apt update -qq && apt install -y deborphan
    fi
    deborphan | xargs -r apt -y remove --purge

    echo "Find and delete temporary files..."
    find /home /tmp /var /root -type f \( -name "*.bak" -o -name "*.old" -o -name "*.tmp" -o -name "core.*" \) -print

    declare -A dirs_retention
    dirs_retention=(
        ["/var/cache/apt/archives"]=0
        ["/var/tmp"]=7
        ["/var/log"]=30:"*.gz,*.old"
        ["/var/crash"]=0
        ["/var/backups"]=30
        ["/tmp"]=2
    )

    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            username=$(basename "$user_home")

            declare -A user_dirs
            user_dirs=(
                ["$user_home/.cache"]=30
                ["$user_home/.local/share/Trash"]=0
                ["$user_home/.thumbnails"]=30
                ["$user_home/.mozilla/firefox/*/cache2"]=0
                ["$user_home/.config/google-chrome/Default/Cache"]=0
                ["$user_home/.config/chromium/Default/Cache"]=0
            )

            for dir in "${!user_dirs[@]}"; do
                retention=${user_dirs[$dir]}
                clean_directory "$dir" "$retention" &
            done
        fi
    done

    for dir in "${!dirs_retention[@]}"; do
        IFS=':' read -r retention exclude <<<"${dirs_retention[$dir]}"
        clean_directory "$dir" "$retention" "$exclude" &
    done

    clean_directory "/root/.cache" 30 &

    wait
}

update_system() {
    log_message "Starting APT operations"

    tries=0
    while ! apt update -y; do
        ((tries++))
        [[ $tries -ge 5 ]] && error_message "APT locked too long. Aborting." && return 1
        echo "APT locked, waiting..."
        sleep 5
    done

    if ! check_command apt-get; then
        error_message "aptnot found. Cannot perform system update."
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "Dry-run: Would update and upgrade system packages"
    else
        echo 'Updating package lists...'
        if [[ $VERBOSE -eq 1 ]]; then
            apt update -y
        else
            apt update -y &
            show_spinner $!
        fi

        echo 'Upgrading packages...'
        if [[ $VERBOSE -eq 1 ]]; then
            apt upgrade -y
        else
            apt upgrade -y &
            show_spinner $!
        fi

        echo 'Performing full upgrade...'
        if [[ $VERBOSE -eq 1 ]]; then
            apt full-upgrade -y
        else
            apt full-upgrade -y &
            show_spinner $!
        fi

        echo 'Removing unused packages...'
        if [[ $VERBOSE -eq 1 ]]; then
            apt autoremove --purge -y
        else
            apt autoremove --purge -y &
            show_spinner $!
        fi

        echo 'Cleaning APT cache...'
        if [[ $VERBOSE -eq 1 ]]; then
            apt autoclean
        else
            apt autoclean &
            show_spinner $!
        fi
    fi
}

clean_journal() {
    if [[ "$SKIP_JOURNAL" -eq 1 ]]; then
        echo "Skipping systemd journal cleanup as per user request."
    elif check_command journalctl; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would vacuum systemd journal"
        else
            echo 'Vacuuming systemd journal...'
            if [[ $VERBOSE -eq 1 ]]; then
                echo "Journal size before cleanup:"
                journalctl --disk-usage

                echo "Vacuuming journal entries older than 14 days..."
                journalctl --vacuum-time=14d

                echo "Limiting journal size to 500MB..."
                journalctl --vacuum-size=500M

                echo "Journal size after cleanup:"
                journalctl --disk-usage
            else
                journalctl --vacuum-time=14d &
                show_spinner $!
                journalctl --vacuum-size=500M &
                show_spinner $!
            fi
        fi
    else
        log_message "journalctl not found, skipping journal cleanup."
    fi
}

clean_old_kernels() {
    if check_command dpkg; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would remove old kernels"
        else
            echo 'Checking for old kernels...'

            current_kernel=$(uname -r | sed 's/-generic//')

            installed_kernels=$(dpkg -l | grep -E 'linux-image-[0-9]+' | grep -v "$current_kernel" | awk '{print $2}')

            if [[ -n "$installed_kernels" ]]; then
                echo "Found old kernels to remove."
                if [[ $VERBOSE -eq 1 ]]; then
                    echo "Current kernel: $current_kernel"
                    echo "Old kernels to remove:"
                    echo "$installed_kernels"
                fi

                for kernel in $installed_kernels; do
                    echo "Removing old kernel: $kernel"
                    if [[ $VERBOSE -eq 1 ]]; then
                        apt purge -y "$kernel"
                    else
                        apt purge -y "$kernel" &>/dev/null &
                        show_spinner $!
                    fi
                done

                if [[ $VERBOSE -eq 1 ]]; then
                    apt autoremove -y
                else
                    apt autoremove -y &>/dev/null &
                    show_spinner $!
                fi
            else
                echo "No old kernels found to remove."
            fi
        fi
    fi
}

clean_docker() {
    if [[ "$SKIP_DOCKER" -eq 1 ]]; then
        echo "Skipping Docker cleanup as per user request."
    elif check_command docker; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run: Would clean Docker system"
        else
            echo 'Cleaning Docker...'

            if [[ $VERBOSE -eq 1 ]]; then
                echo "Docker disk usage before cleanup:"
                docker system df
            fi

            echo 'Removing stopped containers...'
            if [[ $VERBOSE -eq 1 ]]; then
                docker container prune -f
            else
                docker container prune -f &
                show_spinner $!
            fi

            echo 'Removing unused images...'
            if [[ $VERBOSE -eq 1 ]]; then
                docker image prune -f
            else
                docker image prune -f &
                show_spinner $!
            fi

            echo 'Removing unused volumes...'
            if [[ $VERBOSE -eq 1 ]]; then
                docker volume prune -f
            else
                docker volume prune -f &
                show_spinner $!
            fi

            echo 'Removing unused networks...'
            if [[ $VERBOSE -eq 1 ]]; then
                docker network prune -f
            else
                docker network prune -f &
                show_spinner $!
            fi

            echo 'Performing full Docker cleanup...'
            if [[ $VERBOSE -eq 1 ]]; then
                docker system prune -a -f --volumes
                echo "Docker disk usage after cleanup:"
                docker system df
            else
                docker system prune -a -f --volumes &
                show_spinner $!
            fi
        fi
    else
        log_message "Docker not found, skipping Docker cleanup."
    fi
}

clean_browser_cache() {
    log_message "Cleaning browser caches"

    for profile_path in /home/*/.mozilla/firefox/*/; do
        if [[ -d "$profile_path" ]]; then
            clean_directory "${profile_path}cache2" 0 &
            clean_directory "${profile_path}thumbnails" 0 &
            clean_directory "${profile_path}cookies.sqlite" 0 &
        fi
    done

    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            chrome_path="${user_home}/.config/google-chrome/Default/Cache"
            if [[ -d "$chrome_path" ]]; then
                clean_directory "$chrome_path" 0 &
            fi

            chromium_path="${user_home}/.config/chromium/Default/Cache"
            if [[ -d "$chromium_path" ]]; then
                clean_directory "$chromium_path" 0 &
            fi
        fi
    done

    wait
}

# Uncomment the following line to enable the remove_duplicates function
# remove_duplicates() {
#     if check_command fdupes; then
#         if [[ "$DRY_RUN" -eq 1 ]]; then
#             echo "Dry-run: Would search for and list duplicate files in /home"
#         else
#             echo "Searching for duplicate files in /home (this may take a while)..."
#             if [[ $VERBOSE -eq 1 ]]; then
#                 fdupes -r /home -f | tee /tmp/duplicates.txt
#             else
#                 fdupes -r /home -f > /tmp/duplicates.txt
#             fi
#             echo "Duplicate files listed in /tmp/duplicates.txt"
#             echo "To remove duplicates automatically, install fdupes and run: fdupes -r -d -N /home"
#         fi
#     else
#         log_message "fdupes not found. Install it with 'apt install fdupes' to find duplicate files."
#     fi
# }

show_space_report() {
    echo
    echo "====== Space Usage Report ======"
    df -h / /home /var /tmp | column -t
    echo
    # Uncomment if you  want to see the largest directories in /home and / and sort by size
    # echo "Largest directories:"
    # du -sh /* 2>/dev/null | sort -hr | head -10
    # echo "Space usage by user:"
    # du -sh /home/* 2>/dev/null | sort -hr | head -10
    echo "====== Space Usage General ======"
    df -h
    echo
}

main() {
    echo "System Cleaner v${VERSION} starting..."
    echo "$(date): Starting cleanup process" | tee -a "${LOG_FILE}"

    rotate_logs

    update_system
    perform_package_cleanup
    perform_cleanup
    clean_journal
    clean_old_kernels
    clean_docker
    clean_browser_cache
    # remove_duplicates

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "Dry-run completed. No changes were made."
    else
        echo "System cleanup completed successfully."
        show_space_report
    fi

    log_message "Cleanup process completed"
}

main
