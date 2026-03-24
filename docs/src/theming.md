# Theming

Themes are defined in `config/themes.toml`. Change the active theme and **save** — dwm, terminal, rofi, and polybar all update instantly. No restart needed.

```toml
[active]
theme = "nord"   # ← change this line to switch themes
```

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
| `ghostty_theme` | Ghostty built-in theme name |
| `rofi_theme` | Rofi `.rasi` theme (filename without extension) |
| `polybar_bg` / `polybar_fg` / `polybar_accent` / `polybar_urgent` | Polybar colors |
| `dark_mode` | GTK dark preference (`true` / `false`) |

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
# ... term_color0–15 ...

ghostty_theme   = "Catppuccin Mocha"
rofi_theme      = "sidetab-catppuccin"
polybar_bg      = "#1e1e2e"
polybar_fg      = "#cdd6f4"
polybar_bg_alt  = "#313244"
polybar_fg_alt  = "#a6adc8"
polybar_accent  = "#89b4fa"
polybar_urgent  = "#f38ba8"
dark_mode       = true
```

Then set `theme = "mytheme"` under `[active]` and save.

---

## Applying Themes via Control Center

Open the Control Center with <kbd>Super</kbd> + <kbd>F1</kbd>, navigate to **Appearance → Select Theme**, and pick from the list. The theme switches immediately.

---

## Rofi Themes

Rofi theme files live in `config/rofi/themes/`. The active theme's `rofi_theme` key selects which `.rasi` file is used.

Available rofi themes: `nord`, `onedark`, `catppuccin`, `dracula`, `gruvbox`, `everforest`, `monochrome`, `rosepine`, `solarized`, `tokyonight`.

## Wallpapers

Place images in `~/Pictures/backgrounds/`. Use `Super` + `Shift` + `W` to randomize, or set a specific one:

```bash
feh --bg-fill ~/Pictures/backgrounds/mywall.jpg
```
