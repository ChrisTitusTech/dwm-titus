# Phase 5 Managed Accessibility Policy

## Scope

This `ACCESSIBILITY-001` review boundary adds the persistent managed-shell
policy used by later Settings controls. It covers high contrast and reduced
motion only. Notification behavior and practical X11 input controls remain
separate Phase 5 boundaries.

## State Contract

`dwm-accessibility-settings` owns
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/accessibility.conf` and exposes
`accessibility-settings-protocol 1`. An absent file means standard contrast and
full motion. A valid file stores exactly one contrast choice and one motion
choice:

```text
accessibility-settings-protocol	1	0
contrast	standard
motion	full
```

The helper supports bounded `status`, `set`, and `reset` actions. It serializes
mutations, publishes a complete file atomically, preserves the existing file
mode, rejects symlinks, hard links, unsafe ownership and unsafe directories,
and refuses to overwrite state that changes during a transaction. Malformed or
incomplete version 1 data can be repaired by an explicit mutation. Future
protocol versions are preserved and reject every mutation while the shell uses
safe defaults. Its watch action may create only the missing user-owned
`dwm-titus` configuration directory; it never creates policy state.

## Shell Behavior

One root-scoped `AccessibilityModel` runs a bounded status command at startup.
The helper emits readiness only after inotify confirms its watch on the
validated owning configuration directory. QML then requests the initial
validated status snapshot and repeats that request for later events without
reading the state file itself. High contrast strengthens semantic borders and
muted text through `Theme.qml`. Reduced motion sets the shared managed animation
durations to zero. The model introduces no state polling, new privilege
boundary, compositor dependency, or Wayland API.

## Validation

Focused checks:

```text
make check-accessibility
scripts/quickshell-qmllint --root config/quickshell
```

The helper tests cover defaults, persistence, reset, file-mode preservation,
inotify delivery, malformed and future state, unsafe symlink and hard-link
paths, invalid values, runtime path validation, and mutation lock contention.
The Quickshell checks cover strict protocol parsing, helper-owned event-driven
refresh, semantic theme policy, and shell ownership.
