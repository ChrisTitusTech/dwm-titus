---
title: Keybindings
description: A complete reference for dwm-titus launchers, windows, workspaces, media controls, screenshots, and system actions.
navLabel: Keybindings
eyebrow: Reference
---

# Keybindings

> Press <kbd>Super</kbd> + <kbd>/</kbd> inside dwm to open a live, searchable
> Quickshell keybind viewer.

**MODKEY** = <kbd>Super</kbd> (Windows key) in the shipped `config.h`.

Bindings are defined in `config/hotkeys.toml` and reload instantly on save — no recompile needed.

---

## Launchers

| Keys | Action |
|------|--------|
| `Super` + `R` | App launcher (Quickshell) |
| `Super` + `X` | Alacritty terminal |
| `Super` + `E` | File manager |
| `Super` + `V` | Clipboard history (capture and disk persistence are separate opt-ins) |
| `Super` + `B` | Browser |
| `Super` + `W` | Looking Glass VM client (when installed) |
| `Super` + `Shift` + `W` | Randomize wallpaper |
| `Super` + `/` | Keybind viewer |
| `Super` + `F1` | Control Center |
| `Super` + `Alt` + `F1` | Control Center (alternate) |
| `Super` + `Shift` + `R` | Restart Quickshell |
| `Super` + `Ctrl` + `R` | Force-stop Steam, Wine/Proton, and Windows applications |

`Super` + `Ctrl` + `R` force-kills matching processes without relaunching them.
Unsaved application or game progress can be lost.

## Screenshots

| Keys | Action |
|------|--------|
| `Super` + `P` | Screenshot active monitor (cursor omitted) |
| `Super` + `Shift` + `P` | Screenshot selection → file |
| `Super` + `Ctrl` + `P` | Screenshot selection → clipboard |

All `dwm-screenshot` capture modes omit the mouse cursor.
`maim` region captures start selection immediately without a monitor chooser.
The active-monitor shortcut uses the monitor under the pointer. Clipboard
captures are PNG selections owned by `xclip`, while captures saved to disk use
JPEG. The lightweight capture flow intentionally has no annotation toolbar.

## Applications and Web Apps

| Keys | Action |
|------|--------|
| `Super` + `A` | ChatGPT |
| `Super` + `Shift` + `A` | Gemini |
| `Super` + `Shift` + `X` | X/Twitter — new post |

`Super` + `A` opens an installed ChatGPT desktop application when one is
available and falls back to the ChatGPT web app otherwise. The application
launcher hides the ChatGPT web entry while a native desktop entry is installed.
Existing systems with the former stock web-app binding receive the same
native-first behavior through the updated `webapp-launch` helper. Upgrades do
not edit customized hotkey files.

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
| `Super` + `F` | Floating layout |
| `Super` + `M` | Toggle monocle focus mode and bar |
| `Super` + `Space` | Toggle floating for window |
| `Super` + `Shift` + `M` | Toggle floating for window |
| `Super` + `Shift` + `Y` | Fake fullscreen (bar stays) |
| `Super` + `Shift` + `B` | Toggle bar visibility |

`Super` + `M` switches to the monocle layout and toggles the bar. It does not
request per-window fullscreen; applications or window rules do that when
needed. The saved pre-focus layout is shared across tags and monitors, so
switching tags before pressing the binding again may restore a different
layout. The monocle layout has no separate direct layout binding. To select it
directly, add a `setlayout` record with `layout_idx=2` to `hotkeys.toml`.

Entering floating mode with a toggle shrinks a tiled window by 15% around its
current center, subject to the application's minimum size and resize increments.
Toggle again to return it to the tiling layout. `Super` + `F` applies the same
shrink to each visible tiled window when entering floating layout; `Super` + `T`
retiles them. Pressing `Super` + `F` again leaves their sizes unchanged. Windows
already floated individually keep their size and position. Mouse dragging and resizing keep
their existing behavior. Existing hotkey configuration needs no changes; restart
the dwm session after updating to activate this behavior.

