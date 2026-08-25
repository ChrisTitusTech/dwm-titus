# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versions from `config.mk`.

## [Unreleased]

### Added

- Add versioned user-session wallpaper state through `dwm-settings-wallpaper`,
  with persisted Feh fit modes, bounded preview and automatic rollback,
  external-change protection, reset, interrupted-preview recovery, and a
  legacy random-wallpaper fallback when a saved image disappears. Session
  startup restores the managed choice without writing `~/.fehbg`; one-off
  randomization retains the saved selection for the next session and gives
  previews an exact live rollback baseline. Settings Appearance exposes the
  same candidate, fit, preview, keep, revert, apply, reset, and missing-file
  state through one root-scoped model.

- Begin Phase 5 with a versioned, read-only appearance provider that validates
  the active and available themes, resolves a safe recovery theme, exposes the
  shared semantic palette, and reports GTK, Qt, cursor, terminal, and compositor
  integration failures without modifying user configuration.

- Add transactional theme changes through `dwm-settings-theme`, including
  bounded previews, confirm and revert actions, automatic timeout rollback,
  managed-default reset, hash-guarded interrupted-operation recovery, and the
  existing Control Center selection path. Theme comments, custom definitions,
  file modes, and unrelated settings remain intact. Integration outputs are
  staged and compare-and-swap published, manual applies honor active previews,
  and DWM re-arms hot reload after the user theme directory is first created.

- Add one root-scoped Appearance model as the owner of theme inventory,
  validation, and semantic shell colors, plus a Settings Appearance pane for
  bounded preview, keep, revert, apply, reset, and interrupted-operation
  recovery. Partial toolkit, terminal, cursor, and compositor application is
  reported explicitly, while unsafe ownership or symlink paths keep the pane
  readable and disable mutation.

- Add one shared session-action model for Lock, Log Out, Suspend, Reboot, and
  Shutdown across the panel and Settings. Fixed helper actions require exact
  accepted records, preserve destructive confirmations, attribute failures to
  the initiating surface, reject overlap, and exit only the verified current
  DWM through its cleanup-aware `SIGUSR2` endpoint.

- Add a versioned Defaults provider and Settings pane for browser, terminal,
  file-manager, and selected MIME handlers. Candidate validation, scoped
  transactional writes, exact rollback, hash-guarded recovery, and live
  inotify updates preserve unrelated XDG and hotkey state.

- Add versioned XDG autostart inventory and next-login controls with effective
  state, origin, visibility, risk, and revision records. User overrides are
  backed up and atomically verified; vendor files remain immutable and
  session-critical changes require confirmation.

- Add a shared, versioned power provider and Settings pane for UPower battery
  and external-power state, Power Profiles selection, X11 DPMS, automatic
  locking, logind suspend capability, and lid availability. One parent-bound
  D-Bus monitor refreshes both panel and Settings state without idle polling.
  Dedicated images select `power-profiles-daemon`; existing Fedora installs
  retain any compatible `ppd-service` provider already installed.

- Add a native-first PipeWire audio model and Settings pane for output and input
  selection, volume, mute, microphone visibility, and per-application streams.
  A versioned bounded snapshot protocol supplies inventories, while one
  generation-checked fallback subscription is used only when native state does
  not initialize or disconnects.

- Add shared, versioned NetworkManager and BlueZ provider models and Settings
  panes for Ethernet, Wi-Fi, saved profiles, VPN status, bounded discovery,
  pairing, trust, connection, and removal workflows. Fixed actions preserve
  stable identities, secured Wi-Fi secrets use ephemeral mode-0600 password
  files, and advanced editing remains delegated to trusted platform tools.

- Add a focused large-surface source contract, a private nested-X11
  interaction and screenshot harness, and checked-in before/after review
  evidence for P3-UI4.

- Add an X11-native Quickshell command menu with typed navigation for apps,
  desktop settings and services, screenshots, system actions, and a public
  `menu open|close|toggle|summon` IPC surface. Opening the menu moves the
  pointer into its search field to preserve keyboard focus under DWM.

- Install Gear Lever from a user-scoped Flathub remote by default with the
  recommended/full desktop and both Fedora image variants.

### Changed

- Make DWM's hot-reloaded TOML paths honor `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME`, matching the managed shell and appearance provider.

- Complete Phase 4 Power, Session, Defaults, and XDG autostart integration.
  Fresh Fedora 44 LightDM activation now runs the installed DWM and one managed
  Quickshell shell with one panel per active monitor; unavailable battery, lid,
  destructive power, repeated-login, and real `startx` paths remain explicitly
  qualified instead of overstated.

- Make the Bash-based status publisher single-instance per user and X display
  using exact resolved command-path matching instead of its interpreter process
  name. Track and reap subscription children so repeated session startup cannot
  leave duplicate publishers or orphaned watcher pipelines.

- Complete Phase 3 connectivity, audio, and large-surface integration and make
  Power, Session, and Defaults the active Phase 4 planning boundary. Remaining
  Wi-Fi association and Bluetooth pairing-recovery hardware limits stay
  explicitly recorded rather than being described as verified.

- Restyle Settings, System Health, notification popups/history, and the
  application launcher with a shared presentation-only large-surface header,
  semantic status accents, numbered navigation, and consistent search and card
  treatments while preserving their existing providers, IPC names, X11 titles,
  lifecycle, privilege boundaries, and interaction behavior.

