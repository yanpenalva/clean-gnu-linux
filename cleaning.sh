#!/usr/bin/env bash

set -e

unalias rm 2>/dev/null || true
unset -f rm 2>/dev/null || true

trap 'echo "An error occurred. Exiting..." >&2; exit 1' ERR

VERSION="1.2.0"

# Configuration defaults
LOG_FILE="/var/log/system_cleaner.log"
ERROR_LOG="/var/log/system_cleaner_errors.log"
SLEEP_TIME=1
MAX_LOG_SIZE=100
BACKUP_LOGS=0

# Operational flags
DRY_RUN=0
VERBOSE=1
QUIET=0
SKIP_UPGRADE=0
SKIP_USER_CACHE=0
SKIP_KERNELS=0
SKIP_DOCKER=0
SKIP_JOURNAL=0
DOCKER_VOLUMES=0
DOCKER_ALL=0

# Interactive / TTY detection
IS_TTY=0
if [[ -t 1 && -t 2 ]]; then
    IS_TTY=1
fi

# Terminal colors
if [[ $IS_TTY -eq 1 ]]; then
    COLOR_RED="\e[31m"
    COLOR_GREEN="\e[32m"
    COLOR_YELLOW="\e[33m"
    COLOR_CYAN="\e[36m"
    COLOR_RESET="\e[0m"
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_RESET=""
fi

log_message() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local user_info
    user_info=$(whoami 2>/dev/null || echo "root")
    echo "----------[ ${user_info} ${timestamp} ]---------- $1" >>"${LOG_FILE}" 2>/dev/null || true
    if [[ $QUIET -eq 0 && $VERBOSE -eq 1 ]]; then
        echo -e "$1"
    fi
}

error_message() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "ERROR [${timestamp}]: $1" >>"${ERROR_LOG}" 2>/dev/null || true
    if [[ $QUIET -eq 0 ]]; then
        echo -e "${COLOR_RED}ERROR: $1${COLOR_RESET}" >&2
    fi
}

info_message() {
    if [[ $QUIET -eq 0 ]]; then
        echo -e "$1"
    fi
}

rotate_logs() {
    for logfile in "${LOG_FILE}" "${ERROR_LOG}"; do
        if [[ -f "$logfile" ]]; then
            local size
            size=$(du -m "$logfile" 2>/dev/null | cut -f1)
            if [[ -n "$size" && $size -gt $MAX_LOG_SIZE ]]; then
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

check_command() {
    command -v "$1" >/dev/null 2>&1
}

show_spinner() {
    local pid=$1
    if [[ $QUIET -eq 1 || $IS_TTY -eq 0 ]]; then
        wait "$pid" 2>/dev/null || true
        return 0
    fi

    local delay=0.1
    local spinstr='|/-\'
    echo -n "Processing "
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    echo "Done!"
}

clean_directory() {
    local target_path=$1
    local days=${2:-0}
    local exclude=${3:-""}

    # Resolve glob expansion for passed target path
    local -a expanded_dirs=()
    shopt -s nullglob
    # shellcheck disable=SC2206
    expanded_dirs=($target_path)
    shopt -u nullglob

    if [[ ${#expanded_dirs[@]} -eq 0 ]]; then
        if [[ -d "$target_path" ]]; then
            expanded_dirs=("$target_path")
        else
            return 0
        fi
    fi

    for dir in "${expanded_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi

        local -a find_args=("$dir" "-mindepth" "1")
        if [[ $days -gt 0 ]]; then
            find_args+=("-mtime" "+$days")
        fi

        if [[ -n "$exclude" ]]; then
            local IFS=','
            for pattern in $exclude; do
                find_args+=("!" "-name" "$pattern")
            done
            unset IFS
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            local file_count
            file_count=$(find "${find_args[@]}" 2>/dev/null | wc -l)
            local dir_size
            dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            if [[ $days -gt 0 ]]; then
                info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would clean items older than $days days in $dir ($file_count items matched, dir size: ${dir_size:-0})"
            else
                info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would clean all items in $dir ($file_count items matched, dir size: ${dir_size:-0})"
            fi
        else
            local before_size
            before_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_message "Cleaning $dir (retention: ${days}d, size before: ${before_size})..."

            # Execute deletion safely and efficiently
            find "${find_args[@]}" -depth -exec rm -rf -- {} + 2>/dev/null || true

            local after_size
            after_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_message "Directory $dir cleaned: Before=$before_size, After=$after_size"
        fi
    done
}

print_help() {
    echo -e "${COLOR_CYAN}System Cleaner Script v${VERSION}${COLOR_RESET}"
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --dry-run           Simulate actions without making changes"
    echo "  --skip-upgrade      Skip system package updates and upgrades (apt update/upgrade)"
    echo "  --skip-user-cache   Skip cleaning user directories (~/.cache, trash, browser caches)"
    echo "  --skip-kernels      Skip old kernel cleanup"
    echo "  --skip-docker       Skip Docker cleanup"
    echo "  --skip-journal      Skip systemd journal cleanup"
    echo "  --docker-volumes    Prune unused Docker volumes (CAUTION: permanent data deletion)"
    echo "  --docker-all        Prune all unused images, stopped containers, networks, and build cache"
    echo "  --no-verbose        Disable verbose output (verbose is ON by default)"
    echo "  --quiet             Mute console output completely (for background/cron jobs)"
    echo "  --backup-logs       Backup log files instead of truncating them when rotating"
    echo "  --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --dry-run                    # Simulate cleanup"
    echo "  $0 --skip-upgrade               # Clean caches without upgrading packages"
    echo "  $0 --skip-docker --quiet        # Clean system quietly without touching Docker"
    echo "  $0 --docker-volumes             # Clean system including unused Docker volumes"
    exit 0
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
    --dry-run) DRY_RUN=1 ;;
    --skip-upgrade) SKIP_UPGRADE=1 ;;
    --skip-user-cache) SKIP_USER_CACHE=1 ;;
    --skip-kernels) SKIP_KERNELS=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-journal) SKIP_JOURNAL=1 ;;
    --docker-volumes) DOCKER_VOLUMES=1 ;;
    --docker-all) DOCKER_ALL=1 ;;
    --no-verbose) VERBOSE=0 ;;
    --quiet) QUIET=1; VERBOSE=0 ;;
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

