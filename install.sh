#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────
# dwm-titus installer for Arch Linux
# Installs build/runtime dependencies, compiles dwm,
# installs configs, and sets up Xorg session entry.
# ─────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# ─────────────────────────────────────────────────────────
# Detect AUR helper or fall back to pacman
# ─────────────────────────────────────────────────────────
detect_pkg_manager() {
    if command -v paru &>/dev/null; then
        PKG_MGR="paru"
    elif command -v yay &>/dev/null; then
        PKG_MGR="yay"
    else
        PKG_MGR="sudo pacman"
    fi
    info "Using package manager: $PKG_MGR"
}

install_packages() {
    $PKG_MGR -S --needed --noconfirm "$@"
}

# ─────────────────────────────────────────────────────────
# Build dependencies (required to compile dwm)
# ─────────────────────────────────────────────────────────
BUILD_DEPS=(
    base-devel
    libx11
    libxft
    libxinerama
    imlib2
    libxcb
    xcb-util
    freetype2
    fontconfig
    xorg-server
    xorg-xinit
    xorg-xrandr
    xorg-xsetroot
    xorg-xset
)

# ─────────────────────────────────────────────────────────
# Runtime dependencies (needed for full desktop experience)
# ─────────────────────────────────────────────────────────
RUNTIME_DEPS=(
    rofi
    picom
    dunst
    feh
    flameshot
    dex
    polkit-mate
    alsa-utils
)

# ─────────────────────────────────────────────────────────
# Font packages
# ─────────────────────────────────────────────────────────
FONT_DEPS=(
    noto-fonts-emoji
    ttf-meslo-nerd
)

# ─────────────────────────────────────────────────────────
# Main install flow
# ─────────────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║        dwm-titus Installer (Arch)         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# Must be on Arch
if ! command -v pacman &>/dev/null; then
    err "This installer is designed for Arch Linux (pacman not found)."
    exit 1
fi

detect_pkg_manager

# ── Step 1: Install build dependencies ──────────────────
info "Installing build dependencies..."
install_packages "${BUILD_DEPS[@]}"
ok "Build dependencies installed."

# ── Step 2: Install runtime dependencies ────────────────
info "Installing runtime dependencies..."
install_packages "${RUNTIME_DEPS[@]}"
ok "Runtime dependencies installed."

# ── Step 3: Install fonts ───────────────────────────────
info "Installing fonts..."
install_packages "${FONT_DEPS[@]}"

# Install bundled Polybar fonts (MaterialIcons, Feather)
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ -d "$REPO_DIR/polybar/fonts" ]; then
    cp -r "$REPO_DIR/polybar/fonts/"* "$FONT_DIR/"
    fc-cache -fv >/dev/null 2>&1
    ok "Polybar icon fonts installed to $FONT_DIR"
fi
ok "Fonts installed."

# ── Step 4: Optional terminal emulator ──────────────────
echo ""
info "Select a terminal emulator to install (default keybind: SUPER+X):"
echo "  1) ghostty  (default in config.h)"
echo "  2) alacritty"
echo "  3) kitty"
echo "  4) skip (already installed or using another)"
echo ""
read -rp "Choice [1-4]: " term_choice
case "$term_choice" in
    1) install_packages ghostty 2>/dev/null || warn "ghostty not found in repos. Install manually or via AUR." ;;
    2) install_packages alacritty ;;
    3) install_packages kitty ;;
    4) info "Skipping terminal install." ;;
    *) info "Skipping terminal install." ;;
esac

# ── Step 5: Optional Polybar ────────────────────────────
echo ""
read -rp "Install Polybar? (recommended, used as status bar) [Y/n]: " polybar_choice
polybar_choice="${polybar_choice:-Y}"
if [[ "$polybar_choice" =~ ^[Yy] ]]; then
    install_packages polybar
    ok "Polybar installed."
fi

# ── Step 6: Create config.h from config.def.h ───────────
cd "$REPO_DIR"
if [ ! -f config.h ]; then
    cp config.def.h config.h
    info "Created config.h from config.def.h — edit this file to customize."
else
    info "config.h already exists, preserving your customizations."
fi

# ── Step 7: Compile and install dwm ─────────────────────
info "Compiling dwm..."
make clean
make
info "Installing dwm (requires sudo)..."
sudo make install
ok "dwm installed to /usr/local/bin/dwm"

# ── Step 8: Copy terminal/rofi configs ──────────────────
info "Installing configuration files..."

# Rofi
mkdir -p "$HOME/.config/rofi"
cp -rn "$REPO_DIR/config/rofi/"* "$HOME/.config/rofi/" 2>/dev/null || true
chmod +x "$HOME/.config/rofi/powermenu.sh" 2>/dev/null || true

# Terminal configs (copy only if not already present)
for term_dir in alacritty ghostty kitty; do
    if [ -d "$REPO_DIR/config/$term_dir" ]; then
        mkdir -p "$HOME/.config/$term_dir"
        cp -rn "$REPO_DIR/config/$term_dir/"* "$HOME/.config/$term_dir/" 2>/dev/null || true
    fi
done

ok "Config files installed to ~/.config/"

# ── Step 9: Verify session entry ────────────────────────
if [ -f /usr/share/xsessions/dwm.desktop ]; then
    ok "dwm.desktop session entry is in place."
else
    warn "dwm.desktop not found in /usr/share/xsessions/ — display manager won't show dwm."
    warn "Run 'sudo make install' again or copy dwm.desktop manually."
fi

# ── Step 10: Verify .xinitrc ────────────────────────────
if [ -f "$HOME/.xinitrc" ]; then
    ok ".xinitrc exists (for startx users)."
else
    warn ".xinitrc not found. If using startx instead of a display manager,"
    warn "copy the example: cp $REPO_DIR/.xinitrc ~/.xinitrc"
fi

# ── Done ────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Next steps:"
echo "  • Edit config.h to customize keybinds, colors, and autostart programs"
echo "  • After editing config.h, recompile: make && sudo make install"
echo "  • Log out and select 'dwm' from your display manager"
echo "  • Or start with: startx"
echo ""
echo "  Key bindings:  SUPER + /     (interactive keybind viewer)"
echo "  Terminal:      SUPER + X"
echo "  App Launcher:  SUPER + R     (rofi)"
echo "  Close Window:  SUPER + Q"
echo ""
echo "  Full reference: see KEYBINDS.md or press SUPER+/ in dwm"
echo ""
