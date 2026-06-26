# Quickshell Active Tasks

This file tracks the next reviewable work for the Quickshell migration.
Long-term sequencing lives in `docs/ROADMAP.md`; product requirements remain
in `SPEC.md`.

## Completed Phase: Quickshell Baseline

Goal: install Quickshell and confirm it works reliably under Xorg before
replacing Polybar, Rofi, Dunst, or other existing shell components.

- [x] Install Quickshell.
  - Acceptance: `quickshell --version` or the equivalent package command
    confirms Quickshell is installed.
  - Validation: record the installed version and package source.
  - Result: installed `quickshell-0.2.1^git20260209.dacfa9d-3.fc44` from the
    Fedora updates repository with `jemalloc-5.3.0-14.fc44` as a dependency.
    `quickshell --version` reports `quickshell 0.2.1`, revision
    `dacfa9de829ac7cb173825f593236bf2c21f637e`, distributed by Fedora Project.
- [x] Create the base Quickshell config directory.
  - Acceptance: the config lives under the expected XDG config path and does
    not replace existing dwm, Polybar, Rofi, or Dunst configuration.
  - Validation: inspect the created path and confirm existing config files are
    still present.
  - Result: created `/home/titus/.config/quickshell` under
    `XDG_CONFIG_HOME=/home/titus/.config`. Existing
    `/home/titus/.config/dwm-titus`, `/home/titus/.config/polybar`, and
    `/home/titus/.config/rofi` directories remained present; no existing Dunst
    config directory was present to preserve.
- [x] Launch a minimal Quickshell window manually.
  - Acceptance: a minimal test window starts and exits without breaking the
    current dwm session.
  - Validation: run it from a terminal inside the current Xorg session and
    record any stderr output.
  - Result: created `/home/titus/.config/quickshell/shell.qml` with a minimal
    `ShellRoot` and `FloatingWindow` baseline. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` from the active session exited with status 0 after the test
    timer and reported `Configuration Loaded`. `quickshell list` and
    `pgrep -a quickshell` confirmed no remaining Quickshell process.
- [x] Confirm Quickshell starts correctly inside the current Xorg session.
  - Acceptance: Quickshell starts with `XDG_SESSION_TYPE=x11` and the active
    window manager remains dwm.
  - Validation: record `echo "$XDG_SESSION_TYPE"`, `echo "$DESKTOP_SESSION"`,
    and the Quickshell launch result.
  - Result: `XDG_SESSION_TYPE=x11`, `DESKTOP_SESSION=dwm`, and `DISPLAY=:0`.
    `pgrep -a dwm` showed `/usr/local/bin/dwm`, and `wmctrl -m` reported
    `Name: dwm`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` in that session exited with status 0 and reported
    `Configuration Loaded`.
- [x] Confirm Quickshell does not interfere with the current window manager.
  - Acceptance: dwm focus, tagging, terminal launch, and existing keybindings
    still work while the minimal Quickshell process is running.
  - Validation: manually exercise the core workflow and record the result.
  - Result: with the minimal Quickshell window running, `Super+X` launched an
    Alacritty terminal, `Super+J` moved focus from the terminal back to the
    Quickshell baseline window, `Super+2` changed `_NET_CURRENT_DESKTOP` from
    0 to 1, and `Super+1` returned it to 0. The test terminal was closed with
    `wmctrl -ic`, Quickshell was stopped, `quickshell list` and
    `pgrep -a quickshell` confirmed no remaining instance, and `wmctrl -m`
    still reported `Name: dwm`.
- [x] Add a temporary startup command while keeping Polybar and Rofi enabled.
  - Acceptance: Quickshell can be started with the session without removing
    the current fallback shell tools.
  - Validation: restart the session or startup script in a controlled test and
    confirm Polybar/Rofi still work.
  - Result: added a temporary Quickshell startup block to
    `scripts/autostart.sh` that runs `quickshell --no-duplicate` only when
    `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml` exists. The
    existing Polybar launch remains in place, and Rofi remains installed at
    `/usr/bin/rofi` with the existing app-launcher hotkeys still present in
    `hotkeys.toml`. `make check-session-guards` passed with mocked
    display-manager and `startx` runs, confirming Quickshell starts once while
    Polybar still launches and duplicate guards continue to work. `make
    check-shell`, `make check-format`, and `git diff --check` also passed.

## Current Phase: Basic Quickshell Panel

Goal: replace Polybar with a simple Quickshell top panel while keeping Polybar
available as the fallback until the Quickshell panel is usable.

- [x] Build a basic `PanelWindow`.
  - Acceptance: a tracked Quickshell config creates a top panel matching the
    current 30px Polybar height.
  - Validation: launch the config in the active Xorg/dwm session and confirm
    Quickshell reports a running X11 instance while dwm remains the active
    window manager.
  - Result: added `config/quickshell/shell.qml` and synced the active user
    config at `/home/titus/.config/quickshell/shell.qml`. The config creates a
    30px top `PanelWindow` for each `Quickshell.screens` entry, uses the
    current Polybar Nord colors, and sets `exclusiveZone: 30`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; `wmctrl -m` still reported `Name: dwm`; and
    `quickshell list` confirmed no running instance after stopping the test
    process.
- [x] Add clock/date.
  - Acceptance: the panel displays a live date/time value without creating one
    process loop per monitor.
  - Validation: launch the config in the active Xorg/dwm session and confirm
    Quickshell loads, remains listed as an X11 instance, and the date command
    used by the panel returns the expected format.
  - Result: added one shared `clockText` property, a `date` process, and a
    repeating timer to `config/quickshell/shell.qml`. The panel now binds its
    right-side text to `root.clockText`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; `date '+%a %b %d  %H:%M'` returned the expected
    format; and `wmctrl -m` still reported `Name: dwm`.
- [x] Add CPU/RAM indicators.
  - Acceptance: the panel displays a lightweight CPU/RAM summary without
    requiring Polybar or a new package dependency.
  - Validation: run the status command directly, then launch the config in the
    active Xorg/dwm session and confirm Quickshell remains running.
  - Result: added one shared `systemText` property, a `/proc/loadavg` and
    `/proc/meminfo` status process, and a 5 second update timer to
    `config/quickshell/shell.qml`. The command returned output in the form
    `CPU 0.59  RAM 10%`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; and `wmctrl -m` still reported `Name: dwm`.
- [ ] Add network indicator.
- [ ] Add volume indicator.
- [ ] Add battery/power indicator if needed.
- [ ] Reserve screen space correctly.
- [ ] Match current bar height and monitor placement.
- [ ] Disable Polybar only after Quickshell panel is usable.

## Backlog

- [ ] Expose workspace and active-window state to Quickshell.
- [ ] Replace the Rofi app launcher.
- [ ] Add a Quickshell power/user menu.
- [ ] Replace Dunst or other notification UI.
- [ ] Move tray functionality into Quickshell.
- [ ] Add media, audio, and quick controls.
- [ ] Centralize Quickshell styling and reusable components.
- [ ] Remove old dependencies only after Quickshell replacements are stable.
- [ ] Document rollback steps and keep the old shell stack available until the
      migration is proven stable.

## Validation Policy

A task is complete only when its acceptance criteria pass or the exact skipped
environment is recorded. Do not remove Polybar, Rofi, or Dunst from the normal
startup path until the Quickshell replacement for that component has been
validated and rollback steps are documented.
