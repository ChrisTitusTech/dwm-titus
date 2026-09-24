---
title: Desktop Dependencies
description: The packages and services behind each part of the dwm-titus desktop, including install profiles, build tools, and image-specific components.
navLabel: Dependencies
eyebrow: Start here
---

# Dependencies

dwm-titus combines **dwm, Quickshell, and Xorg** with services for audio,
networking, power, authentication, and application integration. Fedora is the
only supported distribution; the documented image target is Fedora 44 x86_64.

This guide describes the major direct dependencies selected by the installer,
not an inventory of your machine or every transitive library. DNF and Flatpak
resolve additional dependencies, including Quickshell's Qt/QML runtime.
The [shared package map](https://github.com/ChrisTitusTech/dwm-titus/blob/main/scripts/dwm-packages.sh)
and [installer](https://github.com/ChrisTitusTech/dwm-titus/blob/main/install.sh)
are the source of truth for package selection and conditional installation.

## Installation Profiles

| Choice | What it installs |
| --- | --- |
| `core` | Build tools and libraries, X11, required runtime utilities, media applications, and one supported terminal. It does not install the complete Quickshell desktop. |
| `recommended` | Core plus Quickshell, desktop services, system-management prerequisites, themes, fonts, and Gear Lever. Screenshot and some theme packages are attempted with failure-tolerant handling. |
| `full` | Recommended plus optional file management, keyring, administration and toolkit utilities, wallpapers, and supported gaming integrations. Installs LightDM if no display manager is detected. |
| Dedicated Fedora image | A prepared complete desktop, including image-specific application defaults and boot/storage support. End-user image installation works offline. |

In the tables below, **Core** means every existing-system profile,
**Desktop** means recommended and full, and **Full** means an optional extra
attempted by full. These describe installer selection, not whether dwm itself
requires a component to keep running. For example, Picom is installed by the
desktop profile, but dwm can run without it.

Preview the actual installation plan before making changes:

```sh
./install.sh --dry-run --non-interactive --profile recommended
```

## Window Manager and Desktop Shell

| Piece | Dependencies | Role and selection |
| --- | --- | --- |
| System foundation | Fedora, RPM/DNF, systemd | Host package management, system services, and user sessions. |
| Display server | `xorg-x11-server-Xorg`, `xorg-x11-xinit` | Core. X11 graphics and `startx` support. This is not a Wayland session. |
| Window manager | Repository-built `dwm` | Tiling, floating windows, tags, focus, window rules, and monitor management. |
| Desktop shell | `quickshell` and managed repository QML | Desktop. Panels, launcher, tray, notifications, Control Center, and Settings. Requires Quickshell 0.3.0 or the compatible Fedora 44 snapshot. |
| Compositor | `picom` | Desktop. Compositing, opacity, shadows, and visual effects. |
| Wallpaper | `feh` | Desktop. Applies wallpaper through the managed helpers. Full additionally attempts to download the wallpaper collection. |
| Session communication | `dbus-x11`, systemd user services | Core D-Bus session support; graphical-session integration makes the display environment available to user services. |
| Application autostart | `dex-autostart` | Desktop. Fallback for XDG autostart when the systemd graphical-session path is unavailable. |
| Login screen | `lightdm`, `slick-greeter` | Dedicated images, or full when no display manager is detected. An existing display manager is retained; detected LightDM receives the project's greeter configuration. |
| Terminal | `alacritty`, with supported fallbacks | Core. Alacritty is preferred. If unavailable, the installer checks existing Kitty, st, Warp, or xterm before attempting another supported terminal package. |
| Screen locking | `light-locker` | Desktop. Locking follows the saved power and locking policy. |

The managed Quickshell configuration lives under
`${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/`. The window manager stays separate
from the shell and system-service backends. Settings provides the interface;
helpers and service APIs perform the underlying operations.

## Hardware and System Services

| Piece | Dependencies | Role and selection |
| --- | --- | --- |
| Audio engine | `pipewire`, `wireplumber`, `pipewire-pulseaudio` | Desktop. Audio processing, device/session policy, and PulseAudio compatibility. |
| Audio tools | `alsa-utils`, `pulseaudio-utils`, `pavucontrol` | Desktop. Mixer commands, audio controls, and a standalone configuration interface. |
| Network connections | `NetworkManager` | Full package group. Backend for networking controls; it may already be present on an existing Fedora system. |
| Bluetooth | `bluez`, `blueman` | Desktop. Bluetooth services and device-management tools. |
| Battery and power profiles | `upower`, `power-profiles-daemon` | Desktop. Battery state and performance/power profiles. The installer retains an installed provider of `ppd-service` rather than replacing it. |
| Brightness | `brightnessctl` | Desktop. Backlight control where supported by the hardware. |
| Display controls | `xrandr`, `xset`, `xsetroot` | Core. Monitor layout/modes, screen power settings, and root-window utilities. |
| Input controls | `xinput`, `setxkbmap`, `xkbset` | Core. Input settings, keyboard layouts, and accessibility controls. |
| Input driver | `xorg-x11-drv-libinput` | Desktop. Xorg keyboard and pointer driver integration. |
| Authorization dialogs | polkit, `mate-polkit` | Desktop selects the authentication agent. Privileged operations use narrow installed helpers and authorization policies; QML stays unprivileged. |
| Credential storage | `gnome-keyring`, `gnome-keyring-pam` | Full. Secret storage and login integration. |

## Applications and Desktop Integration

| Piece | Dependencies | Role and selection |
| --- | --- | --- |
| File manager | `Thunar` | Full. Graphical folder browsing. |
| File access and shares | `gvfs`, `gvfs-smb` | Full. File-access integration and SMB network shares. |
| Thumbnails | `tumbler` | Full. File-manager thumbnail generation. |
| Archives | `thunar-archive-plugin`, `file-roller` | Full. Archive creation/extraction and file-manager integration. |
| Standard user folders | `xdg-user-dirs` | Full. Initializes standard directories such as Pictures and Downloads. |
| Default apps and desktop entries | `xdg-utils`, `desktop-file-utils` | Core. URL/file opening, associations, and desktop-entry utilities. |
| Media playback | `celluloid`, `mpv` | Core. Graphical video player and playback engine. |
| Image viewing | `sxiv` | Core. Image viewer; Feh separately handles wallpapers. |
| Media controls | `playerctl` | Desktop. Controls compatible music and video players. |
| Screenshots | `maim`, managed `dwm-screenshot` helper | Attempted for Desktop. Missing `maim` disables screenshot hotkeys without failing installation. |
| Clipboard | `xclip` | Core. X11 clipboard ownership, including completed screenshot captures. |
| Window inspection and automation | `xdotool`, `xprop` | Core. Window interaction and X11 state inspection used by desktop helpers. |
| Notifications | Quickshell, `libnotify` | Desktop. Quickshell displays notifications; libnotify supplies client tools. |
| Sandboxed applications | `flatpak`, `xdg-desktop-portal-gtk` | Desktop. Flatpak applications and portal integration such as file dialogs. |
| AppImage management | Gear Lever (`it.mijorus.gearlever`) | Desktop. Installed through user-scoped Flathub when needed; integrates AppImages with the launcher. |
| Software management | `PackageKit`, `PackageKit-glib`, `python3-gobject`, `python3-rpm` | Desktop. Package transactions, installed-package information, and system-management integration. |
| User accounts | `accountsservice`; optional `lxqt-admin` | Desktop account-service prerequisites; Full additionally attempts the delegated administration tool. |
| Printing | `cups`, `system-config-printer` | Desktop. Print service and printer-configuration tools. |
| Additional package UI | `dnfdragora` | Full. Standalone graphical package management. |

Package presence does not imply that every service is running or every hardware
feature is available. Settings reports unsupported capabilities and delegates
selected advanced operations to the relevant tools.

## Appearance and Helper Infrastructure

| Piece | Dependencies | Role and selection |
| --- | --- | --- |
| GTK settings | `xsettingsd`, `dconf` | Desktop. Session appearance settings and persistent toolkit preferences. |
| Qt appearance | `qt6ct`, `qt5ct` | Recommended attempts the first available candidate; Full attempts both optional packages. Qt toolkit theme integration. |
| Icons | `adwaita-icon-theme`, `papirus-icon-theme` | Desktop. Application and desktop icons. |
| GTK themes | `arc-theme`, `adw-gtk3-theme`, `numix-gtk-theme`, `yaru-gtk3-theme`, `yaru-gtk4-theme`, `deepin-gtk-theme`, `bluebird-gtk3-theme` | Attempted for Desktop; unavailable themes do not fail installation. Nordic has a separate installation path. |
| Fonts | `google-noto-color-emoji-fonts`, `google-noto-sans-mono-fonts`, Meslo Nerd Font | Desktop. Emoji, monospace text, and icon glyphs. Meslo uses the installer's separate font setup. |
| Helper runtime | `python3` | Core. Managed desktop helpers and supporting scripts. |
| Structured data and events | `jq`, `inotify-tools`, `dbus-tools` | Desktop. JSON processing, filesystem watches, and service communication. |
| Update isolation | `bubblewrap`, `libseccomp` | Desktop. Sandboxing and syscall restrictions for the desktop update workflow. |
| Download and source tools | `curl`, `git`, `unzip` | Core. Downloads, source updates, and archive extraction. |
| Process and session tools | `procps-ng`, `psmisc`, `util-linux` | Core. Process inspection/control and session utilities. |
| File synchronization | `rsync` | Full optional group; also used by image-building tooling. |

The source-update reconciliation group is deliberately smaller than a complete
installation profile: `xsettingsd`, `xkbset`, `bubblewrap`, and `libseccomp`.
Rerun the installer with `recommended` or `full` to add that profile's complete
system-management prerequisites to an older installation.

## Gaming and Image-Specific Components

| Selection | Dependencies | Purpose |
| --- | --- | --- |
| Full gaming integration on x86_64 | `steam`, `gamescope`, `gamemode.x86_64`, `gamemode.i686`, `mangohud.x86_64`, `mangohud.i686` | Game delivery, nested game presentation, performance tuning, and overlays. Includes selected 32-bit support. Third-party repository setup requires approval. |
| Dedicated image browser | `brave-origin` | Brave Origin is the fresh-account browser default. Existing-system application choices are preserved. |
| Dedicated image prompt | Starship | Shell prompt with desktop-matched theming. |
| Terminal workspace | Herdr | Verified offline availability in dedicated images. Existing-system installation and activation remain opt-in; normal terminal launches still open Alacritty directly. |
| NVIDIA image only | `akmod-nvidia`, `xorg-x11-drv-nvidia`, `xorg-x11-drv-nvidia-cuda`, `nvidia-settings` | Proprietary NVIDIA kernel/graphics support and configuration. Excluded from the standard image. |

The image boot/storage group includes `tar`, `dracut-network`, `grub2-pc`,
`grub2-pc-modules`, `grub2-efi-x64`, `shim-x64`, `lvm2`, `cryptsetup`,
`btrfs-progs`, `xfsprogs`, `e2fsprogs`, `mdadm`, and `dosfstools`. These support
image installation, boot, filesystems, encryption, and storage configurations;
they are not additional resident desktop-shell components.

## Build and Validation Dependencies

The source installer compiles dwm, so even `core` selects these build packages:

| Dependencies | Purpose |
| --- | --- |
| `gcc`, `make`, `pkgconf-pkg-config` | C compiler, build system, and library discovery. |
| `libX11-devel`, `libxcb-devel`, `xcb-util-devel` | X11 and XCB interfaces. |
| `libXinerama-devel` | Multi-monitor interfaces. |
| `libXrender-devel`, `libXft-devel` | Rendering and text drawing. |
| `freetype-devel`, `fontconfig-devel` | Font rendering and discovery. |
| `imlib2-devel` | Image handling. |

Development and image-factory profiles have additional tools that are separate
from the everyday desktop:

- **QML development/validation:** `qt6-qtdeclarative-devel`, plus Quickshell and
  `xsettingsd` for validation. QML linting needs explicit Qt and Quickshell
  import roots; see the repository specification.
- **Headless smoke testing:** `xorg-x11-server-Xvfb`, `dbus-daemon`, `gawk`,
  `google-noto-sans-fonts`, and the build/runtime tools in the `ci-smoke` map.
- **Image assembly:** `xorriso`, `rsync`, `squashfs-tools-ng`, `isomd5sum`,
  `python3-pillow`, `fontconfig`, and `google-noto-sans-fonts`.
- **Image factory and VM qualification:** `qemu-system-x86`, `qemu-img`,
  `edk2-ovmf`, `libguestfs`, `pykickstart`, `xz`, `zstd`, and `time`, in addition
  to image-assembly tools.

For installation steps, return to [Installation](/install.html). For the
underlying contracts, see the
[project specification](https://github.com/ChrisTitusTech/dwm-titus/blob/main/SPEC.md).
