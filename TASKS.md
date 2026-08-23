# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 4
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`,
`docs/P4-EVIDENCE.md`, and the four detailed Phase 4 evidence records.

## Active Phase: Personalization and Accessibility

Phase 5 begins from the merged Settings platform and semantic theme adapter.
Keep DWM, X11, Fedora providers, runtime TOML files, existing keybindings, panel
geometry, and user-owned configuration compatible while adding the workflows
below. Do not begin Phase 6 system-management work in Phase 5 changes.

Keep Phase 5 reviewable through these ordered pull-request boundaries. Finish,
validate, and merge each boundary before starting the next one:

1. Read-only appearance inventory and validation protocol.
2. Transactional theme preview, apply, reset, and recovery helper.
3. Shared root appearance model and Settings theme pane.
4. Wallpaper, toolkit, font, cursor, icon, and panel-widget persistence slices,
   split further when one slice cannot remain independently reviewable.
5. Accessibility and notification policy, with UI-5 candidates kept in their
   own later review boundaries.

### THEME-001: Shared Appearance Provider and Safe Theme Changes

- [x] Define a versioned machine-readable provider for the active theme,
  available themes, semantic colors, toolkit state, and per-capability errors.
- [x] Add a user-session transaction helper for bounded preview, confirm,
  automatic or explicit rollback, apply, reset, and interrupted-operation
  recovery without replacing unrelated theme configuration.
- [ ] Add one root-scoped appearance model shared by Settings and existing shell
  surfaces without duplicating the `Theme.qml` or `themes.toml` ownership path.
- [ ] Add a Settings Appearance pane with theme preview, apply, reset, and
  recovery behavior. Preserve comments, custom themes, file mode, and unrelated
  user configuration.
- [ ] Make partial GTK, Qt, terminal, cursor, or compositor application failures
  visible without reporting the selected theme as fully applied.

Acceptance:

- Invalid, missing, duplicate, or incomplete theme records cannot prevent DWM,
  Quickshell, Settings, or an existing theme from loading.
- Preview is bounded and rolls back automatically unless confirmed. Apply and
  reset are transactional, attributed, and converge through hot reload.
- Existing Control Center theme selection remains compatible with the shared
  provider until its presentation can be migrated without behavior drift.

### APPEARANCE-001: Wallpaper, Fonts, Cursors, Icons, and Toolkit Integration

- [ ] Define event-driven inventory and state contracts for wallpaper, supported
  fonts, cursors, icons, GTK, Qt, and compositor integration using stable Fedora
  or X11 interfaces.
- [ ] Add wallpaper selection, fit mode, preview, reset, and missing-file
  recovery without scanning while the Appearance pane is closed.
- [ ] Add bounded user-session controls for supported font, text-size, cursor,
  icon, GTK, and Qt choices. Delegate advanced toolkit editing to a trusted
  Fedora tool where a narrow project contract would be incomplete.
- [ ] Move the existing in-memory panel-widget visibility controls onto shared,
  versioned user state with Settings integration, safe defaults, and migration
  that preserves the current Control Center behavior.
- [ ] Preserve optional-component behavior: missing Picom, Feh, toolkit themes,
  wallpaper directories, or delegated tools must fail only their capability.

Acceptance:

- Selected appearance state persists through a fresh session and follows the
  shared theme where appropriate without overwriting unrelated toolkit files.
- Panel-widget visibility persists through a fresh session, stays consistent on
  every active monitor, and does not duplicate panel models or providers.
- Preview, apply, interruption, rollback, reset, missing-asset, and external-
  change paths converge with explicit status and no orphaned watcher.
- Visible shell surfaces remain opaque, X11-native, correctly stacked, and
  usable at the existing panel and popup geometry contracts.

### ACCESSIBILITY-001: Practical X11 Accessibility and Notification Policy

- [ ] Define capability records for text scaling, contrast, reduced motion,
  notification policy, and practical keyboard or pointer accessibility features
  available through supported Fedora/X11 interfaces.
- [ ] Add accessible Settings controls with keyboard navigation, visible focus,
  usable common display sizes, explanatory unavailable states, and reset.
- [ ] Apply reduced-motion and contrast choices consistently to managed
  Quickshell surfaces without introducing a Wayland, compositor, or polling
  dependency.
- [ ] Add notification behavior controls that preserve the existing D-Bus owner,
  history lifecycle, urgency semantics, and safe failure isolation.

Acceptance:

- Accessibility state persists and is observable through the owning platform or
  managed interface after a fresh session.
- Missing X11 extensions or optional tools degrade per capability and never make
  Settings, notifications, or the shell unavailable.
- Keyboard-only navigation, text scaling, contrast, reduced motion, notification
  delivery/history, and reset behavior pass nested-X11 and real-session checks.

### P5-UI5: Optional X11-Native Experience Integration

- [ ] Inventory UI-5 candidates, beginning with event-driven clipboard history,
  and record an adopt, defer, or reject decision for each candidate.
- [ ] Evaluate every adopted UI-5 experience as an independent review boundary
  with an event-driven provider, explicit data ownership, bounded lifecycle,
  privacy model, and Fedora package impact before implementation.
- [ ] Integrate only approved X11-native experiences into the existing semantic
  design system and command surfaces; do not copy Wayland, Hyprland, layer-shell,
  UWSM, or Omarchy service/plugin backends.
- [ ] Preserve current IPC names, X11 focus/click-away/stacking behavior, monitor
  selection, and closed-surface near-idle behavior.

Acceptance:

- Every inventoried candidate has a recorded adopt, defer, or reject decision.
- Every adopted experience has focused source, helper, lifecycle, nested-X11,
  package/install, and privacy tests.
- Closing a surface leaves no resident scan, duplicate subscription, helper,
  sensitive history owner, or overlapping process.

### P5-VALIDATE: Phase 5 Validation

- [ ] Run focused parser, helper, QML, lifecycle, rollback, and nested-X11 tests
  for every Phase 5 workflow.
- [ ] Exercise reversible appearance and accessibility changes on Fedora 44,
  restore exact original state, and record unavailable toolkit or X11 paths.
- [ ] Compare a 30-second closed baseline with a 30-second sample after opening
  and closing every Phase 5 Settings workflow; the mean Quickshell CPU delta
  must be no more than 0.5 percentage points of one CPU.
- [ ] Run the clean build, full managed repository suite, Quickshell lint,
  ShellCheck, shfmt, staged install, repeated install, and installed-runtime
  parity checks.
- [ ] Qualify a fresh LightDM login, fixture or real `startx`, multi-monitor and
  common display-size rendering, optional-component loss, and recovery after an
  invalid theme or missing asset.

Acceptance:

- Every Phase 5 exit criterion maps to automated evidence or a named manual
  check with Fedora release, session, restoration, and limitations.
- Invalid themes or missing assets cannot prevent login or shell startup.
- Accessibility choices persist, remain keyboard-usable, and do not add idle
  polling, duplicate providers, or orphaned work.

## Phase Completion

When all Phase 5 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 5 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 6 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
