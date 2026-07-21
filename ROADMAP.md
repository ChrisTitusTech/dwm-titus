# Fedora-First Desktop Environment Roadmap

## Mission

dwm-titus is expanding from an opinionated dwm distribution into a cohesive
X11 desktop environment. The primary product is a complete Fedora desktop
installed from the official Fedora Server Network Install ISO. The existing
installer for Debian, Arch, Fedora, and RHEL-family systems remains supported
as a secondary path.

The desktop keeps dwm as the small window-management core and Quickshell as the
managed shell and settings layer. New features must preserve existing keybinds,
runtime TOML configuration, X11 behavior, and the ability to use the session
when optional components fail.

## Delivery Model

- Fedora is the first implementation and release-qualification target.
- Fedora 44 Server Network Install is the current canonical image base.
- Standard and NVIDIA image variants remain separate.
- Debian, Arch, and generic RHEL-family installs retain the core desktop
  contract. New settings capabilities may arrive later on those systems and
  must report or hide unsupported operations cleanly.
- Wayland-native support remains out of scope.
- The Settings experience will be hybrid: common desktop controls belong in a
  cohesive Quickshell application, while high-risk administration is delegated
  to trusted Fedora tools or narrowly scoped privileged helpers.

## Planning Rules

`SPEC.md` defines the durable product contract. This roadmap defines ordered
outcomes. `TASKS.md` contains detailed work only for the active phase.

A phase may advance only when its exit criteria are validated and remaining
limitations are recorded. Completed implementation belongs in `CHANGELOG.md`
and release history rather than in a permanent checked-off task list.

## Phase 1: Settings Platform Foundation

Status: Complete (2026-07-21)

### Objective

Establish the architecture and safety boundaries for one discoverable Settings
application without changing existing desktop behavior.

### Outcomes

- A settings capability model that distinguishes readable state, user-session
  changes, privileged system changes, and unsupported operations.
- A single Quickshell Settings window with stable navigation and an entry point
  from the existing Control Center.
- Event-driven state providers and small, testable helper interfaces.
- A strict privilege boundary: QML remains unprivileged, privileged operations
  are allowlisted, and every system change requires explicit user intent.
- Fedora-first packaging and dependency requirements with clean fallbacks on
  secondary platforms.

### Exit Criteria

- The Settings shell opens and navigates without adding idle polling.
- Read-only capability discovery works on Fedora and degrades cleanly elsewhere.
- Privilege, rollback, error, and unsupported-state behavior are documented and
  covered by focused tests.
- Existing Control Center, launcher, hotkeys, and runtime configuration remain
  compatible.

### Completion Evidence

- The managed Quickshell shell provides one searchable Settings window with
  Control Center and IPC entry points and no polling timer.
- `dwm-settings-provider` reports versioned read-only capability records and
  clean unavailable, restricted, and unsupported states.
- Fedora 44 X11 discovery, nested-X11 keyboard/mouse navigation, provider
  cleanup, and a closed-window CPU sample passed. The full repository check and
  existing nested-X11 runtime tests also passed.
- Authorization, helper ownership, confirmation, cancellation, error, preview,
  rollback, packaging, and validation contracts are recorded in
  `docs/SETTINGS-PLATFORM.md`.
- Arch and generic RHEL package mappings and Debian fallback records were
  statically validated, but real secondary-platform Settings sessions and real
  input/display hardware behavior remain Phase 2 qualification work.

## Phase 2: Displays and Input

### Objective

Make common monitor and input changes available from the Settings application.

### Outcomes

- Display discovery, resolution, refresh rate, position, rotation, primary
  output, and profile management built on the existing display helpers.
- Preview and timed rollback for display changes that could make the session
  unusable.
- Keyboard layout, repeat rate, modifier behavior, pointer speed, acceleration,
  natural scrolling, tap-to-click, and device-specific input controls where the
  X11 driver exposes them.
- Clear reporting when a driver or device does not support a requested setting.

### Exit Criteria

- Single- and multi-monitor changes survive session restart when saved.
- Rejected or unconfirmed display previews return to the previous layout.
- Input changes affect only the selected device and preserve a recovery path.
- Nested-X11 tests cover safe behavior; hardware limitations are recorded.