## Tags (Workspaces)

| Keys | Action |
|------|--------|
| `Super` + `1`–`9` | Switch to tag |
| `Super` + `Ctrl` + `1`–`9` | Also show tag alongside current |
| `Super` + `Shift` + `1`–`9` | Move window to tag |
| `Super` + `Ctrl` + `Shift` + `1`–`9` | Also show window on that tag |
| `Super` + `0` | Show windows from all nine tags; `0` is not a tag |
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
| `Super` + `Shift` + `Q` | Quit dwm and cleanly end the graphical session |
| `Super` + `Ctrl` + `Shift` + `R` | Reboot |
| `Super` + `Ctrl` + `Shift` + `S` | Suspend |

## Mouse

| Action | Function |
|--------|----------|
| `Super` + Left drag | Move window |
| `Super` + Right drag | Resize window |

Middle click is unbound by default. To use it, add a `button=2` record to the
`buttons` array in `hotkeys.toml`.

---

## Customizing Keybinds

Edit `config/hotkeys.toml` — changes take effect on save, no recompile required.

```toml
[vars]
terminal = "alacritty"

keys = [
  { mod="SUPER SHIFT", key="f", desc="Firefox", func="spawn", exec=["firefox"] },
]
```

See the comments in `hotkeys.toml` for a full list of `func` values and modifier syntax.

### Keyboard layouts

Set two or more layouts in Settings -> Input -> Keyboard layout (for example
`us,gr`). Keep a Latin layout first: dwm matches hotkeys against the first
layout's keys. To switch with a key, pick one under Settings -> Input ->
Switch layout with (Alt+Shift, Caps Lock, ...), or type any `grp:` option into
Modifier options. Avoid the Space chords such as `grp:win_space_toggle`: XKB
switches the layout and dwm still runs Super+Space (toggle floating). To switch with a
dwm hotkey instead, bind the `cyclelayout` func; there is no default binding:

```toml
{ mod="SUPER ALT", key="k", desc="Next keyboard layout", func="cyclelayout", i=1 },
```

Settings sets the layout on that keyboard only. X copies it to the shared
keyboard state, which dwm and the panel read, right away if that keyboard was
the last one used, otherwise on its next key press. Until then the panel can
show the old layout; switching works normally after that.

dwm publishes the active layout on the root window, so
`xprop -root _DWM_KEYBOARD_GROUP` shows the current group and the group count,
and `dwm-quickshell-state keyboard-group next` switches from a script.

The browser binding uses `dwm-default-apps open`. Configure it with
Settings -> Defaults or with `dwm-default-apps browsers` and
`dwm-default-apps set-browser <desktop-id>`.

The terminal variable defaults to Alacritty. Settings -> Defaults can select a
validated installed terminal without changing the `Super`+`X` key record. To
use the optional Herdr workspace, install it explicitly, change the binding to
`dwm-terminal`, and set `DWM_HERDR=1` in the session environment.

Clipboard capture is off by default. Open Super+V and choose **Enable; discard
older history** to start capturing new copies through the sensitivity backend.
This deletes older clipboard history without importing it. **Persist** is a
separate opt-in; disabling capture clears both memory and stored history.
**Clear all** also discards older history and restarts observation without
importing the current clipboard.

Browser and terminal copies remain available. Recognized password-manager sources
and sensitivity-marked copies are excluded on a best-effort basis. An unmarked
copy made by a browser extension cannot reliably be distinguished from ordinary
browser text, so it may enter history. Do not enable capture when that limitation
is unacceptable. Backend failure stops capture until an explicit retry.

On upgrade, migration preserves any existing `v` binding regardless of its
modifier. `SUPER` follows the locally compiled `MODKEY`, which may differ from
the stock Super key. If migration reports a V conflict, keep the existing action
or add the Clipboard history command manually with a free modifier combination.
