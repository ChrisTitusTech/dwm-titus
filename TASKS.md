# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 2
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`, and
`docs/SETTINGS-PLATFORM.md`.

## Active Phase: Connectivity and Audio

### CONN-001: Connectivity Provider Contract

- [ ] Define versioned machine-readable records for network, VPN, Bluetooth,
  and provider availability without parsing human-oriented status output.
- [ ] Define required fields for a protocol-version header and each record;
  consumers reject a missing or incompatible major version, reject records
  missing required fields, and ignore documented trailing fields and unknown
  record types for append-only compatibility.
- [ ] Reuse the existing NetworkManager and BlueZ helpers where their output,
  lifecycle, and failure contracts are already suitable.
- [ ] Separate read-only state, user-session actions, delegated authorization,
  and unsupported capabilities in provider and QML state.

Acceptance:

- Opening and closing Network or Bluetooth starts and stops only section-owned
  watches, scans, and helper processes.
- Missing services, adapters, or commands fail only the owning section and do
  not break the Settings shell or core desktop session.
- Provider fixtures cover available, unavailable, restricted, malformed, and
  action-failure records.

### NET-001: Network and VPN Workflows

- [ ] Add Ethernet, Wi-Fi, saved connection, active connection, and VPN status
  to Settings using NetworkManager-owned interfaces.
- [ ] Add scan, saved-profile activation, Wi-Fi connection, disconnect, and
  forget actions with explicit progress and failure states. Bound scans to 10
  seconds, activation and connection to 90 seconds, and disconnect or forget
  to 15 seconds; cancellation terminates the owning helper, cleans temporary
  state, and performs no automatic retry.
- [ ] Delegate advanced, hidden, enterprise, and VPN editing to a trusted
  NetworkManager tool when the workflow is not safely owned by Settings.

Acceptance:

- Secrets reach the fixed NetworkManager helper only over its stdin and a
  caller-owned mode-0600 temporary `nmcli --passwd-file`. The helper authorizes
  only the invoking user, redacts diagnostics, and removes the file on success,
  failure, cancellation, timeout, or signal. Secrets never appear in argv,
  logs, provider records, or persistent QML state.
- Authentication cancellation and service loss leave readable state available
  and do not report the requested action as successful.
- Existing panel network state and Settings converge after each change without
  overlapping polling or duplicate long-lived monitors.

### BT-001: Bluetooth Workflows

- [ ] Add adapter power, bounded discovery, known-device, paired, trusted, and
  connected state using BlueZ-owned interfaces.
- [ ] Add pair, trust, connect, disconnect, and remove actions with per-device
  progress and attributed failures.
- [ ] Carry one validated canonical device address or stable BlueZ object path
  through every request, progress record, completion callback, and error.
- [ ] Report adapter, daemon, hardware, and operation support separately.

Acceptance:

- Discovery stops on section close, timeout, or shell exit and cannot leave a
  background scan running indefinitely.
- A failed, cancelled, or late operation re-resolves and mutates only its stable
  identity; it cannot target a name, enumeration position, or another device.
- Real adapter/device tests cover pairing recovery and service unavailability;
  absent hardware is recorded rather than described as verified.

### AUDIO-001: PipeWire and WirePlumber Provider

- [ ] Define event-driven output, input, stream, volume, mute, default-device,
  and microphone-visibility records using PipeWire/WirePlumber-compatible
  interfaces.
- [ ] Reuse native Quickshell PipeWire signals where stable and provide one
  documented bounded fallback when native state is unavailable.
- [ ] Start one fallback subscription only after native initialization fails or
  disconnects within three seconds. Increment a source generation on every
  transition, ignore events from older generations, terminate the fallback on
  section close or native recovery, and hand new snapshots back to native state
  without overlapping subscriptions.
- [ ] Keep audio and media provider failures independent.

Acceptance:

- Settings adds no audio polling timer and starts no overlapping subscription
  process while a native or shared event source is active.
- Device removal, default changes, service restart, and malformed fallback
  output degrade cleanly without stale success state.
- Provider fixtures cover multiple sinks, sources, applications, and no-audio
  environments.

### AUDIO-002: Audio Controls and Panel Synchronization

- [ ] Add output and input selection, volume, mute, per-application stream, and
  microphone controls only when reported by the provider.
- [ ] Make one root-scoped audio service model authoritative for the panel and
  Settings. Tag mutations with an origin and monotonic generation, reject stale
  generations, and suppress echoed events at their originating surface so both
  consumers converge without feedback loops.
- [ ] Add bounded value validation, partial-failure reporting, and reset or
  recovery behavior for disappearing devices and streams.

Acceptance:

- Common output, input, mute, volume, and application-stream workflows no
  longer require a terminal on the qualified Fedora session.
- A Settings action updates the panel and an external PipeWire change updates
  Settings without reopening either surface.
- Service unavailability and authorization cancellation do not hide readable
  state or affect unrelated sections.

### CA-VALIDATE: Phase 3 Validation

- [ ] Run focused shell, QML, provider, helper, and nested-X11 tests for all
  connectivity and audio interactions.
- [ ] Exercise NetworkManager workflows with a real Fedora Ethernet or Wi-Fi
  connection, including cancellation and service-unavailable recovery.
- [ ] Exercise BlueZ workflows with a real adapter and device, or record the
  exact hardware path that remains unqualified.
- [ ] Exercise PipeWire/WirePlumber outputs, inputs, application streams, and
  microphone state in a real Fedora session.
- [ ] Verify closed Settings sections leave no scans, duplicate subscriptions,
  or overlapping commands. Compare a 30-second closed baseline with a
  30-second sample after opening and closing each section; the mean Quickshell
  CPU delta must be no more than 0.5 percentage points of one CPU.
- [ ] Run the full repository validation and record secondary-platform gaps.

Acceptance:

- Every Phase 3 exit criterion maps to passing automated evidence or a named
  manual check with release, hardware, session, and limitation details.
- Common network, Bluetooth, and audio workflows work without a terminal on the
  qualified Fedora session, fail safely, and remain synchronized with panel
  controls.
- No phase is described as hardware- or platform-verified when its required
  environment was not tested.

## Phase Completion

When all Phase 3 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 3 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 4 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