## Phase 3: Connectivity and Audio

### Objective

Provide desktop-grade network, Bluetooth, and sound management.

### Outcomes

- NetworkManager-backed Ethernet, Wi-Fi, saved connection, and VPN status and
  actions, with secrets handled by trusted platform facilities.
- Bluetooth discovery, pairing, connection, trust, and removal workflows.
- Output and input device selection, volume, mute, per-application streams, and
  microphone visibility through PipeWire/WirePlumber-compatible interfaces.
- Event-driven updates with bounded command execution and no overlapping polls.

### Exit Criteria

- Common connection and audio workflows no longer require a terminal.
- Authentication cancellation and service unavailability fail safely.
- Existing panel quick controls remain synchronized with Settings.

## Phase 4: Power, Session, and Defaults

### Objective

Unify normal session behavior and application defaults.

### Outcomes

- Power profiles, battery status, idle policy, DPMS, suspend, lid behavior, and
  lock timing with explicit capability checks.
- Default browser, terminal, file manager, and MIME handler management through
  standard XDG interfaces.
- User-visible XDG autostart controls that preserve vendor files and existing
  user overrides.
- Consistent logout, reboot, shutdown, lock, and recovery behavior.

### Exit Criteria

- Settings survive logout and reboot without duplicate services or autostarts.
- Destructive power actions keep confirmation and authorization boundaries.
- Defaults are visible through standard XDG inspection tools.

## Phase 5: Personalization and Accessibility

### Objective

Make the desktop appearance and interaction model configurable as one system.

### Outcomes

- Theme, wallpaper, font, cursor, icon, GTK, Qt, panel-widget, and notification
  controls backed by shared theme data.
- Text size, contrast, reduced-motion, notification, and other practical X11
  accessibility options supported by the selected components.
- Preview, reset, and rollback behavior for appearance changes.

### Exit Criteria

- Supported applications and shell surfaces follow the selected appearance.
- Invalid themes or missing assets cannot prevent login or shell startup.
- Accessibility choices persist and are usable at common display sizes.

## Phase 6: System Management

### Objective

Cover the system tasks users reasonably expect from a desktop environment
without turning Quickshell into an unrestricted administration console.

### Outcomes

- User-initiated Fedora update status and installation with transparent logs,
  failure reporting, and reboot guidance.
- Date, time, timezone, locale, user-account, printer, and software-source entry
  points through stable platform services or trusted Fedora tools.
- System information, storage overview, privacy/security status, diagnostics,
  recovery actions, and reset guidance.
- Advanced storage changes, firewall policy, service administration, and other
  high-risk tasks remain delegated unless a later specification defines a safe
  narrow interface.

### Exit Criteria

- Every privileged action is allowlisted, confirmed, auditable, and cancelable.
- Read-only status remains available when authorization is denied.
- Interrupted updates and failed delegated tools produce actionable recovery
  guidance rather than ambiguous success.

## Phase 7: Fedora Image and Release Qualification

### Objective

Deliver a repeatable Fedora-first desktop installation and upgrade experience.

### Outcomes

- Fedora Server Network Install remains the documented minimal base.
- Standard and NVIDIA Kickstarts, package manifests, repository policy, and
  first-boot behavior are qualified against the supported Fedora release.
- Installation, upgrade, migration, rollback, and recovery paths preserve user
  data and managed configuration ownership.
- VM and hardware matrices cover UEFI, legacy BIOS where supported, common
  display configurations, audio, networking, suspend, and NVIDIA limitations.

### Exit Criteria

- A clean supported Fedora image installs, reboots, and reaches a usable dwm
  session with the documented desktop features.
- Kickstart syntax, package resolution, ISO construction, and first boot are
  recorded for each released image.
- Unsupported or untested hardware and secondary-platform gaps are stated
  precisely in release notes.

## Future Evaluation

After the Fedora-first phases are stable, evaluate broader feature parity for
Debian, Arch, and generic RHEL-family systems, additional accessibility work,
sharing and peripheral workflows, and whether a Wayland successor should be a
separate project. These are not current commitments.
