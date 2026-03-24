# Patches & Features

dwm-titus is a heavily patched build. Below is every addition on top of stock dwm.

---

## Window Management Patches

### Pertag
Each tag independently remembers its layout, master count, and master/stack sizing. Switching tags restores the previous layout for that tag.

### Cfact
Assign per-window size weights within the stack area. Windows are no longer forced to equal height.

| Keys | Action |
|------|--------|
| `Super` + `Shift` + `H` | Grow this window's slot |
| `Super` + `Shift` + `L` | Shrink this window's slot |
| `Super` + `Shift` + `O` | Reset to equal sizing |

### Movestack
Reorder windows within the stack without using the mouse.

| Keys | Action |
|------|--------|
| `Super` + `Shift` + `J` | Move window down |
| `Super` + `Shift` + `K` | Move window up |

### Window Swallowing
When a GUI application is launched from a terminal, it replaces the terminal in the layout. Closing the app brings the terminal back.

Controlled via window rules in `config.h`:
```c
{ "ghostty", NULL, NULL, 0, 0, 1, 0, -1 },  /* isterminal = 1 */
```

### Fullscreen (3-State)
Three fullscreen modes available:

| Mode | Keys | Description |
|------|------|-------------|
| True fullscreen | `Super` + `M` | Hides bar, takes full screen |
| Fake fullscreen | `Super` + `Shift` + `Y` | Looks fullscreen, bar still usable |
| Monocle layout | — | Single window view, bar visible |

---

## Bar & EWMH

### Polybar Integration
The built-in dwm bar is replaced by Polybar. dwm-titus feeds tag and window data to Polybar via EWMH atoms, keeping it fully informed.

Multi-monitor support: each monitor gets its own Polybar instance. The primary monitor hosts the system tray and EWMH tag reporting.

### EWMH Compliance
Implements `_NET_WM_STATE`, `_NET_CURRENT_DESKTOP`, `_NET_NUMBER_OF_DESKTOPS`, and related atoms so external tools and taskbars work correctly.

### Window Icons
Title bar icons via `_NET_WM_ICON`. Applications that set this atom display their icon in the bar.

### Systray
A built-in system tray is compiled in. It is disabled by default when Polybar is running (to avoid duplication), but can be re-enabled in `config.h`.

---

## Visual

### Noborder
When only one window is visible on a tag, its border is automatically removed for a cleaner look. Borders return when a second window appears.

### Cursor Warp
When focus moves to a different window or monitor (via keyboard), the mouse cursor warps to the center of the newly focused window.

---

## Live Configuration

### TOML Hotkeys (`hotkeys.toml`)
Keybindings are parsed from `config/hotkeys.toml` at runtime. Edit and save — bindings update without recompiling or restarting dwm.

### TOML Themes (`themes.toml`)
Colors for dwm, terminal, rofi, and polybar are all sourced from `config/themes.toml`. Save the file to apply a new theme instantly across all apps.

---

## Scripts & Utilities

| Script | Description |
|--------|-------------|
| `dwm-controlcenter` | Rofi-based control center (`Super`+`F1`) |
| `dwm-keybinds` | Searchable keybind viewer (`Super`+`/`) |
| `dwm-screenshot` | Wrapper for flameshot (full, gui, clip modes) |
| `theme-apply.sh` | Applies active theme from `themes.toml` to all apps |
| `webapp-create` | Creates a web app shortcut |
| `webapp-launch` | Launches a URL as a standalone web app window |
| `autostart.sh` | Runs programs on dwm start |
| `check-deps.sh` | Checks all required dependencies |
| `active-audio` | Displays active audio device in Polybar |
| `disable-powersaving` | Disables DPMS and screen blanking |

---

## Multi-Monitor

Xinerama support with per-monitor Polybar bars. Tags are independent per monitor. Windows can be moved between monitors with `Super` + `Shift` + `,`/`.`.
