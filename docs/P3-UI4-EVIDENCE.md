# P3-UI4 Large-Surface Evidence

## Scope

P3-UI4 applies the shared semantic shell language to Settings, System Health,
notification popups/history, and the application launcher. It does not add or
change connectivity, Bluetooth, audio, provider, helper, privilege, panel, or
keybinding behavior.

The presentation-only `LargeSurfaceHeader` is shared by all four converted
surfaces. It owns no process, provider, or lifecycle state. Existing model
ownership, IPC targets, X11 titles, surface types, monitor selection, preview
and repair confirmation flows, notification lifecycle, and launcher release
behavior remain authoritative.

## Visual Evidence

The checked-in evidence contains:

- `docs/evidence/p3-ui4/before-live`: baseline captures and X11 properties from
  the active Fedora X11 two-monitor session before P3-UI4.
- `docs/evidence/p3-ui4/before-nested`: baseline captures and X11 properties
  from commit `a20ee6f` in a 1280x800 nested X11 session.
- `docs/evidence/p3-ui4/after-nested`: P3-UI4 captures and X11 properties from
  the same 1280x800 nested X11 contract.

Nested geometry remained 980x620 for Settings and 1280x800 fullscreen for
System Health. The launcher intentionally changed from 760x560 to 820x600 and
notification history from 520x560 to 560x600 to accommodate the shared header
and denser metadata without reducing result space.

## Intentional Adaptation

The visual language borrows the approved compact hierarchy, uppercase metadata,
accent rails, outlined state pills, numbered navigation, and semantic status
colors. It intentionally retains the configured dwm theme palette, X11 window
types, dwm placement, existing fonts, and native Quickshell controls. It does
not copy Omarchy wallpaper, Hyprland geometry, layer-shell behavior, services,
plugins, or Wayland dependencies.

## Automated Evidence

`tests/test-quickshell-large-surfaces.sh` enforces the presentation boundary,
stable X11 titles, retained behavior hooks, and forbidden-runtime exclusions.
`tests/test-quickshell-large-surfaces-xvfb.sh` exercises the four surfaces in a
private 1280x800 X11 and D-Bus session with a private configuration, data,
runtime, and cache root. It covers launcher keyboard and pointer activation,
Escape dismissal, model release, Settings navigation, System Health fullscreen
precedence, notification delivery/history, and a closed-process CPU sample.

The nested renderer is forced to Qt software mode only for deterministic X11
screen capture. Product runtime selection is unchanged.

## Live Qualification

The final approved revision must still be synchronized with
`scripts/dev-sync-install.sh`. After synchronization, this document will record
the two-monitor placement, keyboard and pointer paths, notification
delivery/history, Settings preview cancellation, System Health cancellation,
tray ownership, fullscreen precedence, and the required 30-second closed versus
post-open/close CPU comparison.
