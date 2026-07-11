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
)

required_packages=(
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
	DISTRO_ID=fedora dwm_packages rhel full | awk 'NF' | sort -u
)

for mapping in arch:gvfs-smb rhel:gvfs-smb debian:gvfs-backends; do
	family=${mapping%%:*}
	package=${mapping#*:}
	DISTRO_ID=$([[ $family == rhel ]] && printf fedora || printf '%s' "$family") \
		dwm_packages "$family" full | grep -Fxq "$package"
done

for ks in "$standard_ks" "$nvidia_ks"; do
	for repo_line in "${required_repos[@]}"; do
		grep -Fq "$repo_line" "$ks"
	done
	for package in "${required_packages[@]}"; do
		grep -Fxq "$package" "$ks"
	done
	for package in "${mapped_fedora_packages[@]}"; do
		grep -Fxq "$package" "$ks"
	done
	if grep -Eq 'updates-testing|rpmfusion-.*-updates-testing' "$ks"; then
		printf 'Testing repo found in %s\n' "$ks" >&2
		exit 1
	fi
	grep -Fq "url --metalink=\"https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch\"" "$ks"
	grep -Fq 'firstboot --disable' "$ks"
	grep -Fq 'selinux --disabled' "$ks"
	grep -Fq './install.sh --non-interactive --profile core' "$ks"
	if grep -Eq 'systemctl --user (enable|start).*(dwm|wm)-graphical-session' "$ks"; then
		printf 'Kickstart starts graphical autostart before the first dwm session: %s\n' "$ks" >&2
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
