#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/dwm-utils.sh
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/dwm-packages.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

usage() {
	cat <<EOF
Usage: ./install.sh [options]

Options:
  --profile PROFILE      Install profile: core, recommended, or full.
                         Defaults to DWM_INSTALL_PROFILE or full.
  --non-interactive      Use unattended defaults and do not prompt.
  --yes                  Accept the interactive install summary.
  --dry-run              Print the resolved plan and exit before changes.
  -h, --help             Show this help.
EOF
}

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
VICINAE_RELEASE_API="https://api.github.com/repos/vicinaehq/vicinae/releases/latest"
VICINAE_ASSET_NAME="Vicinae-x86_64.AppImage"
VICINAE_TMP_DIR=""
VICINAE_SOURCE_DIR=""
ARCH="$(uname -m)"
INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"
NON_INTERACTIVE=false
ASSUME_YES=false
DRY_RUN=false

while (($# > 0)); do
	case "$1" in
	--profile)
		if (($# < 2)); then
			err "--profile requires a value."
			exit 1
		fi
		INSTALL_PROFILE=$2
		shift 2
		;;
	--profile=*)
		INSTALL_PROFILE=${1#*=}
		shift
		;;
	--non-interactive)
		NON_INTERACTIVE=true
		ASSUME_YES=true
		shift
		;;
	--yes)
		ASSUME_YES=true
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "Unknown option: $1"
		usage >&2
		exit 1
		;;
	esac
done

case "$INSTALL_PROFILE" in
core | minimal)
	INSTALL_PROFILE="core"
	;;
recommended | full) ;;
*)
	err "Unsupported DWM_INSTALL_PROFILE: $INSTALL_PROFILE"
	err "Supported profiles: core, recommended, full"
	exit 1
	;;
esac

if [[ ! -t 0 || ! -t 1 ]]; then
	NON_INTERACTIVE=true
	ASSUME_YES=true
fi

if [[ $EUID -eq 0 && $DRY_RUN != true ]]; then
	err "Run this installer as a normal user. It invokes sudo only when needed."
	exit 1
fi

is_arch_arm() {
	[[ $DISTRO_FAMILY == "arch" &&
		($ARCH == "aarch64" || $ARCH == "armv7h" || $ARCH == "armv7l") ]]
}

install_recommended_profile() {
	[[ $INSTALL_PROFILE == "recommended" || $INSTALL_PROFILE == "full" ]]
}

install_optional_profile() {
	[[ $INSTALL_PROFILE == "full" ]]
}

package_line() {
	local profile=$1

	dwm_packages "$DISTRO_FAMILY" "$profile" | paste -sd ' ' -
}

print_summary_profile() {
	local label=$1
	local profile=$2
	local packages

	packages="$(package_line "$profile")"
	if [[ -n $packages ]]; then
		printf '  %s: %s\n' "$label" "$packages"
	else
		printf '  %s: none\n' "$label"
	fi
}

print_install_summary() {
	echo ""
	echo "Installation summary:"
	printf '  Distribution: %s\n' "$DISTRO_NAME"
	printf '  Family: %s\n' "$DISTRO_FAMILY"
	printf '  Package manager: %s\n' "$PKG_CMD"
	printf '  Profile: %s\n' "$INSTALL_PROFILE"
	printf '  Mode: %s\n' "$([[ $NON_INTERACTIVE == true ]] && echo non-interactive || echo interactive)"
	print_summary_profile "Required packages" required
	if install_recommended_profile; then
		print_summary_profile "Recommended packages" recommended
	else
		printf '  Recommended packages: skipped\n'
	fi
	if install_optional_profile; then
		print_summary_profile "Optional extras" optional
	else
		printf '  Optional extras: skipped\n'
	fi
	if is_arch_arm; then
		print_summary_profile "Arch ARM terminal candidates" terminal-arm
		print_summary_profile "Arch ARM video fallback" arm-video
	else
		print_summary_profile "Terminal candidates" terminal
	fi
	echo ""
}

