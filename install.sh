#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/scripts/dwm-utils.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

command -v pacman &>/dev/null || { err "This installer requires Arch Linux (pacman not found)."; exit 1; }

DWM_DATA_DIR="$HOME/.local/share/dwm-titus"
BG_DIR="$HOME/Pictures/backgrounds"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║        dwm-titus Installer (Arch)         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Package manager: $PKG_CMD"

# ── Build dependencies ───────────────────────────────────
info "Installing build dependencies..."
install_packages base-devel libx11 libxft libxinerama imlib2 libxcb xcb-util freetype2 fontconfig

if pacman -Qq 2>/dev/null | grep -q '^xlibre'; then
    info "Xlibre detected — skipping xorg-server."
elif ! pacman -Qi xorg-server &>/dev/null; then
    install_packages xorg-server
fi
install_packages xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset
ok "Build dependencies installed."

# ── Runtime dependencies ─────────────────────────────────
info "Installing runtime dependencies..."
install_packages rofi picom dunst feh flameshot dex mate-polkit alsa-utils git unzip xclip \
    xorg-xprop thunar gvfs tumbler thunar-archive-plugin nwg-look xdg-user-dirs \
    xdg-desktop-portal-gtk pipewire pavucontrol gnome-keyring networkmanager network-manager-applet
ok "Runtime dependencies installed."

# ── Fonts ────────────────────────────────────────────────
info "Installing fonts..."
install_packages noto-fonts-emoji ttf-meslo-nerd
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ -d "$REPO_DIR/config/polybar/fonts" ]; then
    cp -r "$REPO_DIR/config/polybar/fonts/"* "$FONT_DIR/"
    fc-cache -fv >/dev/null 2>&1
fi
ok "Fonts installed."

# ── Terminal emulator ────────────────────────────────────
terminal=""
for t in ghostty kitty alacritty; do command -v "$t" &>/dev/null && { terminal="$t"; break; }; done

if [ -n "$terminal" ]; then
    ok "Terminal already installed: $terminal"
else
    info "No supported terminal found — installing ghostty..."
    install_packages ghostty 2>/dev/null || warn "ghostty not in repos — install from https://ghostty.org"
fi

# ── Polybar + XDG dirs + wallpapers ──────────────────────
install_packages polybar
command -v xdg-user-dirs-update &>/dev/null && xdg-user-dirs-update

mkdir -p "$HOME/Pictures"
if [ ! -d "$BG_DIR" ]; then
    info "Downloading Nord wallpapers..."
    git clone https://github.com/ChrisTitusTech/nord-background.git "$BG_DIR" 2>/dev/null \
        && ok "Wallpapers downloaded to $BG_DIR" \
        || warn "Failed to download wallpapers. Add your own to $BG_DIR."
else
    ok "Wallpapers already present."
fi

# ── Compile & install dwm ────────────────────────────────
cd "$REPO_DIR"
[ -f config.h ] || { cp config.def.h config.h; info "Created config.h — edit to customize."; }
info "Compiling and installing dwm..."
make clean && make
sudo make install
ok "dwm installed."

# ── Configs ──────────────────────────────────────────────
info "Installing configuration files..."

# Rofi
mkdir -p "$HOME/.config/rofi"
cp -rn "$REPO_DIR/config/rofi/"* "$HOME/.config/rofi/" 2>/dev/null || true
chmod +x "$HOME/.config/rofi/powermenu.sh" 2>/dev/null || true

# Terminal configs
for term_dir in alacritty kitty; do
    [ -d "$REPO_DIR/config/$term_dir" ] || continue
    mkdir -p "$HOME/.config/$term_dir"
    cp -rn "$REPO_DIR/config/$term_dir/"* "$HOME/.config/$term_dir/" 2>/dev/null || true
done

# Ghostty
if [ -d "$REPO_DIR/config/ghostty" ]; then
    mkdir -p "$HOME/.config/ghostty/themes"
    cp -rn "$REPO_DIR/config/ghostty/config" "$HOME/.config/ghostty/config" 2>/dev/null || true
    cp -r  "$REPO_DIR/config/ghostty/themes/"* "$HOME/.config/ghostty/themes/" 2>/dev/null || true
    ok "Ghostty themes installed."
fi

# Autostart + theme scripts
mkdir -p "$DWM_DATA_DIR/scripts" "$DWM_DATA_DIR/ghostty/themes"
for f in "$REPO_DIR/scripts/autostart.sh" "$REPO_DIR/scripts/theme-apply.sh"; do
    dst="$DWM_DATA_DIR/scripts/$(basename "$f")"
    [ "$(realpath "$f")" != "$(realpath "$dst" 2>/dev/null)" ] && cp "$f" "$dst" || true
done
chmod +x "$DWM_DATA_DIR/scripts/"*.sh
for f in "$REPO_DIR/config/ghostty/themes/"*; do
    dst="$DWM_DATA_DIR/ghostty/themes/$(basename "$f")"
    [ "$(realpath "$f")" != "$(realpath "$dst" 2>/dev/null)" ] && cp "$f" "$dst" || true
done

info "Applying initial theme..."
"$DWM_DATA_DIR/scripts/theme-apply.sh" 2>/dev/null \
    || warn "theme-apply.sh had a non-fatal issue — it will work once DWM starts."
ok "Configuration files installed."

# ── Display manager ──────────────────────────────────────
currentdm=""
for dm in sddm lightdm gdm; do command -v "$dm" &>/dev/null && { currentdm="$dm"; break; }; done

if [ -n "$currentdm" ]; then
    ok "Display manager already installed: $currentdm"
else
    info "No display manager found — installing SDDM..."
    install_packages sddm
    sudo systemctl enable sddm
    ok "SDDM installed and enabled."
fi

# ── Verify ───────────────────────────────────────────────
[ -f /usr/share/xsessions/dwm.desktop ] \
    && ok "dwm.desktop session entry is in place." \
    || warn "dwm.desktop missing from /usr/share/xsessions/ — run 'sudo make install' again."

[ -f "$HOME/.xinitrc" ] \
    && ok ".xinitrc exists." \
    || warn ".xinitrc not found. Copy with: cp $REPO_DIR/.xinitrc ~/.xinitrc"

# ── Done ─────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Detected: $DISTRO_NAME"
echo "  • Edit config.h to customize, then: make && sudo make install"
echo "  • Log out and select 'dwm', or start with: startx"
echo ""
echo "  SUPER+/   keybind viewer     SUPER+X  terminal"
echo "  SUPER+F1  control center     SUPER+R  app launcher (rofi)"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: KEYBINDS.md or SUPER+/ in dwm"
echo ""
