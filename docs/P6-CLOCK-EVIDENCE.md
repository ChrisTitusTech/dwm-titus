# Phase 6 Shared Clock Evidence

This qualifies the shared date/time display boundary, not completion of Phase 6.

## Environment and isolation

- Fedora 44 x86_64, Qt 6.11.2, supported Fedora Quickshell 0.2.1 snapshot.
- Private Xvfb display, copied QML, and Bubblewrap 0.12.0 mount namespace.
- Only the test namespace's `/etc/localtime` symlink was changed. Host timezone,
  system clock, NTP, installed configuration, and live shell were untouched.
- Private workspaces and child processes were cleaned after each run.

## Checks

The standalone QML fixture checks initial display, minute precision, ignored
partial/unavailable/unknown state, unchanged snapshots, changed and returning
timezone identities, and retention of a distinct numeric timestamp. The existing
66-case regional UI matrix also requires the shared clock readout in Settings.

The actual X11 fixture changed its private timezone from UTC to America/Chicago
and back. All samples retained timestamp `1788825480000`: the panel changed from
`23:58` to `18:58` and back, and Settings changed from UTC to CDT and back.
A partial Chicago record preserved the displayed UTC value until an available
record arrived. Both restored strings exactly matched their starting values.

An initial implementation reread `SystemClock.date` after the timezone change.
The namespace test reproduced a five-hour timestamp shift with unchanged wall
time. Retaining a numeric timestamp at native ticks fixes that issue. A separate
run kept Chicago active through the next real minute tick: timestamp
`1788825600000` rendered `19:00 CDT`, matching an independent Python ZoneInfo
calculation. No synthetic host clock or service mutation was used.

Screenshots of both shared formats were visually checked. Qt's documented
[timezone refresh API](https://doc.qt.io/qt-6/qml-qtqml-date.html#string-date-timezoneupdated)
and the matching [Quickshell SystemClock contract](https://quickshell.org/docs/v0.2.1/types/Quickshell/SystemClock/)
inform the implementation. The single native minute source remains the normal
tick owner; no extra poller or resident helper was introduced.

![Shared clock formats in UTC](evidence/p6-clock/utc.png)

![The same instant in Chicago](evidence/p6-clock/chicago.png)

## Remaining qualification

This does not establish graphical authorization, native host timezone mutation,
closed-pane external timezone discovery, visible NTP sampling, or combined
installed-session acceptance. Those remain separate Phase 6 work.
