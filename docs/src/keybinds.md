# Keybindings

> Press <kbd>Super</kbd> + <kbd>/</kbd> inside dwm to open a live, searchable keybind viewer via rofi.

**MODKEY** = <kbd>Super</kbd> (Windows key) in the shipped `config.h`.

Bindings are defined in `config/hotkeys.toml` and reload instantly on save — no recompile needed.

---

## Launchers

| Keys | Action |
|------|--------|
| `Super` + `R` | App launcher (rofi) |
| `Super` + `X` | Terminal |
| `Super` + `E` | File manager |
| `Super` + `B` | Browser |
| `Super` + `/` | Keybind viewer |
| `Super` + `F1` | Control Center |

## Screenshots

| Keys | Action |
|------|--------|
| `Super` + `P` | Full screenshot |
| `Super` + `Shift` + `P` | Screenshot selection → file |
| `Super` + `Ctrl` + `P` | Screenshot selection → clipboard |

## Web Apps

| Keys | Action |
|------|--------|
| `Super` + `A` | ChatGPT |
| `Super` + `Shift` + `A` | Gemini |
| `Super` + `Shift` + `X` | X/Twitter — new post |

## Window Management

| Keys | Action |
|------|--------|
| `Super` + `J` | Focus next window |
| `Super` + `K` | Focus previous window |
| `Super` + `Shift` + `J` | Move window down in stack |
| `Super` + `Shift` + `K` | Move window up in stack |
| `Super` + `Return` | Promote window to master |
| `Super` + `Q` | Close window |
| `Super` + `I` | Add window to master area |
| `Super` + `D` | Remove window from master area |
| `Super` + `H` | Shrink master area |
| `Super` + `L` | Expand master area |
| `Super` + `Shift` + `H` | Increase window cfact size |
| `Super` + `Shift` + `L` | Decrease window cfact size |
| `Super` + `Shift` + `O` | Reset window cfact |

## Layouts

| Keys | Action |
|------|--------|
| `Super` + `T` | Tiling layout |
| `Super` + `M` | Fullscreen (monocle) |
| `Super` + `Space` | Toggle floating for window |
| `Super` + `Shift` + `M` | Toggle floating for window |
| `Super` + `Shift` + `Y` | Fake fullscreen (bar stays) |
| `Super` + `Shift` + `B` | Toggle bar visibility |

## Tags (Workspaces)

| Keys | Action |
|------|--------|
| `Super` + `1`–`9` | Switch to tag |
| `Super` + `Ctrl` + `1`–`9` | Also show tag alongside current |
| `Super` + `Shift` + `1`–`9` | Move window to tag |
| `Super` + `Ctrl` + `Shift` + `1`–`9` | Also show window on that tag |
| `Super` + `0` | Show all tags |
| `Super` + `Tab` | Previous tag |

## Multi-Monitor

| Keys | Action |
|------|--------|
| `Super` + `,` | Focus left monitor |
| `Super` + `.` | Focus right monitor |
| `Super` + `Shift` + `,` | Send window to left monitor |
| `Super` + `Shift` + `.` | Send window to right monitor |

## Media Keys

| Keys | Action |
|------|--------|
| `XF86AudioRaiseVolume` | Volume up |
| `XF86AudioLowerVolume` | Volume down |
| `XF86AudioMute` | Mute toggle |
| `XF86MonBrightnessUp` | Brightness up |
| `XF86MonBrightnessDown` | Brightness down |

## Session & Power

| Keys | Action |
|------|--------|
| `Super` + `Ctrl` + `Q` | Power menu |
| `Super` + `Shift` + `Q` | Quit dwm |
| `Super` + `Ctrl` + `Shift` + `R` | Reboot |
| `Super` + `Ctrl` + `Shift` + `S` | Suspend |

## Mouse

| Action | Function |
|--------|----------|
| `Super` + Left drag | Move window |
| `Super` + Middle click | Toggle floating |
| `Super` + Right drag | Resize window |

---

## Customizing Keybinds

Edit `config/hotkeys.toml` — changes take effect on save, no recompile required.

```toml
[vars]
terminal = "ghostty"

keys = [
  { mod="SUPER SHIFT", key="f", desc="Firefox", func="spawn", exec=["firefox"] },
]
```

See the comments in `hotkeys.toml` for a full list of `func` values and modifier syntax.
