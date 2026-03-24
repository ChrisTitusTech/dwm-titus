# Control Center

The Control Center is a rofi-based menu providing system health, quick actions, appearance settings, and more.

**Open:** <kbd>Super</kbd> + <kbd>F1</kbd> — or run `dwm-controlcenter` from a terminal.

Navigate with arrow keys or type to filter. Press <kbd>Esc</kbd> or <kbd>←</kbd> to go back.

---

## Modules

### System Health

Runs a full dependency check and reports:

- Build tools (`cc`, `make`) and required libraries
- Xorg / Xlibre installation
- Runtime programs: rofi, picom, dunst, feh, flameshot, polybar
- Terminal emulators (ghostty, alacritty, kitty, st)
- Fonts: MesloLGS Nerd, Noto Color Emoji
- Running services: picom, dunst, polybar, dbus, NetworkManager
- Config paths: `.xinitrc`, polybar dir, rofi dir, wallpaper folder

Selecting a failed item offers to run `install.sh` (auto-fix) or `check-deps.sh` (details).

### Quick Actions

| Action | Description |
|--------|-------------|
| Restart Picom | Kill and relaunch the compositor |
| Restart Dunst | Kill and relaunch the notification daemon |
| Restart Polybar | Relaunch using `~/.config/polybar/launch.sh` |
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
| Edit Polybar Config | Open polybar config in `$EDITOR` |
| GTK Theme Settings | Launch `nwg-look` for GTK theming |

### Keybind Viewer

Displays all bindings from `hotkeys.toml` in a searchable rofi list. Same as pressing <kbd>Super</kbd> + <kbd>/</kbd>.

---

## Running from Terminal

```bash
dwm-controlcenter
```

The script auto-detects your terminal emulator (ghostty → alacritty → kitty → st → xterm) and uses the active rofi theme from `~/.config/rofi/themes/controlcenter.rasi`.
