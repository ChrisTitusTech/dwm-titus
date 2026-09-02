# Phase 5 Managed Accessibility Policy

## Scope

This `ACCESSIBILITY-001` contract covers persistent managed-shell high contrast
and reduced motion plus their dedicated Settings controls. Practical X11 input
controls are documented separately in `P5-INPUT-ACCESSIBILITY.md`; notification
behavior remains a separate Phase 5 boundary.

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

Status output is append-only within protocol version 1. Consumers validate one
unique state, contrast, motion, mutation-readiness, and terminal completion
record while ignoring unknown record types.

The helper supports bounded `status`, `set`, and `reset` actions. Status includes
an explicit mutation-readiness record so consumers never infer safety from a
human-readable detail. It serializes
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
reading the state file itself. Watchers that were established restart after
directory replacement or child failure; pre-readiness failures use five bounded
exponential-backoff attempts and then stop. High contrast strengthens semantic
borders and muted text through `Theme.qml`. Reduced motion sets the shared
managed animation durations to zero. The model introduces no state polling, new
privilege boundary, compositor dependency, or Wayland API.

The Appearance pane exposes keyboard-focusable, labeled high-contrast and
reduced-motion switches plus reset. Every switch routes pointer, keyboard, and
assistive press or toggle actions through the same guarded mutation path.
Capability discovery validates one bounded, complete versioned status response
before advertising either mutation and degrades malformed, unresponsive, or
unsafe provider state without affecting other Settings records.

## Validation

Focused checks:

```text
make check-accessibility
scripts/quickshell-qmllint --root config/quickshell
```

The helper and provider tests cover defaults, persistence, reset, file-mode
preservation, inotify delivery and child failure, malformed and future state, unsafe symlink
and hard-link paths, invalid values, runtime path validation, mutation lock
contention, bounded discovery, and malformed-provider isolation. The Quickshell
checks cover strict protocol parsing, helper-owned event-driven refresh,
semantic theme policy, accessible control semantics, shell ownership, and
nested-X11 persistent set and reset actions.
