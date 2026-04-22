#!/bin/bash
# ─────────────────────────────────────────────────────────
# install-arm.sh — dwm-dohc installer for Arch Linux ARM
# Tested architectures: aarch64 (Raspberry Pi 4/5, Rock Pi,
#   ODROID, etc.) and armv7h
# Packages verified against https://archlinuxarm.org/packages
# ─────────────────────────────────────────────────────────
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/scripts/dwm-utils.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# ── Architecture check ───────────────────────────────────
ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7h" && "$ARCH" != "armv7l" ]]; then
    err "This installer is for ARM systems only (detected: $ARCH)."
    err "For x86_64, use install.sh instead."
    exit 1
fi

command -v pacman &>/dev/null || { err "This installer requires Arch Linux ARM (pacman not found)."; exit 1; }

BG_DIR="$HOME/Pictures/backgrounds"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║     dwm-dohc Installer (Arch Linux ARM)  ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Architecture : $ARCH"
info "Package manager: $PKG_CMD"

# ── Build dependencies ───────────────────────────────────
# All verified available on archlinuxarm.org/packages (aarch64 + armv7h):
#   base-devel, libx11 1.8.x, libxft 2.3.x, libxinerama, imlib2 1.12.x,
#   libxcb, xcb-util, freetype2, fontconfig
info "Installing build dependencies..."
install_packages base-devel libx11 libxft libxinerama imlib2 libxcb xcb-util freetype2 fontconfig
ok "Build dependencies installed."

# ── Xorg server ──────────────────────────────────────────
# xorg-server 21.1.x is available for aarch64/armv7h.
# xf86-video-fbdev provides a framebuffer fallback driver used by most
# ARM single-board computers that lack a dedicated GPU driver package.
info "Installing Xorg server..."
if ! pacman -Qi xorg-server &>/dev/null; then
    install_packages xorg-server
fi
install_packages xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset

# Install framebuffer video driver as a safe fallback for ARM SBCs.
# On boards with a Mali, Vivante, or other GPU, you may want the
# appropriate vendor driver (e.g. xf86-video-armsoc-git from AUR).
if ! pacman -Qq xf86-video-fbdev &>/dev/null 2>&1; then
    info "Installing ARM framebuffer video driver (xf86-video-fbdev)..."
    install_packages xf86-video-fbdev \
        && ok "xf86-video-fbdev installed." \
        || warn "xf86-video-fbdev not found — your board's GPU driver may already provide Xorg support."
fi
ok "Xorg server installed."

# ── Runtime dependencies ─────────────────────────────────
# All packages verified on https://archlinuxarm.org/packages:
#   rofi 1.7.x, picom 13.x, dunst 1.13.x, feh 3.12.x,
#   flameshot 13.x, dex, mate-polkit 1.28.x, alsa-utils,
#   git, unzip, xclip, xorg-xprop, thunar + plugins,
#   nwg-look 1.0.x, xdg-user-dirs, xdg-desktop-portal-gtk,
#   pipewire, pavucontrol, gnome-keyring, networkmanager,
#   network-manager-applet, libnotify, rsync
info "Installing runtime dependencies..."
install_packages rofi picom dunst feh flameshot dex mate-polkit alsa-utils git unzip xclip \
    xorg-xprop thunar gvfs tumbler thunar-archive-plugin nwg-look xdg-user-dirs \
    xdg-desktop-portal-gtk pipewire pavucontrol gnome-keyring networkmanager network-manager-applet \
    libnotify rsync
ok "Runtime dependencies installed."

# ── Qt / GTK theming ─────────────────────────────────────
# dconf, qt6ct, qt5ct — all verified on archlinuxarm.org
info "Installing Qt/GTK dark-mode dependencies..."
install_packages dconf
install_packages qt6ct 2>/dev/null || install_packages qt5ct 2>/dev/null \
    || warn "Neither qt6ct nor qt5ct found — Qt apps may not respect dark mode."
ok "Qt/GTK theming dependencies installed."

# ── Fonts ────────────────────────────────────────────────
# noto-fonts-emoji and ttf-meslo-nerd verified on archlinuxarm.org
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
# NOTE: ghostty is NOT available on Arch Linux ARM.
# kitty 0.46.x and alacritty 0.17.x are both available for aarch64/armv7h.
# Preference order: kitty → alacritty (ghostty intentionally excluded on ARM).
terminal=""
for t in kitty alacritty; do command -v "$t" &>/dev/null && { terminal="$t"; break; }; done

if [ -n "$terminal" ]; then
    ok "Terminal already installed: $terminal"
else
    info "No supported terminal found — installing kitty..."
    install_packages kitty 2>/dev/null \
        || { warn "kitty failed, trying alacritty..."; install_packages alacritty; }
fi

# ── Polybar + XDG dirs + wallpapers ──────────────────────
# polybar 3.7.x verified on archlinuxarm.org/packages/aarch64/polybar
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

# ── Display manager ──────────────────────────────────────
# sddm 0.21.x verified on archlinuxarm.org/packages/aarch64/sddm
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

# ── ARM-specific: picom backend advisory ─────────────────
# Many ARM SBCs lack full OpenGL/GLX support. If picom crashes on startup,
# edit ~/.config/picom.conf and set:
#   backend = "xrender";
# instead of the default "glx" backend.
echo ""
warn "ARM NOTE: If picom causes display issues, set 'backend = \"xrender\"' in ~/.config/picom.conf"
warn "ARM NOTE: Some SBCs (e.g. older Raspberry Pi) may need 'dtoverlay=vc4-kms-v3d' in /boot/config.txt for hardware-accelerated Xorg."

# ── Build & Install dwm ──────────────────────────────────
cd "$REPO_DIR"
sudo make clean install

# ── Done ─────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Architecture: $ARCH (Arch Linux ARM)"
echo "  • Edit config.h to customize, then: make && sudo make install"
echo "  • Log out and select 'dwm', or start with: startx"
echo ""
echo "  SUPER+/   keybind viewer     SUPER+X  terminal"
echo "  SUPER+F1  control center     SUPER+R  app launcher (rofi)"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: docs/src/keybinds.md or SUPER+/ in dwm"
echo ""
