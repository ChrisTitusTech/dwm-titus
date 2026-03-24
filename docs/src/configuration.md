# Configuration

dwm-titus uses two TOML config files that **live-reload on save** — no recompile needed for most changes.

| File | Purpose |
|------|---------|
| `config/hotkeys.toml` | All keybindings |
| `config/themes.toml` | Colors, themes, border size |

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
terminal = "ghostty"
webapp   = "webapp-launch"

keys = [
  { mod="SUPER",       key="x",  desc="Terminal",    func="spawn", exec=["$terminal"] },
  { mod="SUPER SHIFT", key="f",  desc="Firefox",     func="spawn", exec=["firefox"] },
]
```

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

## Autostart

Programs launched at startup are configured in `config.h` under `autostart[]`:

```c
static const char *const autostart[] = {
    "picom", NULL,
    "dunst", NULL,
    NULL /* terminate */
};
```

Alternatively, place `.desktop` files in `~/.config/autostart/` — dwm-titus uses `dex` to process them.
