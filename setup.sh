#!/usr/bin/env bash
set -Eeuo pipefail

# Restore packages and personal desktop configuration from this repository.
# Run as the normal user (not as root) from an extracted/cloned repository.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

if [[ "${EUID}" -eq 0 ]]; then
    printf 'Run this script as your normal user, not root.\n' >&2
    exit 1
fi

if [[ ! -f "$PACKAGES_FILE" ]]; then
    printf 'Missing packages.txt next to setup.sh: %s\n' "$PACKAGES_FILE" >&2
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    printf 'This script expects Arch Linux with pacman and sudo installed.\n' >&2
    exit 1
fi

mapfile -t PACKAGES < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE")
if [[ "${#PACKAGES[@]}" -eq 0 ]]; then
    printf 'packages.txt contains no package names.\n' >&2
    exit 1
fi

printf '\n==> Installing packages listed in packages.txt\n'
sudo pacman -S --needed "${PACKAGES[@]}"

printf '\n==> Enabling NetworkManager and Bluetooth\n'
sudo systemctl enable NetworkManager.service
if systemctl list-unit-files bluetooth.service --no-legend 2>/dev/null | grep -q '^bluetooth\.service'; then
    sudo systemctl enable bluetooth.service
fi

BACKUP_DIR="$HOME/config-backup-before-portable-setup-$(date +%Y%m%d-%H%M%S)"
BACKUP_MADE=0
backup_path() {
    local source_path="$1"
    local backup_name="$2"
    if [[ -e "$source_path" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a -- "$source_path" "$BACKUP_DIR/$backup_name"
        BACKUP_MADE=1
    fi
}

mkdir -p "$CONFIG_HOME/hypr" "$CONFIG_HOME/waybar"

# Restore Hyprland's Lua entry point, if it exists in the repository.
if [[ -f "$SCRIPT_DIR/hyprland.lua" ]]; then
    if [[ "$(realpath -m -- "$SCRIPT_DIR/hyprland.lua")" != "$(realpath -m -- "$CONFIG_HOME/hypr/hyprland.lua")" ]]; then
        backup_path "$CONFIG_HOME/hypr/hyprland.lua" "hyprland.lua"
        install -m 644 -- "$SCRIPT_DIR/hyprland.lua" "$CONFIG_HOME/hypr/hyprland.lua"
        printf 'Restored ~/.config/hypr/hyprland.lua\n'
    else
        printf 'Hyprland Lua config is already in its destination; left unchanged.\n'
    fi
else
    printf 'No hyprland.lua found in repository; skipped.\n'
fi

# Restore Waybar files. Existing files are backed up before copying.
if [[ -d "$SCRIPT_DIR/waybar" ]]; then
    if [[ "$(realpath -m -- "$SCRIPT_DIR/waybar")" != "$(realpath -m -- "$CONFIG_HOME/waybar")" ]]; then
        backup_path "$CONFIG_HOME/waybar" "waybar"
        mkdir -p "$CONFIG_HOME/waybar"
        cp -a -- "$SCRIPT_DIR/waybar/." "$CONFIG_HOME/waybar/"
        printf 'Restored Waybar configuration.\n'
    else
        printf 'Waybar directory is already in its destination; left unchanged.\n'
    fi
else
    printf 'No waybar/ directory found in repository; skipped.\n'
fi

# Optional config: copied only if the user adds it to the repository.
if [[ -f "$SCRIPT_DIR/hyprlock.conf" ]]; then
    backup_path "$CONFIG_HOME/hypr/hyprlock.conf" "hyprlock.conf"
    install -m 644 -- "$SCRIPT_DIR/hyprlock.conf" "$CONFIG_HOME/hypr/hyprlock.conf"
    printf 'Restored Hyprlock configuration.\n'
fi

if [[ "$BACKUP_MADE" -eq 1 ]]; then
    printf '\nPrevious configuration backups were saved to: %s\n' "$BACKUP_DIR"
fi

printf '\nDone. Log out and start Hyprland to use the restored desktop.\n'
