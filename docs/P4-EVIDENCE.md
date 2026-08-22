# Phase 4 Integration Evidence

Date: 2026-08-22

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

## Final Activation and Manual Acceptance

- PR #168 merged as `7b4b64e8da8abbb280580c36f99e43f15faecc4f` after
  exact-head validate, Quickshell QML, CodeQL, documentation, and CodeRabbit
  checks passed. Three actionable review threads posted after merge were
  corrected and regression-tested in the Phase 4 closeout.
- `scripts/dev-sync-install.sh` synchronized the final closeout and reported
  every managed file current. After a
  fresh LightDM login, `/proc/529804/exe`, `/usr/local/bin/dwm`, and the checkout
  DWM all had SHA-256
  `63b7edf38b957f9659a8b66831065c3ffcca0bb71820cc474885fbf8766882c1`.
- The active Fedora 44 X11 session had one managed Quickshell instance, two
  visible 30-pixel panels for the two active monitors, six registered tray
  items, an available Power provider, and no Defaults or autostart watcher
  workspace after Settings closed. The user manually accepted the visible
  panel, Settings, Power menu, confirmation, and normal-launch behavior.
- LightDM authentication and Xauthority setup succeeded without retry or error.
  The observed login reached DWM and Quickshell within about three seconds and
  completed `graphical-session.target` without a retry, timeout, or duplicate
  shell process. The journal records the previous target stopping before the
  new session completed, but one login does not establish that ordering as the
  cause of the perceived delay or prove its future recurrence.
- The final helper-only synchronization replaced the on-disk DWM inode while
  the accepted session remained active. The running deleted inode, installed
  binary, and checkout still had the same SHA-256 above; no DWM or QML source
  changed in the closeout, so a second disruptive logout was not required.

## Explicit Limitations

- This workstation has no battery or lid hardware, so those transitions remain
  fixture-qualified.
- Real suspend/resume, reboot, and shutdown were not initiated because they
  would interrupt the active development and review session. Their fixed
  helper, confirmation, denial, and failure paths are automated.
- No sacrificial real locker was available; lock/unlock remains nested- and
  failure-fixture-qualified.
- An actual reboot and repeated real display-manager cycles are not claimed.
  Persistent file state, startup replay, repeated display-manager and `startx`
  autostart execution, process cleanup, and graceful nested DWM logout are
  fixture-qualified; one fresh real display-manager login completed the
  installed activation gate.
- The live terminal setting is read-only while the user file remains a symlink.
- `startx` preserves its TTY scope by design. Exact path, UID, and display
  matching prevents repeated-start duplication, but an abandoned publisher
  from an abnormal X-server loss may require scoped cleanup in a future phase.
