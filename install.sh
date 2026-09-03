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
  --install-herdr        Install verified Herdr as an optional workspace.
  --skip-herdr           Do not install Herdr.
  --enable-fedora-gaming-repos
                         Approve the Gamescope COPR and RPM Fusion nonfree.
  --dry-run              Print the resolved plan and exit before changes.
  -h, --help             Show this help.
EOF
}

case "$DISTRO_FAMILY" in
fedora)
	command -v dnf &>/dev/null || {
		err "Fedora was detected, but dnf was not found."
		exit 1
	}
	;;
*)
	err "Unsupported distribution: $DISTRO_NAME"
	err "dwm-titus supports Fedora only."
	exit 1
	;;
esac

BG_DIR="$HOME/Pictures/backgrounds"
MESLO_VERSION="3.4.0"
MESLO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${MESLO_VERSION}/Meslo.zip"
MESLO_SHA256="13b502ac8c2bd9d3161018064560e23cd42b175bb730780a270975265a19ad57"
NORDIC_THEME_URL="https://github.com/EliverLara/Nordic.git"
NORDIC_THEME_REF="master"
ARCH="$(uname -m)"
FEDORA_GAMING_COPR="christitustech/copr-fedora"
INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"
HERDR_INSTALL_MODE="${DWM_INSTALL_HERDR:-false}"
NON_INTERACTIVE=false
ASSUME_YES=false
FEDORA_GAMING_REPOS_APPROVED=false
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
	--install-herdr)
		HERDR_INSTALL_MODE=true
		shift
		;;
	--skip-herdr)
		HERDR_INSTALL_MODE=false
		shift
		;;
	--enable-fedora-gaming-repos)
		FEDORA_GAMING_REPOS_APPROVED=true
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

case "$HERDR_INSTALL_MODE" in
auto)
	# Retain compatibility with the old value, but no longer install Herdr by
	# default for any profile.
	HERDR_INSTALL_MODE=false
	;;
1 | true | yes)
	HERDR_INSTALL_MODE=true
	;;
0 | false | no)
	HERDR_INSTALL_MODE=false
	;;
*)
	err "Unsupported DWM_INSTALL_HERDR: $HERDR_INSTALL_MODE"
	err "Supported values: auto, true, false"
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

install_recommended_profile() {
	[[ $INSTALL_PROFILE == "recommended" || $INSTALL_PROFILE == "full" ]]
}

install_optional_profile() {
	[[ $INSTALL_PROFILE == "full" ]]
}

herdr_arch_supported() {
	case $ARCH in
	x86_64 | amd64 | aarch64 | arm64)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

install_herdr_profile() {
	[[ $HERDR_INSTALL_MODE == true ]] && herdr_arch_supported
}

fedora_gaming_profile() {
	[[ $DISTRO_ID == "fedora" && $INSTALL_PROFILE == "full" && $ARCH == "x86_64" ]]
}

confirm_fedora_gaming_repositories() {
	local answer

	if ! fedora_gaming_profile || [[ $FEDORA_GAMING_REPOS_APPROVED == true ]]; then
		return
	fi
	if [[ $NON_INTERACTIVE == true ]]; then
		warn "Skipping Fedora gaming packages because third-party repositories were not approved."
		warn "Re-run with --enable-fedora-gaming-repos to approve the Gamescope COPR and RPM Fusion nonfree."
		return
	fi

	printf 'Enable the %s COPR and RPM Fusion nonfree for Fedora gaming packages? [y/N] ' \
		"$FEDORA_GAMING_COPR"
	read -r answer
	case "$answer" in
	y | Y | yes | YES)
		FEDORA_GAMING_REPOS_APPROVED=true
		;;
	*)
		warn "Fedora gaming repositories declined; skipping Steam, Gamescope, GameMode, and MangoHud."
		;;
	esac
}

