# Keybindings Reference

> **Tip:** Press <kbd>SUPER</kbd> + <kbd>/</kbd> inside dwm to launch an interactive keybind viewer (rofi).

These are the **default keybindings** from `config.def.h`. If you've customized `config.h`, your bindings may differ.

## Modifier Key

The default modifier key (`MODKEY`) is <kbd>Alt</kbd> in `config.def.h`.
The customized `config.h` uses <kbd>Super</kbd> (Windows key) instead.

---

## Window Management

| Keybind | Action |
|---------|--------|
| `MODKEY` + `J` | Focus next window in stack |
| `MODKEY` + `K` | Focus previous window in stack |
| `MODKEY` + `Shift` + `J` | Move window down in stack |
| `MODKEY` + `Shift` + `K` | Move window up in stack |
| `MODKEY` + `Return` | Swap focused window with master |
| `MODKEY` + `Shift` + `C` | Close focused window |
| `MODKEY` + `I` | Increase number of master windows |
| `MODKEY` + `D` | Decrease number of master windows |
| `MODKEY` + `H` | Shrink master area |
| `MODKEY` + `L` | Expand master area |
| `MODKEY` + `Shift` + `H` | Increase client size factor (cfact) |
| `MODKEY` + `Shift` + `L` | Decrease client size factor (cfact) |
| `MODKEY` + `Shift` + `O` | Reset client size factor |

## Layouts

| Keybind | Action |
|---------|--------|
| `MODKEY` + `T` | Tile layout (master + stack) |
| `MODKEY` + `F` | Floating layout |
| `MODKEY` + `M` | Monocle layout (single fullscreen) |
| `MODKEY` + `Shift` + `F` | Toggle actual fullscreen |
| `MODKEY` + `Space` | Toggle last layout |
| `MODKEY` + `Shift` + `Space` | Toggle floating for focused window |
| `MODKEY` + `Shift` + `Y` | Toggle fake fullscreen |

## Tags (Workspaces)

| Keybind | Action |
|---------|--------|
| `MODKEY` + `1-9` | Switch to tag 1-9 |
| `MODKEY` + `Ctrl` + `1-9` | Toggle tag view (show multiple tags) |
| `MODKEY` + `Shift` + `1-9` | Move focused window to tag 1-9 |
| `MODKEY` + `Ctrl` + `Shift` + `1-9` | Toggle tag on focused window |
| `MODKEY` + `0` | View all tags |
| `MODKEY` + `Shift` + `0` | Apply focused window to all tags |
| `MODKEY` + `Tab` | Switch to previously viewed tag |

## Multi-Monitor

| Keybind | Action |
|---------|--------|
| `MODKEY` + `,` | Focus previous monitor |
| `MODKEY` + `.` | Focus next monitor |
| `MODKEY` + `Shift` + `,` | Move window to previous monitor |
| `MODKEY` + `Shift` + `.` | Move window to next monitor |

## Launching

| Keybind | Action |
|---------|--------|
| `MODKEY` + `R` | Open dmenu (application launcher) |
| `MODKEY` + `X` | Open terminal |

## Session

| Keybind | Action |
|---------|--------|
| `MODKEY` + `Shift` + `Q` | Quit dwm |

## Mouse Bindings

| Action | Function |
|--------|----------|
| `MODKEY` + Left Click on window | Move window |
| `MODKEY` + Middle Click on window | Toggle floating |
| `MODKEY` + Right Click on window | Resize window |

---

## Customized Bindings (config.h)

The shipped `config.h` remaps several keys from the defaults above. Notable changes:

| Keybind | Action |
|---------|--------|
| `SUPER` + `R` | Launch rofi (replaces dmenu) |
| `SUPER` + `X` | Open ghostty terminal |
| `SUPER` + `Q` | Close window (replaces `Shift`+`C`) |
| `SUPER` + `/` | Show interactive keybind viewer |
| `SUPER` + `F1` | Open Control Center (health, actions, appearance) |
| `SUPER` + `E` | Open file manager |
| `SUPER` + `P` | Full screenshot (flameshot) |
| `SUPER` + `Shift` + `P` | Screenshot selection |
| `SUPER` + `Ctrl` + `P` | Screenshot to clipboard |
| `SUPER` + `W` | Launch Looking Glass |
| `SUPER` + `Shift` + `W` | Randomize wallpaper |
| `SUPER` + `Shift` + `B` | Toggle bar |
| `SUPER` + `M` | Fullscreen |
| `SUPER` + `Ctrl` + `Q` | Power menu (rofi) |
| `SUPER` + `Ctrl` + `Shift` + `R` | Reboot |
| `SUPER` + `Ctrl` + `Shift` + `S` | Suspend |
| `SUPER` + `A` | Open ChatGPT |
| `SUPER` + `Shift` + `A` | Open Gemini |
| `XF86 BrightnessUp/Down` | Adjust screen brightness |
| `XF86 AudioRaise/Lower/Mute` | Volume control |
