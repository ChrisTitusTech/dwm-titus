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
- [ ] Test tray apps:
  - [ ] Network manager applet
  - [ ] Audio applet if used
  - [ ] Discord/Steam/etc.
  - [ ] Syncthing/Nextcloud/etc.
- [x] Confirm left-click/right-click behavior
- [x] Confirm icons scale correctly

### Exit Criteria

- Tray icons appear correctly
- Menus work
- No missing tray clients from the old bar

---

## Phase 8: Media, Audio, and Quick Controls

### Objective

Add shell controls that previously required separate scripts or widgets.

### Tasks

- [ ] Add volume display
- [ ] Add volume up/down/mute actions
- [ ] Add microphone mute status
- [ ] Add media player display using MPRIS
- [ ] Add play/pause/next/previous controls
- [ ] Add brightness controls if needed
- [ ] Add Bluetooth status if needed

### Exit Criteria

- Common audio/media controls work from Quickshell
- Existing hotkeys continue to work
- Media state updates live

---

## Phase 9: Styling and Theming

### Objective

Make the Quickshell setup visually consistent and easier to maintain.

### Tasks

- [ ] Define shared colors
- [ ] Define font choices
- [ ] Define spacing variables
- [ ] Define icon sizing
- [ ] Create reusable components
- [ ] Separate config into logical modules:
  - [ ] Panel
  - [ ] Launcher
  - [ ] Notifications
  - [ ] Tray
  - [ ] Menus
  - [ ] Services
- [ ] Add light/dark theme support if desired

### Exit Criteria

- Styling is centralized
- Components are reusable
- Config is readable enough to maintain long-term

---

## Phase 10: Remove Old Dependencies

### Objective

Remove Rofi-era bar/Rofi only after Quickshell replacements are stable.

### Tasks

- [ ] Remove Rofi-era bar from startup
- [ ] Remove Rofi launcher backup keybind
- [ ] Remove Rofi power-menu backup keybind
- [ ] Keep packages installed temporarily
- [ ] Run the Quickshell setup for several normal sessions
- [ ] Remove unused packages after validation
- [ ] Document rollback steps

### Exit Criteria

- Daily workflow works without Rofi-era bar/Rofi
- No missing launcher, panel, tray, or notification functionality
- Rollback path is documented

---

## Rollback Plan

Keep the old stack available until the Quickshell setup is proven stable.

### Rollback Tasks

- [ ] Keep old Rofi-era bar config
- [ ] Keep old Rofi scripts
- [ ] Keep old WM keybinds commented, not deleted
- [ ] Add emergency keybind to launch terminal
- [ ] Add emergency keybind to restart Quickshell
- [ ] Document how to restore the old startup commands

Example fallback commands:

```sh
legacy-bar main &
rofi -show drun
```