confirm_install_summary() {
	local answer

	print_install_summary

	if [[ $DRY_RUN == true ]]; then
		ok "Dry run complete; no changes were made."
		exit 0
	fi

	if [[ $ASSUME_YES == true ]]; then
		return
	fi

	printf 'Continue with installation? [y/N] '
	read -r answer
	case "$answer" in
	y | Y | yes | YES) ;;
	*)
		err "Installation cancelled."
		exit 1
		;;
	esac
}

cleanup() {
	if [[ -n $VICINAE_TMP_DIR ]]; then
		rm -rf "$VICINAE_TMP_DIR"
	fi
}
trap cleanup EXIT

prepare_vicinae() {
	local metadata
	local appimage
	local asset_url
	local asset_digest
	local expected_sha256

	if [[ $(uname -m) != x86_64 ]]; then
		warn "Vicinae provides an x86_64 AppImage; skipping it on $(uname -m)."
		return 1
	fi

	VICINAE_TMP_DIR="$(mktemp -d)"
	metadata="$VICINAE_TMP_DIR/release.json"
	appimage="$VICINAE_TMP_DIR/$VICINAE_ASSET_NAME"

	info "Resolving the latest Vicinae release..."
	if ! curl --fail --location --show-error --silent \
		-H "Accept: application/vnd.github+json" \
		"$VICINAE_RELEASE_API" --output "$metadata"; then
		err "Failed to query the latest Vicinae release."
		return 1
	fi

	asset_url="$(
		awk -v asset="$VICINAE_ASSET_NAME" '
            index($0, "\"name\": \"" asset "\"") { found = 1 }
            found && /"browser_download_url":/ {
                sub(/^[^:]*: "/, "")
                sub(/".*$/, "")
                print
                exit
            }
        ' "$metadata"
	)"
	asset_digest="$(
		awk -v asset="$VICINAE_ASSET_NAME" '
            index($0, "\"name\": \"" asset "\"") { found = 1 }
            found && /"digest":/ {
                sub(/^[^:]*: "/, "")
                sub(/".*$/, "")
                print
                exit
            }
        ' "$metadata"
	)"

	if [[ -z $asset_url ]]; then
		err "The latest Vicinae release does not contain $VICINAE_ASSET_NAME."
		return 1
	fi
	if [[ $asset_digest != sha256:* ]]; then
		err "GitHub did not provide a SHA-256 digest for $VICINAE_ASSET_NAME."
		return 1
	fi
	expected_sha256="${asset_digest#sha256:}"

	info "Downloading $VICINAE_ASSET_NAME..."
	if ! curl --fail --location --show-error --silent \
		"$asset_url" --output "$appimage"; then
		err "Failed to download Vicinae."
		return 1
	fi

	if ! printf '%s  %s\n' "$expected_sha256" "$appimage" |
		sha256sum --check --status; then
		err "Vicinae AppImage checksum verification failed."
		return 1
	fi

	chmod +x "$appimage"
	info "Extracting the Vicinae AppImage..."
	if ! (
		cd "$VICINAE_TMP_DIR"
		"$appimage" --appimage-extract >/dev/null
	); then
		err "Failed to extract the Vicinae AppImage."
		return 1
	fi

	VICINAE_SOURCE_DIR="$VICINAE_TMP_DIR/squashfs-root"
	if [[ ! -x $VICINAE_SOURCE_DIR/AppRun ||
		! -x $VICINAE_SOURCE_DIR/usr/bin/vicinae ]]; then
		err "The Vicinae AppImage extraction is incomplete."
		VICINAE_SOURCE_DIR=""
		return 1
	fi

	ok "Vicinae downloaded, verified, and extracted."
}

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
	local profile="terminal"

	if is_arch_arm; then
		profile="terminal-arm"
	fi

	if ! dwm_install_first_available_profile "$profile"; then
		err "No supported terminal is available in the enabled repositories."
		return 1
	fi
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
	lightdm.service)
		echo "lightdm"
		return
		;;
	gdm.service)
		echo "gdm"
		return
		;;
	sddm.service)
		echo "sddm"
		return
		;;
	esac

	for unit in lightdm gdm sddm; do
		if command -v "$unit" &>/dev/null; then
			echo "$unit"
			return
		fi
	done
}

