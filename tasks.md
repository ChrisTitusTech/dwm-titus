# Active Project Tasks

`SPEC.md` defines the product contract. This file tracks active and recurring
implementation work. The completed Quickshell migration remains documented in
`docs/ROADMAP.md` as historical context.

## Current Maintenance

- [x] Guard graphical-session cleanup against nested X11 displays.
- [x] Isolate Xvfb runtime tests from live XDG data paths.
- [x] Add CI coverage for GCC, Clang, nested X11, and all supported distribution families.
- [x] Add repository-owned Quickshell QML linting.
- [x] Stop tracking generated mdBook output and validate documentation in CI.
- [x] Add contributor, security, changelog, ownership, and dependency-update policy.

## Recurring Release Qualification

- [ ] Run `make check` from a clean release commit.
- [ ] Run `make check-xvfb-runtime check-monitor-tags` in isolated X11.
- [ ] Run `make check-container-smoke` for Debian, Arch, and RHEL families.
- [ ] Run `make check-quickshell-qml` and the managed shell runtime checks when QML changes.
- [ ] Record tested distributions, architectures, X11 environments, and known limitations.
- [ ] Update `CHANGELOG.md`, build reproducible artifacts, and verify published checksums.
