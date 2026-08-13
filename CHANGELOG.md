# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versions from `config.mk`.

## [Unreleased]

## [0.6.0] - 2026-08-13

### Added

- A developer live-install synchronization command that builds, backs up,
  installs, verifies all managed files, safely coordinates Quickshell
  activation, and reports the remaining dwm session-restart boundary.
- A checksum-verified Herdr installer and default Herdr-on-Alacritty terminal
  workspace for recommended, full, and dedicated Fedora image installs, with
  automatic integration setup for detected Codex and Claude Code CLIs.
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

- `Super`+`P` now captures only the active monitor instead of combining all
  monitors into one Flameshot image, and all screenshot modes omit the cursor.
- Plain `dwm-terminal` launches now open Herdr when available, while explicit
  command launches bypass Herdr and retain the existing terminal-emulator
  contract.
- The Control Center now uses one clean dropdown card with direct Applications
  and utility entries, in-place secondary pages, and consistent click-away and
  Escape dismissal.
- The panel audio widget now shows the current volume percentage beside the
  speaker icon and hides the percentage when audio is unavailable.
- Multi-monitor panels now keep popup and Control Center navigation on the
  invoking screen and show only the workspaces owned by that monitor.
- The managed Quickshell bar now appears on every active monitor, with
  panel-triggered popups anchored to the monitor where they were opened.
- Power actions now use the same compact menu header, flat rows, spacing, and
  confirmation layout as the Control Center.
- Documentation is built and tested from `docs/src/`; generated mdBook output
  is no longer version controlled.
- Release guidance requires validated, committed source and explicit platform
  coverage.

### Fixed

- Keep Quickshell notifications and panel-transient control popups above normal
  client windows while preserving true fullscreen applications above every
  shell surface through one centralized X11 stacking pass, returning input
  focus to fullscreen when a hidden panel popup requests it.
- Map Quickshell panels even when their geometry is reconciled before dwm
  receives the initial map request.
- Keep tray context menus above managed windows, start a single tray-owning
  Flameshot daemon with a sanitized X11 environment, and default to its native
  X11 capture backend when no explicit backend preference is configured.
- Keep the Quickshell bar above normal desktop windows while allowing true
  fullscreen applications to cover it without panel redraw flashes.
- Keep `install-herdr --dry-run` side-effect free, have `install.sh` skip
  unsupported automatic ARMv7 installs, and warn when a preserved legacy
  terminal hotkey bypasses Herdr.
- Install the PAM integration package alongside GNOME Keyring so LightDM can
  unlock the login keyring without a second password prompt.
- Restore independent Quickshell StatusNotifier tray rendering and resilient
  icon fallbacks for background-only tray clients.
- Prevent nested dwm/Xvfb instances from terminating the active graphical login
  by verifying the logind display and isolating `XDG_DATA_HOME` in runtime tests.

[Unreleased]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.5.2...v0.6.0
