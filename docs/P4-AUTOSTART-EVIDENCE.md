# Phase 4 XDG Autostart Evidence

Date: 2026-08-21

<!-- markdownlint-disable MD013 -->

This document records the implemented and tested evidence for the
`AUTOSTART-001` backend. Settings integration, installed-runtime checks, live
restoration, and phase-wide limitations are summarized in `P4-EVIDENCE.md`.

## Provider and action contract

`dwm-xdg-autostart snapshot` emits tab-separated records:

```text
autostart-protocol\t1\t0
provider\t<ready|degraded|unavailable>\t<detail>
entry\t<desktop-id>\t<name>\t<origin>\t<effective-state>\t<visibility>\t<user-present>\t<vendor-present>\t<can-reset>\t<risk>\t<revision>\t<can-enable>\t<can-disable>\t<detail>
```

The supported entry enums are:

- Origin: `vendor`, `user-override`, or `user-only`.
- Effective state: `enabled`, `disabled`, `non-applicable`, `conditional`,
  `unsupported`, or `malformed`.
- Visibility: `visible`, `hidden`, `not-shown`, `conditional`, or `unknown`.
- Risk: `normal` or `session-critical`.

Every revision is a lowercase SHA-256 value derived from the selected origin
and safe user and vendor file contents. The helper sanitizes all human-readable
fields to one TSV line.

Successful `set` and `reset` operations emit exactly one result record after
the resulting state has been parsed and verified:

```text
autostart-protocol\t1\t0
action\tsuccess\t<set|reset>\t<desktop-id>\t<effective-state>\t<new-revision>\t<backup-path-or-empty>\t<detail>
```

Errors are written to stderr and return nonzero without emitting an action
success record. Mutations change only the user XDG override used at the next
login. The helper does not start, stop, signal, or restart session processes.

`dwm-xdg-autostart watch` uses one parent-bound `inotifywait` process and emits:

```text
autostart-watch-protocol\t1\t0
ready\tautostart
changed\tautostart
```

Each watcher generation emits `ready` only after inotify has established its
watches. The watcher observes the safe user autostart directory and applicable
vendor directories, rebasing through the deepest existing parent when the user
configuration path does not yet exist. It survives a stopped and continued
live parent, and terminates the inotify child after owner death.

## Resolution and mutation behavior

- The user entry under `$XDG_CONFIG_HOME/autostart` takes precedence.
- Vendor directories are searched in `XDG_CONFIG_DIRS` order and the first
  matching desktop ID wins.
- Only immediate, safe `.desktop` basenames are inventoried. Symlinked,
  non-regular, oversized, malformed, and unsafe-path entries degrade per item.
- `Hidden=true`, `OnlyShowIn`, `NotShowIn`, `TryExec`, and
  `AutostartCondition` are represented without guessing conditional state.
- Disable adds the `X-DWM` exclusion or removes the `X-DWM` and legacy `dwm`
  tokens from an existing `OnlyShowIn` list. Enable removes both exclusion
  tokens and adds `X-DWM` to a restrictive `OnlyShowIn` list.
- Vendor files are never written or removed. Unrelated desktop-entry keys,
  comments, groups, and visibility tokens are retained in the user override.
- `Hidden=true` is not silently defeated. An unavailable `TryExec` cannot be
  presented as successfully enabled.
- Mutating light-locker, Picom, or the MATE polkit agent requires the exact
  `confirm-session-critical` token.
- Existing user overrides receive a verified mode-0600 backup in the hidden,
  user-owned `.dwm-titus-backups` directory before a material rewrite or
  reset. Writes use a same-directory temporary file and atomic rename.
- An expected revision and an owned action lock reject stale or overlapping
  actions. A PID/start-time owner record permits safe recovery of a stale lock.
- Mutations reject root execution, unsafe desktop IDs, relative or traversing
  XDG paths, parent and leaf symlinks, path escapes, foreign-owned user paths,
  hard-linked overrides, and unsafe backup directories.

## Automated evidence

The focused fixture covers:

- User/vendor precedence and ordered vendor lookup.
- Vendor-only, user-only, hidden, restrictive, conditional, missing `TryExec`,
  malformed, symlinked, and session-critical records.
- Versioned snapshot and exact action records.
- Disable, enable, reset, no-op behavior, stale revision rejection, and action
  locking, including disable and re-enable of an `OnlyShowIn=X-DWM` entry.
- Vendor immutability and preservation of unrelated comments, groups, keys,
  and non-dwm desktop tokens.
- Verified backups and a simulated backup failure that leaves the original
  override unchanged.
- TERM, HUP, and INT rollback before transaction commit, with no false success
  record and exact prior bytes and mode restored. A separate post-commit output
  interruption fixture proves the committed mutation remains applied while no
  incomplete success record is emitted.
- Symlink and hard-link mutation rejection without changing the outside file.
- Unavailable snapshot state for a symlinked configuration path.
- Confirmation enforcement for a session-critical entry.
- Real inotify events after the watcher is ready, convergence from an initially
  absent multi-level configuration path, STOP/CONT of its live parent, and
  cleanup of both helper and inotify child after owner death.

Validated commands:

```text
tests/test-dwm-xdg-autostart.sh
bash -n scripts/dwm-xdg-autostart tests/test-dwm-xdg-autostart.sh
shellcheck scripts/dwm-xdg-autostart tests/test-dwm-xdg-autostart.sh
shfmt -d scripts/dwm-xdg-autostart tests/test-dwm-xdg-autostart.sh
```

All commands passed on the evidence date. The inotify branch ran on this host;
the focused test skips that runtime branch when `inotifywait` is unavailable so
package and installed-runtime validation must independently require it.

## Runtime boundaries

Search, confirmation, origin rendering, action attribution, pane-owned watcher
lifecycle, package/Kickstart/install symmetry, restored live mutation, repeated
display-manager and `startx` fixtures, full repository tests, and the 30-second
CPU comparison are integrated. A fresh real display-manager login activated one
managed shell and the expected tray applications without duplicate autostarts.
Repeated real logout/login remains an explicit workstation limitation in
`P4-EVIDENCE.md`.
