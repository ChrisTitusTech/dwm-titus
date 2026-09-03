# Fedora-Only Desktop Environment Roadmap

## Mission

dwm-titus is expanding from an opinionated dwm build into a cohesive
X11 desktop environment. The product is a complete Fedora desktop installed
from the official Fedora Server Network Install ISO or onto an existing Fedora
installation.

The desktop keeps dwm as the small window-management core and Quickshell as the
managed shell and settings layer. New features must preserve existing keybinds,
runtime TOML configuration, X11 behavior, and the ability to use the session
when optional components fail.

## Delivery Model

- Fedora is the only supported distribution, implementation target, and
  release-qualification target.
- Fedora 44 Server Network Install is the current canonical image base.
- Standard and NVIDIA image variants remain separate.
- No other distribution is part of the product, installer, test, or release
  contract.
- Wayland-native support remains out of scope.
- The Settings experience will be hybrid: common desktop controls belong in a
  cohesive Quickshell application, while high-risk administration is delegated
  to trusted Fedora tools or narrowly scoped privileged helpers.

## Planning Rules

`SPEC.md` defines the durable product contract. This roadmap defines ordered
outcomes. `TASKS.md` contains detailed work only for the active numbered
product phase and may order that phase into multiple reviewable pull-request
slices.

A phase may advance only when its exit criteria are validated and remaining
limitations are recorded. Completed implementation belongs in `CHANGELOG.md`
and release history rather than in a permanent checked-off task list.

## Integrated Omarchy-Inspired X11 UI Delivery

Status: Integrated into the numbered roadmap; `P3-UI4` is complete in PR #163

The Omarchy-inspired overhaul is not a second roadmap. Its visual and
interaction work is folded into the existing Fedora product phases while DWM,
X11, Fedora providers, helpers, IPC, and session policy remain authoritative.
The `UI-1` through `UI-6` names identify the approved review boundaries from
the design plan; the `P3-UI4` form identifies where a slice belongs in the
product roadmap.

- UI-1, semantic theme tokens and shared controls: Phase 3 prerequisite,
  complete in PR #157.
- UI-2, DWM command menu and shared launcher model: Phase 3 prerequisite,
  complete in PR #158 and corrective PR #160.
- UI-3, panel and existing quick panels: Phase 3 prerequisite, complete in
  PR #159.
- P3-UI4, Settings, System Health, notifications, and launcher: complete in
  PR #163.
- UI-5, optional X11-native experiences: candidate review complete in Phase 5
  with no adopted runtime experience.
- UI-6, whole-shell integration hardening: planned for Phase 7 image and
  release qualification, with no major features.

### Integrated Boundaries

- Reuse `themes.toml`, root-scoped state models, installed helpers, IPC names,
  window titles, X11 surface types, and the existing 30px panel contract.
- Do not ship Wayland, Hyprland, layer-shell, UWSM, `wl-*`, or Omarchy service
  and plugin backends.
- Keep `P3-UI4` visual and interaction focused. Phase 3 provider and action
  work was delivered in the later, separate PR #164 and PR #166 slices.
- Keep lock, polkit, idle, power, and background policy on the existing X11 and
  Fedora implementations.
- Treat an event-driven clipboard-history backend as a separate review boundary
  if UI-5 adopts it.

### Integrated Delivery Order

UI-1 is the merged foundation. UI-2 and UI-3 were parallel children and are
now unified on `main`. `P3-UI4` established the shared large-surface language
used by the completed Phase 3 provider work and the later power, defaults,
personalization, accessibility, and system-management phases. Phases 3 and 4
are complete and product Phase 5 is active. The UI-5 review adopted no runtime
experience; any future reopening requires a new roadmap decision and an
independent review boundary. UI-6 closes the desktop during Phase 7 release
qualification.

### UI Overhaul Exit Criteria

- Every converted surface preserves its backend, lifecycle, IPC, X11 focus,
  click-away, stacking, and monitor-selection behavior.
