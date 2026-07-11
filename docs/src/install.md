# Installation

> A supported Debian-, Arch-, or Fedora/RHEL-family distribution with Xorg is
> required.

## Quick Install (Recommended)

The easiest way is via [Linutil](https://christitus.com/linux):

```bash
curl -fsSL https://christitus.com/linux | sh
```

In the TUI, press `v` to multi-select, then select **dwm**, **bash prompt**,
and **alacritty**. Press `Enter` to install.

![linutil-appinstall](images/linutil-applications.png)

## Manual Install

### 1. Dependencies

The supported dependency path is the installer because it resolves package
names for Debian-, Arch-, and Fedora/RHEL-family systems from the shared map:

```bash
./install.sh --dry-run --non-interactive --profile core
./install.sh --profile full
```

Use `core` for the required build/X11/session packages and one terminal,
`recommended` for the desktop layer, or `full` for optional extras such as
file-manager integration, portals, wallpapers, and display-manager setup.

### 2. Clone and Build

```bash
git clone https://github.com/ChrisTitusTech/dwm-titus.git
cd dwm-titus
cp config.def.h config.h
make
sudo make install
```

### Automated Installer

```bash
./install.sh
```

The script detects the distribution family and handles dependency
installation, font copying, display-manager integration, and config placement.
Existing user configuration and `.xinitrc` files are preserved.

Installer package profiles are selected with `DWM_INSTALL_PROFILE`:

- `core`: required build packages, X11/session runtime, and one supported
  terminal.
- `recommended`: `core` plus the recommended desktop layer such as Quickshell,
  Quickshell, Picom, Feh, Dex, fonts, theming, screenshot, audio, Bluetooth
  control and tray tools, and brightness tools. It also installs portable GTK theme packages where available and
  installs Nordic system-wide for the default Nord theme.
- `full`: `recommended` plus optional extras such as Thunar with SMB-share
  browsing, network tray utilities, portals, wallpapers, and display-manager
  setup.

The default is `full` to preserve the historical automated installer behavior.
For a minimal install:

```bash
DWM_INSTALL_PROFILE=core ./install.sh
```

The same profile can be selected with a flag:

```bash
./install.sh --profile core
```

Interactive runs print the resolved package plan before prompting. For CI,
packaging checks, or scripted validation, use the non-interactive flags:

```bash
./install.sh --dry-run --non-interactive --profile core
./install.sh --non-interactive --yes --profile recommended
```

## Starting dwm

**Display manager** (SDDM, GDM, LightDM): log out and select **dwm** from the session list.

**startx:**
```bash
startx
```

The provided `.xinitrc` disables screen blanking, starts the configured Quickshell panel, and runs dwm.

## Minimal Session Profile

The minimal supported profile is useful for lean systems, recovery sessions,
and portability testing. It keeps only:

- an X11 server and either a display-manager session or `startx`
- D-Bus session support
- `dwm`
- one supported terminal available through `dwm-terminal`
- required X11 helpers used by core startup and display commands, such as
  `xrandr`, `xset`, and `xsetroot`

Quickshell, Picom, Feh, Dex, a polkit agent, screenshot tools, wallpapers, tray
utilities, and audio or brightness helpers are optional in this profile.
Missing optional components should appear as degraded features in
`dwm-diagnostics`, not as session-fatal failures.

For `startx`, a minimal `.xinitrc` can be:

```sh
#!/bin/sh
xset s off
xset -dpms
xsetroot -cursor_name left_ptr
exec dbus-run-session dwm
```

If the login path already creates a user D-Bus session, use `exec dwm`
instead of wrapping it with `dbus-run-session`.

After installation, verify the profile with:

```bash
dwm-diagnostics
dwm-terminal --print-command
```

`dwm-diagnostics` must report zero required failures before treating the
minimal profile as ready. Optional degraded features can remain unresolved.
