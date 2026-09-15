---
title: Theming
description: Change dwm-titus colors, borders, wallpaper, fonts, text scale, cursor, icons, and application appearance.
navLabel: Theming
eyebrow: Personalization
---

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

---
## Fonts and Text Size

Open **Settings -> Appearance -> Font and text size** to choose one font and
text scale for the shell and desktop applications. Type an installed font family
or choose one of the suggestions. Available scales are 75,
87.5, 100, 112.5, 125, 150, 175, and 200 percent. Use **Apply font** or
**Apply text size**, or return to **Follow system font/scale**. Applications
that cache toolkit settings may need reopening.

The shell observes desktop font and scale changes even while Settings is
closed. Qt's native DPI scale is counted once, so 200 percent does not become
400 percent in the shell. **Follow system scale** preserves the native display
DPI instead of forcing a 100 percent display. The icon font remains the shipped Meslo Nerd Font,
so changing the text family cannot remove panel or menu glyphs.

The same shared settings are available from a terminal:

```bash
dwm-settings-personalization apply font "Noto Sans"
dwm-settings-personalization apply text-size 1.25
dwm-settings-personalization reset font
dwm-settings-personalization reset text-size
```

Existing `font.conf` files are preserved as a startup fallback when desktop
typography cannot be read. A later read failure keeps the last valid choice. The legacy shell-only helper remains available for recovery
and compatibility; its settings no longer take precedence over readable
desktop typography:

```bash
token="font-$$"
dwm-settings-font preview "$token" 30 "Noto Sans" 1.25
dwm-settings-font keep "$token"

dwm-settings-font apply "Noto Sans" 1.10
dwm-settings-font reset
```

The setting owns only `font.conf` under the dwm-titus XDG configuration
directory. A malformed file falls back to the existing Meslo family at 100
percent without preventing shell startup.

### Desktop Application Appearance

The **Desktop applications** area provides cursor and icon choices. Font and
text size live in the single section above. GTK and Qt styling is normally
set by the selected theme, so their separate selectors are hidden. Existing
saved toolkit overrides remain preserved and can still be reset from a
terminal. Application status cards and the keyboard/pointer access summary
are hidden; actionable errors and recovery controls remain visible.

Use **Follow system icons** or **Follow DWM theme** for the cursor to remove a
saved override. Asset discovery runs only while Appearance is open.

The same fixed actions are available from a terminal:

```bash
dwm-settings-personalization apply cursor Adwaita
dwm-settings-personalization apply gtk Adwaita-dark
dwm-settings-personalization apply qt gtk3
dwm-settings-personalization reset cursor
dwm-settings-personalization reset gtk
dwm-settings-personalization reset qt
dwm-settings-personalization status
```

If `status` reports that the project-owned personalization state is malformed,
Settings exposes **Repair personalization state**. The equivalent
`dwm-settings-personalization repair` command resets only the persisted
overrides to follow-source preferences; it does not silently rewrite current
desktop settings. Apply or reset the desired choices afterward.
Files carrying a reserved newer personalization protocol are left untouched;
use a compatible newer dwm-titus version rather than repairing them.

The apply and reset paths share the theme transaction and integration locks.
If rollback cannot safely restore a changed output, recovery data remains under
the dwm-titus appearance state directory for the existing theme recovery flow.
