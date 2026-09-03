---
title: Fedora Installation
description: Install the complete dwm-titus Fedora X11 desktop from an image or onto an existing Fedora system.
navLabel: Installation
eyebrow: Start here
---

# Fedora Installation

> **dwm-titus is Fedora-only.** Fedora Linux with Xorg is required for every
> supported installation, package, test, and release path.

## Quick Install (Recommended)

The easiest way is via [Linutil](https://christitus.com/linux):

```bash
curl -fsSL https://christitus.com/linux | sh
```

In the TUI, press `v` to multi-select, then select **dwm**, **bash prompt**,
and **alacritty**. Press `Enter` to install.

Herdr is optional. To add its checksum-verified helper after the Linutil path,
run:

```bash
install-herdr
```

![The dwm-titus applications menu in Linutil](/images/linutil-applications.png)

## Manual Install

### 1. Dependencies

The supported dependency path is the installer because it resolves Fedora
package names from the shared map:

```bash
./install.sh --dry-run --non-interactive --profile core
./install.sh --profile full
```

Use `core` for the required build/X11/session packages and Alacritty,
`recommended` for the complete desktop layer, or `full` for optional extras
such as file-manager integration, keyring login integration, wallpapers, and
display-manager setup. On x86_64 Fedora, `full` can also install Steam,
Gamescope, GameMode, and MangoHud after repository approval.
The installer separately asks before enabling the `christitustech/copr-fedora`
COPR for patched Gamescope and RPM Fusion nonfree for Steam. Declining skips the
gaming subset without affecting other full-profile extras.

### 2. Clone and Build

```bash
git clone https://github.com/ChrisTitusTech/dwm-titus.git
cd dwm-titus
cp config.def.h config.h
./scripts/dev-sync-install.sh
```

For later source-checkout updates, run the same command so the binary,
installed helpers, managed Quickshell configuration, and data copy stay at one
revision. Run `./scripts/dev-sync-install.sh --check` after any requested
session restart to verify the active runtime.

### Automated Installer

```bash
./install.sh
```

The script requires `ID=fedora` before handling dependency installation, font
copying, display-manager integration, or config placement. Every other
operating-system identity is rejected before changes are made.
Existing user configuration and `.xinitrc` files are preserved. Upgrades remove
the known legacy `dwm-graphical-session.service` and
`wm-graphical-session.service` early-start configuration so XDG applications
start only after the X11 display environment is available; customized user
units are disabled from early startup but otherwise preserved.

System files are installed with `sudo`, while configuration and data under the
user's XDG directories are installed as that user.

If a v0.6.0 Fedora image left the default XDG parents owned by root, first
verify that none of them is a symbolic link, then repair only those parents and
rerun the installer:

```bash
xdg_parents=()
for path in "$HOME/.local" "$HOME/.local/share" "$HOME/.config"; do
    test ! -L "$path" || {
        printf 'Refusing symbolic link: %s\n' "$path" >&2
        exit 1
    }
    test -e "$path" || continue
    test -d "$path" || { printf 'Refusing non-directory: %s\n' "$path" >&2; exit 1; }
    xdg_parents+=("$path")
done
((${#xdg_parents[@]} == 0)) || sudo chown "$(id -u):$(id -g)" -- "${xdg_parents[@]}"
./install.sh
```

This repair is intentionally non-recursive so it does not change unrelated
user files.

Every profile and Fedora image defaults to Alacritty without Herdr. With the
explicit `--install-herdr` option, the repository downloads the official
`https://herdr.dev/install.sh` into an isolated staging directory and verifies
repository-pinned SHA-256 checksums for both that installer and its resulting
Herdr binary before copying it into `~/.local/bin`. A checksum mismatch or
network failure leaves Alacritty usable and reports the Herdr failure. When the
`codex` or `claude` command is already available, the helper also runs Herdr's
matching `integration install` command so native Codex and Claude Code sessions
can be restored. Integration failures are reported separately from binary
installation failures.

When matching vendor XDG entries exist for Picom, the polkit agent, or Light
Locker, the installer copies each entry to the user autostart directory and
adds only the dwm session exclusion. Original commands and vendor session
guards remain intact, no entry is created when the vendor entry is absent, and
existing user entries are preserved.

Installer package profiles are selected with `DWM_INSTALL_PROFILE`:

- `core`: required build packages, X11/session runtime, and Alacritty. Herdr is
  skipped unless `--install-herdr` is provided.
- `recommended`: `core` plus the recommended desktop layer such as Quickshell,
  Picom, Feh, Dex, fonts, theming, screenshot, audio, Bluetooth control and
  tray tools, brightness tools, Flatpak, the GTK desktop portal, PackageKit,
  AccountsService, CUPS, and the Fedora printer configuration tool. These
  system services are prerequisites for the planned Phase 6 Settings update,
  account-summary, and printer entry points. The profile also adds Flathub for
  the target user, installs Gear Lever as the default AppImage manager, installs
  the available Fedora GTK theme packages, and installs Nordic system-wide for
  the default Nord theme. Later source-checkout synchronization reconciles the
  required Phase 6 PackageKit, Python RPM binding, AccountsService, CUPS, and
  printer-tool packages before reporting a recommended/full install current.
- `full`: `recommended` plus optional extras such as Thunar with SMB-share
  browsing, network tray utilities, keyring login integration,
  wallpapers, and display-manager setup. x86_64 Fedora full installs also
  include Steam, Gamescope, and 64-bit and 32-bit GameMode and MangoHud support
  after separate repository approval.
  The installer enables the `christitustech/copr-fedora` COPR for Gamescope and
  RPM Fusion nonfree for Steam, then adds the invoking user to the `gamemode`
  group; log out and back in before using its privileged tuning helpers.

The default is `full` to preserve the historical automated installer behavior.
Existing source-checkout installations upgrading into Phase 6 should rerun
`./install.sh --profile recommended` (or `full`) to install the new system
management packages; a dry run previews the added packages first. The update
does not remove packages or alter the host SELinux policy.
If `maim` is unavailable in the enabled Fedora repositories, the installer
skips that add-on instead of failing the desktop install and reports that the
screenshot hotkeys are unavailable.

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
./install.sh --non-interactive --yes --profile full --enable-fedora-gaming-repos
```

Without `--enable-fedora-gaming-repos`, unattended Fedora full installs skip
Steam, Gamescope, GameMode, and MangoHud rather than changing repository trust.

Herdr is skipped for every profile unless `--install-herdr` or
`DWM_INSTALL_HERDR=true` is provided. Its published Linux binaries support
x86_64 and aarch64. Installation alone does not change the terminal default;
set `DWM_HERDR=1` and run `dwm-terminal` to enter the optional workspace.
Herdr can also be installed or repaired separately:

```bash
install-herdr
install-herdr --force
```

Upgrades preserve an existing `hotkeys.toml`. If an earlier installer seeded
its `terminal` variable to `dwm-terminal`, set it to `alacritty` to adopt the
current direct-terminal default. The installer does not overwrite that
user-owned choice.

## Starting dwm

**Display manager** (SDDM, GDM, LightDM): log out and select **dwm** from the session list.

When the interactive installer runs inside an active X11 session, it offers
the `dwm-display-setup` wizard after installation. The wizard previews the
chosen resolution and multi-monitor layout, then installs a backed-up Xorg
fragment. Installations run from a TTY or in non-interactive mode defer this
step; after the first X11 login, run:

```bash
dwm-display-setup
```

The installed Settings display provider is machine-oriented. Its actions are:

```text
dwm-settings-display discover
dwm-settings-display watch
dwm-settings-display save NAME SPEC...
dwm-settings-display preview TOKEN SECONDS SPEC...
dwm-settings-display preview-profile TOKEN SECONDS NAME
dwm-settings-display keep TOKEN [NAME]
dwm-settings-display revert TOKEN
dwm-settings-display preview-status [TOKEN]
dwm-settings-display install-profile NAME
dwm-settings-display rollback-system
```

Discovery and live previews require `xrandr`, and the hotplug watch requires
`udevadm`. Persistent install and rollback additionally require `pkexec` plus
the root-owned helper installed at `${PREFIX}/libexec/dwm-titus/`. Profiles are
stored under
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/display-profiles/`. No move is
needed for profiles created by `dwm-display-profile`, which uses the same
directory. If `DWM_DISPLAY_PROFILE_DIR` previously pointed elsewhere, either
keep that environment override or move those `.conf` files into the default
directory before using Settings.

The input provider exposes the corresponding session actions:

```text
dwm-settings-input discover
dwm-settings-input watch
dwm-settings-input watch-apply
dwm-settings-input apply-saved
dwm-settings-input preview TOKEN SECONDS DEVICE SETTING VALUE
dwm-settings-input keep TOKEN
dwm-settings-input revert TOKEN
dwm-settings-input preview-status [TOKEN]
dwm-settings-input reset DEVICE SETTING
```

Input discovery and per-device actions require `xinput`; keyboard layout and
modifier operations also require `setxkbmap`; session-wide XKB accessibility
controls require `xkbset`; stable hardware identity and hotplug watching use
`udevadm`, and the session watcher uses `flock` from `util-linux` to prevent
duplicate replay workers. Kept values default to
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/input-settings.conf`. Set
`DWM_INPUT_SETTINGS_FILE` to use a different file. The normal session startup
invokes `apply-saved` idempotently and runs `watch-apply` to debounce input
hotplug events before replaying saved values for returning devices.

**startx:**
```bash
startx
```

The provided `.xinitrc` disables screen blanking, starts the configured Quickshell panel, and runs dwm.

## Minimal Session Profile

The minimal supported profile is useful for lean Fedora systems, recovery
sessions, and minimal Fedora qualification. It keeps only:

- an X11 server and either a display-manager session or `startx`
- D-Bus session support
- `dwm`
- Alacritty as the default terminal, with `dwm-terminal` available to delegated
  tools that require fallback selection
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
The default binding opens Alacritty directly. A plain `dwm-terminal` also opens
the selected emulator directly unless `DWM_HERDR=1` explicitly enables Herdr.
Commands such as `dwm-terminal -e sh -c 'command'` always bypass Herdr.
