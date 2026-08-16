# Configuration

dwm-titus keeps user configuration under
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/`. Hotkeys and themes
**live-reload on save** — no recompile needed for most changes.

| File | Purpose |
|------|---------|
| `config/hotkeys.toml` | All keybindings |
| `config/themes.toml` | Colors, themes, border size |
| `power.conf` | Control Center screen DPMS and auto-lock choices |

For deeper changes (window rules, fonts, refresh rate), edit `config.h` and
run the complete developer synchronization command:

```bash
./scripts/dev-sync-install.sh
```

It rebuilds dwm, updates all installed commands and managed Quickshell/data
files when needed, verifies parity, and reports whether the dwm session must be
restarted. When a session restart is already required, it activates Quickshell
there so the tray host starts before tray clients. Use
`./scripts/dev-sync-install.sh --check` for a non-mutating audit.

---

## config.h Essentials

`config.h` is your personal copy of `config.def.h`. It is created automatically by `make` if it doesn't exist.

```bash
$EDITOR config.h
./scripts/dev-sync-install.sh
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

`dwm-terminal` prefers Alacritty and opens Herdr inside it for a plain
interactive launch. If Herdr is unavailable, it opens the selected emulator
directly. Explicit arguments such as `dwm-terminal -e command` always bypass
Herdr so application launchers and maintenance actions keep working.

Thunar's seeded **Open Terminal Here** action launches Alacritty directly in
the selected directory. It intentionally bypasses Herdr while leaving the
normal `Super` + `X` terminal workspace unchanged. Existing Thunar custom
actions are preserved during installation and upgrades.

Set `DWM_TERMINAL` to choose another outer emulator, set `DWM_HERDR=0` to
disable the Herdr layer, or set `DWM_HERDR_COMMAND` to another Herdr binary
path.

Default applications use freedesktop settings. Run `dwm-default-apps browsers`
to list browser desktop files, `dwm-default-apps set-browser firefox.desktop`
to set the default browser, or `dwm-default-apps set-mime <mime> <desktop-id>`
for other file types.

Display profiles are optional files under
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/display-profiles`. Use
`dwm-display-profile template` to print the format, `dwm-display-profile list`
to show profiles, and `dwm-display-profile apply <name>` to run the profile
through `xrandr`.

For persistent Xorg configuration, run `dwm-display-setup`. The interactive
wizard detects connected outputs and their exact advertised timings, then asks
for resolution, refresh rate, rotation, absolute position, and the primary
display. It checks whether the active Xorg driver exposes compatible TearFree
support or the NVIDIA Full Composition Pipeline and enables only the compatible
default. The proposed layout is applied as a live preview and automatically
restored unless it is confirmed. Advanced calls may pass
`--force-full-composition-pipeline off` to disable the NVIDIA default; forcing
it on with an incompatible kernel or Xorg driver is rejected.

Accepted layouts are installed as the isolated managed fragment
`/etc/X11/xorg.conf.d/90-dwm-titus-display.conf`; existing Xorg files are not
replaced. Each change creates a versioned backup. Use
`dwm-display-setup rollback` to restore the newest backup, or
`dwm-display-setup status` to inspect the managed file and current layout.
Advanced users can pass an existing display-profile file to
`dwm-display-setup generate`, `preview`, or `install`.
For noninteractive session changes, `dwm-display-setup capture` prints the
current complete RandR profile, `dwm-display-setup validate <profile>` checks a
profile with `xrandr --dryrun`, and `dwm-display-setup apply <profile>` changes
the current X11 layout after validation.

The Settings Displays page uses the same profile grammar and validation through
`dwm-settings-display`. Named profiles remain user-owned under the XDG path.
Installing one persistently requires explicit confirmation and authorization;
only the root-owned helper under `${PREFIX}/libexec/dwm-titus/` may update the
managed Xorg fragment. Legacy profiles that omit complete position or rotation
state remain usable with `dwm-display-profile`, but Settings will not preview or
install them until they are resaved as a complete layout.

Per-device input values kept in Settings are stored in
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/input-settings.conf`. The
event-driven input provider uses a hardware serial or path when available,
re-resolves that identity before every change, and skips a disconnected device
rather than applying its settings to another XInput ID. Session startup runs
`dwm-settings-input apply-saved` and starts an event-driven, debounced hotplug
replay so returning devices regain saved values. Repeating the apply is safe.
The replay watcher is scoped to the owning dwm process and exits at logout,
including when dwm was launched through `startx`.

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

```sh
flatpak install flathub io.github.flattool.Ignition
```

or you can create your own .desktop file in ~/.config/autostart/

`set-refresh.desktop` Example:

```ini
[Desktop Entry]
Type=Application
Exec=xrandr --output HDMI-0 --primary --mode 1920x1080 --pos 0x0 --rotate normal --rate 120 --output DP-0 --off --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Set Refresh
```