configure_fedora_gaming_repositories() {
	local fedora_release
	local plugin_package
	local rpmfusion_release_url

	if [[ $DISTRO_ID != "fedora" || $INSTALL_PROFILE != "full" || $ARCH != "x86_64" ]]; then
		return 1
	fi
	if [[ $FEDORA_GAMING_REPOS_APPROVED != true ]]; then
		return 1
	fi

	if ! dnf copr --help &>/dev/null; then
		info "Installing the DNF COPR plugin..."
		for plugin_package in dnf5-plugins dnf-plugins-core; do
			if install_packages "$plugin_package"; then
				break
			fi
		done
		if ! dnf copr --help &>/dev/null; then
			warn "Could not install a working DNF COPR plugin; skipping Fedora gaming packages."
			return 1
		fi
	fi

	if ! command -v rpm &>/dev/null; then
		warn "rpm is unavailable; cannot determine the Fedora release for RPM Fusion."
		return 1
	fi
	fedora_release=$(rpm -E '%fedora')
	case "$fedora_release" in
	'' | *[!0-9]*)
		warn "Could not determine the numeric Fedora release for RPM Fusion."
		return 1
		;;
	esac
	rpmfusion_release_url="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"
	info "Enabling RPM Fusion nonfree for Steam..."
	if ! sudo dnf install -y "$rpmfusion_release_url"; then
		warn "Could not enable RPM Fusion nonfree; skipping Fedora gaming packages."
		return 1
	fi

	info "Enabling the $FEDORA_GAMING_COPR COPR for the patched Gamescope package..."
	if ! sudo dnf copr enable -y "$FEDORA_GAMING_COPR"; then
		warn "Could not enable $FEDORA_GAMING_COPR; skipping Fedora gaming packages."
		return 1
	fi
}

