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

- [x] Create one capability-to-package map for Debian, Arch, and RHEL families.
  - Scope: keep package capability groups in `scripts/dwm-packages.sh` and use
    them from the main installer and dependency checker.
  - Acceptance: `install.sh` and `scripts/check-deps.sh` consume the shared map
    instead of duplicating Debian, Arch, and RHEL package lists.
  - Validation: `bash -n install.sh scripts/dwm-packages.sh scripts/check-deps.sh`,
    `make check-shell`, `make check-format`, `make check-build-config`.
- [x] Refactor `install.sh`, `install-arm.sh`, and `scripts/check-deps.sh` to
  consume the shared map.
  - Scope: merge ARM-specific installer behavior into `install.sh`, keep ARM
    package exceptions in `scripts/dwm-packages.sh`, and leave `install-arm.sh`
    as an ARM-only compatibility wrapper.
  - Acceptance: Arch ARM terminal, framebuffer video-driver, and display
    manager choices come from shared package profiles instead of a separate
    installer implementation.
  - Validation: `bash -n install.sh install-arm.sh scripts/dwm-packages.sh`,
    `make check-shell`, `make check-format`, `make`.
- [x] Split installer profiles into required, recommended, and optional.
  - Scope: add runtime-required package groups, keep recommended desktop
    packages separate from optional extras, and make `install.sh` select core,
    recommended, or full package layers.
  - Acceptance: Debian, Arch, and RHEL families expose non-empty required,
    recommended, optional, and full profiles from the shared map; optional
    extras are skipped with warnings when unavailable.
  - Validation: `bash -n install.sh scripts/dwm-packages.sh scripts/check-deps.sh`,
    `make check-shell`, `make check-format`, `make check-build-config`,
    `make`, and package-map profile count smoke test.
- [x] Add non-interactive installer flags for CI and packaging.
  - Scope: add `--profile`, `--non-interactive`, `--yes`, and `--dry-run`,
    while keeping an explicit package summary before any installing work.
  - Acceptance: interactive runs show the resolved summary before prompting;
    non-interactive and dry-run invocations do not prompt; dry-run exits before
    package, filesystem, or sudo changes.
  - Validation: `bash -n install.sh scripts/dwm-packages.sh`, `./install.sh --help`,
    `./install.sh --dry-run --non-interactive --profile core`,
    `make check-shell`, `make check-format`, `make check-build-config`,
    `make`.
- [x] Add Debian, Arch, and Fedora/RHEL container smoke tests.
  - Scope: add `tests/test-container-smoke.sh` and `make check-container-smoke`
    using Podman or Docker with configurable Debian, Arch, and RHEL-family
    images.
  - Acceptance: each container resolves the required package profile from
    `scripts/dwm-packages.sh`, installs it, runs the installer dry-run summary,
    builds dwm, and validates staged install plus uninstall manifest symmetry.
  - Validation: `make check-shell`, `make check-format`,
    `make check-container-smoke` with `debian:stable-slim`,
    `archlinux:latest`, and `fedora:latest`.
- [x] Verify repeated installation preserves user-owned files.
  - Scope: add `tests/test-install-preservation.sh` and
    `make check-install-preservation` using a temporary repo copy and temporary
    home/XDG directories.
  - Acceptance: two repeated user installs preserve existing `config.h`,
    `.xinitrc`, runtime TOML files, and existing Polybar/Picom app config
    markers.
  - Validation: `bash -n tests/test-install-preservation.sh`,
    `make check-shell`, `make check-format`, `make check-install-preservation`.
- [x] Replace remaining Arch-only general documentation.
  - Scope: update README and `docs/src` install/troubleshooting guidance to
    use cross-distro installer profiles, and make power-management remediation
    hints use the detected package manager.
  - Acceptance: source docs no longer tell all users to run pacman-only package
    commands for general install or troubleshooting paths.
  - Validation: source grep for `pacman`/Arch-only install snippets, `bash -n
    scripts/power-management.sh`, `make check-shell`, `make check-format`.

## Current Phase: Runtime Correctness

- [x] Add an Xvfb/Xephyr regression harness for startup, tags, focus,
  fullscreen, EWMH state, and TOML reload.
  - Scope: add `tests/test-xvfb-runtime.sh` and `make check-xvfb-runtime`
    using Xvfb plus a compiled temporary Xlib client.
  - Acceptance: the harness starts dwm in an isolated X server, validates EWMH
    root startup state, focuses a managed client, switches tags, handles an
    EWMH fullscreen request, and proves TOML hotkey reload.
  - Validation: `make check-xvfb-runtime`, `make check-shell`,
    `make check-format`, `git diff --check`.
- [x] Verify autostart behavior across dwm restart, display-manager login, and
  `startx`.
  - Scope: keep Picom, Dunst, Feh, polkit, and XDG autostart helpers from
    escaping the test harness or duplicating across repeated dwm startup.
  - Acceptance: repeated display-manager and `startx`-style autostart runs
    launch singleton helpers once, rerun Polybar launch cleanly, and tolerate
    missing optional commands.
  - Validation: `sh tests/test-autostart.sh`, `make check-session-guards`,
    `make check-shell`, `make check-format`.
