# Phase 4 Defaults Evidence

## Scope and Status

This record qualifies the DEFAULTS-001 backend contract. The Quickshell pane,
package mapping, nested-X11 interactions, and restored live Fedora mutations
are integrated and summarized in `P4-EVIDENCE.md`.

## Backend Contract

`dwm-default-apps snapshot` emits `defaults-protocol` version 1.0 followed by
independent provider, watch, role, MIME, candidate, MIME-candidate, and recovery
records. Empty or malformed XDG state is reported as unavailable; the helper
does not invent a default. Record text is stripped of tabs and line breaks.

The fixed user-session actions are:

- `set-role browser|terminal|file-manager <desktop-id>`
- `set-mime <supported-mime> <desktop-id>`
- `reset-role browser|terminal|file-manager`
- `reset-mime <supported-mime>`

Desktop IDs, desktop-entry type and visibility, role categories, advertised
MIME types, `TryExec` or the non-executed first `Exec` command, terminal
mappings, and installed terminal commands are validated before mutation.
Each candidate is a bounded regular desktop file with exactly one Desktop
Entry group, unique keys, and no control characters. Desktop discovery does
not follow symlinked files or directories, including nested application
directories. Stale desktop files whose launch command is missing are not
offered and fail before any XDG write. Browser selection changes only the four
documented browser associations instead of delegating to the wider
implementation-defined `xdg-settings set` MIME set. The legacy `status`,
`browsers`, `set-browser`, `set-mime`, and `open` entry points remain
compatible.

## Persistence and Recovery

XDG mutations are serialized by a per-user PID/starttime lock that safely
recovers a dead owner's stale lock. The helper refuses MIME and hotkey paths
with a symlink at any existing component, snapshots the exact prior file and
mode, applies only the selected associations, verifies every XDG query, and
restores the prior file on command failure or non-convergence. A successful
mutation stores a
mode-0600 one-level recovery image and the expected post-mutation hash under
`${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/default-apps/`.

Reset is allowed only while the current file still matches that post-mutation
hash. External changes therefore disable stale recovery instead of being
overwritten. Rollback failure is reported separately and never emits a success
record.

Terminal selection replaces only the quoted `[vars].terminal` value in the
existing user `hotkeys.toml`, preserving its spacing or inline comment, the
Super+X binding, and every unrelated setting.
`dwm-terminal` reads that validated command after an explicit `DWM_TERMINAL`
override and before its supported fallback list. Super+B continues through
`dwm-default-apps open`, and Super+E continues through `xdg-open .`; neither
hotkey contract needs rewriting. A missing, non-regular, or symlinked user
hotkeys file makes the terminal role and candidates explicitly restricted;
the readable managed default is not misreported as writable state.

`dwm-default-apps watch` owns a pane-scoped, bounded `inotifywait` cohort over
safe XDG configuration and desktop-entry directories. It advances through the
deepest existing parent until initially absent or externally replaced XDG
configuration and `applications` paths appear. Generation watches are nonrecursive and filter
the exact next component, while existing application roots are recursive for
nested desktop entries. Desktop entries plus `mimeapps.list` and
desktop-specific `*-mimeapps.list` changes trigger refresh. Cleanup is bounded
and reaps the exact child identities. Missing `inotifywait` affects live refresh
only; the snapshot remains readable on demand.

## Automated Evidence

The focused fixtures cover exact versioned records, usable and rejected desktop
entries (including duplicate keys, oversized files, control characters, and
symlink traversal), strict role/MIME membership, exact browser and per-MIME
write and reset scope, unrelated association preservation, mode preservation,
command failure, non-convergence, exact rollback, stale-recovery refusal,
leaf and parent symlink rejection, active and stale operation locks, terminal
availability and hotkey convergence, legacy commands, and recursive external
watch events. Recovery fixtures also cover reset interruption and mode failure,
preservation of an older valid journal when a later journal commit fails, and
multi-level absent configuration creation with watcher-child cleanup.

Run:

```sh
scripts/run-tests make check-default-apps check-terminal
shellcheck scripts/dwm-default-apps scripts/dwm-terminal \
  tests/test-dwm-default-apps.sh tests/test-dwm-terminal.sh
shfmt -d scripts/dwm-default-apps scripts/dwm-terminal \
  tests/test-dwm-default-apps.sh tests/test-dwm-terminal.sh
```

The Phase 4 integration evidence records Fedora 44, the restored MIME hash,
browser/file-manager/MIME mutations, nested-X11 terminal and hotkey behavior,
the live symlink restriction, and the stale Chromium candidate rejection.
