# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 3
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`,
`docs/P3-UI4-EVIDENCE.md`, `docs/P3-CONNECTIVITY-EVIDENCE.md`, and
`docs/P3-AUDIO-EVIDENCE.md`.

## Active Phase: Power, Session, and Defaults

Phase 4 begins from the merged Settings, connectivity, and audio architecture.
Keep the existing panel Power menu, confirmation boundaries, DWM session
lifecycle, user configuration, and XDG overrides compatible while adding the
full-screen Settings workflows below.

### POWER-001: Power Provider and Settings Workflows

- [x] Define versioned machine-readable records for battery state, external
  power, available power profiles, active profile, DPMS, idle timing,
  automatic locking, suspend support, and lid-policy capability.
- [x] Reuse the standard Power Profiles D-Bus provider, UPower, logind, `xset`,
  and the existing Control Center helper only through stable machine
  interfaces. Dedicated images select `power-profiles-daemon`; the
  existing-system installer retains any compatible `ppd-service` provider
  already installed. Consume UPower
  battery property-change signals; allow bounded sampling only for a documented
  fallback with no event source, and keep every service subscription
  event-driven.
- [x] Add a Power Settings pane for available profile selection, DPMS, lock and
  idle timeouts, and supported suspend/lid behavior. Hide or explain unsupported
  hardware without disabling readable state.
- [x] Separate read-only battery state, user-session DPMS/lock changes,
  delegated logind actions, and privileged persistent system policy.
- [x] Preserve the existing user `power.conf`, panel Power menu, confirmation
  dialogs, and service authorization behavior. Failed writes must not be shown
  as saved.

Acceptance:

- Missing batteries, profile services, X11 DPMS, lock providers, or lid
  hardware fail only the owning capability and leave Settings usable.
- Timeout and numeric arguments are bounded; suspend and policy changes retain
  explicit confirmation and authorization boundaries.
- Panel power state and Settings converge without duplicate providers or idle
  polling, and section-owned work stops on close.

### SESSION-001: Session Actions and Recovery Contract

- [ ] Define one shared root-scoped session action model for lock, logout,
  suspend, reboot, and shutdown that reuses the existing Power menu backend.
- [ ] Attribute action progress and failures to the initiating surface, reject
  overlapping session-ending requests, and retain confirmation for every
  destructive action.
- [ ] Preserve both display-manager and `startx` startup, D-Bus session setup,
  graphical-session target ownership, autostop cleanup, tray startup order,
  and optional-component failure tolerance.
- [ ] Document recovery paths for a failed locker, denied logind action,
  incomplete graphical-session startup, and deferred installed-DWM activation.

Acceptance:

- Authorization denial or service loss cannot be reported as success and does
  not terminate unrelated shell providers.
- Lock, logout, suspend, reboot, and shutdown remain reachable from the panel;
  Settings uses the same action and confirmation contracts.
- Repeated login/logout does not leave duplicate Quickshell, locker, portal,
  status, watcher, or XDG autostart processes.

### DEFAULTS-001: Default Application Management

- [ ] Define versioned records for default browser, terminal, file manager,
  supported MIME handlers, candidate desktop entries, and provider availability
  using XDG interfaces rather than parsing human-oriented launcher output.
- [ ] Extend the existing `dwm-default-apps` contract for validated terminal,
  file-manager, browser, and MIME mutations while preserving current hotkeys
  and safe unavailable behavior.
- [ ] Add a Defaults Settings pane with explicit current values, candidate
  selection, per-MIME changes, reset/recovery behavior, and attributed partial
  failures.
- [ ] Preserve user desktop files and existing MIME associations not selected
  for change. Never invent a default when XDG state is absent or malformed.

Acceptance:

- Changes are visible through `xdg-settings` or `xdg-mime`, survive a fresh
  session, and affect only the selected default or MIME type.
- Invalid or missing desktop entries are rejected before mutation. Missing XDG
  tools fail only Defaults and keep readable state where possible.
- Existing browser and terminal hotkeys resolve through the newly selected
  defaults without changing DWM keybinding contracts.

### AUTOSTART-001: User-Visible XDG Autostart Controls

- [ ] Define versioned records for system and user XDG autostart entries,
  effective enabled state, origin, desktop visibility, and unsupported entries.
- [ ] Add enable and disable actions by creating or updating a user override;
  never edit or delete vendor desktop files.
- [ ] Validate desktop IDs and resolved paths, reject symlink escapes, preserve
  unrelated keys, and back up an existing user override before a material
  rewrite.
- [ ] Add searchable Defaults Settings controls with clear vendor/user origin,
  confirmation where disabling a session component risks loss of desktop
  functionality, and reset-to-vendor behavior.

Acceptance:

- Enable, disable, and reset survive logout/login and match the effective XDG
  autostart state without duplicate launches.
- Existing dwm-scoped overrides for the locker, compositor, and polkit agent
  remain preserved unless the user explicitly changes that exact entry.
- Malformed, missing, hidden, or non-applicable entries degrade per item and do
  not break the Defaults pane or session startup.

### P4-VALIDATE: Phase 4 Validation

- [ ] Run focused shell, provider, QML, helper, and nested-X11 tests for power,
  session, defaults, and autostart workflows.
- [ ] Exercise available battery/profile/DPMS/lock paths and record exact absent
  hardware or services rather than claiming them verified.
- [ ] Exercise default browser, terminal, file manager, representative MIME,
  and XDG autostart changes in an isolated user environment and a real Fedora
  session, restoring the original values afterward.
- [ ] Qualify display-manager and `startx` startup, repeated logout/login,
  destructive-action confirmation, authorization denial, and process cleanup.
- [ ] Compare a 30-second closed baseline with a 30-second sample after opening
  and closing every Phase 4 Settings workflow; the mean Quickshell CPU delta
  must be no more than 0.5 percentage points of one CPU.
- [ ] Run the full Fedora repository validation, staged install, and installed
  runtime checks, and record every untested hardware or reboot path.

Acceptance:

- Every Phase 4 exit criterion maps to automated evidence or a named manual
  check with Fedora release, hardware, session, restoration, and limitations.
- Settings and panel workflows share providers, fail safely, persist through a
  fresh session where required, and leave no duplicate services or autostarts.
- No power, lid, battery, display-manager, or reboot path is described as
  verified when its required environment was unavailable.

## Phase Completion

When all Phase 4 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 4 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 5 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
