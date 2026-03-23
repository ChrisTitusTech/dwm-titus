#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────
# dwm-titus installer — Arch Linux
# Installs build/runtime dependencies, compiles dwm,
# installs configs, and sets up Xorg session entry.
# ─────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared utility library
# shellcheck source=scripts/dwm-utils.sh
source "$REPO_DIR/scripts/dwm-utils.sh"

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

# ── Arch Linux check ────────────────────────────────────
if ! command -v pacman &>/dev/null; then
    err "This installer requires Arch Linux (pacman not found)."
    exit 1
fi

# ─────────────────────────────────────────────────────────
# Main install flow
# ─────────────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║        dwm-titus Installer (Arch)         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

info "Package manager: $PKG_CMD"

# ── Step 1: Install build dependencies ──────────────────
info "Installing build dependencies..."
install_packages base-devel libx11 libxft libxinerama imlib2 libxcb xcb-util freetype2 fontconfig

# Install X server: skip xorg-server if any Xlibre package is present
# (Xlibre input/server packages conflict with xorg-server at the ABI level)
if pacman -Qq 2>/dev/null | grep -q '^xlibre'; then
    info "Xlibre installation detected — skipping xorg-server installation."
elif pacman -Qi xorg-server &>/dev/null 2>&1; then
    info "xorg-server already installed — skipping."
else
    install_packages xorg-server
fi
install_packages xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset
ok "Build dependencies installed."

# ── Step 2: Install runtime dependencies ────────────────
info "Installing runtime dependencies..."
install_packages rofi picom dunst feh flameshot dex mate-polkit alsa-utils git unzip xclip \
    xorg-xprop thunar gvfs tumbler thunar-archive-plugin nwg-look xdg-user-dirs \
    xdg-desktop-portal-gtk pipewire pavucontrol gnome-keyring networkmanager network-manager-applet
ok "Runtime dependencies installed."

# ── Step 3: Install fonts ───────────────────────────────
info "Installing fonts..."
install_packages noto-fonts-emoji ttf-meslo-nerd

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
    1) install_packages ghostty 2>/dev/null || warn "ghostty not found in repos. Install manually from https://ghostty.org" ;;
    2) install_packages alacritty ;;
    3) install_packages kitty ;;
    4) info "Skipping terminal install." ;;
    *) info "Skipping terminal install." ;;
esac

# ── Step 5: Install Polybar ──────────────────────────────
info "Installing Polybar (status bar)..."
install_packages polybar
ok "Polybar installed."

# ── Step 6: Create XDG user directories ─────────────────
if command -v xdg-user-dirs-update &>/dev/null; then
    xdg-user-dirs-update
    ok "XDG user directories created."
fi

# ── Step 7: Download wallpapers ─────────────────────────
PIC_DIR="$HOME/Pictures"
BG_DIR="$PIC_DIR/backgrounds"
mkdir -p "$PIC_DIR"
if [ ! -d "$BG_DIR" ]; then
    info "Downloading Nord wallpapers..."
    if git clone https://github.com/ChrisTitusTech/nord-background.git "$BG_DIR" 2>/dev/null; then
        ok "Wallpapers downloaded to $BG_DIR"
    else
        warn "Failed to download wallpapers. Create $BG_DIR and add your own."
    fi
else
    ok "Wallpapers already present at $BG_DIR"
fi

# ── Step 8: Create config.h from config.def.h ────────────
cd "$REPO_DIR"
if [ ! -f config.h ]; then
    cp config.def.h config.h
    info "Created config.h from config.def.h — edit this file to customize."
else
    info "config.h already exists, preserving your customizations."
fi

# ── Step 9: Compile and install dwm ─────────────────────
info "Compiling dwm..."
make clean
make
info "Installing dwm (requires sudo)..."
sudo make install
ok "dwm installed to /usr/local/bin/dwm"

# ── Step 10: Copy terminal/rofi configs ─────────────────
info "Installing configuration files..."

