# Phase 4 Power Evidence

## Scope and Status

This feature record qualifies POWER-001 on Fedora Linux 44 x86_64. Integrated
Phase 4 completion and SESSION-001 power actions are recorded in
`P4-EVIDENCE.md`; unavailable hardware paths remain explicit below.

POWER-001 implementation, automated gates, nested-X11 lifecycle checks,
available live Fedora service mutations, and fresh-login activation are
complete. The remaining limits are physical hardware and destructive
suspend/resume.

## Host and Service Evidence

- UPower 1.91.3 is active. Its aggregate display device reports no battery,
  `LidIsPresent=false`, and `OnBattery=false`.
- `power-profiles-daemon` 0.30 is installed from Fedora 44 and active. It
  advertises `power-saver`, `balanced`, and `performance`. A delegated change
  to `power-saver` converged and the original `balanced` profile was restored.
- systemd-logind reports `CanSuspend=yes`. Hibernate, hybrid sleep, and
  suspend-then-hibernate report `na`. No suspend was initiated because it would
  interrupt the active development and review session.
- logind reports `suspend` on normal lid close, the default external-power
  action, and `ignore` while docked. The host has no lid hardware, so these are
  read-only policy observations.
- The active X11 server reports DPMS enabled with a 3600-second off timeout.
  The light-locker schema is readable, automatic locking is disabled, and no
  light-locker process is running.

## Automated Evidence

The clean build and full managed repository suite pass. Focused backend,
shared-model, Control Center, Settings, package, Kickstart, staged-install, and
nested-X11 targets pass through the managed test workspace. ShellCheck, shfmt,
Markdown lint, and `git diff --check` pass. Quickshell QML lint retains only the
existing `PanelTooltip` and `RunningAppsArea` warning groups.

Fixtures cover the versioned protocol, aggregate and missing battery state,
external power, lid presence and absence, all supported profiles, provider
loss, logind `yes`, `challenge`, `no`, and `na`, malformed battery data,
strict rejection of empty, exponent-form, and hexadecimal integer fields,
acceptance of serialized exponent-form battery energy rates, bounded arguments,
denied or non-converging actions, failed apply and persistence, exact config
preservation, rollback, external light-locker GSettings event forwarding, and
parent-bound cleanup of both event sources.

The QML contract proves one shared root Power model, one filtered event stream,
generation-checked snapshots and actions, no repeating timer, Settings and
Control Center ownership, per-capability failure rendering, panel convergence,
and reuse of the existing confirmed Power menu.

The completed command set was:

```bash
scripts/run-tests make check-quickshell-power check-quickshell-controlcenter \
  check-settings check-quickshell-settings-xvfb
scripts/run-tests scripts/quickshell-qmllint --root config/quickshell
scripts/run-tests make check-kickstart check-install check-fedora-packages
scripts/run-tests make clean all
scripts/run-tests
DWM_SETTINGS_POWER_CPU_SECONDS=30 \
  scripts/run-tests make check-quickshell-settings-xvfb
```

No required nested-X11 dependency was skipped, and QML lint introduced no new
warning class.

## Live and Restoration Evidence

The installed helper reported external power, no battery, no lid, DPMS enabled
at 3600 seconds, automatic lock disabled, suspend available, effective lid
policy, and all three power profiles. A reversible DPMS change to 3599 seconds
converged, then restored 3600 seconds and the exact original mode-0600
`power.conf` SHA-256. The profile mutation also restored its original value.

Nested X11 proved exactly one power event stream while the pane was open and no
section-owned snapshot, watcher, or monitor after leaving or closing it. A
delayed, explicitly requested DPMS mutation remained root-owned across Settings
closure, completed, retained its Settings-attributed result on reopen, and then
restored the fixture baseline. A 30-second closed baseline used 0.100 percent
CPU; the post-Power-workflow sample used 0.033 percent, a 0.067 percentage-point
delta against the 0.5-point limit.

The managed installation matches this checkout. A fresh Fedora 44 LightDM X11
login activated the installed DWM and managed Quickshell tree with one shell,
one panel per active monitor, and registered tray clients. Actual battery and
lid transitions remain unavailable. Suspend/resume and lid-policy mutation
remain limited to their automated contracts and an appropriate destructive-
action or hardware qualification environment.
