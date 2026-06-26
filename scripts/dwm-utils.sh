#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# dwm-utils.sh — Shared utility library for dwm-titus
# Source this file from other scripts:
#   source "$(dirname "$0")/dwm-utils.sh"
# ─────────────────────────────────────────────────────────

# ── Distribution and package manager ────────────────────
DISTRO_ID="unknown"
DISTRO_ID_LIKE=""
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unknown"

if [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	source /etc/os-release
	DISTRO_ID="${ID:-unknown}"
	DISTRO_ID_LIKE="${ID_LIKE:-}"
	DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
fi

case " ${DISTRO_ID} ${DISTRO_ID_LIKE} " in
*" arch "*)
	DISTRO_FAMILY="arch"
	;;
*" fedora "* | *" rhel "* | *" centos "*)
	DISTRO_FAMILY="rhel"
	;;
*" debian "* | *" ubuntu "*)
	DISTRO_FAMILY="debian"
	;;
esac

case "$DISTRO_FAMILY" in
arch)
	if command -v paru &>/dev/null && paru --version &>/dev/null; then
		PKG_CMD="paru -S --needed --noconfirm"
	elif command -v yay &>/dev/null && yay --version &>/dev/null; then
		PKG_CMD="yay -S --needed --noconfirm"
	else
		PKG_CMD="sudo pacman -S --needed --noconfirm"
	fi
	;;
rhel)
	PKG_CMD="sudo dnf install -y"
	;;
debian)
	PKG_CMD="sudo apt-get install -y"
	;;
*)
	PKG_CMD="unavailable"
	;;
esac
export PKG_CMD

install_packages() {
	case "$DISTRO_FAMILY" in
	arch)
		if command -v paru &>/dev/null && paru --version &>/dev/null; then
			paru -S --needed --noconfirm "$@"
		elif command -v yay &>/dev/null && yay --version &>/dev/null; then
			yay -S --needed --noconfirm "$@"
		else
			sudo pacman -S --needed --noconfirm "$@"
		fi
		;;
	rhel)
		sudo dnf install -y "$@"
		;;
	debian)
		sudo apt-get install -y "$@"
		;;
	*)
		printf 'Unsupported distribution: %s\n' "$DISTRO_NAME" >&2
		return 1
		;;
	esac
}

package_available() {
	case "$DISTRO_FAMILY" in
	arch)
		pacman -Si "$1" &>/dev/null
		;;
	rhel)
		dnf -q repoquery --available --qf '%{name}' "$1" 2>/dev/null |
			command grep -Fxq "$1"
		;;
	debian)
		apt-cache show "$1" &>/dev/null
		;;
	*)
		return 1
		;;
	esac
}

install_optional_package() {
	local package=$1

	if package_available "$package"; then
		install_packages "$package"
		return
	fi

	printf 'Optional package is unavailable in enabled repositories: %s\n' "$package" >&2
	return 1
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
	for t in alacritty kitty st warp-terminal xterm; do
		if command -v "$t" &>/dev/null; then
			echo "$t"
			return
		fi
	done
	echo "xterm"
}
