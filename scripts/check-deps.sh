#!/bin/bash
# ─────────────────────────────────────────────────────────
# dwm-titus dependency checker — Arch Linux
# Run before building to verify all required packages
# are installed. Exit code 0 = all good, 1 = missing deps.
# ─────────────────────────────────────────────────────────

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

check_pkg() {
    if pacman -Qi "$1" &>/dev/null; then
        printf "  ${GREEN}✓${NC} %s\n" "$1"
    else
        printf "  ${RED}✗${NC} %s ${YELLOW}(not installed)${NC}\n" "$1"
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

echo ""
echo "═══ dwm-titus Dependency Check (Arch Linux) ═══"
echo ""

# ── Build dependencies ──────────────────────────────────
echo "Build Dependencies (required to compile):"
for pkg in base-devel libx11 libxft libxinerama imlib2 libxcb xcb-util freetype2 fontconfig; do
    check_pkg "$pkg"
done
check_cmd "cc"
check_cmd "make"
echo ""

# ── Xorg / Xlibre ───────────────────────────────────────
echo "X Server Components:"
# Accept either Xorg or Xlibre as the X server
# Detect Xlibre by any installed xlibre-* package (server, drivers, etc.)
if pacman -Qq 2>/dev/null | grep -q '^xlibre'; then
    xlibre_pkg=$(pacman -Qq 2>/dev/null | grep '^xlibre' | head -1)
    printf "  ${GREEN}✓${NC} Xlibre detected (%s)\n" "$xlibre_pkg"
elif pacman -Qi xorg-server &>/dev/null; then
    printf "  ${GREEN}✓${NC} xorg-server\n"
else
    printf "  ${RED}✗${NC} xorg-server or xlibre ${YELLOW}(not installed)${NC}\n"
    MISSING=$((MISSING + 1))
fi
for pkg in xorg-xinit xorg-xrandr xorg-xset xorg-xsetroot; do
    check_pkg "$pkg"
done

# ── Runtime dependencies ────────────────────────────────
echo "Runtime Dependencies (desktop experience):"
check_cmd "rofi"
check_cmd "picom"
check_cmd "dunst"
check_cmd "feh"
check_cmd "flameshot"
check_cmd "dex"
check_cmd "amixer"
echo ""

# ── Terminal emulators ──────────────────────────────────
echo "Terminal Emulators (at least one required):"
TERM_FOUND=0
for term in ghostty alacritty kitty st; do
    if command -v "$term" &>/dev/null; then
        printf "  ${GREEN}✓${NC} %s\n" "$term"
        TERM_FOUND=1
    fi
done
if [ $TERM_FOUND -eq 0 ]; then
    printf "  ${RED}✗${NC} No supported terminal found ${YELLOW}(install ghostty, alacritty, kitty, or st)${NC}\n"
    MISSING=$((MISSING + 1))
fi
echo ""

# ── Optional but recommended ────────────────────────────
echo "Optional (recommended):"
check_cmd "polybar"
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
    echo "  Install missing packages with: sudo pacman -S <package>"
    echo "  Or run: ./install.sh   (automated install)"
    exit 1
fi
echo ""
