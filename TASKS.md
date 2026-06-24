# dwm-titus Active Tasks

This file tracks the next reviewable work. Product requirements live in
`SPEC.md`; sequencing and long-term scope live in `docs/ROADMAP.md`.

## Current Phase: Build and Repository Readiness

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

### Next tasks

- [ ] Untrack `config.h` while preserving the working-tree file.
  - Scope: repository index and contributor documentation only.
  - Acceptance: a clone creates `config.h` from `config.def.h`; upgrades never
    replace a local `config.h`.
  - Validation: clean-clone build and upgrade simulation.
- [ ] Define an installation manifest.
  - Scope: replace wildcard installation of `scripts/*` with explicit runtime
    commands, libraries, and data files.
  - Acceptance: install and uninstall touch only listed project-owned paths.
  - Validation: compare staged tree before and after uninstall.
- [ ] Add release checks.
  - Scope: deterministic archive contents, version naming, generated session
    entry, and no object files or local config.
  - Acceptance: `make release-check` validates a newly generated archive.
- [ ] Resolve compiler truncation warnings in the TOML and layout-symbol paths.
  - Scope: bounded string copies and path construction only; no behavior
    changes.
  - Acceptance: `make clean && make` completes without truncation warnings.
- [ ] Validate the new optional-session duplicate guards.
  - Scope: Feh, Picom, Dunst, polkit, Polybar, and XDG autostart under a
    display manager and `startx`.
  - Acceptance: restarting dwm does not create duplicate long-running
    processes; missing optional commands do not produce session-fatal errors.

## Next Phase: Installer and Distribution Parity

- [ ] Create one capability-to-package map for Debian, Arch, and RHEL families.
- [ ] Refactor `install.sh`, `install-arm.sh`, and `scripts/check-deps.sh` to
  consume the shared map.
- [ ] Split installer profiles into required, recommended, and optional.
- [ ] Add Debian, Arch, and Fedora/RHEL container smoke tests.
- [ ] Replace remaining Arch-only general documentation.

## Validation Policy

A task is complete only when its acceptance command passes or the exact skipped
environment is recorded. Runtime and multi-monitor tasks cannot be marked
complete from compile-only validation.