# Root privilege check (unless --help was called)
if [[ $EUID -ne 0 ]]; then
    echo -e "${COLOR_RED}This script must be run as root (or with sudo).${COLOR_RESET}" >&2
    exit 1
fi

update_system() {
    if [[ $SKIP_UPGRADE -eq 1 ]]; then
        info_message "Skipping system package updates as requested (--skip-upgrade)."
        return 0
    fi

    if ! check_command apt-get; then
        log_message "apt-get not found. Skipping system update."
        return 0
    fi

    log_message "Starting APT operations"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would run apt update, upgrade, full-upgrade, autoremove, autoclean"
        return 0
    fi

    local tries=0
    while ! apt-get update -qq; do
        ((tries++))
        if [[ $tries -ge 5 ]]; then
            error_message "APT package database locked or network unavailable. Skipping update."
            return 1
        fi
        info_message "APT locked, waiting..."
        sleep 5
    done

    info_message "Upgrading packages..."
    if [[ $VERBOSE -eq 1 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    else
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y &>/dev/null &
        show_spinner $!
    fi

    info_message "Performing full upgrade..."
    if [[ $VERBOSE -eq 1 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    else
        DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y &>/dev/null &
        show_spinner $!
    fi

    info_message "Removing unused packages..."
    if [[ $VERBOSE -eq 1 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    else
        DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y &>/dev/null &
        show_spinner $!
    fi

    info_message "Cleaning APT cache..."
    if [[ $VERBOSE -eq 1 ]]; then
        apt-get autoclean -y
    else
        apt-get autoclean -y &>/dev/null &
        show_spinner $!
    fi
}

perform_package_cleanup() {
    log_message "Performing package cache cleanup"

    if check_command apt-get; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would clean apt archives cache"
        else
            info_message "Cleaning APT package cache..."
            if [[ $VERBOSE -eq 1 ]]; then
                apt-get clean -y
            else
                apt-get clean -y &>/dev/null &
                show_spinner $!
            fi
        fi
    fi

    if check_command flatpak; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would uninstall unused Flatpak runtimes and packages"
        else
            info_message "Cleaning Flatpak unused runtimes and packages..."
            if [[ $VERBOSE -eq 1 ]]; then
                flatpak uninstall --unused -y 2>/dev/null || true
            else
                flatpak uninstall --unused -y &>/dev/null &
                show_spinner $!
            fi
        fi
    fi

    if check_command snap; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would clean disabled Snap package revisions and retain settings"
        else
            info_message "Cleaning disabled Snap revisions..."
            snap set system refresh.retain=2 2>/dev/null || true
            local disabled_snaps
            disabled_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}') || true
            if [[ -n "$disabled_snaps" ]]; then
                while read -r snapname revision; do
                    [[ -z "$snapname" || -z "$revision" ]] && continue
                    info_message "Removing disabled snap: $snapname (revision $revision)"
                    snap remove "$snapname" --revision="$revision" 2>/dev/null || true
                done <<<"$disabled_snaps"
            fi
        fi
    fi
}

perform_cleanup() {
    log_message "Starting filesystem cleanup"

    # Clean root development/tool caches
    clean_directory "/root/.cache/pip" 30
    clean_directory "/root/.npm" 30
    clean_directory "/root/.composer/cache" 30
    clean_directory "/root/.cache" 30

    # Clean system temporary and logging directories
    clean_directory "/var/cache/apt/archives" 0
    clean_directory "/var/tmp" 7
    clean_directory "/var/log" 30 "*.gz,*.old"
    clean_directory "/var/crash" 0
    clean_directory "/var/backups" 30
    clean_directory "/tmp" 2

    # User directory cleanup
    if [[ $SKIP_USER_CACHE -eq 1 ]]; then
        info_message "Skipping user home cache cleanup as requested (--skip-user-cache)."
        return 0
    fi

    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            # Developer caches
            clean_directory "$user_home/.cache/pip" 30
            clean_directory "$user_home/.npm" 30
            clean_directory "$user_home/.composer/cache" 30

            # General caches and trash
            clean_directory "$user_home/.cache/thumbnails" 0
            clean_directory "$user_home/.thumbnails" 30
            clean_directory "$user_home/.local/share/Trash" 0
            clean_directory "$user_home/.cache" 30
        fi
    done
}

clean_browser_cache() {
    if [[ $SKIP_USER_CACHE -eq 1 ]]; then
        return 0
    fi

    log_message "Cleaning browser caches"

    # Firefox cache (preserving cookies, sqlite databases, logins and preferences)
    for profile_path in /home/*/.mozilla/firefox/*/; do
        if [[ -d "$profile_path" ]]; then
            clean_directory "${profile_path}cache2" 0
            clean_directory "${profile_path}jumpListCache" 0
            clean_directory "${profile_path}startupCache" 0
        fi
    done

    # Chromium-based browser caches (Chrome, Chromium, Brave, Edge)
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            # Google Chrome
            clean_directory "${user_home}/.config/google-chrome/Default/Cache" 0
            clean_directory "${user_home}/.config/google-chrome/Default/Code Cache" 0
            clean_directory "${user_home}/.config/google-chrome/Default/GPUCache" 0

            # Chromium
            clean_directory "${user_home}/.config/chromium/Default/Cache" 0
            clean_directory "${user_home}/.config/chromium/Default/Code Cache" 0
            clean_directory "${user_home}/.config/chromium/Default/GPUCache" 0

            # Brave Browser
            clean_directory "${user_home}/.config/BraveSoftware/Brave-Browser/Default/Cache" 0
            clean_directory "${user_home}/.config/BraveSoftware/Brave-Browser/Default/Code Cache" 0
            clean_directory "${user_home}/.config/BraveSoftware/Brave-Browser/Default/GPUCache" 0

            # Microsoft Edge
            clean_directory "${user_home}/.config/microsoft-edge/Default/Cache" 0
            clean_directory "${user_home}/.config/microsoft-edge/Default/Code Cache" 0
            clean_directory "${user_home}/.config/microsoft-edge/Default/GPUCache" 0
        fi
    done
}

clean_journal() {
    if [[ "$SKIP_JOURNAL" -eq 1 ]]; then
        info_message "Skipping systemd journal cleanup as per user request (--skip-journal)."
        return 0
    fi

    if ! check_command journalctl; then
        log_message "journalctl not found, skipping journal cleanup."
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would vacuum systemd journal (entries older than 14d and size > 500M)"
    else
        info_message "Vacuuming systemd journal..."
        if [[ $VERBOSE -eq 1 ]]; then
            info_message "Journal size before cleanup:"
            journalctl --disk-usage 2>/dev/null || true
            journalctl --vacuum-time=14d 2>/dev/null || true
            journalctl --vacuum-size=500M 2>/dev/null || true
            info_message "Journal size after cleanup:"
            journalctl --disk-usage 2>/dev/null || true
        else
            journalctl --vacuum-time=14d &>/dev/null || true
            journalctl --vacuum-size=500M &>/dev/null || true
        fi
    fi
}

clean_old_kernels() {
    if [[ $SKIP_KERNELS -eq 1 ]]; then
        info_message "Skipping kernel cleanup as requested (--skip-kernels)."
        return 0
    fi

    if ! check_command dpkg; then
        return 0
    fi

    info_message "Checking for obsolete kernels..."
    local running_kernel
    running_kernel=$(uname -r)

    # Get all installed linux-image package names with version numbers
    local installed_images
    installed_images=$(dpkg -l | awk '/^ii  linux-image-[0-9]/ {print $2}' | sort -V)

    if [[ -z "$installed_images" ]]; then
        info_message "No kernel images managed via dpkg found."
        return 0
    fi

    # Find the newest installed kernel (highest version)
    local newest_installed_image
    newest_installed_image=$(echo "$installed_images" | tail -n 1)

    # Filter out kernels to remove
    local kernels_to_remove=""
    for pkg in $installed_images; do
        # Always protect currently running kernel
        if [[ "$pkg" == *"$running_kernel"* ]]; then
            continue
        fi
        # Always protect the newest installed kernel image (preserves bootable kernel after upgrade without reboot)
        if [[ "$pkg" == "$newest_installed_image" ]]; then
            continue
        fi
        kernels_to_remove+="$pkg "
    done

    kernels_to_remove=$(echo "$kernels_to_remove" | xargs)

    if [[ -z "$kernels_to_remove" ]]; then
        info_message "No obsolete kernels found to remove. (Running: $running_kernel, Latest: $newest_installed_image)"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would safely remove obsolete kernels: $kernels_to_remove"
        info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Protected kernels: Running ($running_kernel), Newest installed ($newest_installed_image)"
    else
        info_message "Removing obsolete kernels: $kernels_to_remove"
        log_message "Purging obsolete kernels: $kernels_to_remove (Protected: $running_kernel, $newest_installed_image)"

        # shellcheck disable=SC2086
        if [[ $VERBOSE -eq 1 ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get purge -y $kernels_to_remove || apt-get --fix-broken install -y
            DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
        else
            DEBIAN_FRONTEND=noninteractive apt-get purge -y $kernels_to_remove &>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y &>/dev/null || true
        fi
    fi
}

clean_docker() {
    if [[ "$SKIP_DOCKER" -eq 1 ]]; then
        info_message "Skipping Docker cleanup as requested (--skip-docker)."
        return 0
    fi

    if ! check_command docker; then
        # Docker not installed: skip cleanly without warning or attempting install
        return 0
    fi

    # Check if docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_message "Docker daemon is not running, skipping Docker cleanup."
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would prune stopped containers, unused networks, and dangling images"
        if [[ $DOCKER_ALL -eq 1 ]]; then
            info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would prune ALL unreferenced Docker images (--docker-all)"
        fi
        if [[ $DOCKER_VOLUMES -eq 1 ]]; then
            info_message "${COLOR_YELLOW}[Dry-run]${COLOR_RESET} Would prune unused Docker volumes (--docker-volumes)"
        fi
        return 0
    fi

    info_message "Cleaning Docker resources..."

    if [[ $VERBOSE -eq 1 ]]; then
        info_message "Docker disk usage before cleanup:"
        docker system df 2>/dev/null || true
    fi

    # Standard safe cleanup
    docker container prune -f >/dev/null 2>&1 || true
    docker network prune -f >/dev/null 2>&1 || true

    if [[ $DOCKER_ALL -eq 1 ]]; then
        info_message "Pruning all unused Docker images (--docker-all)..."
        docker image prune -a -f >/dev/null 2>&1 || true
    else
        info_message "Pruning dangling Docker images..."
        docker image prune -f >/dev/null 2>&1 || true
    fi

    docker builder prune -f >/dev/null 2>&1 || true

    if [[ $DOCKER_VOLUMES -eq 1 ]]; then
        info_message "${COLOR_YELLOW}Pruning unused Docker volumes (--docker-volumes)...${COLOR_RESET}"
        docker volume prune -f >/dev/null 2>&1 || true
    fi

    if [[ $VERBOSE -eq 1 ]]; then
        info_message "Docker disk usage after cleanup:"
        docker system df 2>/dev/null || true
    fi
}

show_space_report() {
    if [[ $QUIET -eq 1 ]]; then
        return 0
    fi

    echo
    echo -e "${COLOR_CYAN}====== Space Usage Report ======${COLOR_RESET}"
    df -h / /home /var /tmp 2>/dev/null | column -t || df -h /
    echo
}

main() {
    rotate_logs

    log_message "Clean GNU/Linux v${VERSION} starting (DryRun=${DRY_RUN}, SkipUpgrade=${SKIP_UPGRADE}, SkipUserCache=${SKIP_USER_CACHE})"

    info_message "${COLOR_GREEN}Clean GNU/Linux v${VERSION} starting...${COLOR_RESET}"

    update_system
    perform_package_cleanup
    perform_cleanup
    clean_browser_cache
    clean_journal
    clean_old_kernels
    clean_docker

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info_message "${COLOR_YELLOW}Dry-run completed. No changes were made.${COLOR_RESET}"
    else
        info_message "${COLOR_GREEN}System cleanup completed successfully.${COLOR_RESET}"
        show_space_report
    fi

    log_message "Cleanup process completed"
}

main
