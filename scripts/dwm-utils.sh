#!/bin/bash
# ─────────────────────────────────────────────────────────
# dwm-utils.sh — Shared utility library for dwm-dohc
# Source this file from other scripts:
#   source "$(dirname "$0")/dwm-utils.sh"
# ─────────────────────────────────────────────────────────

# ── Package Manager ─────────────────────────────────────
# Prefer AUR helpers for access to AUR packages
if command -v paru &>/dev/null; then
    PKG_CMD="paru -S --needed --noconfirm"
elif command -v yay &>/dev/null; then
    PKG_CMD="yay -S --needed --noconfirm"
else
    PKG_CMD="sudo pacman -S --needed --noconfirm"
fi

install_packages() {
    # shellcheck disable=SC2086
    $PKG_CMD "$@" >/dev/null
}

# ── Hardware Detection ──────────────────────────────────

# Detect GPU type: nvidia, amd, intel, or unknown
detect_gpu() {
    if command -v lspci &>/dev/null; then
        local vga
        vga=$(lspci 2>/dev/null | command grep -i 'vga\|3d\|display' || true)
        if echo "$vga" | command grep -qi nvidia; then
            echo "nvidia"
        elif echo "$vga" | command grep -qi 'amd\|radeon'; then
            echo "amd"
        elif echo "$vga" | command grep -qi intel; then
            echo "intel"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Detect battery device name (e.g., BAT0, BAT1)
detect_battery() {
    command ls /sys/class/power_supply/ 2>/dev/null | command grep -E '^BAT[0-9]' | head -1
}

# Detect AC adapter name (e.g., ACAD, AC0, ADP1)
detect_adapter() {
    command ls /sys/class/power_supply/ 2>/dev/null | command grep -Ev '^BAT' | head -1
}

# Detect if running on a laptop (has battery)
is_laptop() {
    [ -n "$(detect_battery)" ]
}

# Detect first available terminal emulator
detect_terminal() {
    for t in ghostty alacritty kitty st warp-terminal xterm; do
        if command -v "$t" &>/dev/null; then
            echo "$t"
            return
        fi
    done
    echo "xterm"
}