install_lightdm_config() {
	local lightdm_config="/etc/lightdm/lightdm.conf"

	sudo make -C "$REPO_DIR/lightdm" install
	if command -v restorecon &>/dev/null; then
		sudo restorecon \
			"$lightdm_config" \
			/etc/lightdm/slick-greeter.conf \
			/usr/share/pixmaps/dwm-titus.jpg \
			/usr/share/pixmaps/dwm-titus-logo.png
	fi
}

enable_vicinae_user_service() {
	if ! command -v systemctl &>/dev/null; then
		warn "systemctl not found; enable Vicinae later with: systemctl --user enable vicinae.service"
		return
	fi

	info "Enabling the Vicinae user service..."
	if ! systemctl --user daemon-reload; then
		warn "Could not contact the user systemd manager; enable Vicinae after login with: systemctl --user enable vicinae.service"
		return
	fi

	if ! systemctl --user enable vicinae.service; then
		warn "Could not enable the Vicinae user service; run later: systemctl --user enable vicinae.service"
		return
	fi

	ok "Vicinae user service enabled."
}

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║             dwm-titus Installer           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Distribution: $DISTRO_NAME"
info "Family: $DISTRO_FAMILY"
info "Package manager: $PKG_CMD"
info "Install profile: $INSTALL_PROFILE"
confirm_install_summary

if [[ $NON_INTERACTIVE != true ]]; then
	"$REPO_DIR/scripts/configure-build.sh"
else
	"$REPO_DIR/scripts/configure-build.sh" --non-interactive
fi

if [[ $DISTRO_FAMILY == "debian" ]]; then
	info "Refreshing apt package metadata..."
	sudo apt-get update
fi

# ── Required build and runtime dependencies ──────────────
info "Installing required build and runtime dependencies..."
dwm_install_package_profile build
if [[ $DISTRO_FAMILY == "arch" ]]; then
	if pacman -Qq 2>/dev/null | command grep -q '^xlibre'; then
		info "Xlibre detected - skipping xorg-server."
	elif ! pacman -Qi xorg-server &>/dev/null; then
		dwm_install_package_profile x11-server
	fi
else
	dwm_install_package_profile x11-server
fi
dwm_install_package_profile x11
dwm_install_package_profile runtime-required
if is_arch_arm; then
	if dwm_install_first_available_profile arm-video; then
		ok "ARM framebuffer video driver installed."
	else
		warn "ARM framebuffer video driver unavailable; your board's GPU driver may already provide Xorg support."
	fi
fi
ok "Required build and runtime dependencies installed."

# ── Recommended desktop dependencies ─────────────────────
if install_recommended_profile; then
	info "Installing recommended desktop dependencies..."
	dwm_install_package_profile desktop
	dwm_install_package_profile theme
	dwm_install_package_profile fonts
	dwm_install_package_profile bar
	ok "Recommended desktop dependencies installed."
else
	warn "Skipping recommended desktop dependencies for core profile."
fi

# ── Optional desktop extras ──────────────────────────────
if install_optional_profile; then
	info "Installing optional desktop extras..."
	if ! dwm_install_available_package_profile optional; then
		warn "Some optional desktop extras were unavailable in enabled repositories."
	fi
	ok "Optional desktop extras processed."
else
	warn "Skipping optional desktop extras for $INSTALL_PROFILE profile."
fi

# ── Vicinae app launcher ─────────────────────────────────
if install_recommended_profile && ! prepare_vicinae; then
	warn "Vicinae will not be installed. Rofi remains available with SUPER+Shift+R."