# Rofi
mkdir -p "$HOME/.config/rofi"
cp -rn "$REPO_DIR/config/rofi/"* "$HOME/.config/rofi/" 2>/dev/null || true
chmod +x "$HOME/.config/rofi/powermenu.sh" 2>/dev/null || true
chmod +x "$HOME/.config/rofi/themes/controlcenter.rasi" 2>/dev/null || true

# Terminal configs (copy only if not already present)
for term_dir in alacritty ghostty kitty; do
    if [ -d "$REPO_DIR/config/$term_dir" ]; then
        mkdir -p "$HOME/.config/$term_dir"
        cp -rn "$REPO_DIR/config/$term_dir/"* "$HOME/.config/$term_dir/" 2>/dev/null || true
    fi
done

# Polybar
mkdir -p "$HOME/.config/polybar"
cp -rn "$REPO_DIR/polybar/"* "$HOME/.config/polybar/" 2>/dev/null || true
chmod +x "$HOME/.config/polybar/launch.sh" 2>/dev/null || true

# dwm-titus TOML configs (hotkeys + themes, hot-reload at runtime)
DWM_CFG_DIR="$HOME/.config/dwm-titus"
mkdir -p "$DWM_CFG_DIR"
cp -n "$REPO_DIR/config/hotkeys.toml" "$DWM_CFG_DIR/hotkeys.toml" 2>/dev/null || true
cp -n "$REPO_DIR/config/themes.toml"  "$DWM_CFG_DIR/themes.toml"  2>/dev/null || true
ok "dwm-titus TOML configs installed to $DWM_CFG_DIR"

# Autostart scripts (dwm runautostart looks here)
DWM_DATA_DIR="$HOME/.local/share/dwm-titus"
mkdir -p "$DWM_DATA_DIR/scripts"
cp "$REPO_DIR/scripts/autostart.sh" "$DWM_DATA_DIR/scripts/autostart.sh"
cp "$REPO_DIR/scripts/autostart_blocking.sh" "$DWM_DATA_DIR/scripts/autostart_blocking.sh"
chmod +x "$DWM_DATA_DIR/scripts/autostart.sh" "$DWM_DATA_DIR/scripts/autostart_blocking.sh"

ok "Config files installed to ~/.config/"

# ── Step 11: Display manager setup ──────────────────────
currentdm="none"
for dm in gdm sddm lightdm; do
    if command -v "$dm" &>/dev/null; then
        currentdm="$dm"
        break
    fi
done

if [ "$currentdm" = "none" ]; then
    echo ""
    read -rp "No display manager found. Install SDDM? [Y/n]: " dm_choice
    dm_choice="${dm_choice:-Y}"
    if [[ "$dm_choice" =~ ^[Yy] ]]; then
        install_packages sddm
        sudo systemctl enable sddm
        ok "SDDM installed and enabled."
    else
        info "Skipping display manager. Use 'startx' to launch dwm."
    fi
else
    ok "Display manager already installed: $currentdm"
fi

# ── Step 12: Verify session entry ───────────────────────
if [ -f /usr/share/xsessions/dwm.desktop ]; then
    ok "dwm.desktop session entry is in place."
else
    warn "dwm.desktop not found in /usr/share/xsessions/ — display manager won't show dwm."
    warn "Run 'sudo make install' again or copy dwm.desktop manually."
fi

# ── Step 13: Verify .xinitrc ────────────────────────────
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
info "Detected: $DISTRO_NAME"
info "Next steps:"
echo "  • Edit config.h to customize keybinds, colors, and autostart programs"
echo "  • After editing config.h, recompile: make && sudo make install"
echo "  • Log out and select 'dwm' from your display manager"
echo "  • Or start with: startx"
echo ""
echo "  Key bindings:  SUPER + /     (interactive keybind viewer)"
echo "  Control Center: SUPER + F1  (health checks, settings)"
echo "  Terminal:      SUPER + X"
echo "  App Launcher:  SUPER + R     (rofi)"
echo "  Close Window:  SUPER + Q"
echo ""
echo "  Full reference: see KEYBINDS.md or press SUPER+/ in dwm"
echo ""
