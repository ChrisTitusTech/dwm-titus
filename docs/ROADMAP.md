# Quickshell Migration Roadmap

## Goal

Replace the current Rofi-era bar/Rofi/widget stack with a Quickshell-based shell layer for an Xorg setup while keeping the window manager stable.

Target setup:

- Xorg session
- Existing window manager remains in place
- Quickshell handles panels, widgets, menus, notifications, and shell UI
- Migration happens incrementally so the desktop never becomes unusable

---

## Phase 1: Quickshell Baseline

### Objective

Install Quickshell and confirm it works reliably under Xorg before replacing anything.

### Tasks

- [x] Install Quickshell
- [x] Create base config directory
- [x] Launch a minimal Quickshell window manually
- [x] Confirm it starts correctly inside the current Xorg session
- [x] Confirm it does not interfere with the current WM
- [x] Add a temporary startup command but keep Rofi-era bar/Rofi enabled

### Exit Criteria

- [x] Quickshell launches successfully
- [x] No login/session breakage
- [x] Existing Rofi-era bar/Rofi workflow still works as fallback

---

## Phase 2: Replace Rofi-era bar with a Basic Quickshell Panel

### Objective

Replace Rofi-era bar with a simple Quickshell top or bottom panel.

### Tasks

- [x] Build a basic `PanelWindow`
- [x] Add clock/date
- [x] Add CPU/RAM indicators
- [x] Add network indicator
- [x] Add volume indicator
- [x] Add battery/power indicator if needed
- [x] Reserve screen space correctly
- [x] Match current bar height and monitor placement
- [x] Disable Rofi-era bar only after Quickshell panel is usable

### Exit Criteria

- [x] Quickshell panel fully replaces basic Rofi-era bar functionality
- [x] Panel survives reloads
- [x] Window manager respects reserved screen space
- [x] Rofi-era bar can be removed from startup

---

## Phase 3: Workspace and Window State Integration

### Objective

Expose workspace/tag state from the Xorg window manager to Quickshell.

### Notes

Quickshell does not directly manage Xorg workspaces for DWM-style setups. Workspace state may need to come from scripts, `xprop`, `xdotool`, `wmctrl`, or a WM-specific patch/status output.

Phase 3 will expose state through a small shell bridge that reads the existing
EWMH root window properties with `xprop`, reads the active window title with
`xdotool` and `xprop`, and switches workspaces with `wmctrl -s` when clickable
tag switching is available. WM keybinds remain the primary control path.

### Tasks

- [x] Decide how workspace/tag state will be exposed
- [x] Create a script or IPC bridge for current workspace/tag
- [x] Display active workspace/tag in Quickshell
- [x] Add clickable workspace/tag switching if practical
- [x] Display active window title
- [x] Add fallback behavior when no active window exists

### Exit Criteria

- [x] Quickshell shows useful workspace/tag state
- [x] Active window title works
- [x] Existing WM keybinds remain the primary control path

---

## Phase 4: Replace Rofi App Launcher

### Objective

Create a Quickshell launcher for desktop applications.

### Tasks

- [x] Build launcher popup/window
- [x] Index `.desktop` applications
- [x] Add search/filter input
- [x] Launch selected app
- [x] Add keyboard navigation
- [x] Add close-on-launch behavior
- [x] Bind launcher open/close through WM keybinds
- [x] Keep Rofi installed as fallback during testing

### Exit Criteria

- [x] Quickshell launcher can replace normal app-launching workflow
- [x] Keyboard navigation feels reliable
- [x] Launcher opens quickly enough for daily use
- [x] Rofi backup keybinds are intentionally retained until final cleanup

---

## Phase 5: Add Power/User Menu

### Objective

Replace small Rofi scripts such as power menus, logout menus, and utility menus.

### Tasks

- [x] Create power menu UI
- [x] Add lock
- [x] Add logout
- [x] Add reboot
- [x] Add shutdown
- [x] Add confirmation step for destructive actions
- [x] Add optional quick actions:
  - [x] Screenshot
  - [x] File manager
  - [x] Terminal
  - [x] Browser
  - [x] Settings scripts

### Exit Criteria

- [x] Common Rofi script menus are replaced
- [x] Destructive actions require confirmation
- [x] Keybinds are updated to Quickshell menus

---

## Phase 6: Notifications

### Objective

Replace external notification UI with Quickshell notifications.

### Tasks

- [x] Enable Quickshell notification daemon functionality
- [x] Build notification popup UI
- [x] Add notification history
- [x] Add dismiss action
- [x] Add timeout behavior
- [x] Add urgency styling
- [x] Test with common apps:
  - [x] Browser
  - [x] Discord/Slack
  - [x] Terminal notify-send
  - [x] Steam/game launchers

### Exit Criteria

