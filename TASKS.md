# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 1
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`, and
`docs/SETTINGS-PLATFORM.md`.

## Active Phase: Displays and Input

### DISP-001: Display Provider Contract

- [ ] Add a versioned display provider for connected outputs, modes, refresh
  rates, positions, rotations, primary state, profiles, and persistence state.
- [ ] Reuse `dwm-display-profile` and `dwm-display-setup` parsing and validation
  instead of duplicating RandR or Xorg policy in QML.
- [ ] Report unsupported driver properties and missing X11 state explicitly.

Acceptance:

- Discovery is machine-readable and bounded, with fixtures for single-monitor,
  multi-monitor, disconnected-output, malformed-output, and unavailable cases.
- Opening and closing the Displays section starts and stops only section-owned
  watches and helper processes.
- Discovery performs no mutation and requires no authorization.

### DISP-002: Display Layout and Preview

- [ ] Add Settings controls for resolution, refresh rate, position, rotation,
  primary output, output enablement, and saved profiles.
- [ ] Generate a complete proposed layout and validate it before live apply.
- [ ] Add explicit preview, Keep, Revert, timeout, and automatic rollback
  states using the Phase 1 application contract.

Acceptance:

- Every preview captures the previous complete layout before applying changes.
- Rejection, timeout, Settings close, or apply failure restores the previous
  live layout and reports rollback success or failure.
- Keyboard and mouse users can recover without relying on the changed output.

### DISP-003: Persistent Display Profiles

- [ ] Save named user profiles under the existing XDG display-profile path.
- [ ] Define and implement a narrow installed-helper operation for persistent
  managed Xorg fragment install and rollback.
- [ ] Add confirmation, ownership, permission, backup, and polkit-denial tests.

Acceptance:

- Repository, XDG, home-directory, symlinked, or writable helper copies cannot
  be elevated.
- The helper accepts validated structured display data only, never arbitrary
  paths, commands, or Xorg text.
- Persistent install creates an isolated managed fragment and recoverable
  backup without replacing unrelated Xorg configuration.

### INPUT-001: Input Device Provider

- [ ] Discover keyboards, pointers, touchpads, and relevant X11/libinput
  properties by stable device ID.
- [ ] Map layout, repeat, modifier, speed, acceleration, natural scrolling,
  tap-to-click, and other supported properties without assuming every driver
  exposes them.
- [ ] Report unsupported properties per device.

Acceptance:

- Device and property output is machine-readable and handles names containing
  whitespace or punctuation safely.
- Hotplug updates are event-driven where X11 provides a usable event source;
  any fallback is bounded and documented.
- Missing devices or drivers do not break Displays or other Settings sections.

### INPUT-002: Input Changes and Recovery

- [ ] Add per-device Settings controls only for properties reported by the
  provider.
- [ ] Apply session changes to the selected stable device ID and define the
  persistence format and startup application path.
- [ ] Add reset, invalid-value, disconnected-device, and partial-failure
  behavior.

Acceptance:

- A change cannot affect a different device because names or enumeration order
  changed.
- Keyboard changes preserve a documented recovery path that does not require
  the changed layout or modifier.
- Re-running startup application is idempotent and preserves unrelated user
  configuration.

### DI-VALIDATE: Phase 2 Validation

- [ ] Run focused shell, QML, helper, and nested-X11 tests for display and input
  providers and interactions.
- [ ] Validate single- and multi-monitor previews, persistence, restart, and
  rollback in a real Fedora X11 session.
- [ ] Validate available input controls on representative keyboard, pointer,
  and touchpad hardware and record absent hardware.
- [ ] Run the full repository validation and record secondary-platform gaps.

Acceptance:

- Every Phase 2 exit criterion maps to passing automated evidence or a named
  manual check with release, hardware, session, and limitation details.
- No phase is described as hardware- or platform-verified when its required
  environment was not tested.

## Phase Completion

When all Phase 2 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 2 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 3 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
