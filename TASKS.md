# dwm-titus Active Tasks

This file tracks the next reviewable work. Product requirements live in
`SPEC.md`; sequencing and long-term scope live in `docs/ROADMAP.md`.

## Completed Phase: Build and Repository Readiness

### Completed in this phase

- [x] Use portable `-O2` optimization by default.
  - Acceptance: `make` produces a binary without host-specific CPU flags.
  - Validation: `make clean && make`.
- [x] Add an opt-in native build.
  - Acceptance: `make native` applies host-specific optimization flags.
- [x] Add build dependency diagnostics.
  - Acceptance: missing `pkg-config` modules are listed before compilation.
- [x] Add staged-install validation.
  - Acceptance: `make check-install` validates binary, man page, scripts, and
    the generated X session entry under a temporary `DESTDIR`.
- [x] Make the X session binary path follow `PREFIX`.
  - Acceptance: staging with `PREFIX=/usr` writes `Exec=/usr/bin/dwm`.
- [x] Make pull-request CI enforce repository checks.
  - Acceptance: CI runs `make check` and does not ignore build failures.
- [x] Resolve compiler truncation warnings in the TOML and layout-symbol paths.
  - Scope: bounded string copies and path construction only; no behavior
    changes.
  - Acceptance: `make clean && make` completes without truncation warnings.
  - Validation: clean build completed without compiler warnings.
- [x] Add guided first-install generation of `config.h`.
  - Acceptance: interactive installs ask stable compile-time questions;
    unattended installs use configurable defaults; existing files are
    preserved.
  - Validation: `make check-build-config`.

### Next tasks

- [x] Untrack `config.h` while preserving the working-tree file.
  - Scope: repository index and contributor documentation only.
  - Acceptance: a clone creates `config.h` from `config.def.h`; upgrades never
    replace a local `config.h`.
  - Validation: clean-clone build and upgrade simulation.
  - Result: index-based clean-checkout build and local-marker upgrade
    preservation simulation passed.
- [x] Define an installation manifest.
  - Scope: replace wildcard installation of `scripts/*` with explicit runtime
    commands, libraries, and data files.
  - Acceptance: install and uninstall touch only listed project-owned paths.
  - Validation: compare staged tree before and after uninstall.
  - Result: staged contents match the explicit manifest and uninstall restores
    the original staged file set.
- [x] Add release checks.
  - Scope: deterministic archive contents, version naming, generated session
    entry, and no object files or local config.
  - Acceptance: `make release-check` validates a newly generated archive.
  - Result: two generated archives are byte-identical and archive content,
    naming, session path, and exclusions are validated.
- [x] Validate the new optional-session duplicate guards.
  - Scope: Feh, Picom, Dunst, polkit, Polybar, and XDG autostart under a
    display manager and `startx`.
  - Acceptance: restarting dwm does not create duplicate long-running
    processes; missing optional commands do not produce session-fatal errors.
  - Validation: `make check-session-guards` validates repeated direct and
    startx-style invocations with isolated process mocks, plus a missing
    optional-command case. A live LightDM session retained a stable Polybar
    process count across repeated startup, and an isolated `startx`/Xvfb
    session started dwm, loaded runtime configuration, exposed EWMH desktops,
    tolerated missing optional helpers, and exited cleanly.

## Current Phase: Installer and Distribution Parity

- [ ] Create one capability-to-package map for Debian, Arch, and RHEL families.
- [ ] Refactor `install.sh`, `install-arm.sh`, and `scripts/check-deps.sh` to
  consume the shared map.
- [ ] Split installer profiles into required, recommended, and optional.
- [ ] Add Debian, Arch, and Fedora/RHEL container smoke tests.
- [ ] Replace remaining Arch-only general documentation.

## Current Phase: Minimal Feature-Complete Desktop

- [x] Select a usable installed terminal at runtime with an actionable fallback
  when none is available.
  - Scope: add a small runtime terminal launcher and make the default hotkey use
    it without changing user-owned `hotkeys.toml` files.
  - Acceptance: `Super+X` resolves the first installed supported terminal, and
    the launcher exits with a clear remediation message when none is available.
  - Validation: `make check-terminal`.
- [x] Add an `xdg-settings` based workflow for browser and default application
  selection.
  - Scope: add `dwm-default-apps` for browser discovery, default browser
    selection through `xdg-settings`, MIME defaults through `xdg-mime`, and
    browser launching with an actionable missing-default message.
  - Acceptance: users can list browser desktop files, set the default browser,
    set a MIME default, and use the default browser hotkey through the helper.
  - Validation: `make check-default-apps`.
- [ ] Add a small display-profile CLI using `xrandr`; profiles remain optional
  user configuration under the XDG config directory.
- [ ] Make Polybar modules capability-driven so missing battery, audio,
  network, temperature, or tray tools hide cleanly.
- [ ] Provide a single diagnostics command that reports required failures and
  optional degraded features separately.
- [ ] Document a minimal session profile that runs only dwm, a terminal, and
  required X11/session services.

## Validation Policy

A task is complete only when its acceptance command passes or the exact skipped
environment is recorded. Runtime and multi-monitor tasks cannot be marked
complete from compile-only validation.
