# Settings Platform Contract

<!-- markdownlint-disable MD013 -->

This document defines the architecture, safety, packaging, and validation
contracts for the unified Settings application, including the Phase 2 display
and input providers. `SPEC.md` remains the product contract, and
`docs/SETTINGS-CAPABILITIES.md` records the provider inventory.

## Application Contract

The Settings application is one Quickshell `FloatingWindow` titled
`dwm settings`. It is part of the managed Quickshell process and is opened from
Control Center -> Settings, through the `settings` IPC target, or
with `dwm-settings`.

### Navigation and Search

- The left navigation contains Displays, Input, Network, Bluetooth, Audio,
  Power, Defaults, Appearance, and System in stable roadmap order.
- Typing in the search field filters section names and descriptions. When the
  first match changes, Settings transitions the section-owned read/watch
  providers; search never mutates desktop state.
- Up and Down move between visible sections, Enter selects the highlighted
  section, Escape closes Settings, and clicking a section selects it.
- Opening Settings resets navigation to Displays and starts one bounded
  discovery snapshot. Refresh starts a new snapshot only when no snapshot is
  already active.
- Closing Settings stops the discovery process, clears transient search state,
  and leaves persistent panel providers untouched.

Phase 1 is intentionally read-only. Capability cards report the operation
class, provider, state, and recovery detail. Unsupported and restricted cards
stay visible when their explanation helps the user; a missing provider never
prevents another section from opening.

## Helper Protocol

The Phase 1 capability snapshot invokes only `dwm-settings-provider discover`
through the fixed `Commands.settingsProviderCommand()` wrapper. Phase 2 uses
equally fixed display actions (`discover`, `watch`, `save`, `preview`,
`preview-profile`, `keep`, `revert`, `install-profile`, and `rollback-system`)
plus the read-only `preview-status` recovery query,
and equally fixed input actions (`discover`, `watch`, `watch-apply`, `preview`,
`keep`, `revert`, `preview-status`, `reset`, and `apply-saved`). QML cannot
supply command strings, executables, arbitrary
paths, or elevation flags; every argument is validated by the owning helper.

The version 1 output is UTF-8, tab-separated, and line-oriented:

```text
settings-protocol<TAB>1
platform<TAB>id<TAB>family<TAB>display-name
capability<TAB>section<TAB>id<TAB>label<TAB>status<TAB>class<TAB>provider<TAB>detail
```

Fields are single-line values with tabs and line breaks replaced by spaces.
Unknown record types may be ignored. A missing or unsupported protocol record
is a provider failure, not an empty capability set.

Capability statuses are:

| Status | Meaning |
| --- | --- |
| `available` | The provider needed for the reported read path is present. |
| `partial` | Some state is readable, but the complete section contract is not available. |
| `unavailable` | A normally supported provider is missing or not usable. |
| `restricted` | Readable state remains available, but an authorization path is absent. |
| `unsupported` | This phase or platform has no supported provider contract. |

Capability classes are `read-only`, `user-session`, `privileged`, and
`delegated`. The broader inventory also treats an operation with no provider as
unsupported; protocol records express that through the `unsupported` status.

The protocol is append-only within version 1. Changing field order, meaning,
or escaping requires a new protocol version and a compatibility test.

## UI and Operation States

All future section implementations use these states. Phase 1 exercises
`loading`, `unavailable`, `failure`, and unsupported state through discovery
and tests. Existing health tests cover restricted authorization while existing
display tests cover preview rollback. Mutation-specific Settings states become
active when the owning roadmap phase adds mutations.

| State | Required behavior |
| --- | --- |
| `loading` | Keep navigation usable, show progress, and prevent overlapping provider launches. |
| `unavailable` | Identify the missing provider or service and give the next action. |
| `permission-denied` | Preserve readable state, clear pending authorization, and allow retry. |
| `failure` | Attribute the error to one provider and leave other sections usable. |
| `dirty` | Show unapplied user changes and require Apply, Reset, or explicit navigation handling. |
| `saved` | Confirm the durable target and the successfully persisted value. |
| `preview` | Show the deadline, previous state, and explicit Keep/Revert actions. |
| `rollback` | Restore captured state automatically on timeout, rejection, close, or provider failure. |

Closing a section must stop watches and child processes that exist only for
that section. Shared event sources required by the persistent panel, such as
the existing NetworkManager and MPRIS streams, remain owned by their shared
models and must not be duplicated by Settings.

## Authorization and Safety Contract

Phase 1 Settings exposes no mutation or elevated operation. Future providers
must follow this boundary:

| Operation class | Allowed execution path |
| --- | --- |
| Read-only | Unprivileged service API or fixed helper snapshot. |
| User-session | Fixed helper action with validated argv that changes only invoking-user state. |
| Privileged | Explicit confirmation followed by an installed, root-owned, non-writable helper with an operation allowlist. |
| Delegated | Fixed launch or service request to a trusted platform tool that owns policy and authorization. |

### Privileged Allowlist Boundary

- No Phase 1 Settings operation is on the privileged allowlist.
- Existing health actions remain limited to failed-service actions,
  NetworkManager, Bluetooth, and time synchronization as specified in
  `SPEC.md`; they are not automatically Settings actions.
- Phase 2 display persistence allows only validated generated-fragment install
  and rollback operations. It does not accept arbitrary paths, Xorg text,
  commands, or environment-selected executables.
- Repository, XDG, home-directory, symlinked, group-writable, and
  other-user-writable helper copies must never be elevated.
- A trusted helper must resolve outside user-writable paths, be owned by root,
  and have no group or other write bits before polkit or sudo executes it.
- Broad passwordless sudo, a generic command runner, arbitrary service names,
  and arbitrary file writes are forbidden.

### Confirmation, Cancellation, Audit, and Rollback

- The UI must describe the exact target, new value, impact, authorization need,
  and recovery path before a privileged or destructive request.
- Closing the confirmation surface, pressing Escape, rejecting polkit, or
  timing out cancels the request and preserves readable state.
- Previewable display changes default to a 15-second rollback deadline. A
  provider must capture the prior state before applying the preview.
- Helpers return a typed operation ID, result, and bounded diagnostic. They
  must not log secrets, passwords, environment dumps, or unbounded command
  output.
- Success is reported only after the provider confirms the mutation. A failed
  persist step after a live preview triggers rollback and reports both results.

The Control Center's legacy terminal `sudo systemctl restart NetworkManager`
action and `dwm-display-setup` terminal sudo flow remain compatibility paths;
neither is a Settings provider contract.

## Fedora-First Packaging Plan

Package ownership stays centralized in `scripts/dwm-packages.sh`. Phase 1 adds
no runtime dependency beyond capabilities already present in the existing
desktop and image profiles.

| Capability | Fedora source | Current image/map status | Secondary behavior |
| --- | --- | --- | --- |
| Settings window | Quickshell 0.3 or newer | `quickshell` is already in both Fedora Kickstarts and `rhel:desktop` | Present in `arch:desktop`; Debian reports the UI unsupported unless Quickshell is installed separately. |
| Capability helper | POSIX shell and base utilities | Installed as a project command; no new package | Portable across all supported families. |
| Display/default state | RandR and XDG utilities | Already in Fedora Kickstarts and required profiles | Family X11/runtime profiles provide equivalents. |
| Network/Bluetooth/audio/power state | NetworkManager, BlueZ, PipeWire/WirePlumber, X11 tools, light-locker | Already in Fedora Kickstarts and desktop profiles | Missing optional providers produce unavailable or partial cards. |
| Authorization discovery | Polkit agent and trusted installed helper | Fedora image already includes a polkit agent; helper installation remains project-owned | Missing authorization leaves read-only state available. |
| QML development | Qt declarative development tools | `rhel:qml-development` maps `qt6-qtdeclarative-devel`; intentionally excluded from runtime images | `arch:qml-development` and `debian:qml-development` own their package names. |

The `qml-development` profile is opt-in developer tooling and is not part of
`required`, `recommended`, `optional`, `full`, or either Kickstart. This avoids
expanding the installed desktop for users who do not develop QML while keeping
all family-specific package names in one map.

## Validation Plan

| Phase 1 exit criterion | Automated evidence | Manual or runtime evidence |
| --- | --- | --- |
| Settings opens and navigates without idle polling | `make check-settings check-quickshell-settings-xvfb check-quickshell-qml` | Open from Control Center, search, use keyboard/mouse navigation, close, and record the closed CPU/process sample. |
| Fedora discovery and clean fallback | `make check-settings` exercises Fedora 44 and Debian 13 fixtures | Run `dwm-settings-provider discover` on the Fedora qualification host and record platform/provider rows. |
| Privilege, rollback, errors, unsupported state | `make check-settings check-system-health check-display-setup` plus source assertions for the no-elevation boundary | Cancel or deny any future authorization prompt; verify readable state remains. Phase 1 has no privileged Settings action to authorize. |
| Existing desktop compatibility | Existing launcher, Control Center, controls, network, health, runtime, install, and preservation checks in `make check` | Verify existing Control Center and hotkeys in the qualification session. |
| Packaging and ownership | `make check-install check-install-manifest check-kickstart` | Verify installed helper ownership when a privileged Settings helper is introduced. None is introduced in Phase 1. |

