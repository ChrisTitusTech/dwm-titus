#!/usr/bin/env bash
# Shared package capability map for dwm-titus installers and diagnostics.

dwm_packages() {
	local family=$1
	local profile=$2

	case "$family:$profile" in
	fedora:build)
		printf '%s\n' \
			gcc make pkgconf-pkg-config libX11-devel libXft-devel \
			libXinerama-devel libXrender-devel imlib2-devel libxcb-devel \
			xcb-util-devel freetype-devel fontconfig-devel
		;;
	fedora:x11)
		printf '%s\n' xorg-x11-server-Xorg xorg-x11-xinit xrandr xset xsetroot xinput setxkbmap
		;;
	fedora:runtime-required)
		printf '%s\n' dbus-x11 curl git procps-ng psmisc unzip util-linux xclip xdotool xprop xdg-utils
		;;
	fedora:desktop)
		# Fedora 44 publishes the compatible Quickshell snapshot in its official
		# fedora/updates repositories. It is required and belongs in the strict
		# desktop transaction; the Fedora package-map check proves availability.
		printf '%s\n' \
			quickshell picom feh dex-autostart mate-polkit \
			alsa-utils brightnessctl pulseaudio-utils pipewire pavucontrol \
			pipewire-pulseaudio wireplumber libnotify light-locker xorg-x11-drv-libinput \
			bluez blueman playerctl flatpak xdg-desktop-portal-gtk
		;;
	fedora:desktop-optional)
		printf '%s\n' \
			Thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs gnome-keyring gnome-keyring-pam NetworkManager \
			rsync
		;;
	fedora:gaming)
		if [[ ${ARCH:-$(uname -m)} == x86_64 ]]; then
			printf '%s\n' \
				steam gamescope gamemode.x86_64 gamemode.i686 \
				mangohud.x86_64 mangohud.i686
		fi
		;;
	fedora:theme)
		printf '%s\n' dconf
		;;
	fedora:theme-gtk)
		printf '%s\n' \
			arc-theme adw-gtk3-theme numix-gtk-theme \
			yaru-gtk3-theme yaru-gtk4-theme deepin-gtk-theme \
			bluebird-gtk3-theme
		;;
	fedora:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	fedora:fonts)
		printf '%s\n' google-noto-color-emoji-fonts google-noto-sans-mono-fonts
		;;
	fedora:qml-development)
		printf '%s\n' qt6-qtdeclarative-devel
		;;
	fedora:qml-validation)
		printf '%s\n' quickshell
		dwm_packages "$family" qml-development
		;;
	fedora:lightdm)
		printf '%s\n' lightdm slick-greeter
		;;
	fedora:terminal)
		printf '%s\n' alacritty kitty
		;;
	fedora:terminal-primary)
		printf '%s\n' alacritty
		;;
	fedora:screenshot-optional)
		printf '%s\n' maim
		;;
	fedora:required)
		dwm_packages "$family" build
		dwm_packages "$family" x11
		dwm_packages "$family" runtime-required
		;;
	fedora:recommended)
		dwm_packages "$family" desktop
		dwm_packages "$family" screenshot-optional
		dwm_packages "$family" theme
		dwm_packages "$family" theme-gtk
		dwm_packages "$family" fonts
		;;
	fedora:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
		;;
	fedora:full)
		dwm_packages "$family" required
		dwm_packages "$family" recommended
		dwm_packages "$family" optional
		dwm_packages "$family" gaming
		;;
	*)
		return 1
		;;
	esac
}

dwm_install_package_profile() {
	local profile=$1
	local packages=()
	local package

	while IFS= read -r package; do
		[[ -n $package ]] && packages+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#packages[@]} == 0)); then
		return 0
	fi

	install_packages "${packages[@]}"
}

dwm_install_available_package_profile() {
	local profile=$1
	local package
	local status=0

	while IFS= read -r package; do
		[[ -n $package ]] || continue
		if ! install_optional_package "$package"; then
			printf 'Skipping unavailable optional package: %s\n' "$package" >&2
			status=1
		fi
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	return "$status"
}

dwm_install_first_available_package() {
	local package

	for package in "$@"; do
		if install_optional_package "$package" 2>/dev/null; then
			return 0
		fi
	done

	return 1
}

dwm_install_first_available_profile() {
	local profile=$1
	local packages=()
	local package

	while IFS= read -r package; do
		[[ -n $package ]] && packages+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#packages[@]} == 0)); then
		return 1
	fi

	dwm_install_first_available_package "${packages[@]}"
}
