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
- `docs/evidence/p3-ui4/after-live`: final Settings and launcher captures from
  both active monitors, plus System Health, notification popup, geometry, and
  X11 property evidence from the Fedora session.

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

The approved revision was synchronized on Fedora Linux 44 x86_64 with
`scripts/dev-sync-install.sh`. The sync created rollback backup
`20260821T204131Z-33360`, verified every managed file, and restarted the managed
Quickshell instance through `dwm-quickshell-controlcenter action
restart-quickshell`.

The active X11 layout was:

- HDMI-0: 1920x1080 at 0,0.
- DP-0: 2560x1440 at 0,1080 and primary.

Settings centered at 469,229 on HDMI-0 and 789,1489 on DP-0 while retaining its
980x620 geometry. The launcher centered at 549,239 on HDMI-0 and 869,1499 on
DP-0 with its intentional 820x600 geometry. Both surfaces rendered and accepted
their keyboard and pointer paths on the live managed shell.

The matching `.geometry` files are authoritative for each final captured
placement. `WM_NORMAL_HINTS` in the `.xprop` files can retain the position from
the preceding placement request after DWM moves the client to another monitor;
those requested coordinates are not the final frame coordinates.

Live interaction evidence:

- Keyboard and pointer launcher activation each opened a new Alacritty window,
  closed the launcher, and returned `launcher applicationConsumers` to zero.
- A no-op two-output display preview became active through the Settings pointer
  path. Closing Settings canceled the preview, returned `preview-status` to
  `result none`, and left the before/after `xrandr --query` byte-identical.
- Closing System Health canceled its user/system scan within the bounded
  ten-second check. Its X11 window retained `_NET_WM_STATE_FULLSCREEN` while a
  notification popup remained visible above the fullscreen surface.
- A real D-Bus notification was delivered, dismissed with the popup pointer
  control, recorded in history, and the history window closed with Escape. The
  synthetic evidence entries were then removed without changing real history.
- The managed shell recovered all five tray items after each deliberate restart.

The required 30-second closed baseline measured 0.000 percent of one CPU. After
opening and closing every converted surface and restarting the managed shell,
the 30-second post-operation sample also measured 0.000 percent. The mean delta
was therefore 0.000 percentage points, within the 0.5-point limit. RSS moved
from 202504 KiB to 201464 KiB during the post-operation sample.

The installed `/usr/local/bin/dwm` remains a session-restart activation gate;
P3-UI4 changes no DWM source or binary behavior, and the running DWM continues
to use the already-qualified executable until logout/login.