configure_fedora_gamemode_access() {
	local target_user

	if [[ $DISTRO_ID != "fedora" || $INSTALL_PROFILE != "full" ]]; then
		return
	fi
	if ! getent group gamemode >/dev/null 2>&1; then
		warn "GameMode was not installed; skipping privileged tuning access."
		return
	fi

	target_user=$(id -un)
	if id -nG "$target_user" | tr ' ' '\n' | command grep -Fxq gamemode; then
		ok "$target_user already has GameMode tuning access."
		return
	fi

	info "Adding $target_user to the gamemode group..."
	sudo usermod -aG gamemode "$target_user"
	warn "Log out and back in before using GameMode privileged tuning."
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
		printf '  Gear Lever: user-scoped Flathub install (%s)\n' 'it.mijorus.gearlever'
	else
		printf '  Recommended packages: skipped\n'
	fi
	if install_optional_profile; then
		print_summary_profile "Optional extras" optional
		if fedora_gaming_profile; then
			print_summary_profile "Fedora gaming packages" gaming
			if [[ $FEDORA_GAMING_REPOS_APPROVED == true ]]; then
				printf '  Third-party repositories: approved\n'
			else
				printf '  Third-party repositories: require separate confirmation\n'
			fi
		fi
	else
		printf '  Optional extras: skipped\n'
	fi
	print_summary_profile "Terminal candidates" terminal
	if install_herdr_profile; then
		printf '  Herdr workspace: verified user install from https://herdr.dev/install.sh\n'
	elif [[ $HERDR_INSTALL_MODE == true ]]; then
		printf '  Herdr workspace: skipped (unsupported architecture: %s)\n' "$ARCH"
	else
		printf '  Herdr workspace: skipped (optional; use --install-herdr to enable)\n'
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

install_nordic_gtk_theme() {
	local target="/usr/share/themes/Nordic"
	local tmp_dir

	if [[ -d "$target/gtk-3.0" || -d "$target/gtk-4.0" ]]; then
		ok "Nordic GTK theme is already installed system-wide."
		return 0
	fi

	if ! command -v git &>/dev/null; then
		warn "git is unavailable; skipping Nordic GTK theme install."
		return 1
	fi

	tmp_dir="$(mktemp -d)"
	if ! git clone --depth 1 --branch "$NORDIC_THEME_REF" "$NORDIC_THEME_URL" "$tmp_dir/Nordic" 2>/dev/null; then
		rm -rf "$tmp_dir"
		warn "Could not download Nordic GTK theme; continuing without it."
		return 1
	fi

	sudo rm -rf "$target"
	sudo install -d -m 0755 /usr/share/themes
	sudo cp -a "$tmp_dir/Nordic" "$target"
	sudo find "$target" -type d -exec chmod 0755 {} +
	sudo find "$target" -type f -exec chmod 0644 {} +
	rm -rf "$tmp_dir"
	ok "Nordic GTK theme installed system-wide."
}

install_supported_terminal() {
	if ! dwm_install_first_available_profile terminal; then
		err "No supported terminal is available in the enabled repositories."
		return 1
	fi
}

configure_quickshell_picom_opacity() {
	local config="/etc/xdg/picom.conf"
	local backup="${config}.dwm-titus.bak"
	local tooltip_rule="^([[:space:]]*\"[0-9]+([.][0-9]+)?:window_type = 'tooltip')(\"[[:space:]]*,?[[:space:]]*)$"
	local configured_rule="^[[:space:]]*\"[0-9]+([.][0-9]+)?:window_type = 'tooltip' && name != 'quickshell'\"[[:space:]]*,?[[:space:]]*$"
	local tmp

	if [[ ! -f $config ]]; then
		warn "Picom system config not found; skipping Quickshell opacity override."
		return
	fi
	if sudo grep -Eq "$configured_rule" "$config"; then
		ok "Quickshell Picom opacity is already configured."
		return
	fi
	if ! sudo grep -Eq "$tooltip_rule" "$config"; then
		warn "Recognized Picom tooltip opacity rule not found; preserving $config."
		return
	fi

	tmp="$(mktemp)"
	if ! sudo sed -E \
		"s/${tooltip_rule}/\\1 \&\& name != 'quickshell'\\3/" \
		"$config" | tee "$tmp" >/dev/null; then
		rm -f "$tmp"
		warn "Could not prepare the Quickshell Picom opacity override."
		return
	fi

	if [[ ! -f $backup ]]; then
		sudo install -o root -g root -m 0644 "$config" "$backup"
	fi
	sudo install -o root -g root -m 0644 "$tmp" "$config"
	rm -f "$tmp"
	ok "Configured fully opaque Quickshell windows in Picom."
}

configure_displays_after_install() {
	local answer

	if [[ $NON_INTERACTIVE == true ]]; then
		warn "Display setup deferred for non-interactive installation."
		warn "Run dwm-display-setup from an X11 session after login."
		return 0
	fi
	if [[ -z ${DISPLAY:-} ]] || ! command -v xrandr >/dev/null 2>&1; then
		warn "Display setup needs an active X11 session and was deferred."
		warn "After login, run: dwm-display-setup"
		return 0
	fi
	if ! xrandr --query 2>/dev/null | awk '$2 == "connected" { found = 1 } END { exit !found }'; then
		warn "No connected X11 outputs were detected; display setup was deferred."
		return 0
	fi

	printf 'Configure persistent display resolution and positioning now? [Y/n] '
	read -r answer
	case $answer in
	n | N | no | NO)
		warn "Display setup skipped. Run dwm-display-setup when ready."
		;;
	*)
		if ! "$REPO_DIR/scripts/dwm-display-setup" wizard; then
			warn "Display setup did not complete. Existing Xorg configuration was preserved."
			warn "Run dwm-display-setup to try again."
		fi
		;;
	esac
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
	local lightdm_seat_section="SeatDefaults"
	local lightdm_greeter_session="lightdm-slick-greeter"
	local lightdm_session_wrapper="/etc/lightdm/Xsession"
	local lightdm_logind_check=false

	lightdm_seat_section="Seat:*"
	lightdm_greeter_session="slick-greeter"
	lightdm_session_wrapper=""
	lightdm_logind_check=true

	sudo make -C "$REPO_DIR/lightdm" \
		LIGHTDM_SEAT_SECTION="$lightdm_seat_section" \
		LIGHTDM_GREETER_SESSION="$lightdm_greeter_session" \
		LIGHTDM_SESSION_WRAPPER="$lightdm_session_wrapper" \
		LIGHTDM_LOGIND_CHECK="$lightdm_logind_check" \
		install
	if command -v restorecon &>/dev/null; then
		sudo restorecon \
			"$lightdm_config" \
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
info "Install profile: $INSTALL_PROFILE"
confirm_install_summary
confirm_fedora_gaming_repositories

if [[ $NON_INTERACTIVE != true ]]; then
	"$REPO_DIR/scripts/configure-build.sh"
else
	"$REPO_DIR/scripts/configure-build.sh" --non-interactive
fi

# ── Required build and runtime dependencies ──────────────
info "Installing required build and runtime dependencies..."
dwm_install_package_profile build
dwm_install_package_profile x11
dwm_install_package_profile runtime-required
ok "Required build and runtime dependencies installed."

