# Theming

Themes are defined in `config/themes.toml`. Change the active theme and **save**
to update dwm, Quickshell, terminal, GTK, and Qt styling. No restart needed.

```toml
[active]
theme = "nord"   # ← change this line to switch themes
```

The managed transaction helper is the safe command-line interface for theme
changes:

```sh
dwm-settings-theme preview preview-1 15 dracula
dwm-settings-theme keep preview-1       # confirm before the timeout
dwm-settings-theme revert preview-1     # or restore immediately
dwm-settings-theme abandon preview-1    # accept a conflicting external edit
dwm-settings-theme apply gruvbox
dwm-settings-theme reset                # restore the managed default selection
```

An unconfirmed preview restores the exact previous `themes.toml` bytes and
mode automatically. Apply and reset preserve comments, custom theme sections,
and unrelated appearance settings. If an operation is interrupted after its
atomic write, inspect and restore it with:

```sh
dwm-settings-theme recovery-status
dwm-settings-theme recover
```

Recovery refuses to overwrite an externally changed theme file.

---

## Available Themes

### Dark

| Theme | Description |
|-------|-------------|
| `nord` | Arctic, cool blue palette (default) |
| `dracula` | Purple-tinted dark theme |
| `gruvbox` | Warm retro earth tones |
| `catppuccin` | Mocha variant — soft pastels |
| `tokyonight` | Deep blue-grey night theme |
| `onedark` | Atom One Dark inspired |
| `solarized` | Dark variant of Solarized |
| `rosepine` | Muted rose/pine tones |
| `everforest` | Muted green forest palette |
| `monochrome` | Black and white minimal |

### Light

| Theme | Description |
|-------|-------------|
| `catppuccin-latte` | Catppuccin light variant |
| `gruvbox-light` | Warm light tones |
| `solarized-light` | Classic Solarized light |
| `rosepine-dawn` | Rose Pine dawn variant |
| `tokyonight-day` | Tokyo Night day variant |

---

## Border Size

```toml
[appearance]
borderpx = 1   # 0 = no border, 1 = thin (default), 2-3 = thicker
```

---

## What Each Theme Controls

Each `[theme.name]` section sets colors for all components:

| Key | Applies To |
|-----|-----------|
| `normfgcolor` / `normbgcolor` / `normbordercolor` | Unfocused bar and windows |
| `selfgcolor` / `selbgcolor` / `selbordercolor` | Focused window and active tag |
| `term_bg` / `term_fg` / `term_cursor` | Terminal background, text, cursor |
| `term_color0`–`term_color15` | Full 16-color terminal palette |
| `dark_mode` | GTK dark preference and Capitaine cursor variant (`true` / `false`) |
| `gtk_theme` | Optional installed GTK theme name for GTK apps such as Thunar |

Quickshell derives its opaque surfaces, text, borders, accent, success,
warning, and danger colors from the active theme's existing dwm and terminal
color keys.

---

## Creating a Custom Theme

Add a new section to `themes.toml`:

```toml
[theme.mytheme]
normfgcolor     = "#cdd6f4"
normbgcolor     = "#1e1e2e"
normbordercolor = "#313244"
selfgcolor      = "#cdd6f4"
selbgcolor      = "#89b4fa"
selbordercolor  = "#89b4fa"

term_bg         = "#1e1e2e"
term_fg         = "#cdd6f4"
term_cursor     = "#f5e0dc"
# ... term_color0-15 ...
dark_mode       = true
gtk_theme       = "Nordic"
```

Then set `theme = "mytheme"` under `[active]` and save.

---

## Applying Themes via Control Center

Open the Control Center with <kbd>Super</kbd> + <kbd>F1</kbd>, navigate to **Appearance → Select Theme**, and pick from the list. The theme switches immediately.

---
## Wallpapers

Place images in `~/Pictures/backgrounds/`. Open **Settings → Appearance** to
select an image, choose its fit, preview it for 30 seconds, apply it, or reset
to the random session default. Use `Super` + `Shift` + `W` or
`dwm-settings-wallpaper randomize` for a one-off random wallpaper in the
current session, or persist a specific image and fit from a terminal:

```bash
dwm-settings-wallpaper apply "$HOME/Pictures/backgrounds/mywall.jpg" fill
```

Supported fit modes are `center`, `fill`, `max`, `scale`, and `tile`. Preview a
choice for 30 seconds before keeping it:

```bash
token="wallpaper-$$"
dwm-settings-wallpaper preview "$token" 30 \
  "$HOME/Pictures/backgrounds/mywall.jpg" max
dwm-settings-wallpaper keep "$token"
```

Use `dwm-settings-wallpaper reset` to return to the session's random-fill
default. If a saved image is removed, login remains usable and falls back to
that default until another image is selected or the setting is reset.