- [x] Make the power menu fit and remain keyboard-usable below 1080p.
  - Scope: expose the generated rofi theme override for tests and validate
    low-resolution display sizing without launching a live rofi session.
  - Acceptance: the power menu stays centered within 1366x768 and 800x600
    displays, uses a scrollable non-fixed list, disables custom input, and
    retains rofi's no-custom script-mode guard.
  - Validation: `make check-powermenu-layout`, `make check-shell`,
    `make check-format`, `git diff --check`.
- [x] Validate missing X properties and malformed `_NET_WM_ICON` data without
  crashing.
  - Scope: make `_NET_WM_ICON` parsing use explicit bounds and extend the Xvfb
    harness with clients missing name/class hints and a truncated icon
    property.
  - Acceptance: dwm keeps running and managing clients with absent optional
    hints or malformed icon data.
  - Validation: `make clean`, `make`, `make check-xvfb-runtime`,
    `make check-shell`, `make check-format`, `git diff --check`.
- [x] Make TOML reload transactional.
  - Scope: reject invalid existing user TOML files without falling back to
    defaults over the current runtime state.
  - Acceptance: a bad user `hotkeys.toml` reload reports the exact file as
    invalid and preserves the previously loaded hotkey bindings.
  - Validation: `make check-xvfb-runtime`, `make`, `make check-shell`,
    `make check-format`, `git diff --check`.
- [x] Fix monitor-to-monitor tag switching so cursor position and Polybar EWMH
  state update together.
  - Scope: guard the cross-monitor `view()` path that switches `selmon`, focuses
    the target monitor/window, warps the cursor, and updates EWMH current
    desktop state.
  - Acceptance: source-level regression covers both cross-monitor handoff and
    already-active target tag paths. Real nested multi-monitor Xinerama coverage
    is deferred to Phase 5 because this host's Xvfb reports only one monitor.
  - Validation: `make check-monitor-tags`, `make`, `make check-shell`,
    `make check-format`.

## Completed Phase: Minimal Feature-Complete Desktop

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
- [x] Add a small display-profile CLI using `xrandr`; profiles remain optional
  user configuration under the XDG config directory.
  - Scope: add `dwm-display-profile` with optional profiles under
    `${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/display-profiles`.
  - Acceptance: users can list profiles, print the profile directory, inspect
    current `xrandr` state, print a template, and apply a profile without
    sourcing user-controlled shell.
  - Validation: `make check-display-profile`.
- [x] Make Polybar modules capability-driven so missing battery, audio,
  network, temperature, or tray tools hide cleanly.
  - Scope: detect Polybar module capabilities in `config/polybar/launch.sh`
    and export module lists plus device names for the minimal theme.
  - Acceptance: missing battery, audio, wireless, wired, temperature, or tray
    capability is omitted from the runtime module list before Polybar starts.
  - Validation: `make check-polybar-capabilities`.
- [x] Provide a single diagnostics command that reports required failures and
  optional degraded features separately.
  - Scope: add `dwm-diagnostics` with separate required and optional desktop
    sections and failure counts.
  - Acceptance: required failures produce a nonzero exit; optional degraded
    features are reported without making the core diagnostic fail.
  - Validation: `make check-diagnostics`.
- [x] Document a minimal session profile that runs only dwm, a terminal, and
  required X11/session services.
  - Scope: document the core-only profile in installation docs and link it from
    the README.
  - Acceptance: required profile components and optional degraded desktop
    features are separated, with `startx` and diagnostic verification steps.
  - Validation: `git diff --check`.

## Validation Policy

A task is complete only when its acceptance command passes or the exact skipped
environment is recorded. Runtime and multi-monitor tasks cannot be marked
complete from compile-only validation.

## Current Phase: Core Maintainability

- [x] Document patch ownership and invariants for EWMH, pertag, swallowing,
  systray, fullscreen, icons, and runtime TOML.
  - Scope: add a Phase 4 maintenance baseline that identifies the owning source
    areas, invariants, and existing regression coverage before extraction work.
  - Acceptance: each named subsystem has documented invariants and validation
    notes, including explicit gaps where direct automated coverage is missing.
  - Validation: `make check`, `git diff --check`.
- [x] Group static declarations and implementation sections by subsystem.
  - Scope: regroup declarations and implementation blocks inside `dwm.c`
    without changing behavior.
  - Acceptance: related patched subsystems are easier to locate and no runtime
    behavior changes.
  - Validation: `make check`.
- [x] Extract runtime TOML loading/reload state behind a narrow interface.
  - Scope: isolate runtime TOML state transitions while preserving
    transactional reload behavior.
  - Acceptance: invalid reloads keep the last valid state and existing hotkey,
    theme, and rule behavior remains covered.
  - Validation: `make check-xvfb-runtime`, `make check`.
- [ ] Extract EWMH property updates behind a narrow interface.
  - Scope: isolate root/client property updates from layout and monitor logic.
  - Acceptance: EWMH state remains synchronized with focus, tag, fullscreen,
    and client-list changes.
  - Validation: `make check-xvfb-runtime`, `make check-monitor-tags`,
    `make check`.
- [ ] Replace unchecked formatting and allocation edge cases in touched paths.
  - Scope: address issues encountered while touching maintainability paths,
    without broad unrelated rewrites.
  - Acceptance: touched paths check allocation and formatting boundaries.
  - Validation: `make check`.
