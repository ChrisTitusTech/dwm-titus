# Configuration

dwm-titus keeps user configuration under
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/`. Hotkeys and themes
**live-reload on save** — no recompile needed for most changes.

| File | Purpose |
|------|---------|
| `config/hotkeys.toml` | All keybindings |
| `config/themes.toml` | Colors, themes, border size |
| `power.conf` | Control Center screen DPMS and auto-lock choices |

For deeper changes (window rules, fonts, refresh rate), edit `config.h` and run `make && sudo make install`.

---

## config.h Essentials

`config.h` is your personal copy of `config.def.h`. It is created automatically by `make` if it doesn't exist.

```bash
$EDITOR config.h
make && sudo make install
```

### Key Options

| Setting | Description |
|---------|-------------|
| `refresh_rate` | Match your monitor (default 60; set 120 for high-refresh) |
| `fonts[]` | Font family and size used in the bar |
| `colors[]` | Managed by `themes.toml` — rarely edit directly |
| `autostart[]` | Programs launched on dwm start |
| `rules[]` | Per-app window rules (floating, tag assignment, terminal flag) |
| `keys[]` | Fallback static keybinds (prefer `hotkeys.toml`) |
| `MODKEY` | `Mod4Mask` = Super, `Mod1Mask` = Alt |

### Window Rules

Rules in `config.h` let you assign windows to specific tags or force float:

```c
/* class      instance  title   tags mask  isfloating  isterminal  noswallow  monitor */
{ "Gimp",     NULL,     NULL,   0,         1,          0,           0,        -1 },
{ "Firefox",  NULL,     NULL,   1 << 1,    0,          0,          -1,        -1 },
```

---

## hotkeys.toml — Live Keybinds

Add or change bindings without recompiling. Save the file and they apply instantly.

```toml
[vars]
terminal = "dwm-terminal"
webapp   = "webapp-launch"

keys = [
  { mod="SUPER",       key="x",  desc="Terminal",    func="spawn", exec=["$terminal"] },
  { mod="SUPER SHIFT", key="f",  desc="Firefox",     func="spawn", exec=["firefox"] },
]
```

`dwm-terminal` selects the first installed supported terminal at launch time.
Set `DWM_TERMINAL` or replace `terminal` with a specific command if you want a
fixed terminal.

Default applications use freedesktop settings. Run `dwm-default-apps browsers`
to list browser desktop files, `dwm-default-apps set-browser firefox.desktop`
to set the default browser, or `dwm-default-apps set-mime <mime> <desktop-id>`
for other file types.

Display profiles are optional files under
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/display-profiles`. Use
`dwm-display-profile template` to print the format, `dwm-display-profile list`
to show profiles, and `dwm-display-profile apply <name>` to run the profile
through `xrandr`.

Power settings are managed from Control Center -> Power. The generated
`power.conf` is authoritative once created and persists screen DPMS state,
display-off timing, and automatic idle and suspend locking. Startup reapplies
this file before background session services are launched. Manual locking
remains available when automatic locking is disabled. The screen locker runs
only while automatic locking is enabled or for the duration of an explicit
manual lock, so DPMS display-off events remain independent from locking.
External `loginctl lock-session` requests are forwarded to `dwm-lock` by an
event-driven session listener. Until `power.conf` exists, dwm-titus leaves any
user or distribution-managed locker untouched.

### Modifier Syntax

Use space-separated modifiers: `"SUPER"`, `"SUPER SHIFT"`, `"SUPER CTRL"`, `"SUPER CTRL SHIFT"`.

### Available Functions

| `func` | Parameters | Description |
|--------|-----------|-------------|
| `spawn` | `exec=[...]` or `cmd="..."` | Run a program |
| `killclient` | — | Close focused window |
| `zoom` | — | Promote/demote master |
| `focusstack` | `i=1` or `i=-1` | Focus next/prev window |
| `movestack` | `i=1` or `i=-1` | Reorder in stack |
| `incnmaster` | `i=1` or `i=-1` | Change master count |
| `setmfact` | `f=0.05` or `f=-0.05` | Resize master area |
| `setcfact` | `f=0.25` / `f=-0.25` / `f=0.00` | Resize window slot |
| `setlayout` | `layout_idx=0/1/2` | 0=tile, 1=float, 2=monocle |
| `togglefloating` | — | Float/tile window |
| `fullscreen` | — | True fullscreen |
| `togglefakefullscreen` | — | Fullscreen with bar |
| `togglebar` | — | Show/hide bar |
| `focusmon` | `i=1` or `i=-1` | Focus monitor |
| `tagmon` | `i=1` or `i=-1` | Send window to monitor |
| `view` | `ui=-1` = all tags | Switch tag |
| `quit` | — | Exit dwm |

### Tag Bindings

Tag bindings auto-generate all four variants (switch, toggle-view, move, toggle-tag):

```toml
tag_keys = [
  { key="1", tag=0 },
  { key="2", tag=1 },
]
```

---

## Notes on XDG Autostart

Recommend using Flatpak to install programs on startup:

```
flatpak install flathub io.github.flattool.Ignition
```

or you can create your own .desktop file in ~/.config/autostart/

`set-refresh.desktop` Example:

```
[Desktop Entry]
Type=Application
Exec=xrandr --output HDMI-0 --primary --mode 1920x1080 --pos 0x0 --rotate normal --rate 120 --output DP-0 --off --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Set Refresh
```
