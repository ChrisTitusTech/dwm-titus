# Window overview

Choose Window overview in Control Center or the command menu. The fullscreen
view contains one card per managed application window across all tags, including
several windows from the same application. Each card identifies the title,
application, complete tag list and owning monitor. Type to filter by application,
title or tag. Use Tab/Shift+Tab, Up/Down, or Left/Right with an empty search,
then Enter; clicking a card selects it directly. Escape or Close dismisses the
view and restores previous focus. The empty and no-match states are explicit.

Selection does not change a window's tags or monitor. dwm chooses its actual
monitor and retains that monitor's visible tag if it already contains the
window; otherwise it selects the lowest assigned tag on that monitor, then
focuses and raises the selected window. Explicit selection exits another visible
fullscreen client on that monitor when it would cover the selection. A closed window produces an actionable
error and the overview can be reopened. The overview tracks open, close, title
and tag changes through X11 events; there is no polling or screenshot capture.
Cards are used instead of live pixel previews, including on hidden tags.

`dwm-window-overview open`, `toggle` and `close` use the managed Quickshell IPC
instance. Existing hotkeys are preserved. A custom binding can invoke
`dwm-window-overview toggle`. `list` prints a JSON snapshot including active client; `watch` streams
changed snapshots while subscribed; `activate XID` validates membership and
waits up to two seconds for focus. Internal `restore XID` restores focus on
cancellation only while the client remains visible, without switching tags or
exiting a fullscreen peer. The backend uses Python's standard library
and libX11, with bounded property and client-list reads (4096 windows maximum).

The C core only publishes versioned full-tag and monitor metadata and handles
a bounded explicit activation request. Search, cards, keyboard navigation and
application labels stay in Quickshell. The helper and window delegates exist
only while the overview is visible. An older running dwm reports that a session
restart is required.

## Interface

- `_DWM_WINDOW_OVERVIEW` on the root: CARDINAL/32 version 1.
- `_DWM_CLIENT_INFO` on each managed client: CARDINAL/32 values version (1),
  full tag mask and dwm monitor number. Docks and unmanaged overlays have no
  such metadata and are omitted. The overview excludes its own shell window.
- `_DWM_WINDOW_ACTIVATE`: root-directed ClientMessage/32 naming the client in
  `window`, version 1 in `data.l[0]`, and mode 0 (select) or 1 (restore
visible focus only) in `data.l[1]`. dwm ignores unknown clients, formats
  and versions. The ordinary `_NET_ACTIVE_WINDOW` policy is preserved.

## Validation

`make check-window-overview` runs real dwm and Quickshell on private one-monitor
and two-monitor Xinerama servers. It covers individual same-application cards,
multiple tags, titles changing while open, keyboard and actual mouse selection,
Escape focus restoration, multi-tag assignment preservation, closing before
selection, fullscreen occlusion, swallowing/restoration metadata, malformed optional title metadata and the empty state. An 80-card
UI fixture checks scrolling to the final row. It samples idle CPU. Set
`DWM_FEATURE_EVIDENCE_DIR` to save dark and shipped light-theme screenshots.
Physical hotplug, distinct physical display arrangements and GPU behavior still
need hardware qualification; the two-screen fixture uses Xvfb Xinerama.

![Nested X11 validation: overview-dark.png](validation/issue-350/overview-dark.png)

![Nested X11 validation: overview-light.png](validation/issue-350/overview-light.png)
