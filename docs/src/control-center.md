# Control Center

The Control Center is an anchored Quickshell popup for panel settings, system
health, quick actions, appearance settings, power management, and keybind
discovery.

**Open:** <kbd>Super</kbd> + <kbd>F1</kbd>, or run `dwm-controlcenter` from a
terminal.

The popup opens from the panel logo. Its side card contains panel widget
visibility, utilities, quick actions, appearance controls, and persisted DPMS
and auto-lock timing. Press <kbd>Esc</kbd> or click outside it to close it.

---

## Network Popover

The panel network indicator opens a Quickshell network popover. It shows active
NetworkManager connections, scans visible Wi-Fi networks, and connects to open
or WPA personal networks directly. Successful Wi-Fi connections are saved as
NetworkManager profiles, so they reconnect normally in later sessions.

Hidden SSIDs and enterprise Wi-Fi are handled through the optional
`nm-connection-editor` fallback when it is installed.

## Bluetooth Popover

The panel Bluetooth indicator opens a compact device manager. It can power the
adapter on or off, scan for devices, pair and trust a new device, connect a
paired device, and disconnect a connected device through `bluetoothctl`.

## Panel Widgets

The Bar Functions card can show or hide the workspace, volume, Bluetooth,
network, and power widgets for the current Quickshell session. The redesigned
panel retains the active-window title, status segments, and system tray, and
shows all nine dwm tags (workspaces). Hovering icon-only panel controls displays
a text tooltip.

The panel, popovers, and control-center cards use fully opaque colors. Their
palette follows the active theme in `themes.toml` and updates when that file is
changed.

---

## Modules

### System Health

System Health opens as a separate full-screen dashboard on the current
monitor. It starts two read-only scans: session checks run immediately, and a
privileged scan completes current-boot journal, kernel, system-service, and
drive checks. If cached or `NOPASSWD` sudo access is available, the scan runs
without a prompt. Otherwise the running polkit agent requests graphical
authorization. Cancelling the prompt leaves a partial report and marks its
coverage as incomplete.

The dashboard groups checks into:

- Boot and kernel errors from `journalctl`, with `dmesg` as a fallback
- Failed user and system services, one service per row
- Memory, pressure, load, swap, filesystem space, and inode use
- Local routing, resolver, and NetworkManager state
- X11, D-Bus, dwm, Quickshell, Picom, audio, and managed configuration
- Required commands, libraries, terminals, and package-database consistency
- Available battery, thermal, and SMART drive-health data

Use **Issues Only** to hide passing checks. Expand any card to see bounded
evidence; the dashboard counts the complete matching log set even when only a
sample is displayed. It does not contact an external service to test Internet
connectivity and does not scan previous boots.

Boot-journal and kernel-error cards with matching entries include **Copy** and
**Export**. Copy sends the card's readable bounded evidence to the X11
clipboard with `xclip`. Export saves the same content in the user's home
directory as a private timestamped file, such as
`boot2026-07-09-143000.txt` or `kernel-errors2026-07-09-143000.txt`. Existing
files are never overwritten.

Repair buttons always require confirmation. Each failed service row offers
Start, Stop, Restart, Disable, and Enable. User units are managed with
`systemctl --user`; system units request administrator authorization through
polkit. An action is accepted only while that exact service remains failed.
The dashboard can also restart known desktop/audio components, launch the
interactive dependency installer, restart NetworkManager or Bluetooth, and
repair the detected time-synchronization provider.

Installing the health helper in a root-owned system path remains recommended:

```bash
sudo make install-system
```

The managed copy under `~/.local/share/dwm-titus` is never elevated itself. If
the installed helper is unavailable, cached or `NOPASSWD` sudo can still run
the validated root-owned system commands. Polkit authorization requires the
root-owned installed helper.

### Quick Actions

| Action | Description |
|--------|-------------|
| Restart Picom | Kill and relaunch the compositor |
| Reload Wallpaper | Randomize from `~/Pictures/backgrounds/` |
| Toggle Compositor | Start or stop picom |
| Restart NetworkManager | `sudo systemctl restart NetworkManager` |
| Run Dependency Check | Opens `check-deps.sh` in a terminal |
| Install Missing Deps | Runs `install.sh` in a terminal |

### Appearance

| Action | Description |
|--------|-------------|
| Select Theme | Pick from all themes defined in `themes.toml` |
| Randomize Wallpaper | Random image from `~/Pictures/backgrounds/` |
| Open Wallpaper Folder | Open folder in file manager |
| GTK Theme Settings | Launch `nwg-look` for GTK theming |

### Power Settings

The Power Settings card retains the existing persisted screen-DPMS and
auto-lock controls. Each feature can be enabled or disabled and assigned a
5-minute, 10-minute, 15-minute, 30-minute, or 1-hour timeout.

### Keybind Viewer

Displays all bindings from `hotkeys.toml` in a searchable Quickshell list. Same
as pressing <kbd>Super</kbd> + <kbd>/</kbd>.

---

## Running from Terminal

```bash
dwm-controlcenter
```

The script is a compatibility wrapper around the Quickshell IPC target:

```bash
quickshell ipc --path "${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus/config/quickshell/shell.qml" call controlcenter toggle
```

Open or refresh System Health directly through its IPC target:

```bash
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call systemhealth open
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call systemhealth refresh
```

The diagnostic helper can also produce its structured snapshot in a terminal:

```bash
dwm-system-health scan-user
```