# ── Recommended desktop dependencies ─────────────────────
if install_recommended_profile; then
	info "Installing recommended desktop dependencies..."
	dwm_install_package_profile desktop
	dwm_install_package_profile system-management
	if ! env -u DWM_TEST_MODE -u DWM_TEST_QUICKSHELL_VERSION \
		"$REPO_DIR/scripts/dwm-quickshell-version-check"; then
		err "The installed Quickshell build is incompatible with dwm-titus."
		exit 1
	fi
	if ! dwm_install_available_package_profile screenshot-optional; then
		warn "maim is unavailable in the enabled repositories; screenshot hotkeys will remain disabled."
	fi
	dwm_install_package_profile theme
	if ! dwm_install_available_package_profile theme-gtk; then
		warn "Some GTK theme packages were unavailable in enabled repositories."
	fi
	install_nordic_gtk_theme || true
	dwm_install_package_profile fonts
	info "Setting up Gear Lever for AppImage management..."
	if "$REPO_DIR/scripts/install-gearlever"; then
		ok "Gear Lever is installed."
	else
		warn "Gear Lever setup failed; retry with scripts/install-gearlever when Flathub is reachable."
	fi
	ok "Recommended desktop dependencies installed."
else
	warn "Skipping recommended desktop dependencies for core profile."
fi

if command -v picom >/dev/null 2>&1; then
	configure_quickshell_picom_opacity
fi

# ── Optional desktop extras ──────────────────────────────
if install_optional_profile; then
	info "Installing optional desktop extras..."
	if ! dwm_install_available_package_profile optional; then
		warn "Some optional desktop extras were unavailable in enabled repositories."
	fi
	if fedora_gaming_profile; then
		if [[ $FEDORA_GAMING_REPOS_APPROVED != true ]]; then
			warn "Fedora gaming packages were skipped because their repositories were not approved."
		elif configure_fedora_gaming_repositories; then
			info "Installing Fedora gaming packages..."
			if ! dwm_install_available_package_profile gaming; then
				warn "Some Fedora gaming packages were unavailable in the approved repositories."
			fi
			configure_fedora_gamemode_access
		else
			warn "Fedora gaming repository setup failed; no gaming packages were installed."
		fi
	fi
	ok "Optional desktop extras processed."
else
	warn "Skipping optional desktop extras for $INSTALL_PROFILE profile."
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
	ok "Fonts installed."
fi

# ── Terminal emulator ────────────────────────────────────
terminal=""
if command -v alacritty &>/dev/null; then
	terminal="alacritty"
	ok "Preferred terminal already installed: $terminal"
else
	info "Installing the preferred Alacritty terminal from enabled repositories..."
	if dwm_install_first_available_profile terminal-primary; then
		terminal="alacritty"
		ok "Preferred terminal installed: $terminal"
	else
		warn "Alacritty is unavailable; falling back to another supported terminal."
		for t in kitty st warp-terminal xterm; do command -v "$t" &>/dev/null && {
			terminal="$t"
			break
		}; done
		if [ -z "$terminal" ]; then
			install_supported_terminal
			terminal="$(detect_terminal)"
		fi
	fi
fi

# ── Herdr terminal workspace ─────────────────────────────
if install_herdr_profile; then
	info "Installing the verified Herdr workspace for interactive terminals..."
	if "$REPO_DIR/scripts/install-herdr"; then
		ok "Herdr is installed; set DWM_HERDR=1 and use dwm-terminal to open it in $terminal."
	else
		herdr_status=$?
		if [[ $herdr_status -eq 2 ]]; then
			warn "Herdr is ready, but one or more detected agent integrations could not be installed."
		else
			warn "Herdr installation failed; Alacritty remains the default terminal."
		fi
	fi
elif [[ $HERDR_INSTALL_MODE == true ]]; then
	warn "Skipping Herdr installation on unsupported architecture: $ARCH."
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
	info "No display manager found - installing LightDM..."
	dwm_install_package_profile lightdm
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
cd "$REPO_DIR"
make clean
make
sudo make install-system \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	DATADIR="/usr/share"
make install-user \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
configure_displays_after_install

# ── Done ─────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Detected: $DISTRO_NAME"
echo "  • Build configuration: $REPO_DIR/config.h"
echo "  • Reconfigure by removing config.h and running the installer again"
echo "  • Display setup: dwm-display-setup"
echo "  • Log out and select 'dwm', or start with: startx"
if [[ $currentdm == "lightdm" ]]; then
	echo "  • Start LightDM now (optional): sudo systemctl start lightdm.service"
fi
echo ""
echo "  SUPER+/   keybind viewer     SUPER+X  terminal"
echo "  SUPER+F1  control center     SUPER+R  app launcher"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: https://dwm.christitus.com/keybinds.html or SUPER+/ in dwm"
echo ""
