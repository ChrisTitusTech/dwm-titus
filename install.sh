#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/dwm-utils.sh
source "$REPO_DIR/scripts/dwm-utils.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

if [[ $EUID -eq 0 ]]; then
    err "Run this installer as a normal user. It invokes sudo only when needed."
    exit 1
fi

case "$DISTRO_FAMILY" in
    arch)
        command -v pacman &>/dev/null || {
            err "Arch-family distribution detected, but pacman was not found."
            exit 1
        }
        ;;
    rhel)
        command -v dnf &>/dev/null || {
            err "RHEL-family distribution detected, but dnf was not found."
            exit 1
        }
        ;;
    debian)
        command -v apt-get &>/dev/null || {
            err "Debian-family distribution detected, but apt-get was not found."
            exit 1
        }
        ;;
    *)
        err "Unsupported distribution: $DISTRO_NAME"
        err "Supported installer families: Debian, Arch, and Fedora/RHEL."
        exit 1
        ;;
esac

BG_DIR="$HOME/Pictures/backgrounds"
MESLO_VERSION="3.4.0"
MESLO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${MESLO_VERSION}/Meslo.zip"
MESLO_SHA256="13b502ac8c2bd9d3161018064560e23cd42b175bb730780a270975265a19ad57"

install_meslo_nerd_font() {
    local font_dir="$HOME/.local/share/fonts/Meslo"
    local tmp_dir
    local archive

    if fc-list 2>/dev/null | command grep -Eqi 'MesloLGS (NF|Nerd Font)'; then
        ok "MesloLGS Nerd Font is already installed."
        return
    fi

    tmp_dir="$(mktemp -d)"
    archive="$tmp_dir/Meslo.zip"

    info "Downloading Meslo Nerd Font v${MESLO_VERSION}..."
    if ! curl --fail --location --show-error --silent "$MESLO_URL" --output "$archive"; then
        rm -rf "$tmp_dir"
        err "Failed to download Meslo Nerd Font."
        return 1
    fi

    if ! printf '%s  %s\n' "$MESLO_SHA256" "$archive" | sha256sum --check --status; then
        rm -rf "$tmp_dir"
        err "Meslo Nerd Font checksum verification failed."
        return 1
    fi

    mkdir -p "$font_dir"
    unzip -j -q -o "$archive" '*.ttf' -d "$font_dir"
    rm -rf "$tmp_dir"
    fc-cache -f "$font_dir" >/dev/null 2>&1
    ok "MesloLGS Nerd Font installed."
}

install_supported_terminal() {
    case "$DISTRO_FAMILY" in
        arch)
            install_optional_package ghostty 2>/dev/null ||
                install_packages kitty
            ;;
        rhel)
            if package_available alacritty; then
                install_packages alacritty
            elif package_available kitty; then
                install_packages kitty
            else
                err "No supported terminal is available in the enabled repositories."
                return 1
            fi
            ;;
        debian)
            if package_available alacritty; then
                install_packages alacritty
            elif package_available kitty; then
                install_packages kitty
            else
                err "No supported terminal is available in the enabled repositories."
                return 1
            fi
            ;;
    esac
}

configure_seeded_terminal() {
    local hotkeys_file=$1
    local terminal=$2

    if [[ $HOTKEYS_EXISTED == true ]]; then
        return
    fi

    sed -i -E \
        "s|^terminal = \"[^\"]*\"|terminal = \"$terminal\"|" \
        "$hotkeys_file"
    ok "Configured the default terminal: $terminal"
}

detect_display_manager() {
    local unit

    unit="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
    case "$(basename "$unit")" in
        lightdm.service) echo "lightdm"; return ;;
        gdm.service) echo "gdm"; return ;;
        sddm.service) echo "sddm"; return ;;
    esac

    for unit in lightdm gdm sddm; do
        if command -v "$unit" &>/dev/null; then
            echo "$unit"
            return
        fi
    done
}