- Managed QML contains no Wayland or Hyprland runtime dependency.
- Focused source checks, Quickshell lint, nested-X11 interaction tests, the full
  managed repository suite, and real-session manual checks pass.
- Closed surfaces leave no resident list models, scans, duplicate subscriptions,
  or overlapping helper commands, and the mean idle CPU delta remains within
  0.5 percentage points of one CPU.
- The final approved revision is synchronized through
  `scripts/dev-sync-install.sh`, with installed parity and any required
  logout/login activation gate recorded.

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
- Fedora packaging and dependency requirements with clean unavailable states
  for missing hardware or services.

### Exit Criteria

- The Settings shell opens and navigates without adding idle polling.
- Read-only capability discovery works on Fedora and degrades cleanly when a
  Fedora service or hardware capability is absent.
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

## Phase 2: Displays and Input

Status: Complete (2026-08-15)

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
- Default to TearFree or Full Composition Pipeline where the driver supports
  it, selecting the compatible option and falling back to existing dwm
  behavior.

### Exit Criteria

- Single- and multi-monitor changes survive session restart when saved.
- Rejected or unconfirmed display previews return to the previous layout.
- Input changes affect only the selected device and preserve a recovery path.
- Nested-X11 tests cover safe behavior; hardware limitations are recorded.

### Implementation and Qualification Evidence

- Fedora Linux 44 x86_64 X11 discovered two active outputs. A complete no-op
  two-monitor preview applied and returned to the byte-equivalent captured
  layout after the two-second watchdog timeout.
- A Logitech G502 pointer-speed preview and a Glorious GMMK3 keyboard-layout
  preview both changed only the selected stable device and automatically
  restored the prior value. No touchpad was connected, so touchpad behavior is
  fixture- and nested-X11-tested but not hardware-qualified.
- Nested X11 at 1280x800 discovered one output and two virtual input devices,
  exercised Displays and Input section lifecycle, closed cleanly, and measured
  0.00 percent Quickshell CPU while closed.
- Fedora 44 container validation resolved the XInput packages, built the
  project, validated staged install/uninstall symmetry, and passed the
  root-helper trust and authorization-denial tests.
- Named profile persistence, generated managed-fragment install/backup/rollback,
  and idempotent input startup apply are automated. In a Fedora 44 UEFI VM,
  root-owned mode-0644 generated fragments preserved both a non-default
  single-output mode and a two-output 1024x768 plus 800x600 layout across real
  LightDM/Xorg restarts. Xorg logs confirmed that the managed OutputClass and
  both monitor sections were applied.
- The restart qualification exposed and fixed a driver-matching defect: the
  generated OutputClass now maps the virtio PCI bus driver to Xorg's
  `virtio_gpu` DRM driver name.
- On representative NVIDIA hardware, both active outputs reported
  ForceFullCompositionPipeline availability and the active NVIDIA MetaMode
  confirmed it enabled. Generated persistence enables the NVIDIA option by
  default, leaves unsupported drivers unchanged, and rejects an explicit
  forced-on request on incompatible drivers.
- No physical touchpad was available. This limitation does not affect the
  Fedora Phase 2 exit criteria.

## Phase 3: Connectivity and Audio

Status: Complete (2026-08-21)

### Objective

Provide desktop-grade network, Bluetooth, and sound management.

### Outcomes

- NetworkManager-backed Ethernet, Wi-Fi, saved connection, and VPN status and
  actions, with secrets handled by trusted platform facilities.
- Bluetooth discovery, pairing, connection, trust, and removal workflows.
- Output and input device selection, volume, mute, per-application streams, and
  microphone visibility through PipeWire/WirePlumber-compatible interfaces.
- Event-driven updates with bounded command execution and no overlapping polls.
- Omarchy-inspired large-surface styling for Settings, System Health,
  notifications, and the application launcher, using the merged design system
  without changing their providers or X11 contracts.

### Exit Criteria

