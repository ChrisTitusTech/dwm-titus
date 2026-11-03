# dwm-titus runtime configuration

Facts below were read from dwm-titus `dwm.c`, `tomlparser.c`, and the shipped
`config/*.toml`. When an installed system disagrees, trust its source copy in
`~/.local/share/dwm-titus/` (or the user's checkout) over this file.

## Files and load order

- User files: `${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/hotkeys.toml`,
  `themes.toml`, `window-rules.toml`.
- Defaults: `${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus/config/`. A default is
  used only when the user file does not exist.
- A user file that parses to zero entries (empty, comments only, unreadable)
  triggers a critical `dwm: bad config` notification and loads nothing from
  that file. Do not leave an empty user file in place.
- Saving any of the three files (close-write or rename into the directory)
  reloads all three, re-grabs keys, and runs
  `~/.local/share/dwm-titus/scripts/theme-apply.sh`. `kill -USR1 "$(pidof dwm)"`
  forces the same reload.
- dwm logs to stderr, which LightDM sends to `~/.xsession-errors`:
  `dwm: loaded N keybinds from hotkeys config`, `... button bindings ...`,
  `dwm: loaded theme from config`, `dwm: loaded N window rules from config`,
  plus `dwm: unknown keysym '...'` and `dwm: unknown func '...'`.

## Parser limits

The parser is a small line parser, not full TOML:

- Arrays of inline tables: `name = [` on one line, one `{ k=v, ... }` per
  line, `]` alone on its line. `[[name]]` tables also work.
- Values: `"string"`, `[ "string", ... ]`, or numbers. Use `1`/`0`, not
  `true`/`false`, inside inline tables.
- Unknown keys are accepted and ignored with no warning. Check field names
  against the lists below.
- At most 512 key/value pairs per file, counting every field inside every
  inline table (the shipped `hotkeys.toml` already uses about 296), 511-char
  strings, 32 array items, and 64 window rules. Extra entries are dropped
  silently, so large additions can make the last bindings vanish.

## hotkeys.toml

- `[vars]`: `name = "value"`; `$name` expands inside `exec` items and `cmd`.
  Unknown `$X` is left as is: `cmd` hands it to `/bin/sh`, but `exec` passes
  it literally.
- `keys = [ { mod="SUPER SHIFT", key="Return", func="spawn", exec=["..."] } ]`.
  `key` is an X keysym name. `desc` is for the cheatsheet only.
- New bindings must go inside the `keys = [ ... ]` array. The commented
  "CUSTOM SHORTCUTS" examples after `tag_keys` in the shipped file sit
  outside the array and do nothing if uncommented there.
- Modifiers (space-separated): `SUPER` and `MODKEY` both mean the compile-time
  `MODKEY` from `config.h` (Super by default, but a user may have changed it),
  `SHIFT`, `CTRL`, `ALT`, `Mod2Mask`..`Mod5Mask`, `""` for none. Unknown
  tokens are ignored silently.
- `func` values and arguments:
  - `spawn`: `exec=["argv", ...]` (preferred) or `cmd="shell string"`
  - `focusstack`, `movestack`, `incnmaster`, `focusmon`, `tagmon`:
    `i=1` or `i=-1`; `moveorplace` and `sigstatusbar` take an integer `i`
    (the shipped mouse binding uses `moveorplace` with `i=2`)
  - `setmfact`, `setcfact`: `f=0.05` (`setcfact` `f=0.00` resets)
  - `view`, `toggleview`, `tag`, `toggletag`: `ui=` tag bitmask (`-1` = all)
  - `setlayout`: `layout_idx` 0 tile, 1 floating, 2 monocle
  - no argument: `killclient`, `quit` (ends the session), `zoom`,
    `togglebar`, `togglefloating`, `fullscreen`, `togglefakefullscreen`,
    `resizemouse`
- `tag_keys = [ { key="1", tag=0 } ]`: `tag` is 0-based. Each entry creates
  four MODKEY bindings: view, +Ctrl toggleview, +Shift tag, +Ctrl+Shift
  toggletag.
- `buttons = [ { click="ClkClientWin", mod="SUPER", button=1, func="..." } ]`.
  Click targets: `ClkTagBar`, `ClkLtSymbol`, `ClkStatusText`, `ClkWinTitle`,
  `ClkClientWin`, `ClkRootWin`.
- Before adding a binding, check its `mod` + `key` against every `keys` entry
  and against the four bindings each `tag_keys` entry generates (MODKEY,
  +Ctrl, +Shift, +Ctrl+Shift with that key; MODKEY is whatever `config.h`
  sets). dwm runs every matching binding, so a duplicate fires both actions.
  Check that the keysym exists (`xmodmap -pke` or the dwm log after saving).

## window-rules.toml

- `rules = [ { class="...", isfloating=1 } ]`.
- Fields read: `class`, `instance`, `title` (substring matches), `tags`
  (1-9, 1-based; anything else means the current tag), `monitor` (index,
  default -1), `isfloating`, `alwaysontop`, `isterminal`, `noswallow`, `fullscreen`, `fakefullscreen`, `ignoresizehints`.
  Fullscreen rules apply on management or a late title match; fakefullscreen
  takes precedence without advertising EWMH fullscreen. `ignoresizehints=1`
  bypasses client size hints. Check the installed source for version support.
- `float` is not a field; it is ignored silently. Use `isfloating=1`.
- Every matching rule applies in order and assigns `isfloating`,
  `isterminal`, `noswallow`, and `alwaysontop`; a later match resets them.
  Append a specific rule after the general rules it overrides (for example
  after `{ class="Alacritty", isterminal=1 }`), and repeat fields such as
  `isterminal=1` that the general rule set. `alwaysontop=1` implies floating.
- Get the class and title of a window from the live session:
  `xprop WM_CLASS WM_NAME` (click the window), or
  `xprop -id "$(xdotool getactivewindow)" WM_CLASS WM_NAME`.
  `WM_CLASS` prints instance first, then class.

## themes.toml

- `[active] theme = "<name>"` selects `[theme.<name>]`. An unknown name falls
  back to Nord colors without a warning.
- dwm reads `normfgcolor normbgcolor normbordercolor selfgcolor selbgcolor
  selbordercolor` (`#RRGGBB`) and `[appearance] borderpx`.
- `theme-apply.sh` reads `term_bg term_fg term_cursor term_color0`..`15`,
  `dark_mode`, and `gtk_theme`, then updates Alacritty, kitty, GTK, Qt,
  xsettingsd, and cursors.
- Switch themes with `dwm-settings-theme apply <name>` or the Control Center
  rather than by editing `[active]`. List the theme names with
  `grep '^\[theme\.' ~/.config/dwm-titus/themes.toml`.
- For a custom theme, copy an existing `[theme.<name>]` block under a new name
  and keep every key.

## config.h (build time)

- Holds `MODKEY`, `fonts[]`, `tags[]`, `layouts[]`, `mfact`, `nmaster`,
  `showbar`, `topbar`, `snap`, `cursorwarp`, `swallowfloating`, and similar.
  Keys, rules, and colors are not in `config.h`, even where older docs say so.
- `config.h` is created from `config.def.h` only when it is missing. It is the
  user's file and is never overwritten by updates.
- Rebuild from the checkout with `./scripts/dev-sync-install.sh`
  (`--check` verifies without changes). It runs `sudo make install`, then
  a new dwm session is required.

## Generated files: do not hand-edit

`~/.config/dwm-titus/` also holds files written by helpers:

- `theme-env.sh`, `xsettingsd.conf`, `cursor.Xresources`: `theme-apply.sh`
- `personalization.conf`: `dwm-settings-theme personalize`
- `font.conf`: `dwm-settings-font`
- `wallpaper.conf`: `dwm-settings-wallpaper`
- `input-settings.conf`: `dwm-settings-input`
- `display-profiles/`: `dwm-settings-display`
- `power.conf`: `dwm-quickshell-controlcenter power-*`
- `panel-widgets.conf`: `dwm-panel-settings`
- `accessibility.conf`: `dwm-accessibility-settings`
- `notification-settings.json`: the panel
