# Quickshell Active Tasks

This file tracks the next reviewable work for the Quickshell migration.
Long-term sequencing lives in `docs/ROADMAP.md`; product requirements remain
in `SPEC.md`.

## Current Phase: Quickshell Baseline

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
- [ ] Launch a minimal Quickshell window manually.
  - Acceptance: a minimal test window starts and exits without breaking the
    current dwm session.
  - Validation: run it from a terminal inside the current Xorg session and
    record any stderr output.
- [ ] Confirm Quickshell starts correctly inside the current Xorg session.
  - Acceptance: Quickshell starts with `XDG_SESSION_TYPE=x11` and the active
    window manager remains dwm.
  - Validation: record `echo "$XDG_SESSION_TYPE"`, `echo "$DESKTOP_SESSION"`,
    and the Quickshell launch result.
- [ ] Confirm Quickshell does not interfere with the current window manager.
  - Acceptance: dwm focus, tagging, terminal launch, and existing keybindings
    still work while the minimal Quickshell process is running.
  - Validation: manually exercise the core workflow and record the result.
- [ ] Add a temporary startup command while keeping Polybar and Rofi enabled.
  - Acceptance: Quickshell can be started with the session without removing
    the current fallback shell tools.
  - Validation: restart the session or startup script in a controlled test and
    confirm Polybar/Rofi still work.

## Backlog

- [ ] Replace Polybar with a basic Quickshell panel.
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