- Restyle the X11 Quickshell panel and its Audio, Bluetooth, Network, Control
  Center, and Power popups with shared Omarchy-inspired hero, separator,
  slider, toggle, and semantic interaction components while preserving DWM
  state, Fedora helpers, IPC, monitor routing, and click-away behavior.

- Consolidate Fedora package, build, install, and privileged-helper validation
  into the existing Fedora CI job, removing the nested container smoke job and
  redundant install and monitor checks. Keep the optional Clang portability
  build available through manual workflow dispatch instead of every push and
  pull request.

- Make Alacritty the direct `Super`+`X` terminal default for every install
  profile and Fedora image. Herdr remains available only through explicit
  `--install-herdr` and `DWM_HERDR=1` opt-ins.

- Move Flatpak and the GTK desktop portal into the recommended Fedora desktop
  layer so AppImage management works in the default X11 session.

- Remove obsolete distribution-matrix Settings and package-family test
  fixtures while retaining the Fedora-only boundary test that proves an
  unsupported installer cannot perform package or system mutations.

### Fixed

- Keep the managed Quickshell recovery scoped to the exact configuration and
  display, validate fixed PID/start-time cohorts before signals, and bound
  graceful and forced recovery so a stale shell cannot suppress the panel or
  terminate another Quickshell instance.

- Apply DPMS and automatic-lock changes before atomically replacing the user
  `power.conf`, reject out-of-range timeouts, and restore the prior live state
  when apply or persistence fails. Verify the restoration and report a distinct
  rollback failure when the exact captured live state cannot be recovered, so
  an unsuccessful change is never shown as saved.

- Restart unexpectedly exited parent-bound NetworkManager and media
  subscriptions after a bounded delay, preserving one live subscription per
  shared root model without polling.

- Bind long-lived NetworkManager and media watcher children to the originating
  Quickshell process identity so an ungraceful shell exit cannot leave orphaned
  subscriptions behind.

- Require root-owned, non-writable parent directories for installed health
  helpers and report administrative authorization available only when polkit
  or noninteractive sudo can actually authorize the operation.
- Preserve command-menu selection when asynchronous application state refreshes
  and tolerate bounded slow X11 window mapping before pointer-focus fallback.

## [0.6.1] - 2026-08-17

### Added

- Interactive Displays and Input Settings panes with versioned, event-driven
  providers; complete display layout previews and named profiles; stable
  per-device input controls; timed rollback; reset; and session persistence.
- A narrow root-owned display helper for confirmed managed Xorg fragment
  installation and rollback, with installed-path, ownership, permission,
  symlink, structured-input, and authorization-denial coverage.
- Fedora hardware, nested-X11, and Fedora 44 container validation for the
  Phase 2 provider, packaging, recovery, and privilege contracts.
- NVIDIA ForceFullCompositionPipeline capability discovery and safe persistent
  defaults, with unsupported drivers left unchanged and incompatible forced-on
  requests rejected.

### Changed

- Narrow platform support, the installer, package mapping, fixtures, and CI to
  Fedora only. Tests now run in a disposable workspace below `$HOME/tmp` and
  remove it after success, failure, or interruption.
- Thunar's seeded **Open Terminal Here** action now launches Alacritty directly
  instead of entering the Herdr workspace.
- Replace Flameshot with the X11-native `maim` capture tool. Saved captures use
  JPEG, active-monitor captures use the monitor under the pointer, and region
  clipboard captures use an `xclip`-owned PNG selection that pastes reliably
  into Chromium-based applications without a monitor chooser or resident
  screenshot daemon.

### Fixed

- Enforce the Fedora-only power-management boundary before any status scan or
  system change, and keep fixture overrides out of the privileged path.
- Reject direct root `make install` calls without a target user before building
  or writing any system files.
- Keep Fedora image XDG parents owned by the installer-created user, run the
  user-scoped install stage without root privileges or ownership-changing
  syscalls, avoid rebuilding user-owned sources during the privileged system
  stage, preserve existing XDG directory modes, make direct root installs drop
  privileges for the user stage, and document a narrow v0.6.0 repair.
- Match generated Xorg OutputClass rules against the DRM driver name, including
  mapping virtio PCI devices to `virtio_gpu`, so saved display layouts survive
  a real Xorg restart. Associate NVIDIA RandR names through per-display driver
  targets so additional DRM providers do not hide supported anti-tearing.
- Remove Quickshell notification cards when their sender closes the underlying
  notification, and dismiss overflow notifications instead of retaining hidden
  objects that can accumulate during a long session.

## 0.6.0 - 2026-08-13 (withdrawn)

> Withdrawn because Fedora image installations could create user XDG
> directories as root. Superseded by v0.6.1.

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
  platform detection, focused shell/QML/Xvfb tests, and a centralized QML
  development package profile.
- Settings platform contracts for helper lifecycle, UI states, authorization,
  confirmation, rollback, packaging, and phase validation.
- Cross-compiler, nested-X11, and container validation in CI.
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

- Remove the unavailable `nwg-look` package from the Fedora dependency and
  Kickstart package sets so Fedora 44 Anaconda installations can resolve the
  complete desktop package transaction. The GTK settings action remains an
  optional delegated tool and is shown only when `nwg-look` is installed.
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

[Unreleased]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/ChrisTitusTech/dwm-titus/compare/v0.5.2...v0.6.1
