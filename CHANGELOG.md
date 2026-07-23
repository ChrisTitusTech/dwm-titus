# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versions from `config.mk`.

## [Unreleased]

### Added

- A unified, read-only Quickshell Settings foundation with Control Center and
  IPC entry points, searchable keyboard/mouse navigation, and explicit
  provider availability and unsupported-state reporting.
- A versioned `dwm-settings-provider` capability-discovery protocol with
  Fedora-first detection, secondary-platform fallbacks, focused shell/QML/Xvfb
  tests, and a centralized cross-family QML development package profile.
- Settings platform contracts for helper lifecycle, UI states, authorization,
  confirmation, rollback, packaging, and phase validation.
- Cross-compiler, nested-X11, and Debian/Arch/RHEL container validation in CI.
- Repository-owned Quickshell QML lint automation.
- Contributor, security, ownership, dependency-update, and active-task guidance.

### Changed

- The Control Center now uses one clean dropdown card with direct Applications
  and utility entries, in-place secondary pages, and consistent click-away and
  Escape dismissal.
- Power actions now use the same compact menu header, flat rows, spacing, and
  confirmation layout as the Control Center.
- Documentation is built and tested from `docs/src/`; generated mdBook output
  is no longer version controlled.
- Release guidance requires validated, committed source and explicit platform
  coverage.

### Fixed

- Install the PAM integration package alongside GNOME Keyring so LightDM can
  unlock the login keyring without a second password prompt.
- Restore independent Quickshell StatusNotifier tray rendering and resilient
  icon fallbacks for background-only tray clients.
- Prevent nested dwm/Xvfb instances from terminating the active graphical login
  by verifying the logind display and isolating `XDG_DATA_HOME` in runtime tests.

[Unreleased]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.5.0...HEAD
