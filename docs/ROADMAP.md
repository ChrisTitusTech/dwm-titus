# dwm-titus Roadmap

## Product Direction

dwm-titus is an opinionated, minimal X11 desktop built around dwm. "Feature
complete" means the requirements in `SPEC.md` are implemented, documented,
and validated across the supported distribution families. It does not mean
adding every desktop feature to the window-manager process.

The project follows these rules:

- Keep the C core focused on window management and X11 integration.
- Prefer small command-line helpers and standard freedesktop interfaces over
  new resident services.
- Keep optional visual components replaceable and failure-tolerant.
- Add dependencies only when they are available on Debian, Arch, and RHEL
  families and materially improve a required capability.
- Require a regression test before extracting tightly coupled code from
  `dwm.c`.
- Treat GUI configuration as optional tooling, not part of the core runtime.

## Phase 0: Build and Repository Readiness

Goal: make every change reviewable and prevent known portability regressions.

- [x] Use portable compiler optimizations by default and keep native tuning
  opt-in.
- [x] Fail early when required `pkg-config` modules are missing.
- [x] Validate staged installation with `DESTDIR`.
- [x] Generate the display-manager `Exec` path from `PREFIX`.
- [x] Run build, shell, and staged-install validation in pull requests.
- [x] Resolve compiler truncation warnings in TOML and layout-symbol handling.
- [x] Validate the implemented duplicate-process guards for Picom, Dunst, Feh,
  and polkit in both display-manager and `startx` sessions.
- [x] Stop tracking generated/local build configuration such as `config.h`
  without deleting an existing user's file.
- [x] Define one source of truth for installable scripts and data files.
- [x] Add release artifact validation and a documented release checklist.

Exit criteria:

- `make check` passes from a clean checkout.
- CI blocks merges on compile, shell, or staged-install failures.
- A non-default `PREFIX` produces a working session entry.

## Phase 1: Installer and Distribution Parity

Goal: provide one safe installation workflow for every supported family and
architecture.

Audit status: package capability mappings now live in
`scripts/dwm-packages.sh` and are consumed by `install.sh` and
`scripts/check-deps.sh`. ARM-specific terminal, video-driver, and display
manager package exceptions now live in the shared map and are selected by
`install.sh`; `install-arm.sh` remains as a compatibility wrapper. Required,
recommended, optional, and full package profiles are now separated in the
shared map and selected by `install.sh`. The manual installation docs still
include Arch-family commands, and there is no current roadmap-linked container
target that validates Debian, Arch, and Fedora/RHEL together.

- [x] Move package capability mappings into one data module used by the
  installer and dependency checker.
- [x] Merge ARM handling into `install.sh`; keep architecture-specific package
  exceptions in the shared dependency map.
- [x] Separate required build/runtime packages from recommended desktop
  packages and optional extras.
- [ ] Add non-interactive flags for CI and packaging while preserving an
  explicit interactive summary for users.
- [ ] Add container validation for one Debian, one Arch, and one Fedora/RHEL
  representative.
- [ ] Verify that repeated installation preserves `config.h`, runtime TOML,
  `.xinitrc`, and application configuration.
- [ ] Remove Arch-only commands from general documentation and diagnostics.

Exit criteria:

- Each family resolves and installs the same required capabilities.
- Clean build and staged install pass in all three family containers.
- Unsupported derivatives fail clearly or require explicit family selection.

## Phase 2: Runtime Correctness

Goal: stabilize the required desktop behavior before adding new features.

Audit status: current-tree evidence is not sufficient to check off these tasks.
The autostart guard test exists, but `make check-session-guards` currently
fails in the live desktop environment while validating the Picom duplicate
guard, so the autostart verification item remains unchecked until that path
passes reliably.

- [ ] Add an Xvfb/Xephyr regression harness for startup, tags, focus,
  fullscreen, EWMH state, and TOML reload.
- [ ] Fix monitor-to-monitor tag switching so cursor position and Polybar EWMH
  state update together.
- [ ] Make the power menu fit and remain keyboard-usable below 1080p.
- [ ] Make TOML reload transactional: invalid files retain the last valid
  configuration and report the exact file and error.
- [ ] Validate missing X properties and malformed `_NET_WM_ICON` data without
  crashing.
- [ ] Verify autostart behavior across dwm restart, display-manager login, and
  `startx`.

Exit criteria:

- Core window-management actions have automated smoke coverage.
- Known multi-monitor and low-resolution bugs are closed with regression tests.
- Invalid or missing optional configuration cannot terminate the session.

## Phase 3: Minimal Feature-Complete Desktop

Goal: complete the product requirements without moving desktop policy into
`dwm.c`.

- [x] Select a usable installed terminal at runtime with an actionable fallback
  when none is available.
- [x] Add an `xdg-settings` based workflow for browser and default application
  selection.
- [x] Add a small display-profile CLI using `xrandr`; profiles remain optional
  user configuration under the XDG config directory.
- [x] Make Polybar modules capability-driven so missing battery, audio,
  network, temperature, or tray tools hide cleanly.
- [x] Provide a single diagnostics command that reports required failures and
  optional degraded features separately.
- [x] Document a minimal session profile that runs only dwm, a terminal, and
  required X11/session services.

Exit criteria:

- dwm remains usable without Polybar, Picom, Dunst, wallpaper, or a preferred
  terminal.
- Every default keybinding either works with required dependencies or reports a
  clear remediation.
- Display-manager and `startx` sessions satisfy the runtime criteria in
  `SPEC.md`.

## Phase 4: Core Maintainability

Goal: reduce risk in the patched C core after behavior is covered by tests.

- [ ] Document patch ownership and invariants for EWMH, pertag, swallowing,
  systray, fullscreen, icons, and runtime TOML.
- [ ] Group static declarations and implementation sections by subsystem.
- [ ] Extract runtime TOML loading/reload state behind a narrow interface.
- [ ] Extract EWMH property updates behind a narrow interface.
- [ ] Replace unchecked formatting and allocation edge cases in touched paths.
- [ ] Keep layout and event-loop code in `dwm.c` unless extraction measurably
  improves clarity without increasing coupling.

Exit criteria:

- Extracted modules have direct tests or runtime regression coverage.
- No extraction adds blocking work to the X event loop.
- The default binary and runtime dependency footprint do not materially grow.

## Phase 5: Release Qualification

Goal: make support claims evidence-based.

- [ ] Run clean installer validation on current Debian/Ubuntu, Arch, and
  Fedora/Rocky representatives.
- [ ] Run real or nested X11 validation for single- and multi-monitor behavior.
- [ ] Validate x86_64 and one supported ARM system.
- [ ] Publish known limitations, tested versions, upgrade notes, and checksums.
- [ ] Tag a release only after the acceptance criteria in `SPEC.md` are met.

## Deferred and Out of Scope

These items may live in separate optional projects or documentation, but they
do not belong in the core roadmap:

- Plymouth, GRUB hiding, bootloader changes, proprietary driver installation,
  and automatic security-policy changes.
- A Wayland compositor.
- Bundled gaming-stack installation or hardware-specific gaming setup.
- A mandatory GUI for hotkeys, themes, or window rules.
- A new daemon when a script, XDG interface, or existing session service is
  sufficient.
