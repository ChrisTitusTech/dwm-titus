# Phase 4 Integration Evidence

Date: 2026-08-21

## Qualification Scope

This record qualifies Phase 4 Power, Session, Defaults, and XDG autostart on
Fedora Linux 44 x86_64 under X11. Detailed provider and safety contracts remain
in the four feature evidence records. Unsupported physical and destructive
paths are listed explicitly instead of being described as exercised.

## Delivered Workflows

- One root-scoped Power model supplies the panel, Control Center, Settings, and
  the shared session menu. Native UPower and Power Profiles signals remain
  available to the panel; bounded policy snapshots and parent-bound watches run
  only while a consuming surface is open.
- One session-action model exposes Lock, Log Out, Suspend, Reboot, and Shutdown
  from the panel and Settings. Destructive actions retain confirmation,
  overlapping requests are rejected, helper success is strict, and progress or
  failure remains attributed to its initiating surface.
- Defaults manages browser, terminal, file manager, and allowlisted MIME
  handlers through standard XDG state. Writes are serialized, verified,
  rollback-capable, recovery is hash-guarded, and unrelated associations are
  preserved.
- XDG autostart inventory shows origin, effective state, applicability, risk,
  and recovery state. Mutations affect only user overrides, never vendor files,
  and session-critical changes require confirmation.
- The managed status publisher is single-instance per user and X display even
  though its Bash shebang reports `bash` as the process name. Its provider and
  parser children are direct, tracked children and are reaped during teardown.

## Automated Validation

The exact combined worktree passed:

```text
scripts/run-tests make clean all
scripts/run-tests
scripts/run-tests scripts/quickshell-qmllint --root config/quickshell
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
git diff --check
```

The full managed suite includes focused power, session, Defaults, autostart,
status-publisher, package, Kickstart, staged-install, repeated-install,
Quickshell model, and nested-X11 Settings coverage. QML lint retained only the
pre-existing `PanelTooltip.qml` qmltypes warnings and `RunningAppsArea.qml`
warnings; the Phase 4 files introduced no new warning class.

Nested X11 exercised browser, file-manager, terminal, MIME, autostart, power,
and shared session-action surfaces. Settings watchers were exactly one while
their owning pane was open and zero after close. The final full-suite
30-second closed baseline used 0.033 percent of one CPU and the post-workflow
closed sample used 0.000 percent, a 0.033 percentage-point delta against the
0.5-point limit.

The same nested run replaced the Defaults and autostart helpers with fixtures
that emitted exact success-looking records and then exited nonzero. The checked
QML command boundary suppressed both records, retained failure messages, and
left the selected terminal and autostart state unchanged.

Display-manager and `startx` fixture paths each ran autostart twice and retained
one status publisher per display. A separate cross-display case retained one
publisher on each display. The graceful logout fixture used a real nested DWM,
verified `_NET_WM_PID`, invoked the installed-form helper, and observed the
autostop completion marker. Session-action failure fixtures cover unavailable
locker, denied logind requests, stale or replaced DWM identities, and strict
absence of false-success records.

## Live Fedora and Restoration Evidence

- UPower was active with no aggregate battery and no lid hardware. External
  power was online. No battery or physical-lid transition is claimed.
- `power-profiles-daemon` advertised power-saver, balanced, and performance.
  A power-saver mutation converged and the original balanced profile was
  restored.
- DPMS was enabled at 3600 seconds. A reversible 3599-second mutation converged,
  then restored 3600 and the exact original mode-0600 `power.conf` bytes.
- logind reported suspend available. Suspend/resume was not executed in the
  active development session.
- An isolated browser mutation converged all four documented associations and
  restored the original MIME file SHA-256
  `a24288b44458a9287011b9c42d7d66eb095c3d7fc6771b87543486263febf3b8`.
- The live file-manager and `text/plain` mutations converged, then restored the
  same MIME baseline. The stale nonlaunchable `chromium.desktop` entry was
  rejected before mutation.
- The live terminal role is intentionally restricted because the user
  `hotkeys.toml` is a symlink. A regular-file nested-X11 fixture qualified
  terminal mutation, hot reload, Super+X resolution, and exact reset.
- `keyboard-debounce.desktop` was disabled and enabled through a user override,
  then the external backup was restored byte-for-byte with SHA-256
  `fc5e686b5e10c791ae596dd47f8822cd9c670a883ef736ff2b77228e11e87333`.
- Live inspection exposed three extra status-publisher roots and six orphaned
  watcher grandchildren from repeated autostart execution. Each PID, UID,
  start time, command path, and display was checked before termination. The
  original session-owned publisher remained, and the guard plus direct-child
  teardown regression prevents recurrence.

## Explicit Limitations

- This workstation has no battery or lid hardware, so those transitions remain
  fixture-qualified.
- Real suspend/resume, reboot, and shutdown were not initiated because they
  would interrupt the active development and review session. Their fixed
  helper, confirmation, denial, and failure paths are automated.
- No sacrificial real locker was available; lock/unlock remains nested- and
  failure-fixture-qualified.
- Repeated display-manager logout/login and reboot persistence are not claimed.
  Automated fixtures qualify repeated autostart execution and graceful nested
  DWM logout; one fresh real display-manager login remains the final activation
  gate after the reviewed tree is installed.
- The live terminal setting is read-only while the user file remains a symlink.
- `startx` preserves its TTY scope by design. Exact path, UID, and display
  matching prevents repeated-start duplication, but an abandoned publisher
  from an abnormal X-server loss may require scoped cleanup in a future phase.
- The final installed DWM binary requires one logout/login before its graceful
  logout endpoint can be observed in the active session. Installed-file parity
  and the post-login panel/process check are recorded at final synchronization.
