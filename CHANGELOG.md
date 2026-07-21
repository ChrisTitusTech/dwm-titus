# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versions from `config.mk`.

## [Unreleased]

### Added

- Cross-compiler, nested-X11, and Debian/Arch/RHEL container validation in CI.
- Repository-owned Quickshell QML lint automation.
- Contributor, security, ownership, dependency-update, and active-task guidance.

### Changed

- Documentation is built and tested from `docs/src/`; generated mdBook output
  is no longer version controlled.
- Release guidance requires validated, committed source and explicit platform
  coverage.

### Fixed

- Prevent nested dwm/Xvfb instances from terminating the active graphical login
  by verifying the logind display and isolating `XDG_DATA_HOME` in runtime tests.

[Unreleased]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.5.0...HEAD
