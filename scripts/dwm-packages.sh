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
	arch:desktop)
		printf '%s\n' \
			rofi picom dunst feh flameshot dex mate-polkit alsa-utils \
			brightnessctl curl git procps-ng psmisc unzip xclip xdotool \
			xorg-xprop thunar gvfs tumbler thunar-archive-plugin nwg-look \
			xdg-user-dirs xdg-utils xdg-desktop-portal-gtk pipewire \
			pipewire-pulse wireplumber pavucontrol gnome-keyring \
			networkmanager network-manager-applet libnotify rsync
		;;
	arch:desktop-optional) ;;
	arch:theme)
		printf '%s\n' dconf
		;;
	arch:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	arch:fonts)
		printf '%s\n' noto-fonts-emoji ttf-meslo-nerd
		;;
	arch:bar)
		printf '%s\n' polybar
		;;
	arch:lightdm)
		printf '%s\n' lightdm lightdm-slick-greeter
		;;
	arch:terminal)
		printf '%s\n' ghostty kitty alacritty
		;;
	arch:terminal-arm)
		printf '%s\n' kitty alacritty
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
	rhel:desktop)
		printf '%s\n' \
			rofi picom dunst feh flameshot dex-autostart mate-polkit \
			alsa-utils brightnessctl curl git procps-ng psmisc \
			pulseaudio-utils unzip xclip xdotool xprop Thunar gvfs tumbler \
			thunar-archive-plugin file-roller xdg-user-dirs xdg-utils \
			xdg-desktop-portal-gtk pipewire pavucontrol gnome-keyring \
			pipewire-pulseaudio wireplumber NetworkManager \
			network-manager-applet libnotify rsync dbus-x11 \
			xorg-x11-drv-libinput
		;;
	rhel:desktop-optional)
		printf '%s\n' nwg-look
		;;
	rhel:theme)
		printf '%s\n' dconf
		;;
	rhel:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	rhel:fonts)
		printf '%s\n' google-noto-color-emoji-fonts google-noto-sans-mono-fonts
		;;
	rhel:bar)
		printf '%s\n' polybar
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
	debian:desktop)
		printf '%s\n' \
			rofi picom dunst feh flameshot dex mate-polkit alsa-utils \
			brightnessctl curl git procps psmisc pulseaudio-utils unzip \
			xclip xdotool x11-utils thunar gvfs tumbler \
			thunar-archive-plugin file-roller xdg-user-dirs xdg-utils \
			xdg-desktop-portal-gtk pipewire pipewire-pulse wireplumber \
			pavucontrol gnome-keyring network-manager network-manager-gnome \
			libnotify-bin rsync dbus-x11
		;;
	debian:desktop-optional) ;;
	debian:theme)
		printf '%s\n' dconf
		;;
	debian:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	debian:fonts)
		printf '%s\n' fonts-noto-color-emoji fonts-noto-mono
		;;
	debian:bar)
		printf '%s\n' polybar
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
		;;
	*:recommended)
		dwm_packages "$family" desktop
		dwm_packages "$family" theme
		dwm_packages "$family" fonts
		dwm_packages "$family" bar
		;;
	*:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
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