- Common connection and audio workflows no longer require a terminal.
- Authentication cancellation and service unavailability fail safely.
- Existing panel quick controls remain synchronized with Settings.
- The converted large surfaces preserve their existing IPC, focus, lifecycle,
  privilege, and backend behavior in real and nested X11 sessions.

### Completion Evidence

- PR #163 completed the large-surface visual integration while preserving the
  existing Settings, System Health, notification, launcher, IPC, focus, and X11
  contracts in real and nested sessions.
- PR #164 added shared versioned NetworkManager and BlueZ providers, fixed
  bounded actions, secret-safe Wi-Fi handling, real Ethernet, adapter, and
  discovery qualification, and explicit delegation for advanced workflows.
- PR #166 added the native-first shared PipeWire model, bounded versioned audio
  inventory, output/input/stream workflows, generation-checked fallback, and
  real Fedora output, microphone, and application-stream qualification.
- The managed clean build and full repository suite passed. The active X11
  session retained exactly one NetworkManager and one media subscription, no
  native-overlapping audio fallback, and a 0.000 percentage-point Quickshell
  CPU delta after every Settings section was opened and closed.
- The host had no Wi-Fi adapter, so real Wi-Fi association and authentication
  remain fixture-qualified. Bluetooth adapter and discovery were qualified,
  but pairing recovery remains fixture-qualified because no sacrificial device
  was available. These limitations are recorded in the Phase 3 evidence files.

## Phase 4: Power, Session, and Defaults

Status: Complete (2026-08-22)

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

### Completion Evidence

- PR #168 delivered the shared Power and session-action models, transactional
  default-application management, XDG autostart controls, event-driven provider
  lifecycle, and Fedora package/install integration.
- The clean build, full managed repository suite, Quickshell lint, focused shell
  checks, nested-X11 workflows, and exact-head hosted checks passed. Reversible
  live power, browser, file-manager, MIME, and autostart mutations converged and
  restored their recorded baselines.
- After installation, a fresh Fedora 44 LightDM X11 login ran the installed DWM
  byte-for-byte, launched one managed Quickshell instance with one panel per
  active monitor and tray clients, and passed user acceptance of the Phase 4
  Settings and confirmation surfaces. The observed upgrade login reached DWM
  and Quickshell without retries or duplicate processes; the active DWM now
  owns the bounded completion-aware logout path.
- Battery and lid transitions remain fixture-qualified because this workstation
  has neither device. Actual suspend, reboot, and shutdown were not executed;
  their confirmation, authorization-denial, fixed-command, and failure paths are
  automated. Real `startx` and repeated destructive login cycles also remain
  fixture-qualified.

## Phase 5: Personalization and Accessibility

Status: Active (reconciled 2026-09-02; UI-5 review complete, final qualification pending)

### Current Checkpoint

The shared theme provider and transactions are complete. Appearance inventory,
wallpaper persistence, managed-shell fonts and scaling, and desktop font,
cursor, icon, GTK, and Qt controls are merged through PR #184. Panel-widget
persistence merged in PR #186, and cross-capability optional-component
qualification merged in PR #188, completing `APPEARANCE-001`. Managed-shell
contrast and motion controls merged in PR #202, practical XKB input
accessibility controls merged in PR #203, and notification Do Not Disturb and
bounded popup duration merged in PR #204. The current decision record defers
clipboard history and reminders, rejects emoji/symbol and generic image
pickers, and adopts no UI-5 runtime work. Combined Phase 5 qualification
remains open.
`docs/P5-STATUS.md` maps every active checkbox to its current evidence or next
action.

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

Deliver a repeatable Fedora-only desktop installation and upgrade experience.

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
- Unsupported or untested Fedora hardware paths are stated precisely in
  release notes.

## Future Evaluation

After the Fedora phases are stable, evaluate additional accessibility work,
sharing and peripheral workflows, and whether a Wayland successor should be a
separate project. The distribution scope remains Fedora-only; expanding it is
outside this roadmap.
