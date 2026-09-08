# Clean GNU/Linux - Automating System Maintenance 🧹

Clean GNU/Linux is an automated maintenance and cleanup script tailored for Debian and Ubuntu-based Linux distributions. It helps maintain a lean, healthy, and performant operating system by automating routine garbage collection, package housekeeping, cache pruning, and log maintenance—while upholding strict safeguards against accidental data loss.

---

## 📑 Navigation Guide / Table of Contents

- [🌟 Key Features & Safeguards](#-key-features--safeguards)
- [🚀 Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [📖 CLI Options Reference](#-cli-options-reference)
- [💡 Usage Examples](#-usage-examples)
  - [1. Safe Dry-Run Simulation](#1-safe-dry-run-simulation)
  - [2. Routine Maintenance](#2-routine-maintenance-caches-only-no-system-upgrade)
  - [3. Deep Docker Cleanup](#3-deep-docker-cleanup-including-unused-volumes)
  - [4. Server Maintenance](#4-server-maintenance-system-only-keep-user-caches)
- [📋 Logging & Auditing](#-logging--auditing)
- [⏰ Automated Scheduling](#-automated-scheduling)
  - [Option A: Cron Job](#option-a-cron-job-weekly)
  - [Option B: Systemd Timer](#option-b-systemd-timer)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## 🌟 Key Features & Safeguards

- **Safe Package Management**:
    - Updates and upgrades packages (`apt update`, `apt upgrade`, `apt full-upgrade`, `autoremove`, `autoclean`).
    - Can be easily bypassed with `--skip-upgrade` for quick cache-only cleanups.
    - Detects package managers without forcefully installing missing tools.
    - Cleans Flatpak unused runtimes/packages and disabled Snap revisions automatically when present.
- **Kernel Boot Protection**:
    - Automatically identifies obsolete Linux kernel packages while **strictly protecting both the running kernel and the newest installed kernel**. This avoids removing the newly installed kernel before rebooting.
- **Safe Docker Cleanup**:
    - Prunes stopped containers, orphan networks, build cache, and dangling images by default.
    - **Protects persistent volumes and tagged images by default**: requires explicit opt-in flags (`--docker-volumes` / `--docker-all`).
- **User & Browser Cache Optimization**:
    - Safely clears temporary cache files (`~/.cache`, browser render/disk caches for Chrome, Chromium, Firefox, Brave, Edge).
    - **Preserves browser session logins, cookies (`cookies.sqlite`), and bookmarks**.
    - Empties user trash directories (`~/.local/share/Trash`).
    - Easily skipped via `--skip-user-cache`.
- **Accurate Dry-Run Mode**:
    - Preview exactly what files, directories, kernels, and resources would be cleaned without modifying your system.
- **Automation Ready (Cron & Systemd)**:
    - Quiet mode (`--quiet`) and TTY auto-detection to suppress ANSI escape sequences and spinner animations in non-interactive pipelines.

---

## 🚀 Getting Started

### Prerequisites

- A Debian-based Linux distribution (Debian, Ubuntu, Linux Mint, Pop!\_OS, etc.).
- Root privileges (`sudo`) for system-level cleanups.
- Bash 4.0+.

### Installation

1. **Clone the repository:**

    ```bash
    git clone https://github.com/yanbrasiliano/clean-gnu-linux.git
    cd clean-gnu-linux
    ```

2. **Make the script executable:**

    ```bash
    chmod +x cleaning.sh
    ```

3. **Run the script:**
    ```bash
    sudo ./cleaning.sh [options]
    ```

---

## 📖 CLI Options Reference

| Flag                | Description                                                                     | Default |
| :------------------ | :------------------------------------------------------------------------------ | :-----: |
| `--dry-run`         | Simulates all actions and prints affected items without making any changes.     |   Off   |
| `--skip-upgrade`    | Skips system package updates (`apt update`, `apt upgrade`, `apt full-upgrade`). |   Off   |
| `--skip-user-cache` | Skips cleaning user home directories (`~/.cache`, browser caches, trash).       |   Off   |
| `--skip-kernels`    | Skips detection and removal of obsolete kernel packages.                        |   Off   |
| `--skip-docker`     | Skips all Docker cleanup routines.                                              |   Off   |
| `--skip-journal`    | Skips systemd journal vacuuming.                                                |   Off   |
| `--docker-volumes`  | Prunes unused Docker volumes (**Warning**: permanent volume deletion).          |   Off   |
| `--docker-all`      | Prunes all unused Docker images (not just dangling ones).                       |   Off   |
| `--no-verbose`      | Suppresses detailed output lines (verbose output is enabled by default).        |   Off   |
| `--quiet`           | Suppresses all console output except fatal errors (recommended for cron).       |   Off   |
| `--backup-logs`     | Archives old log files instead of truncating them when rotating.                |   Off   |
| `--help`            | Displays the help message with usage guidelines.                                |    -    |

---

## 💡 Usage Examples

### 1. Safe Dry-Run Simulation

Preview everything that will be cleaned, with estimated file counts and sizes:

```bash
sudo ./cleaning.sh --dry-run
```

### 2. Routine Maintenance (Caches Only, No System Upgrade)

Perform complete disk cleanup while keeping existing package versions unchanged:

```bash
sudo ./cleaning.sh --skip-upgrade
```

### 3. Deep Docker Cleanup (Including Unused Volumes)

Clean system and reclaim space from unused Docker containers, images, and volumes:

```bash
sudo ./cleaning.sh --docker-volumes --docker-all
```

### 4. Server Maintenance (System Only, Keep User Caches)

Clean system packages, logs, and journals without touching `/home/*`:

```bash
sudo ./cleaning.sh --skip-user-cache
```

---

## 📋 Logging & Auditing

All operations and errors are logged with timestamps and user credentials:

- **Standard log**: `/var/log/system_cleaner.log`
- **Error log**: `/var/log/system_cleaner_errors.log`

Logs automatically rotate when they exceed 100MB. Use `--backup-logs` if you want rotated logs preserved as `.old` archives instead of being truncated.

---

## ⏰ Automated Scheduling

### Option A: Cron Job (Weekly)

To run the cleanup script quietly every Sunday at 03:00 AM without running package upgrades:

1. Open root crontab:
    ```bash
    sudo crontab -e
    ```
2. Add the following entry:
    ```cron
    0 3 * * 0 /usr/local/bin/cleaning.sh --quiet --skip-upgrade >> /var/log/system_cleaner_cron.log 2>&1
    ```

### Option B: Systemd Timer

1. Create a service file `/etc/systemd/system/clean-gnu-linux.service`:

    ```ini
    [Unit]
    Description=Clean GNU/Linux Maintenance Task
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/cleaning.sh --quiet --skip-upgrade
    ```

2. Create a timer file `/etc/systemd/system/clean-gnu-linux.timer`:

    ```ini
    [Unit]
    Description=Weekly Clean GNU/Linux Maintenance

    [Timer]
    OnCalendar=weekly
    Persistent=true

    [Install]
    WantedBy=timers.target
    ```

3. Enable and activate the timer:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable --now clean-gnu-linux.timer
    ```

---

## 🤝 Contributing

Contributions, bug reports, and suggestions are welcome!

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/new-cleanup`).
3. Commit your changes (`git commit -m 'Add support for X cache'`).
4. Push to the branch (`git push origin feature/new-cleanup`).
5. Open a Pull Request.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