install_lightdm_config() {
    local legacy_config="/etc/lightdm/lightdm.conf"
    local backup

    if sudo test -f "$legacy_config" &&
        sudo grep -Fxq 'greeter-session=lightdm-slick-greeter' "$legacy_config" &&
        sudo grep -Fxq 'user-session=dwm' "$legacy_config" &&
        sudo grep -Fxq 'session-wrapper=/etc/lightdm/Xsession' "$legacy_config"; then
        backup="${legacy_config}.dwm-titus.$(date +%Y%m%d%H%M%S).bak"
        warn "Migrating the legacy dwm-titus LightDM configuration."
        sudo cp -a "$legacy_config" "$backup"
        sudo rm "$legacy_config"
        ok "Legacy LightDM configuration backed up to $backup"
    fi

    sudo make -C "$REPO_DIR/lightdm" install
    if command -v restorecon &>/dev/null; then
        sudo restorecon \
            /etc/lightdm/lightdm.conf.d/90-dwm-titus.conf \
            /etc/lightdm/slick-greeter.conf \
            /usr/share/pixmaps/dwm-titus.jpg \
            /usr/share/pixmaps/dwm-titus-logo.png
    fi
}

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║             dwm-titus Installer           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Distribution: $DISTRO_NAME"
info "Family: $DISTRO_FAMILY"
info "Package manager: $PKG_CMD"

if [[ $DISTRO_FAMILY == "debian" ]]; then
    info "Refreshing apt package metadata..."
    sudo apt-get update
fi

# ── Build dependencies ───────────────────────────────────
info "Installing build dependencies..."
case "$DISTRO_FAMILY" in
    arch)
        install_packages \
            base-devel libx11 libxft libxinerama libxrender imlib2 \
            libxcb xcb-util freetype2 fontconfig pkgconf

        if pacman -Qq 2>/dev/null | command grep -q '^xlibre'; then
            info "Xlibre detected - skipping xorg-server."
        elif ! pacman -Qi xorg-server &>/dev/null; then
            install_packages xorg-server
        fi
        install_packages xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset
        ;;
    rhel)
        install_packages \
            gcc make pkgconf-pkg-config \
            libX11-devel libXft-devel libXinerama-devel libXrender-devel \
            imlib2-devel libxcb-devel xcb-util-devel \
            freetype-devel fontconfig-devel

        install_packages \
            xorg-x11-server-Xorg xorg-x11-xinit xrandr xset xsetroot
        ;;
    debian)
        install_packages \
            build-essential pkg-config \
            libx11-dev libxft-dev libxinerama-dev libxrender-dev \
            libimlib2-dev libx11-xcb-dev libxcb1-dev libxcb-res0-dev \
            libfontconfig-dev libfreetype-dev

        install_packages \
            xserver-xorg-core xinit x11-xserver-utils
        ;;
esac
ok "Build dependencies installed."

# ── Runtime dependencies ─────────────────────────────────
info "Installing runtime dependencies..."
case "$DISTRO_FAMILY" in
    arch)
        install_packages \
            rofi picom dunst feh flameshot dex mate-polkit alsa-utils \
            brightnessctl curl git procps-ng psmisc unzip xclip xdotool \
            xorg-xprop thunar gvfs tumbler \
            thunar-archive-plugin nwg-look xdg-user-dirs \
            xdg-utils xdg-desktop-portal-gtk pipewire pipewire-pulse \
            wireplumber pavucontrol gnome-keyring \
            networkmanager network-manager-applet libnotify rsync
        ;;
    rhel)
        install_packages \
            rofi picom dunst feh flameshot dex-autostart mate-polkit \
            alsa-utils brightnessctl curl git procps-ng psmisc pulseaudio-utils \
            unzip xclip xdotool xprop \
            Thunar gvfs tumbler \
            thunar-archive-plugin file-roller xdg-user-dirs xdg-utils \
            xdg-desktop-portal-gtk pipewire pavucontrol gnome-keyring \
            pipewire-pulseaudio wireplumber NetworkManager \
            network-manager-applet libnotify rsync dbus-x11 \
            xorg-x11-drv-libinput

        if ! package_available nwg-look; then
            warn "nwg-look is not in Fedora's official repositories; skipping it."
        else
            install_packages nwg-look
        fi
        ;;
    debian)
        install_packages \
            rofi picom dunst feh flameshot dex mate-polkit \
            alsa-utils brightnessctl curl git procps psmisc pulseaudio-utils \
            unzip xclip xdotool x11-utils \
            thunar gvfs tumbler thunar-archive-plugin file-roller \
            xdg-user-dirs xdg-utils xdg-desktop-portal-gtk \
            pipewire pipewire-pulse wireplumber pavucontrol gnome-keyring \
            network-manager network-manager-gnome libnotify-bin rsync dbus-x11
        ;;