fi

# ── Qt / GTK theming ─────────────────────────────────────
if install_recommended_profile; then
	info "Configuring Qt/GTK dark-mode dependencies..."
	# dconf: required for gsettings to persist GTK color-scheme changes
	# qt6ct / qt5ct: QT_QPA_PLATFORMTHEME backend for Qt dark mode in standalone WMs
	dwm_install_first_available_profile theme-optional ||
		warn "Neither qt6ct nor qt5ct is available - Qt apps may not respect dark mode."
	ok "Qt/GTK theming dependencies configured."
fi

# ── Fonts ────────────────────────────────────────────────
if install_recommended_profile; then
	info "Installing fonts..."
	FONT_DIR="$HOME/.local/share/fonts"
	mkdir -p "$FONT_DIR"
	install_meslo_nerd_font
	if [ -d "$REPO_DIR/config/polybar/fonts" ]; then
		cp -r "$REPO_DIR/config/polybar/fonts/"* "$FONT_DIR/"
		fc-cache -fv >/dev/null 2>&1
	fi
	ok "Fonts installed."
fi

# ── Terminal emulator ────────────────────────────────────
terminal=""
for t in alacritty ghostty kitty; do command -v "$t" &>/dev/null && {
	terminal="$t"
	break
}; done

if [ -n "$terminal" ]; then
	ok "Terminal already installed: $terminal"
else
	info "No supported terminal found - installing one from enabled repositories..."
	install_supported_terminal
	terminal="$(detect_terminal)"
fi

# ── XDG dirs + wallpapers ────────────────────────────────
if install_optional_profile && command -v xdg-user-dirs-update &>/dev/null; then
	xdg-user-dirs-update
fi

if install_optional_profile; then
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
fi

# ── Display manager ──────────────────────────────────────
currentdm="$(detect_display_manager)"

if [ -n "$currentdm" ]; then
	ok "Display manager already installed: $currentdm"
elif ! install_optional_profile; then
	warn "No display manager found; skipping display-manager installation for $INSTALL_PROFILE profile."
else
	if is_arch_arm; then
		info "No display manager found - installing SDDM for Arch ARM..."
		dwm_install_package_profile arm-display-manager
		sudo systemctl enable sddm.service
		currentdm="sddm"
		ok "SDDM installed and enabled."
	else
		info "No display manager found - installing LightDM..."
		dwm_install_package_profile lightdm
		sudo systemctl enable lightdm.service
		currentdm="lightdm"
		ok "LightDM installed and enabled."
	fi
fi

# ── LightDM greeter config ───────────────────────────────
if [[ $currentdm == "lightdm" ]]; then
	info "Deploying LightDM Slick Greeter config..."
	install_lightdm_config
	ok "LightDM config deployed."
fi

if is_arch_arm; then
	warn "ARM NOTE: If picom causes display issues, set 'backend = \"xrender\"' in ~/.config/picom.conf"
	warn "ARM NOTE: Some SBCs may need a board-specific KMS or GPU driver configuration for accelerated Xorg."
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
	DATADIR="/usr/share" \
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}" \
	VICINAE_SOURCE_DIR="$VICINAE_SOURCE_DIR"
configure_seeded_terminal "$HOTKEYS_FILE" "$terminal"

if [[ -n $VICINAE_SOURCE_DIR ]]; then
	enable_vicinae_user_service
fi

# ── Done ─────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Detected: $DISTRO_NAME"
echo "  • Build configuration: $REPO_DIR/config.h"
echo "  • Reconfigure by removing config.h and running the installer again"
echo "  • Log out and select 'dwm', or start with: startx"
echo ""
echo "  SUPER+/   keybind viewer     SUPER+X  terminal"
echo "  SUPER+F1  control center     SUPER+R  app launcher (Vicinae)"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: docs/src/keybinds.md or SUPER+/ in dwm"
echo ""
