# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 5
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`, and
`docs/P5-EVIDENCE.md`.

## Verified Checkpoint

Phase 5 completed on 2026-09-02 after its final combined Fedora 44, nested-X11,
live-session, install-parity, restoration, and idle-resource qualification.
Deferred and unavailable paths remain explicit in `docs/P5-EVIDENCE.md`.

Phase 6 must keep Settings and all QML unprivileged. Read state through stable
machine interfaces, delegate broad administration to trusted Fedora tools, and
add a privileged helper only for a narrow allowlisted operation that cannot be
completed safely through an existing service.

## Active Phase: System Management

Keep Phase 6 reviewable through these ordered pull-request boundaries. Finish,
validate, and merge each boundary before starting the next one:

1. System-management capability and privilege inventory.
2. Fedora update status, execution, interruption, and recovery.
3. Regional, account, printer, and software-source entry points.
4. System information, storage, privacy, security, diagnostics, and recovery.
5. Combined Phase 6 qualification.

### SYSTEM-001: Capability and Privilege Inventory

- [x] Inventory every Phase 6 state source and mutation path. Classify each as
  read-only, user-session, privileged, delegated, or unsupported.
- [x] Select stable Fedora service, D-Bus, package-manager, AccountsService,
  CUPS, and system-information interfaces without parsing human-oriented output
  when a machine interface exists.
- [x] Define the shared versioned provider records, per-capability failure
  isolation, event sources, cancellation, authorization-denial behavior, and
  audit fields before adding mutations.
- [x] Record which high-risk tasks remain delegated, including advanced storage,
  firewall policy, and general service administration.

Acceptance:

- QML remains unprivileged and can render readable state when authorization or
  an optional service is unavailable.
- Every proposed mutation has one bounded owner, fixed arguments, explicit user
  intent, and an actionable failure or recovery state.

### UPDATE-001: Fedora Updates

Progress: Read-only PackageKit discovery and its Settings pane are implemented.
The journal now supports durable pending admission, identity-checked lifecycle
transitions, restart pruning, recoverable terminal commits, exact retained-result
lookup, and handoff acknowledgment. Operation owners can retain every journal file
identity across unlocked service waits and reacquire bounded exclusive intervals
for checkpoints; unlocked state access and stale ownership are rejected.
The operation formatter reserves required lifecycle records separately from its
bounded progress budget, validates terminal/audit identity, and replays retained
results without an external action. Observed package comparisons use bounded
counts and mismatch samples plus an arrival-ordered digest; they are not persisted
as an atomic completed plan. The internal PackageKit execution owner now gates
mutations on the installed security floor and running daemon version (with exact
running-executable identity required for the same-version Fedora backport), dispatches
only a durably admitted exact transaction, checkpoints restart signals, and
observes through terminal evidence even after a lost method reply. Persistence
failure suppresses terminal success and permits only narrowly bound cancellation.
Fake-bus coverage exercises these paths without changing host packages. Execution
now repeats bounded inventory and simulation reads and compares the confirmed
generation before creating its mutable transaction. Callers cannot supply their
own package IDs or preview to bypass that check. Fixed, bounded kernel boot and
typed logind session evidence readers are available for recovery integration.
The internal recovery coordinator now uses exact-object adoption and a bounded
active list, plus at most 64 history records for updates only. It distinguishes
lookup failure from absence, checkpoints adopted restart signals, rejects stale
ownership, and durably recovers terminal evidence or conservative interruption.
Previous-boot records cannot reintroduce satisfied guidance. Exact-ID watch and
acknowledgment controls now replay
retained results without a service call or keep a verified PackageKit observer
subscribed through completion without reissuing the action. Finite snapshots now
integrate validated journal recovery, boot/session restart pruning, exact active
identities, and terminal handoffs without hiding readable package discovery.
The exact-ID cancel control now pins the backend peer, revalidates ownership and
cancelability, and records only an accepted cancellation request without claiming
a terminal result. Explicit refresh and generation-confirmed install CLI commands
now use the existing execution owner. Pre-admission failures emit a failed request
without inventing a journal transaction; uncertain admission, output, or later
observation failures retain recovery guidance and never fabricate a terminal
result. A standalone Quickshell parser now validates cumulative raw-byte streams,
preserves split UTF-8, retains bounded progress, and requires matching terminal,
audit, completion, and process-exit evidence. A root-scoped observer now restores
exact active and retained identities from startup snapshots, preserves its stream
across pane closure, verifies results before acknowledgment, and bounds failed
recovery to three retries. Native nested-X11 fixtures exercise live progress,
failed-result replay, stale collector data, restart adoption, and failed process
starts without host service calls.
The root owner now accepts only fixed update origins, enforces origin-specific
exit/result validation, and preserves a bounded verified progress log. A shared
exact-ID cancellation/acknowledgment control preserves the live observer and
reconciles a terminal handoff that wins the cancellation race. Native private
fixtures cover rejected admission, uncertain start, denial, revoked cancellation,
control failure and timeout, and overlap rejection. These internal entry points
are not exposed by IPC. Settings now requires a visible confirmation, fresh
discovery, available recovery and action evidence, and an empty operation owner.
The confirmation copies every package change and invalidates on global events,
replacement reads, generation changes, or closure. Explicit cancellation keeps
the owner alive until a verified outcome. Managed snapshots now offer origins
only after complete, idle recovery and the PackageKit security check; installation
also requires a complete supported dependency preview. A disposable Fedora 44
guest exercised real refresh, signed fixture updates with dependency installation
and obsoletion, stale-generation rejection, authorization denial, retained replay,
and acknowledgment. See `docs/P6-UPDATE-EVIDENCE.md` for exact identities and
limitations. Combined installed-X11 acceptance remains outstanding; real in-flight
cancellation and crash recovery remain fixture-qualified, not guest-qualified.
The fixed `watch-updates` command now observes only global PackageKit discovery
changes and daemon ownership changes. It establishes subscriptions before
reporting readiness, bounds setup to ten seconds, and never starts a transaction.
Private-bus and callback fixtures cover filtering, startup races, cleanup, and
lost output. The pane-scoped subscriber now waits for readiness before its first
discovery read, reserves at most one settling read per automatic burst, and
retains explicit-refresh guidance if that read changes again. Snapshot publication
retains ownership through reentrant completion callbacks. Failed monitoring keeps
finite status readable; pane closure stops the subscriber and optional reads
without stopping required recovery or the root operation owner. PackageKit
observer completion and uncertain exit also invalidate discovery without relying
on a global signal. Confirmation invalidation now guards the visible update UI.
The preview validators now preserve requested `install` as well as `update`
actions, matching the PackageKit DNF5 backend's discovery/simulation contract.
Missing or duplicate requested IDs, outbound requested actions, and unrequested
updates still fail closed. A Fedora 44 / PackageKit 1.3.6 read-only snapshot
preserved all 23 requested IDs in 29 preview rows (five installs, 18 updates,
six removals), without the prior malformed-plan error. No package mutation was
performed; this agent process still lacks a logind session, reported separately
as partial recovery evidence; that session therefore cannot enable execution.

- [x] Add user-initiated Fedora update discovery and status through the selected
  stable package-management interface.
- [x] Add confirmed update execution with transparent progress and logs, strict
  success detection, cancellation, and overlap rejection. Keep an operation
  delegated when the platform cannot expose a safe cancellation contract.
- [x] Distinguish authorization denial, network or repository failure, package
  conflicts, interrupted transactions, completed updates, and reboot guidance.
- [x] Preserve recovery guidance across Settings closure or helper interruption
  without claiming ambiguous success.
- [ ] Complete combined installed Fedora 44 X11 update qualification under
  P6-VALIDATE, including graphical authorization. Record real in-flight
  cancellation, crash recovery, and hardware restart as untested unless exercised;
  the current fixture and guest evidence does not establish those runtime paths.

Acceptance:

- No update begins from passive discovery or without explicit confirmation.
- Read-only update status remains available after authorization denial.
- Interrupted or failed updates identify the owning platform state and a safe
  next action.

### REGIONAL-ENTRY-001: Regional and Delegated Administration

Progress: Pure provider validators now bound timezone and locale choice lists,
require exact selected identities, preserve the full allowlisted locale override
set, and reject undisplayable confirmations without truncation. Effective-locale
comparison accepts redundant LC-category elision while checking preserved values.
The validators perform no I/O. Separate fixed timedate1 and locale1 readers now
bound connection setup, service replies, and decoding under a ten-second deadline.
Typed private-bus tests cover success, denial, absence, malformed state, timeout,
and late replies; read-only Fedora 44 probes also passed. No command, D-Bus
mutation, or new protocol minor is enabled. A separate fixed locale catalog
collector now bounds output, process lifetime, signal cleanup, and reaping, with
an independent timeout supervisor for abrupt collector death. It preserves exact
installed identities and starts a new process for every read. Account/printer/source
readers, lifecycle integration, and Settings controls remain outstanding.

- [ ] Add date, time, timezone, and locale status plus safe common actions
  through stable platform services.
- [ ] Add user-account, printer, and software-source entry points through trusted
  Fedora tools or narrowly scoped helpers where the platform lacks a complete
  delegated workflow.
- [ ] Report missing tools, services, hardware, authorization, and unsupported
  operations per capability without hiding readable state.
- [ ] Preserve existing Settings navigation, keyboard accessibility, X11 focus,
  and closed-pane lifecycle behavior.

Acceptance:

- Delegated launches use fixed allowlisted desktop files or commands and report
  launch failure without false success.
- System changes are confirmed and auditable; QML never receives arbitrary
  privileged command or path construction.

### INFO-RECOVERY-001: Information, Diagnostics, and Recovery

- [ ] Add event-driven or bounded system information and storage overview state
  without a new idle poller.
- [ ] Add privacy and security status, diagnostics, recovery actions, and reset
  guidance with clear ownership and limitations.
- [ ] Keep advanced storage mutation, firewall policy, service administration,
  and other broad or destructive operations delegated unless `SPEC.md` first
  defines a safe narrow contract.
- [ ] Add actionable unavailable, denied, failed, canceled, interrupted, and
  recovery states for every surface.

Acceptance:

- Information remains readable when a mutation is denied or unsupported.
- Recovery and reset actions name their scope, consequences, and platform owner
  before confirmation.

### P6-VALIDATE: Phase 6 Validation

- [ ] Run focused provider, parser, privilege, cancellation, lifecycle, failure,
  recovery, QML, and nested-X11 tests for every Phase 6 workflow.
- [ ] Prove every privileged action is allowlisted, explicitly confirmed,
  auditable, cancelable, and unavailable from repository- or user-writable
  helper copies. Exclude or delegate any operation that cannot meet that
  contract.
- [ ] Exercise authorization denial, interrupted updates, failed delegated tools,
  missing services, and recovery without hiding readable status or reporting
  false success.
- [ ] Run the clean build, full managed repository suite, Quickshell lint,
  ShellCheck, shfmt, staged install, repeated install, and installed-runtime
  parity checks.
- [ ] Qualify Fedora 44 real- or nested-X11 rendering, keyboard navigation,
  common display sizes, closed-surface resource use, and all unavailable
  hardware or service paths.

Acceptance:

- Every Phase 6 exit criterion maps to automated evidence or a named manual
  check with Fedora release, session, restoration, and limitations.
- Authorization denial preserves read-only state, and interrupted or failed
  operations end with actionable recovery guidance.

## Phase Completion

When all Phase 6 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 6 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 7 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
