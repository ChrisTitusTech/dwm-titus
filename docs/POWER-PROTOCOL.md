# Power Provider Protocol

## Purpose

`dwm-quickshell-controlcenter power-snapshot` exposes the power state used by
the shared Quickshell Power model. It combines the UPower display device,
Power Profiles D-Bus service, systemd-logind capability state, X11 DPMS, and
the existing light-locker and `power.conf` policy without granting QML a
generic command or privileged interface.

The same root-scoped model supplies the panel battery indicator and the Power
Settings pane. Service events request a new bounded snapshot; they do not
carry trusted state directly into QML.

## Version and Parsing

Records are tab-separated. The first record is:

```text
power-protocol  1  MINOR
```

Consumers require major version `1`, ignore unknown record types and trailing
fields, and reject a known record with missing required fields. Text fields
must not contain tabs or newlines. Boolean fields use `yes` or `no`.
Percentages are integers from 0 through 100, and timeout values are seconds.

The top-level provider record describes the combined surface:

```text
provider  power  available|partial|restricted|unavailable  ACCESS  DETAIL
```

Individual records remain authoritative for their own capability. A missing
battery, profile service, X11 display, locker, logind service, or lid does not
invalidate unrelated readable state.

## State Records

<!-- markdownlint-disable MD013 -->

```text
power-dpms  STATE  ENABLED  TIMEOUT  user-session  DETAIL
power-lock  STATE  ENABLED  TIMEOUT  RUNNING  user-session  DETAIL
power-external  on|off|unknown  DETAIL
```

```text
power-battery  STATE  CHARGE_STATE  PERCENT  TIME_TO_EMPTY  TIME_TO_FULL  ENERGY_RATE  DETAIL
```

```text
power-lid  STATE  open|closed|unknown  read-only|delegated  DETAIL
power-lid-policy  STATE  BATTERY_ACTION  EXTERNAL_ACTION  DOCKED_ACTION  read-only  DETAIL
power-profile-support  STATE  read-only|delegated  DETAIL
power-profile  PROFILE_ID  active|available
power-suspend  STATE  read-only|delegated  DETAIL
```

<!-- markdownlint-enable MD013 -->

`STATE` is `available`, `partial`, `restricted`, or `unavailable`. Battery
state is the aggregate UPower display device. `CHARGE_STATE` is `charging`,
`discharging`, `empty`, `full`, `pending-charge`, `pending-discharge`, or
`unknown`.
UPower reports time values in seconds and energy rate in watts. A system with
no battery emits a valid unavailable battery record rather than inventing a
charge value.

The profile inventory accepts only `power-saver`, `balanced`, and
`performance`. The helper also verifies that a requested profile is currently
advertised by the D-Bus service before changing `ActiveProfile`. Service and
polkit policy remain responsible for authorization.

Suspend is capability state only in POWER-001. `yes` and `challenge` from
logind are represented as available, `no` as restricted, and `na` or an absent
service as unavailable. Actual lock, logout, suspend, reboot, and shutdown
coordination belongs to SESSION-001 and retains the existing Power menu
confirmation boundary.

Lid state comes from UPower. The lid-policy record reads logind's effective
battery, external-power, and docked actions. Each action is `default`,
`ignore`, `poweroff`, `reboot`, `halt`, `kexec`, `suspend`, `hibernate`,
`hybrid-sleep`, `suspend-then-hibernate`, `lock`, or `unknown`. Policy remains
read-only in Settings; the user-writable helper is never elevated to edit it.

## Actions

The fixed user-session actions are:

```text
dwm-quickshell-controlcenter power-profile-set power-saver|balanced|performance
dwm-quickshell-controlcenter power-dpms on|off
dwm-quickshell-controlcenter power-dpms-timeout SECONDS
dwm-quickshell-controlcenter power-lock on|off
dwm-quickshell-controlcenter power-lock-timeout SECONDS
```

DPMS and lock timeouts must be decimal integers from 60 through 86400.
Malformed and out-of-range values fail instead of being silently coerced.
DPMS and lock changes are applied through bounded `xset` and `gsettings`
commands. The mode-0600 user `power.conf` is replaced atomically only after
the live operation succeeds. If apply or persistence fails, the helper returns
failure, attempts to restore the prior live state, leaves the prior file in
place, and emits no success record or notification.

## Events and Lifecycle

Native Quickshell UPower and Power Profiles signals update the shared panel and
Settings model. While either Power Settings or the Control Center Power page
is visible, `power-watch` adds one parent-bound system-bus monitor for UPower,
Power Profiles, and logind. The model debounces event bursts into bounded
snapshots and does not use a repeating timer. Closing the last owning surface
stops snapshot, watch, debounce, and restart work.

An explicitly requested mutation is root-owned and bounded, so closing its
initiating surface does not interrupt apply, persistence, or rollback midway.
Its result remains attributed to the initiating surface and the next open
refreshes the visible state. The helper binds its monitor child to the
originating Quickshell PID and process start time so an ungraceful shell exit
cannot leave an orphaned system-bus monitor.

Settings IPC exposes the same generation-checked DPMS action used by the pane,
plus busy and origin-scoped result state. This keeps nested and live lifecycle
qualification on the real shared model instead of a test-only implementation.

## Failure Boundaries

Every D-Bus read and user-session mutation is bounded. Malformed provider data
clears the owning capability instead of retaining stale success. Profile
changes use fixed service, object, interface, property, type, and allowlisted
profile arguments. QML cannot supply a shell fragment, D-Bus destination,
object path, interface, property, or elevated helper path.
