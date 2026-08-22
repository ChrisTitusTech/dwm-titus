#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)

standard_ks="$repo/dwm-fedora.ks"
nvidia_ks="$repo/dwm-fedora-nvidia.ks"
builder="$repo/scripts/build-dwm-fedora-installer-iso.sh"

# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

required_repos=(
	'repo --name="updates"'
	'repo --name="fedora-cisco-openh264"'
	'repo --name="rpmfusion-free"'
	'repo --name="rpmfusion-free-updates"'
	'repo --name="rpmfusion-free-tainted"'
	'repo --name="rpmfusion-nonfree"'
	'repo --name="rpmfusion-nonfree-updates"'
	'repo --name="rpmfusion-nonfree-tainted"'
	'repo --name="brave-browser"'
	'repo --name="mwt-packages"'
	'repo --name="christitustech-copr-fedora"'
)

required_packages=(
	flatpak
	maim
	steam
	gamescope
	gamemode.x86_64
	gamemode.i686
	mangohud.x86_64
	mangohud.i686
	quickshell
	Thunar
	gvfs
	gvfs-smb
	tumbler
	thunar-archive-plugin
	file-roller
	xdg-user-dirs
	xdg-desktop-portal-gtk
	gnome-keyring
	gnome-keyring-pam
	qt6ct
	qt5ct
	arc-theme
	adw-gtk3-theme
	numix-gtk-theme
	yaru-gtk3-theme
	yaru-gtk4-theme
	deepin-gtk-theme
	bluebird-gtk3-theme
)

mapfile -t mapped_fedora_packages < <(
	ARCH=x86_64 dwm_packages fedora full | awk 'NF' | sort -u
)

dwm_packages fedora runtime-required | grep -Fx xclip >/dev/null
dwm_packages fedora runtime-required | grep -Fx xdotool >/dev/null
dwm_packages fedora recommended | grep -Fx maim >/dev/null

if dwm_packages fedora runtime-required | grep -Fx maim >/dev/null; then
	printf 'Optional screenshot package leaked into required Fedora packages.\n' >&2
	exit 1
fi
dwm_packages fedora screenshot-optional | grep -Fx maim >/dev/null
dwm_packages fedora x11 | grep -Fx setxkbmap >/dev/null
dwm_packages fedora recommended | grep -Fx playerctl >/dev/null
dwm_packages fedora desktop | grep -Fx quickshell >/dev/null
dwm_packages fedora desktop | grep -Fx flatpak >/dev/null
dwm_packages fedora desktop | grep -Fx xdg-desktop-portal-gtk >/dev/null
dwm_packages fedora desktop | grep -Fx dbus-tools >/dev/null
dwm_packages fedora desktop | grep -Fx inotify-tools >/dev/null
if ARCH=x86_64 dwm_packages fedora full | grep -Fx nwg-look >/dev/null; then
	printf 'Unavailable Fedora package leaked into the image package set: nwg-look\n' >&2
	exit 1
fi
dwm_packages fedora full | grep -Fx gvfs-smb >/dev/null
dwm_packages fedora full | grep -Fx gnome-keyring-pam >/dev/null

