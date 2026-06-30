# Control Center

The Control Center is a Quickshell utility window for system health, quick
actions, appearance settings, and keybind discovery.

**Open:** <kbd>Super</kbd> + <kbd>F1</kbd>, or run `dwm-controlcenter` from a
terminal.

The window floats above normal clients like the launcher, network popover, and
power menu. Press <kbd>Esc</kbd> to close it.

---

## Network Popover

The panel network indicator opens a Quickshell network popover. It shows active
NetworkManager connections, scans visible Wi-Fi networks, and connects to open
or WPA personal networks directly. Successful Wi-Fi connections are saved as
NetworkManager profiles, so they reconnect normally in later sessions.

Hidden SSIDs and enterprise Wi-Fi are handled through the optional
`nm-connection-editor` fallback when it is installed.

---

## Modules

### System Health

Runs a full dependency check and reports:

- Build tools (`cc`, `make`) and required libraries
- Xorg / Xlibre installation
- Runtime programs: quickshell, picom, feh, flameshot, bluetoothctl, blueman-applet
- Terminal emulators (alacritty, kitty, st)
- Fonts: MesloLGS Nerd, Noto Color Emoji
- Running services: picom, NetworkManager
- Config paths: `.xinitrc`, Quickshell config, wallpaper folder

Selecting a failed item offers to run `install.sh` (auto-fix) or `check-deps.sh` (details).

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
