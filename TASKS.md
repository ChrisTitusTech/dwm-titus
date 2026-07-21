# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Do not
copy future phases here until the current phase meets its exit criteria.

## Active Phase: Settings Platform Foundation

### SET-001: Capability Inventory

- [ ] Inventory existing Control Center, display, network, Bluetooth, audio,
  power, theme, default-application, and system-health interfaces.
- [ ] Classify every candidate operation as read-only, user-session,
  privileged, delegated, or unsupported.
- [ ] Record Fedora providers and secondary-platform fallback behavior.

Acceptance:

- Each planned Settings section has an owner, state source, mutation path,
  privilege class, failure behavior, and validation method.
- No QML component is designated to execute arbitrary elevated commands.

### SET-002: Settings Application Contract

- [ ] Define navigation, search, section lifecycle, and Control Center entry
  behavior for one Settings window.
- [ ] Define helper input/output contracts without exposing shell command
  construction to QML.
- [ ] Define loading, unavailable, permission-denied, failure, dirty, saved,
  preview, and rollback states.

Acceptance:

- The contract covers keyboard and mouse use on X11.
- Closing a section stops watches and helper processes that are no longer
  needed.
- Unsupported capabilities are hidden or explained without breaking the rest
  of the application.

### SET-003: Authorization and Safety Design

- [ ] Define the allowlist and polkit boundary for future privileged helpers.
- [ ] Define confirmation, timeout, rollback, audit, and cancellation rules.
- [ ] Define installed-helper ownership and permission requirements.

Acceptance:

- Repository and user-writable helper copies can never be elevated.
- Denied or unavailable authorization leaves readable state usable.
- No proposed operation requires broad passwordless sudo access.

### SET-004: Fedora-First Packaging Plan

- [ ] Map Phase 1 runtime and development capabilities to Fedora packages.
- [ ] Identify which capabilities already exist in the current Kickstarts and
  shared dependency map.
- [ ] Define clean behavior for Debian, Arch, and generic RHEL-family installs
  when a Fedora-specific provider is unavailable.

Acceptance:

- No package list is duplicated across future implementation paths.
- Fedora-specific functionality does not weaken the existing core installer
  contract for secondary platforms.

### SET-005: Phase 1 Validation Plan

- [ ] Define focused tests for capability discovery, helper contracts,
  unsupported states, authorization denial, and process cleanup.
- [ ] Define nested-X11 interaction checks and a real Fedora runtime checklist.
- [ ] Define an idle CPU/process sample with the Settings window closed.

Acceptance:

- Every Phase 1 exit criterion maps to an automated check or a named manual
  validation with required evidence.
- Untested environments and hardware cannot be reported as verified.

## Phase Completion

When all Phase 1 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 1 status and any changed assumptions in `ROADMAP.md`.
3. Replace this file's active task set with Phase 2 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
