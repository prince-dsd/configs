#!/usr/bin/env bash

set -u

# ============================================================
# Linux Root Partition Cleanup Utility
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root:"
    echo "  sudo $0"
    exit 1
fi

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

run() {
    if $DRY_RUN; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 bytes"
}

show_disk_usage() {
    echo
    echo "========================================"
    echo " Root Partition Usage"
    echo "========================================"
    df -h /
    echo
}

show_largest_dirs() {
    echo
    echo "========================================"
    echo " Largest directories on /"
    echo "========================================"

    du -xhd1 / 2>/dev/null | sort -hr | head -15

    echo
    echo "Largest directories under /var:"
    du -xhd1 /var 2>/dev/null | sort -hr | head -15

    echo
    echo "Largest directories under /home:"
    du -xhd1 /home 2>/dev/null | sort -hr | head -15
}

clean_apt() {
    if command -v apt-get >/dev/null 2>&1; then
        echo
        echo "[APT] Cleaning package cache..."

        run apt-get clean
        run apt-get autoclean
        run apt-get autoremove -y
    fi
}

clean_dnf() {
    if command -v dnf >/dev/null 2>&1; then
        echo
        echo "[DNF] Cleaning package cache..."

        run dnf clean all
        run dnf autoremove -y
    fi
}

clean_yum() {
    if command -v yum >/dev/null 2>&1; then
        echo
        echo "[YUM] Cleaning package cache..."

        run yum clean all
    fi
}

clean_pacman() {
    if command -v pacman >/dev/null 2>&1; then
        echo
        echo "[PACMAN] Cleaning package cache..."

        # Keep the currently installed packages' cache.
        # -Sc removes packages that are no longer installed.
        run pacman -Sc --noconfirm
    fi
}

clean_zypper() {
    if command -v zypper >/dev/null 2>&1; then
        echo
        echo "[ZYPPER] Cleaning package cache..."

        run zypper clean --all
    fi
}

clean_journal() {
    if command -v journalctl >/dev/null 2>&1; then
        echo
        echo "[SYSTEMD] Cleaning old journal logs..."

        echo "Current journal size:"
        journalctl --disk-usage 2>/dev/null || true

        echo
        echo "Choose journal cleanup:"
        echo "  1) Keep last 7 days"
        echo "  2) Keep last 3 days"
        echo "  3) Keep only 500 MB"
        echo "  4) Skip"

        read -rp "Choice [1-4]: " choice

        case "$choice" in
            1)
                run journalctl --vacuum-time=7d
                ;;
            2)
                run journalctl --vacuum-time=3d
                ;;
            3)
                run journalctl --vacuum-size=500M
                ;;
            *)
                echo "Skipping journal cleanup."
                ;;
        esac
    fi
}

clean_tmp() {
    echo
    echo "[TMP] Cleaning temporary files..."

    # Only delete files older than 7 days.
    if [[ -d /tmp ]]; then
        run find /tmp -xdev -type f -mtime +7 -delete
    fi

    if [[ -d /var/tmp ]]; then
        run find /var/tmp -xdev -type f -mtime +30 -delete
    fi
}

clean_crash_reports() {
    echo
    echo "[CRASH] Cleaning old crash reports..."

    if [[ -d /var/crash ]]; then
        run find /var/crash -type f -mtime +30 -delete
    fi
}

clean_old_kernels_debian() {
    if command -v apt >/dev/null 2>&1; then
        echo
        echo "[KERNEL] Installed kernels:"
        dpkg -l 'linux-image*' 2>/dev/null | grep '^ii' || true

        echo
        echo "Old kernels can consume significant space."
        echo "APT autoremove will remove kernels no longer required."

        read -rp "Run kernel/package autoremove? [y/N]: " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            run apt-get autoremove --purge -y
        fi
    fi
}

clean_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        echo
        echo "[FLATPAK] Removing unused runtimes..."

        run flatpak uninstall --unused -y
    fi
}

clean_snap() {
    if command -v snap >/dev/null 2>&1; then
        echo
        echo "[SNAP] Looking for disabled revisions..."

        snap list --all 2>/dev/null |
            awk '/disabled/{print $1, $3}' |
            while read -r snapname revision; do
                [[ -z "$snapname" ]] && continue

                echo "Removing old snap: $snapname revision $revision"

                if $DRY_RUN; then
                    echo "[DRY-RUN] snap remove $snapname --revision=$revision"
                else
                    snap remove "$snapname" --revision="$revision"
                fi
            done
    fi
}

clean_docker() {
    if command -v docker >/dev/null 2>&1; then
        echo
        echo "[DOCKER] Docker disk usage:"
        docker system df 2>/dev/null || true

        echo
        read -rp "Remove unused Docker containers/images/networks/build cache? [y/N]: " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            run docker system prune -a
        fi
    fi
}

