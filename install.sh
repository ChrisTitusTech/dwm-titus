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
  --enable-fedora-gaming-repos
                         Approve the Gamescope COPR and RPM Fusion nonfree.
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
NORDIC_THEME_URL="https://github.com/EliverLara/Nordic.git"
NORDIC_THEME_REF="master"
ARCH="$(uname -m)"
FEDORA_GAMING_COPR="christitustech/copr-fedora"
INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"
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
	local lightdm_seat_section="SeatDefaults"
	local lightdm_greeter_session="lightdm-slick-greeter"
	local lightdm_session_wrapper="/etc/lightdm/Xsession"
	local lightdm_logind_check=false

	if [[ $DISTRO_FAMILY == "rhel" ]]; then
		lightdm_seat_section="Seat:*"
		lightdm_greeter_session="slick-greeter"
		lightdm_session_wrapper=""
		lightdm_logind_check=true
	fi

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

disable_selinux_for_fedora() {
	local selinux_config="/etc/selinux/config"

	if [[ $DISTRO_ID != "fedora" ]]; then
		return
	fi

	info "Disabling SELinux for Fedora..."
	if command -v getenforce &>/dev/null && [[ $(getenforce 2>/dev/null) == "Enforcing" ]]; then
		sudo setenforce 0 || warn "Could not switch SELinux to permissive for this boot."
	fi
	if [[ -f $selinux_config ]]; then
		sudo sed -i -E 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' "$selinux_config"
	else
		sudo install -d -m 0755 /etc/selinux
		printf '%s\n' 'SELINUX=disabled' 'SELINUXTYPE=targeted' |
			sudo tee "$selinux_config" >/dev/null
	fi
	ok "SELinux disabled for future Fedora boots."
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

if [[ $DISTRO_FAMILY == "debian" ]]; then
	info "Refreshing apt package metadata..."
	sudo apt-get update
fi

disable_selinux_for_fedora

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
	if ! dwm_install_available_package_profile theme-gtk; then
		warn "Some GTK theme packages were unavailable in enabled repositories."
	fi
	install_nordic_gtk_theme || true
	dwm_install_package_profile fonts
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
for t in alacritty kitty; do command -v "$t" &>/dev/null && {
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
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
configure_seeded_terminal "$HOTKEYS_FILE" "$terminal"

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
echo "  SUPER+F1  control center     SUPER+R  app launcher"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: docs/src/keybinds.md or SUPER+/ in dwm"
echo ""