The nested-X11 test must record window geometry, IPC navigation, keyboard and
mouse selection, Escape close, provider cleanup, and a two-second CPU sample
with Settings closed. A passing sample requires less than 10 percent of one CPU
for the managed Quickshell process and no remaining Settings provider process.

Real Fedora evidence must record release, architecture, session type, Settings
entry path, discovered provider states, CPU/process sample, and limitations.
Nested X11 does not prove real hardware providers. Debian, Arch, and generic
RHEL runtime behavior remains unverified until run in those environments even
when fixture and package-map tests pass.

## Phase 1 Qualification Evidence

Evidence recorded on 2026-07-21:

- Fedora Linux 44, x86_64, X11 reported the `rhel` provider family. RandR,
  NetworkManager, BlueZ, PipeWire Pulse, DPMS, light-locker, XDG defaults,
  themes, system health, and the trusted authorization path were discovered as
  available. Phase 2 display/input mutations and later accessibility/system
  administration remained explicitly unsupported.
- Nested X11 at 1280x800 opened the 980x620 Settings window, exercised IPC,
  keyboard, mouse, search, Escape close, and provider cleanup. The two-second
  closed-window sample measured 0.00 percent of one CPU for Quickshell.
- Fedora 44 and Debian 13 fixtures validated available and unavailable provider
  records. Arch and generic RHEL package names were validated through the
  centralized package map but were not runtime-tested.
- The live Fedora check was read-only. No settings mutation, authorization
  prompt, hardware change, session restart, or managed-shell replacement was
  performed.

## Phase 2 Provider and Qualification Evidence

`dwm-settings-display` and `dwm-settings-input` use append-only, version 1,
tab-separated protocols. Display records describe outputs, modes, current and
preferred rates, rotation, primary state, TearFree capability, profiles, and
persistence. Input records describe stable devices, supported settings, and
device-scoped unsupported settings. Tabs and line breaks in external names are
sanitized. QML passes complete structured argv to fixed helper actions and
does not implement RandR, Xorg, XInput, or libinput policy.

Both sections own event-driven udev discovery watches only while active. A
separate session input watcher debounces add/change events and reapplies saved
values when stable devices return. Display and input previews capture prior
state, expose Keep and Revert, and run an external
watchdog so timeout recovery does not depend on the QML process. Closing
Settings requests immediate rollback; the watchdog remains the final recovery
path if the action process is busy or the shell exits. Display finalization is
atomically claimed so Keep cannot race the watchdog. A failed automatic
rollback retains the captured profile, reports the failure in Settings, and
keeps Revert available for retry.

Input persistence requires a udev serial, physical path, or stable physical
sysfs identity. A device without one remains configurable for the current
session, but Settings reports persistence as unsupported and does not save an
event-node-based identity.

Persistent display installation requires a second UI confirmation and
`pkexec`. The helper must be exactly under an installed project libexec path,
root-owned, non-symlinked, and not writable by group or others. Its installed
`dwm-display-setup` dependency has the same ownership checks. It accepts a
validated X11 display, a caller-owned Xauthority file, and structured profile
records only, then writes only
`/etc/X11/xorg.conf.d/90-dwm-titus-display.conf`. Root-container tests cover
repository copies, wrong ownership, writable files, symlinks, injected input,
and authorization denial.

Evidence recorded on 2026-08-15:

- Fedora Linux 44 x86_64 X11 discovered HDMI-0 and DP-0. A complete current
  two-monitor layout preview timed out and restored the exact captured layout.
- A Logitech G502 pointer acceleration preview and a Glorious GMMK3 keyboard
  layout preview changed the selected stable device and restored its prior
  value after timeout. No touchpad was connected; touchpad discovery and
  supported-property behavior are fixture- and nested-X11-tested only.
- Nested X11 at 1280x800 discovered one display and two virtual input devices,
  verified both section states and lifecycle, and measured 0.00 percent of one
  CPU for Quickshell after Settings closed.
- Debian 13, current Arch, and Fedora 44 containers resolved dependencies,
  built, validated staged install/uninstall, and passed privilege tests. This
  qualifies package/build behavior, not real secondary-platform hardware UI.
- A full Rocky Linux 9 container smoke run is blocked pending a reachable
  package source in the qualification environment; its package map and shell
  fixtures are covered, but the complete Rocky install path is not claimed.
- Generated display persistence, backup, rollback, and input startup reapply
  are automated. A real Xorg logout/login using the generated fragment remains
  a release-session check because performing it would terminate the active
  qualification workspace.
- NVIDIA ForceFullCompositionPipeline remains unimplemented and unqualified;
  the current Phase 2 evidence covers RandR layout handling and supported
  TearFree properties only.
