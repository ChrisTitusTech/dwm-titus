# Phase 5 Appearance Inventory Protocol

## Scope

This record defines the first `APPEARANCE-001` review boundary. It adds a
read-only, bounded inventory for wallpaper, font, cursor, icon, GTK, Qt, and
compositor capabilities. Mutations remain outside this boundary.

The inventory is separate from the always-resident semantic theme snapshot.
Quickshell requests it only while the Settings Appearance section is open and
stops both the scan process and its watcher when Settings closes.

## Provider Contract

`dwm-settings-appearance inventory` emits tab-separated protocol version 1.0:

```text
appearance-inventory-protocol  1  0
provider  appearance-inventory  STATE  read-only  DETAIL
watch  STATE  inotifywait  DETAIL
selection  CAPABILITY  STATE  VALUE  OPTION  DETAIL
candidate  CAPABILITY  STATE  TOKEN  LABEL  DETAIL
```

The supported capability identifiers are `wallpaper`, `font`, `cursor`,
`icon`, `gtk`, `qt`, and `compositor`. Every snapshot contains exactly one
selection record for each capability. Candidate records are limited to 256 per
capability, and every field is normalized to one bounded protocol line.

The provider uses these Fedora/X11 interfaces:

- wallpaper files under the configured `~/Pictures/backgrounds` directory;
- Fontconfig's formatted `fc-list` interface, including exact installed-family
  validation for the selected Pango font description;
- `org.gnome.desktop.interface` through `gsettings` for current toolkit, font,
  cursor, and icon selections when available;
- XDG data roots plus user theme roots for cursor, icon, and GTK assets;
- the active Qt platform-theme environment and installed `qt5ct`/`qt6ct`
  tools; and
- `picom` command availability and same-user, same-`DISPLAY` process state for
  compositor status.

Missing optional applications or asset directories fail only their selection
record. They do not make the full inventory unavailable.

Each external candidate producer is limited to three seconds. A producer error
or timeout marks only its capability incomplete. Direct symlinked theme entries
are resolved and included without recursively following unbounded link trees.

## Event Lifecycle

`dwm-settings-appearance watch-inventory` uses `inotifywait` only while the
Appearance section is open. It observes the wallpaper tree, applicable XDG
font/icon/theme roots and their relevant existing descendants, user Fontconfig
configuration, GTK configuration, dconf state, and managed appearance
configuration. Required state roots are reserved before bounded descendant
coverage, so a large wallpaper tree cannot displace toolkit or asset state. The
directory list is deduplicated and capped at 128 entries. When a required asset
root does not yet exist, the nearest safe existing parent is watched so creating
it converges without reopening Settings.

The watcher emits a readiness record only after `inotifywait` confirms every
watch is established. Quickshell waits for that record before starting the
snapshot, eliminating the scan-before-watch race. Each event then ends the
one-shot watcher, schedules one settled inventory refresh, and rebuilds the
directory set only while the section remains open. A watcher that exits without
an event is marked unavailable for the rest of that pane-open lifecycle, so a
permission or kernel watch-limit failure cannot create a restart loop.

Because Picom has no stable session signal in this X11 setup, a separate
pane-scoped process samples same-user Picom processes on the current `DISPLAY`
and emits a record only when that state changes. Both watcher helpers track the
identity of their owning process and terminate themselves if Quickshell exits
without stopping them. Their cleanup uses bounded child termination and reaping.
The scan runs as Quickshell's directly owned child rather than behind an
output-capturing shell. Closing Settings stops both watchers, the pending scan,
settle timers, and restart timers, so the read-only inventory leaves no hidden
scan or orphaned watcher.

## Validation

Run:

```sh
scripts/run-tests make check-appearance
scripts/run-tests tests/test-quickshell-appearance-model.sh
shellcheck scripts/dwm-settings-appearance \
  tests/test-dwm-settings-appearance-inventory.sh
shfmt -d scripts/dwm-settings-appearance \
  tests/test-dwm-settings-appearance-inventory.sh
```

The fixtures cover supported records, stale selected assets, candidate
deduplication and bounds, image filtering, partial GTK assets, per-display
Picom state, missing optional tools, watcher readiness and directory selection,
owner-death cleanup, and watcher unavailability.