for ks in "$standard_ks" "$nvidia_ks"; do
	if grep -Fxq nwg-look "$ks"; then
		printf 'Unavailable Fedora package found in %s: nwg-look\n' "$ks" >&2
		exit 1
	fi
	for repo_line in "${required_repos[@]}"; do
		grep -Fq "$repo_line" "$ks"
	done
	for package in "${required_packages[@]}"; do
		grep -Fxq "$package" "$ks"
	done
	for package in "${mapped_fedora_packages[@]}"; do
		grep -Fxq "$package" "$ks"
	done
	grep -Fxq power-profiles-daemon "$ks"
	grep -Eq '^[[:space:]]*systemctl[[:space:]]+enable[[:space:]]+power-profiles-daemon[.]service([[:space:]]|$)' "$ks"
	if grep -Eq 'updates-testing|rpmfusion-.*-updates-testing' "$ks"; then
		printf 'Testing repo found in %s\n' "$ks" >&2
		exit 1
	fi
	grep -Fq "url --metalink=\"https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch\"" "$ks"
	grep -Fq 'firstboot --disable' "$ks"
	grep -Fq 'selinux --disabled' "$ks"
	grep -Fq './install.sh --non-interactive --profile core' "$ks"
	if grep -Fq -- '--install-herdr' "$ks"; then
		printf 'Herdr must not be installed by default in %s\n' "$ks" >&2
		exit 1
	fi
	grep -Fq 'scripts/install-gearlever' "$ks"
	grep -Fq '%include /tmp/dwm-titus-gaming-repo' "$ks"
	grep -Fq '%include /tmp/dwm-titus-gaming-packages' "$ks"
	# shellcheck disable=SC2016
	grep -Fq 'fedora-$releasever-$basearch/' "$ks"
	# shellcheck disable=SC2016
	if grep -Fq 'fedora-$releasever-x86_64/' "$ks"; then
		printf 'COPR repository is hardcoded to x86_64 outside architecture expansion: %s\n' "$ks" >&2
		exit 1
	fi
	# shellcheck disable=SC2016
	grep -Fq 'case "$(uname -m)" in' "$ks"
	# shellcheck disable=SC2016
	grep -Fq 'usermod -aG gamemode "$target_user"' "$ks"
	grep -Fq "for xdg_dir in \\" "$ks"
	for xdg_parent in \
		"\"\$target_home/.local\"" \
		"\"\$target_home/.local/share\"" \
		"\"\$target_home/.config\""; do
		grep -Fq "$xdg_parent" "$ks"
	done
	grep -Fq "if [ -e \"\$xdg_dir\" ] || [ -L \"\$xdg_dir\" ]; then" "$ks"
	grep -Fq "if [ ! -d \"\$xdg_dir\" ]; then" "$ks"
	grep -Fq "install -d -o \"\$target_user\" -g \"\$target_group\" -m 0755 \"\$xdg_dir\"" "$ks"
	if grep -Fq "install -d -m 0755 \"\$target_home/.local/share\"" "$ks"; then
		printf 'Kickstart creates the user data parent without ownership: %s\n' "$ks" >&2
		exit 1
	fi
	if grep -Eq 'systemctl --user (enable|start).*(dwm|wm)-graphical-session' "$ks"; then
		printf 'Kickstart starts graphical autostart before the first dwm session: %s\n' "$ks" >&2
		exit 1
	fi
done

for package in steam gamescope gamemode.x86_64 gamemode.i686 mangohud.x86_64 mangohud.i686; do
	ARCH=x86_64 dwm_packages fedora full | grep -Fx "$package" >/dev/null
	ARCH=x86_64 dwm_packages fedora gaming | grep -Fx "$package" >/dev/null
	if ARCH=x86_64 dwm_packages fedora optional | grep -Fx "$package" >/dev/null; then
		printf 'Fedora gaming package leaked into the optional profile: %s\n' "$package" >&2
		exit 1
	fi
	if ARCH=aarch64 dwm_packages fedora full | grep -Fx "$package" >/dev/null; then
		printf 'x86-only Fedora gaming package leaked into aarch64 mapping: %s\n' "$package" >&2
		exit 1
	fi
done

if grep -Eq 'akmod-nvidia|xorg-x11-drv-nvidia|nvidia-drm|nouveau' "$standard_ks"; then
	printf 'Standard Kickstart contains NVIDIA-only content.\n' >&2
	exit 1
fi

grep -Fq 'akmod-nvidia' "$nvidia_ks"
grep -Fq 'xorg-x11-drv-nvidia' "$nvidia_ks"
grep -Fq 'xorg-x11-drv-nvidia-cuda' "$nvidia_ks"
grep -Fq 'options nvidia-drm modeset=1 fbdev=1' "$nvidia_ks"
grep -Fq 'rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1' "$nvidia_ks"

grep -Fq 'variant=standard' "$builder"
grep -Fq 'dwm-fedora-nvidia.ks' "$builder"
grep -Fq 'rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1' "$builder"

printf 'Kickstart variants: PASS\n'
