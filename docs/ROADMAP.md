# Quickshell Migration Roadmap

## Goal

Replace the current Polybar/Rofi/widget stack with a Quickshell-based shell layer for an Xorg setup while keeping the window manager stable.

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
- [x] Add a temporary startup command but keep Polybar/Rofi enabled

### Exit Criteria

- [x] Quickshell launches successfully
- [x] No login/session breakage
- [x] Existing Polybar/Rofi workflow still works as fallback

---

## Phase 2: Replace Polybar with a Basic Quickshell Panel

### Objective

Replace Polybar with a simple Quickshell top or bottom panel.

### Tasks

- [x] Build a basic `PanelWindow`
- [x] Add clock/date
- [x] Add CPU/RAM indicators
- [x] Add network indicator
- [x] Add volume indicator
- [x] Add battery/power indicator if needed
- [x] Reserve screen space correctly
- [x] Match current bar height and monitor placement
- [x] Disable Polybar only after Quickshell panel is usable

### Exit Criteria

- [x] Quickshell panel fully replaces basic Polybar functionality
- [x] Panel survives reloads
- [x] Window manager respects reserved screen space
- [x] Polybar can be removed from startup

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

- [ ] Build launcher popup/window
- [ ] Index `.desktop` applications
- [ ] Add search/filter input
- [ ] Launch selected app
- [ ] Add keyboard navigation
- [ ] Add close-on-launch behavior
- [ ] Bind launcher open/close through WM keybinds
- [ ] Keep Rofi installed as fallback during testing

### Exit Criteria

- Quickshell launcher can replace normal app-launching workflow
- Keyboard navigation feels reliable
- Launcher opens quickly enough for daily use
- Rofi can be removed from normal keybinds

---

## Phase 5: Add Power/User Menu

### Objective

Replace small Rofi scripts such as power menus, logout menus, and utility menus.

### Tasks

- [ ] Create power menu UI
- [ ] Add lock
- [ ] Add logout
- [ ] Add reboot
- [ ] Add shutdown
- [ ] Add confirmation step for destructive actions
- [ ] Add optional quick actions:
  - [ ] Screenshot
  - [ ] File manager
  - [ ] Terminal
  - [ ] Browser
  - [ ] Settings scripts

### Exit Criteria

- Common Rofi script menus are replaced
- Destructive actions require confirmation
- Keybinds are updated to Quickshell menus

---

## Phase 6: Notifications

### Objective

Replace Dunst or other notification UI with Quickshell notifications.

### Tasks

- [ ] Enable Quickshell notification daemon functionality
- [ ] Build notification popup UI
- [ ] Add notification history
- [ ] Add dismiss action
- [ ] Add timeout behavior
- [ ] Add urgency styling
- [ ] Test with common apps:
  - [ ] Browser
  - [ ] Discord/Slack
  - [ ] Terminal notify-send
  - [ ] Steam/game launchers

### Exit Criteria

- Notifications appear consistently
- Urgent notifications are obvious
- Notification history works
- Dunst can be disabled

---

## Phase 7: System Tray and App Indicators

### Objective

Move tray functionality into Quickshell.

### Tasks

- [ ] Add system tray area
- [ ] Test tray apps:
  - [ ] Network manager applet
  - [ ] Audio applet if used
  - [ ] Discord/Steam/etc.
  - [ ] Syncthing/Nextcloud/etc.
- [ ] Confirm left-click/right-click behavior
- [ ] Confirm icons scale correctly

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

Remove Polybar/Rofi/Dunst only after Quickshell replacements are stable.

### Tasks

- [ ] Remove Polybar from startup
- [ ] Remove Rofi from keybinds
- [ ] Remove Dunst from startup
- [ ] Keep packages installed temporarily
- [ ] Run the Quickshell setup for several normal sessions
- [ ] Remove unused packages after validation
- [ ] Document rollback steps

### Exit Criteria

- Daily workflow works without Polybar/Rofi/Dunst
- No missing launcher, panel, tray, or notification functionality
- Rollback path is documented

---

## Rollback Plan

Keep the old stack available until the Quickshell setup is proven stable.

### Rollback Tasks

- [ ] Keep old Polybar config
- [ ] Keep old Rofi scripts
- [ ] Keep old Dunst config
- [ ] Keep old WM keybinds commented, not deleted
- [ ] Add emergency keybind to launch terminal
- [ ] Add emergency keybind to restart Quickshell
- [ ] Document how to restore the old startup commands

Example fallback commands:

```sh
polybar main &
dunst &
rofi -show drun
```