esac
ok "Runtime dependencies installed."

# ── Qt / GTK theming ─────────────────────────────────────
info "Installing Qt/GTK dark-mode dependencies..."
# dconf: required for gsettings to persist GTK color-scheme changes
# qt6ct / qt5ct: QT_QPA_PLATFORMTHEME backend for Qt dark mode in standalone WMs
install_packages dconf
install_optional_package qt6ct 2>/dev/null ||
    install_optional_package qt5ct 2>/dev/null ||
    warn "Neither qt6ct nor qt5ct is available - Qt apps may not respect dark mode."
ok "Qt/GTK theming dependencies installed."

# ── Fonts ────────────────────────────────────────────────
info "Installing fonts..."
case "$DISTRO_FAMILY" in
    arch)
        install_packages noto-fonts-emoji ttf-meslo-nerd
        ;;
    rhel)
        install_packages \
            google-noto-color-emoji-fonts \
            google-noto-sans-mono-fonts
        ;;
    debian)
        install_packages \
            fonts-noto-color-emoji \
            fonts-noto-mono
        ;;
esac
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
install_meslo_nerd_font
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
    info "No supported terminal found - installing one from enabled repositories..."
    install_supported_terminal
    terminal="$(detect_terminal)"
fi

# ── Polybar + XDG dirs + wallpapers ──────────────────────
install_packages polybar
command -v xdg-user-dirs-update &>/dev/null && xdg-user-dirs-update

mkdir -p "$HOME/Pictures"
if [ ! -d "$BG_DIR" ]; then
    info "Downloading Nord wallpapers..."
    if git clone https://github.com/ChrisTitusTech/nord-background.git "$BG_DIR" 2>/dev/null; then
        ok "Wallpapers downloaded to $BG_DIR"
    else
        warn "Failed to download wallpapers. Add your own to $BG_DIR."
    fi
else
    ok "Wallpapers already present."
fi



# ── Display manager ──────────────────────────────────────
currentdm="$(detect_display_manager)"

if [ -n "$currentdm" ]; then
    ok "Display manager already installed: $currentdm"
else
    info "No display manager found - installing LightDM..."
    case "$DISTRO_FAMILY" in
        arch)
            install_packages lightdm lightdm-slick-greeter
            ;;
        rhel)
            install_packages lightdm slick-greeter
            ;;
        debian)
            install_packages lightdm slick-greeter
            ;;
    esac
    sudo systemctl enable lightdm.service
    currentdm="lightdm"
    ok "LightDM installed and enabled."
fi

# ── LightDM greeter config ───────────────────────────────
if [[ $currentdm == "lightdm" ]]; then
    info "Deploying LightDM Slick Greeter config..."
    install_lightdm_config
    ok "LightDM config deployed."
fi

# ── Build & Install ──────────────────────────────────────
HOTKEYS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/hotkeys.toml"
if [[ -f $HOTKEYS_FILE ]]; then
    HOTKEYS_EXISTED=true
else
    HOTKEYS_EXISTED=false
fi

cd "$REPO_DIR"
make clean
make
sudo make install \
    USER_HOME="$HOME" \
    OWNER="$(id -un)" \
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
    XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
configure_seeded_terminal "$HOTKEYS_FILE" "$terminal"

if [[ $(uname -m) == x86_64 ]] && command -v systemctl &>/dev/null; then
    info "Enabling the Vicinae user service..."
    systemctl --user daemon-reload
    systemctl --user enable vicinae.service
    ok "Vicinae user service enabled."
fi

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
echo "  SUPER+F1  control center     SUPER+R  app launcher (Vicinae)"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: docs/src/keybinds.md or SUPER+/ in dwm"
echo ""
