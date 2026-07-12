#!/usr/bin/env bash
# Shared package capability map for dwm-titus installers and diagnostics.

dwm_packages() {
	local family=$1
	local profile=$2

	case "$family:$profile" in
	arch:build)
		printf '%s\n' \
			base-devel libx11 libxft libxinerama libxrender imlib2 \
			libxcb xcb-util freetype2 fontconfig pkgconf
		;;
	arch:x11)
		printf '%s\n' xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset
		;;
	arch:x11-server)
		printf '%s\n' xorg-server
		;;
	arch:runtime-required)
		printf '%s\n' dbus curl git procps-ng psmisc unzip xclip xdotool xorg-xprop xdg-utils
		;;
	arch:desktop)
		printf '%s\n' \
			picom feh flameshot dex mate-polkit alsa-utils \
			brightnessctl pipewire pipewire-pulse wireplumber pavucontrol \
			libnotify light-locker bluez-utils blueman
		;;
	arch:desktop-optional)
		printf '%s\n' \
			thunar gvfs gvfs-smb tumbler thunar-archive-plugin nwg-look xdg-user-dirs \
			xdg-desktop-portal-gtk gnome-keyring networkmanager \
			rsync
		;;
	arch:theme)
		printf '%s\n' dconf
		;;
	arch:theme-gtk)
		printf '%s\n' arc-gtk-theme materia-gtk-theme numix-themes yaru-gtk-theme
		;;
	arch:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	arch:fonts)
		printf '%s\n' noto-fonts-emoji ttf-meslo-nerd
		;;
	arch:lightdm)
		printf '%s\n' lightdm lightdm-slick-greeter
		;;
	arch:terminal)
		printf '%s\n' alacritty kitty
		;;
	arch:terminal-arm)
		printf '%s\n' alacritty kitty
		;;
	arch:arm-video)
		printf '%s\n' xf86-video-fbdev
		;;
	arch:arm-display-manager)
		printf '%s\n' sddm
		;;
	rhel:build)
		printf '%s\n' \
			gcc make pkgconf-pkg-config libX11-devel libXft-devel \
			libXinerama-devel libXrender-devel imlib2-devel libxcb-devel \
			xcb-util-devel freetype-devel fontconfig-devel
		;;
	rhel:x11)
		printf '%s\n' xorg-x11-server-Xorg xorg-x11-xinit
		if [[ ${DISTRO_ID:-} == fedora ]]; then
			printf '%s\n' xrandr xset xsetroot
		else
			printf '%s\n' xorg-x11-server-utils
		fi
		;;
	rhel:x11-server)
		:
		;;
	rhel:runtime-required)
		printf '%s\n' dbus-x11 curl git procps-ng psmisc unzip xclip xdotool xprop xdg-utils
		;;
	rhel:desktop)
		printf '%s\n' \
			quickshell picom feh flameshot dex-autostart mate-polkit \
			alsa-utils brightnessctl pulseaudio-utils pipewire pavucontrol \
			pipewire-pulseaudio wireplumber libnotify light-locker xorg-x11-drv-libinput \
			bluez blueman
		;;
	rhel:desktop-optional)
		printf '%s\n' \
			Thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs xdg-desktop-portal-gtk gnome-keyring NetworkManager \
			rsync nwg-look
		;;
	rhel:gaming)
		if [[ ${DISTRO_ID:-} == fedora ]]; then
			printf '%s\n' \
				steam gamescope gamemode.x86_64 gamemode.i686 \
				mangohud.x86_64 mangohud.i686
		fi
		;;
	rhel:theme)
		printf '%s\n' dconf
		;;
	rhel:theme-gtk)
		if [[ ${DISTRO_ID:-} == fedora ]]; then
			printf '%s\n' \
				arc-theme adw-gtk3-theme numix-gtk-theme \
				yaru-gtk3-theme yaru-gtk4-theme deepin-gtk-theme \
				bluebird-gtk3-theme
		fi
		;;
	rhel:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	rhel:fonts)
		printf '%s\n' google-noto-color-emoji-fonts google-noto-sans-mono-fonts
		;;
	rhel:lightdm)
		printf '%s\n' lightdm slick-greeter
		;;
	rhel:terminal)
		printf '%s\n' alacritty kitty
		;;
	debian:build)
		printf '%s\n' \
			build-essential pkg-config libx11-dev libxft-dev \
			libxinerama-dev libxrender-dev libimlib2-dev libx11-xcb-dev \
			libxcb1-dev libxcb-res0-dev libfontconfig-dev libfreetype-dev
		;;
	debian:x11)
		printf '%s\n' xserver-xorg-core xinit x11-xserver-utils
		;;
	debian:x11-server)
		:
		;;
	debian:runtime-required)
		printf '%s\n' dbus-x11 curl git procps psmisc unzip xclip xdotool x11-utils xdg-utils
		;;
	debian:desktop)
		printf '%s\n' \
			picom feh flameshot dex mate-polkit alsa-utils \
			brightnessctl pulseaudio-utils pipewire pipewire-pulse \
			wireplumber pavucontrol libnotify-bin light-locker bluez blueman
		;;
	debian:desktop-optional)
		printf '%s\n' \
			thunar gvfs gvfs-backends tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs xdg-desktop-portal-gtk gnome-keyring \
			network-manager rsync
		;;
	debian:theme)
		printf '%s\n' dconf
		;;
	debian:theme-gtk)
		printf '%s\n' arc-theme materia-gtk-theme numix-gtk-theme yaru-theme-gtk
		;;
	debian:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	debian:fonts)
		printf '%s\n' fonts-noto-color-emoji fonts-noto-mono
		;;
	debian:lightdm)
		printf '%s\n' lightdm slick-greeter
		;;
	debian:terminal)
		printf '%s\n' alacritty kitty
		;;
	*:required)
		dwm_packages "$family" build
		dwm_packages "$family" x11
		dwm_packages "$family" x11-server
		dwm_packages "$family" runtime-required
		;;
	*:recommended)
		dwm_packages "$family" desktop
		dwm_packages "$family" theme
		dwm_packages "$family" theme-gtk
		dwm_packages "$family" fonts
		;;
	*:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
		if [[ $family == rhel && ${DISTRO_ID:-} == fedora ]]; then
			dwm_packages "$family" gaming
		fi
		;;
	*:full)
		dwm_packages "$family" required
		dwm_packages "$family" recommended
		dwm_packages "$family" optional
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