- [x] Notifications appear consistently
- [x] Urgent notifications are obvious
- [x] Notification history works
- [x] No separate notification daemon is required

---

## Phase 7: System Tray and App Indicators

### Objective

Move tray functionality into Quickshell.

### Tasks

- [x] Add system tray area
- [x] Test tray apps:
  - [x] NetworkManager native widget path
  - [x] Audio applet if used
  - [x] Discord/Steam/etc.
  - [x] Syncthing/Nextcloud/etc.
  - [x] Current host SNI clients
- [x] Confirm left-click/right-click behavior
- [x] Confirm icons scale correctly

### Exit Criteria

- [x] Tray icons appear correctly
- [x] Menus work
- [x] No missing tray clients from the old bar

---

## Phase 8: Media, Audio, and Quick Controls

### Objective

Add shell controls that previously required separate scripts or widgets.

### Tasks

- [x] Add volume display
- [x] Add volume up/down/mute actions
- [x] Add microphone mute status
- [x] Add media player display using MPRIS
- [x] Add play/pause/next/previous controls
- [x] Add brightness controls if needed
  - Not needed on the current validation host: `/sys/class/backlight` is empty,
    and `brightnessctl --list` only reports LED devices.
- [x] Add Bluetooth status if needed

### Exit Criteria

- [x] Common audio/media controls work from Quickshell
- [x] Existing hotkeys continue to work
  - No hotkey configuration changes were needed for Phase 8.
- [x] Media state updates live
  - `dwm-quickshell-controls media-watch` streams MPRIS state changes through
    `playerctl --follow` into the Quickshell controls model.

---

## Phase 9: Styling and Theming

### Objective

Make the Quickshell setup visually consistent and easier to maintain.

### Tasks

- [x] Define shared colors
  - `config/quickshell/core/Theme.qml` now owns shell colors, including dark
    and light palette tokens, accent, danger, surfaces, text, and transparent
    values.
- [x] Define font choices
  - The shared theme defines `fontFamily` and the common title, input, panel,
    body, small, and tiny font sizes used across the shell.
- [x] Define spacing variables
  - Common popup margin, popup spacing, row spacing, list spacing, compact
    spacing, and section spacing are centralized in the theme.
- [x] Define icon sizing
  - Launcher, tray, close-button, workspace-button, chip, and notification
    accent sizes are shared theme tokens.
- [x] Create reusable components
  - Added reusable `ShellSurface`, `ShellButton`, and `SectionLabel`
    components under `config/quickshell/core/`.
- [x] Separate config into logical modules:
  - [x] Panel
  - [x] Launcher
  - [x] Notifications
  - [x] Tray
  - [x] Menus
  - [x] Services
- [x] Add light/dark theme support if desired
  - The theme includes dark and light palette branches; the session defaults to
    dark mode and can be switched by changing the theme `dark` flag in one
    place.

### Exit Criteria

- [x] Styling is centralized
  - Repeated colors, fonts, spacing, radii, and shell dimensions now resolve
    through `Theme.qml`.
- [x] Components are reusable
  - Common popup chrome, simple buttons, and section labels are shared instead
    of reimplemented in each feature window.
- [x] Config is readable enough to maintain long-term
  - Feature modules remain split by panel, launcher, notifications, tray,
    network, controls, power menu, state, and core services.
  - Validation: `make check-quickshell-launcher`,
    `tests/test-autostart.sh`, `tests/test-install-preservation.sh`,
    `make check-install-manifest`, repo-scoped Quickshell reload, IPC target
    inspection, and launcher open/close all passed.

---

## Phase 10: Remove Old Dependencies

### Objective

Remove the old shell stack after Quickshell replacements are stable.

### Tasks

- [x] Remove legacy bar startup paths from the normal Quickshell session
- [x] Remove Rofi launcher backup keybind
- [x] Remove Rofi control center and keybind viewer paths
- [x] Remove Rofi power-menu backup path
- [x] Remove Rofi package, config, and theme assets after validation
- [x] Add Quickshell utility-window rules for control center and network UI
- [x] Document rollback steps

### Exit Criteria

- [x] Daily workflow works without the old shell stack
- [x] No missing launcher, panel, tray, notification, power menu, network, or
  control center functionality
- [x] Rollback path is documented

---

## Rollback Plan

The old stack is no longer part of the normal runtime. The supported rollback
path is to revert the Phase 10 commits or restore the specific files from git
history, then rerun the normal install/update flow.

### Rollback Tasks

- [x] Keep emergency terminal keybind
- [x] Keep emergency Quickshell restart keybind
- [x] Document how to restore the old stack from git history

Example rollback commands:

```sh
git log --oneline -- config/rofi config/hotkeys.toml scripts/dwm-controlcenter
git revert <phase-10-commit>
make install
```
