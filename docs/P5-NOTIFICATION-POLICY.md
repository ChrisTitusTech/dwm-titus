# Phase 5 Notification Policy

## Scope

This final `ACCESSIBILITY-001` implementation boundary adds two persistent,
keyboard-focusable controls to Settings Appearance: Do Not Disturb and a
bounded ordinary-popup duration. The root notification model remains the sole
owner of delivery, popup state, history, and the existing
`org.freedesktop.Notifications` server.

## Ownership and State

The user-owned policy file is
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/notification-settings.json`.
Version 1 stores only a boolean Do Not Disturb value and a duration of 4,000,
6,000, or 10,000 milliseconds. Missing state creates the prior defaults: Do
Not Disturb off and an ordinary duration of 6,000 milliseconds.
Malformed state activates those safe defaults and remains visibly partial
until reset repairs it. Writes are atomic, normal mutations remain disabled
until the save is acknowledged, and a save failure makes the policy visibly
unavailable. The file watcher reloads external changes without a polling timer.

Settings capability discovery first asks D-Bus for the notification owner's
Unix process ID through the machine interface. It then verifies that process's
executable and NUL-delimited command line identify Quickshell running the
managed configuration. Default-path launches also require the owner process's
XDG configuration environment to resolve to the same directory. Command-line
and environment config selectors are rejected unless an explicit path resolves
to the managed `shell.qml`. An unrelated daemon or alternate Quickshell
configuration therefore remains observable but cannot enable ineffective
managed controls. A healthy bus with a momentarily unowned name is accepted
only during the first 15 seconds of a managed Quickshell process when that
process launches the provider. After that bounded registration window, an
unowned name keeps the controls unavailable. No privilege boundary or
arbitrary command construction is added.

## Delivery Semantics

Every accepted notification is appended to the existing bounded history before
popup policy is evaluated. Do Not Disturb immediately dismisses existing low-
and normal-urgency popups, suppresses future ones, and expires their tracked
D-Bus objects after history capture. Critical notifications bypass suppression
and retain the existing fixed ten-second timeout. Overflow, sender-close,
dismiss, clear, history persistence, and history reset behavior remain owned by
the existing lifecycle functions. Initial policy loading and external reloads
fail closed for non-critical popups so a saved Do Not Disturb choice cannot
briefly leak an ordinary notification.

## Validation

Focused validation covers strict owner identity, no-owner and external-owner
fallbacks, shell and QML lint, policy persistence across a fresh Quickshell
session, reset, ordinary delivery, suppressed history retention, critical
urgency bypass, and closed-shell CPU sampling:

```text
tests/test-settings.sh
tests/test-quickshell-notifications.sh
scripts/quickshell-qmllint --root config/quickshell
make check-quickshell-settings-xvfb
make check-quickshell-large-surfaces-xvfb
shellcheck scripts/dwm-settings-provider tests/*.sh
shfmt -d scripts/dwm-settings-provider tests/*.sh
```

The focused gates, clean managed build, and full managed repository suite pass.
The current checkout was synchronized to the installed Fedora 44 X11 session;
the supported restart path reduced three stale Quickshell instances to one
managed instance with working IPC and five tray items. Settings then reported
the notification capability available. The installed model persisted 4,000 ms,
suppressed an ordinary popup while retaining it as the newest bounded-history
entry, allowed a critical popup through Do Not Disturb, and reset to Do Not
Disturb off with a 6,000 ms duration. Closed Quickshell CPU measured 0.000% over
30 seconds. The previously absent policy migrated to the versioned default file
and the validation restored those equivalent default values. Installed files
match the checkout; activating the newly installed `dwm` binary still requires
the expected logout and login. Exact-head hosted gates remain required before
merge.
