# Omarchy UI Adaptation for X11

## Purpose

dwm-titus borrows the visual grammar of Omarchy's Quickshell menus without
adopting its Wayland or Hyprland runtime. The result must feel related while
remaining a Fedora X11 desktop whose window manager, providers, IPC, and
session policy continue to belong to dwm-titus.

This is a design influence, not a shell transplant. Omarchy is MIT licensed;
the implementation here uses independently written dwm-titus QML backed by the
existing theme palette and X11-safe shell architecture.

## Adaptation Boundary

The reusable concepts are:

- semantic surface, text, border, and interaction-state roles;
- a compact spacing scale and typographic hierarchy;
- consistent normal, hover, focus, selected, disabled, and danger states;
- bordered popup cards with restrained radii;
- shared controls that make menus look and behave consistently.

The following are intentionally not imported:

- `Quickshell.Wayland`, `Quickshell.Hyprland`, or `WlrLayershell` APIs;
- `hyprctl`, `uwsm-app`, `wl-copy`, `wl-paste`, or other Wayland helpers;
- compositor-owned workspaces, monitor state, keybindings, or window policy;
- Omarchy service providers, command backends, or plugin lifecycle;
- a second shell process or parallel panel implementation.

## Token Contract

`config/quickshell/core/Theme.qml` remains the single theme adapter. Its base
colors still hot-reload from `themes.toml`; semantic roles derive from those
colors so existing themes need no migration.

| Role | dwm-titus source |
| --- | --- |
| Popup and menu surfaces | `bg`, `surface`, `borderStrong` |
| Normal control | `surface`, `border`, `text` |
| Hover control | `surfaceHover`, `borderStrong`, `textStrong` |
| Focused control | normal fill, `accent` border |
| Selected control | `surfaceActive`, `accentSecondary` |
| Disabled control | `barBackground`, `border`, `textMuted` |
| Danger control | existing `danger` role |

The spacing scale runs from 2px through 18px. The type scale preserves the
existing 10px, 12px, 13px, 14px, and 18px sizes. Existing public token names
remain compatibility aliases, which keeps current panels and menus visually
stable while later work migrates incrementally.

## X11 Surface Rules

New menus must use the existing dwm-titus popup and panel primitives. They
must preserve current X11 mapping, click-away, focus, monitor targeting, and
EWMH behavior. A visual component must not own system state: it consumes the
current root-scoped models and invokes their bounded actions.

Popup geometry must remain derived from the target X11 screen and the managed
30px panel. No visual adaptation may introduce a Wayland-only import, command,
or layer-shell assumption. Event-driven providers remain mandatory where the
underlying state exposes a signal, subscription, watch, IPC, or service API.

## Review and Rollout

Each later menu migration should be independently reviewable and should:

1. reuse semantic roles instead of adding local color literals;
2. preserve the current provider and action contract;
3. add focused source checks and exercise the surface in Xvfb or a real X11
   session;
4. verify the managed Quickshell process remains near idle with menus closed;
5. leave unrelated menus unchanged until their own migration.

The static design-system check rejects Wayland and Hyprland dependencies in
the managed shell. The Quickshell lint and X11 runtime checks remain the
authoritative syntax and integration gates.

## Command Menu Contract

The command menu is a DWM-owned navigation surface, not an Omarchy service
port. Its root taxonomy is Apps, Settings, Display / Input, Network,
Bluetooth, Audio, System Health, Keybindings, Screenshots, and System.
Submenus and actions are typed data. Actions may call an allowlisted shell IPC
operation, a fixed helper argument vector, or the existing XDG application
launcher provider; catalog entries cannot contain executable command text.

The `menu` IPC target provides `open`, `close`, `toggle`, and `summon`.
`summon` targets the active DWM panel screen, while `open` preserves the normal
floating-window screen selection. The existing `launcher` IPC target and
Super+r binding remain unchanged for compatibility.

Open the menu on the active screen from a terminal or a user-defined hotkey:

```sh
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call menu summon
```

Apps enters the shared XDG application provider. Display / Input,
Screenshots, and System enter focused submenus; the other root rows open their
existing dwm-titus surface directly. Type to search commands and applications
across the catalog.

The application index is shared only while either surface is open. Closing
the launcher and command menu releases its parsed desktop-entry data so the
new menu does not add a hidden resident application model. Keyboard behavior
includes type-to-search, arrows, Page Up/Down, Home/End, Enter, Left or empty
Backspace to return, and Escape to close.

Run the focused source contract with:

```sh
make check-quickshell-design-system
make check-quickshell-command-menu
```

It is also part of the repository-wide `make check` gate. QML changes still
require `make check-quickshell-qml` plus the applicable X11 runtime suite.
