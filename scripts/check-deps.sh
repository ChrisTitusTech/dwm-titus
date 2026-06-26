#!/bin/bash
# shellcheck disable=SC2059
# ─────────────────────────────────────────────────────────
# dwm-titus dependency checker
# Run before building to verify all required packages
# are installed. Exit code 0 = all good, 1 = missing deps.
# ─────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/dwm-utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/dwm-packages.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MISSING=0

check_cmd() {
	if command -v "$1" &>/dev/null; then
		printf "  ${GREEN}✓${NC} %s\n" "$1"
	else
		printf "  ${RED}✗${NC} %s ${YELLOW}(missing)${NC}\n" "$1"
		MISSING=$((MISSING + 1))
	fi
}

check_pkg_config() {
	if pkg-config --exists "$1" 2>/dev/null; then
		printf "  ${GREEN}✓${NC} pkg-config:%s\n" "$1"
	else
		printf "  ${RED}✗${NC} pkg-config:%s ${YELLOW}(missing)${NC}\n" "$1"
		MISSING=$((MISSING + 1))
	fi
}

check_font() {
	local label="$1"
	shift

	if [ "$#" -eq 0 ]; then
		set -- "$label"
	fi

	local pattern
	for pattern in "$@"; do
		if fc-list 2>/dev/null | command grep -qi "$pattern"; then
			printf "  ${GREEN}✓${NC} %s\n" "$label"
			return
		fi
	done

	printf "  ${RED}✗${NC} %s ${YELLOW}(not found)${NC}\n" "$label"
	MISSING=$((MISSING + 1))
}

check_font_any() {
	local label="$1"
	shift
	check_font "$label" "$@"
}

print_package_profile() {
	local label=$1
	local profile=$2
	local packages

	if ! packages="$(dwm_packages "$DISTRO_FAMILY" "$profile" | paste -sd ' ' -)"; then
		return
	fi

	if [ -n "$packages" ]; then
		printf "  %s: %s\n" "$label" "$packages"
	fi
}

echo "═══ dwm-titus Dependency Check ═══"
echo ""
echo "Distribution: $DISTRO_NAME"
echo "Family: $DISTRO_FAMILY"
echo ""

# ── Build dependencies ──────────────────────────────────
echo "Build Dependencies (required to compile):"
check_cmd "cc"
check_cmd "make"
check_cmd "pkg-config"
for module in x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res; do
	check_pkg_config "$module"
done
echo ""

# ── Xorg / Xlibre ───────────────────────────────────────
echo "X Server Components:"
if command -v Xorg &>/dev/null || command -v Xlibre &>/dev/null; then
	printf "  ${GREEN}✓${NC} X11 server\n"
else
	printf "  ${RED}✗${NC} Xorg or Xlibre ${YELLOW}(missing)${NC}\n"
	MISSING=$((MISSING + 1))
fi
for command in startx xrandr xset xsetroot; do
	check_cmd "$command"
done

# ── Runtime dependencies ────────────────────────────────
echo "Runtime Dependencies (desktop experience):"
check_cmd "rofi"
check_cmd "picom"
check_cmd "dunst"
check_cmd "feh"
check_cmd "flameshot"
if command -v dex &>/dev/null || command -v dex-autostart &>/dev/null; then
	printf "  ${GREEN}✓${NC} XDG autostart runner\n"
else
	printf "  ${RED}✗${NC} dex or dex-autostart ${YELLOW}(missing)${NC}\n"
	MISSING=$((MISSING + 1))
fi
check_cmd "amixer"
echo ""

# ── Terminal emulators ──────────────────────────────────
echo "Terminal Emulators (at least one required):"
TERM_FOUND=0
for term in alacritty ghostty kitty st; do
	if command -v "$term" &>/dev/null; then
		printf "  ${GREEN}✓${NC} %s\n" "$term"
		TERM_FOUND=1
	fi
done
if [ $TERM_FOUND -eq 0 ]; then
	printf "  ${RED}✗${NC} No supported terminal found ${YELLOW}(install alacritty, ghostty, kitty, or st)${NC}\n"
	MISSING=$((MISSING + 1))
fi
echo ""

# ── Optional but recommended ────────────────────────────
echo "Optional (recommended):"
check_cmd "xdg-open"
echo ""

# ── Fonts ───────────────────────────────────────────────
echo "Fonts:"
check_font_any "MesloLGS Nerd Font (NF compatible)" "MesloLGS Nerd Font" "MesloLGS Nerd Font Mono" "MesloLGS NF"
check_font "Noto Color Emoji"
echo ""

# ── Session entry ───────────────────────────────────────
echo "Session Setup:"
if [ -f /usr/share/xsessions/dwm.desktop ]; then
	printf "  ${GREEN}✓${NC} dwm.desktop in /usr/share/xsessions/\n"
else
	printf "  ${YELLOW}○${NC} dwm.desktop not found (run 'sudo make install')\n"
fi
if [ -f "$HOME/.xinitrc" ]; then
	printf "  ${GREEN}✓${NC} ~/.xinitrc exists\n"
else
	printf "  ${YELLOW}○${NC} ~/.xinitrc not found (needed for startx)\n"
fi
echo ""

# ── Summary ─────────────────────────────────────────────
if [ $MISSING -eq 0 ]; then
	printf "${GREEN}All dependencies satisfied. Ready to build!${NC}\n"
	echo "  Run: make && sudo make install"
	exit 0
else
	printf "${RED}$MISSING missing dependency/dependencies.${NC}\n"
	if [ "$DISTRO_FAMILY" != "unknown" ]; then
		echo ""
		echo "Package suggestions from the shared dependency map:"
		print_package_profile "Required" required
		print_package_profile "Recommended desktop" recommended
		print_package_profile "Optional extras" optional
		print_package_profile "Supported terminals" terminal
	fi
	echo "  Run: ./install.sh   (automated install)"
	exit 1
fi