clean_podman() {
    if command -v podman >/dev/null 2>&1; then
        echo
        echo "[PODMAN] Podman disk usage:"
        podman system df 2>/dev/null || true

        echo
        read -rp "Remove unused Podman data? [y/N]: " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            run podman system prune -a
        fi
    fi
}

clean_user_caches() {
    echo
    echo "[CACHE] User/application caches"

    echo
    echo "Large cache directories:"

    find /home /root \
        -xdev \
        -type d \
        \( -name ".cache" -o -name "cache" \) \
        -prune \
        -exec du -sh {} \; \
        2>/dev/null |
        sort -hr |
        head -30

    echo
    read -rp "Remove files older than 30 days from user caches? [y/N]: " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then

        for dir in /home/*/.cache /root/.cache; do
            [[ -d "$dir" ]] || continue

            echo "Cleaning: $dir"

            run find "$dir" \
                -type f \
                -mtime +30 \
                -delete
        done
    fi
}

find_large_files() {
    echo
    echo "========================================"
    echo " Largest files on root filesystem"
    echo "========================================"

    echo "Searching..."

    find / \
        -xdev \
        -type f \
        -size +500M \
        -printf '%s %p\n' \
        2>/dev/null |
        sort -nr |
        head -30 |
        while read -r size path; do
            printf "%8s  %s\n" "$(human_size "$size")" "$path"
        done
}

find_deleted_open_files() {
    echo
    echo "========================================"
    echo " Deleted files still consuming space"
    echo "========================================"

    if command -v lsof >/dev/null 2>&1; then
        lsof +L1 2>/dev/null |
            awk 'NR==1 || $7 > 10485760' |
            head -30
    else
        echo "lsof is not installed."
        echo "Install it with your package manager if needed."
    fi
}

clean_old_logs() {
    echo
    echo "[LOGS] Large log files"

    find /var/log \
        -xdev \
        -type f \
        -size +100M \
        -printf '%s %p\n' \
        2>/dev/null |
        sort -nr |
        head -20 |
        while read -r size path; do
            printf "%8s  %s\n" "$(human_size "$size")" "$path"
        done

    echo
    echo "Do NOT blindly delete log files."
    echo "Journal vacuuming above is the safer option."
}

clean_package_cache() {
    clean_apt
    clean_dnf
    clean_yum
    clean_pacman
    clean_zypper
}

main() {

    clear

    echo "=============================================="
    echo "       Linux Root Partition Cleanup"
    echo "=============================================="

    if $DRY_RUN; then
        echo
        echo "*** DRY-RUN MODE ***"
        echo "Nothing will actually be deleted."
    fi

    show_disk_usage

    echo
    echo "Select cleanup operation:"
    echo
    echo "  1) Safe automatic cleanup"
    echo "  2) Package cache cleanup"
    echo "  3) System journal cleanup"
    echo "  4) Temporary files"
    echo "  5) Flatpak cleanup"
    echo "  6) Snap cleanup"
    echo "  7) Docker cleanup"
    echo "  8) Podman cleanup"
    echo "  9) User/application caches"
    echo " 10) Old kernels/packages"
    echo " 11) Find largest directories"
    echo " 12) Find files larger than 500 MB"
    echo " 13) Find deleted files still using disk"
    echo " 14) Inspect large log files"
    echo " 15) Run everything safe"
    echo "  0) Exit"
    echo

    read -rp "Select [0-15]: " choice

    case "$choice" in

        1)
            clean_package_cache
            clean_journal
            clean_tmp
            clean_crash_reports
            clean_flatpak
            clean_snap
            ;;

        2)
            clean_package_cache
            ;;

        3)
            clean_journal
            ;;

        4)
            clean_tmp
            clean_crash_reports
            ;;

        5)
            clean_flatpak
            ;;

        6)
            clean_snap
            ;;

        7)
            clean_docker
            ;;

        8)
            clean_podman
            ;;

        9)
            clean_user_caches
            ;;

        10)
            clean_old_kernels_debian
            ;;

        11)
            show_largest_dirs
            ;;

        12)
            find_large_files
            ;;

        13)
            find_deleted_open_files
            ;;

        14)
            clean_old_logs
            ;;

        15)
            echo
            echo "Running safe cleanup..."
            echo

            clean_package_cache
            clean_journal
            clean_tmp
            clean_crash_reports
            clean_flatpak
            clean_snap
            clean_old_kernels_debian

            ;;

        0)
            exit 0
            ;;

        *)
            echo "Invalid selection."
            exit 1
            ;;
    esac

    echo
    echo "========================================"
    echo " Cleanup complete"
    echo "========================================"

    show_disk_usage

    echo
    echo "Top-level disk usage:"
    du -xhd1 / 2>/dev/null | sort -hr | head -15
}

main
