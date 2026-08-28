# Phase 5 Project Status

Date: 2026-08-28

## Verification Baseline

This checkpoint was reconciled against `origin/main` at
`5f806afec17a60d56180542dc309750b47672e69`. The panel-widget persistence
branch is one reviewable commit directly on that baseline. GitHub had no open
pull request targeting `main`.

The active `TASKS.md` contains 25 implementation checkboxes. Ten are complete
on `main`; this review boundary validates one additional checkbox and leaves 14
open in the branch. The panel checkbox does not advance the merged-project
count until the branch is reviewed and merged.

The reconciled checkpoint and these documentation changes passed:

```text
scripts/run-tests make clean all
scripts/run-tests
mdbook build docs --dest-dir <temporary-output>
git diff --check
```

The managed suite included the current appearance provider, inventory, font,
personalization, wallpaper, theme transaction, nested-X11, staged-install, and
repeated-install checks. Quickshell lint retained only the already-documented
`PanelTooltip.qml` qmltypes and `RunningAppsArea.qml` warnings. This checkpoint
proves the currently merged baseline is healthy; it does not replace the open
combined Phase 5 qualification tasks.

## Merged Task Evidence

| Task boundary | TASKS.md state | Merged evidence | Verification |
| --- | --- | --- | --- |
| THEME-001 appearance provider | Complete | PR #170 | Five hosted checks passed; one conditional check skipped. |
| THEME-001 safe transactions | Complete | PR #172 | Six hosted checks passed; two conditional checks skipped. |
| THEME-001 shared model and Settings pane | Complete | PR #173 | Five hosted checks passed; one conditional check skipped. |
| THEME-001 partial integration status | Complete | PR #175 and the theme slices above | Five hosted checks passed on PR #175; one conditional check skipped. |
| APPEARANCE-001 inventory | Complete | PR #176 | Five hosted checks passed; one conditional check skipped. |
| APPEARANCE-001 wallpaper | Complete | PRs #177-#180 | Each pull request merged with all executed hosted checks passing. |
| APPEARANCE-001 managed-shell font and scale | Complete | PR #181 | Six hosted checks passed; two conditional checks skipped. |
| APPEARANCE-001 desktop font, cursor, icon, GTK, and Qt backend | Complete | PR #182 | Five hosted checks passed; one conditional check skipped. |
| APPEARANCE-001 desktop controls | Complete | PRs #183 and #184 | All executed hosted checks passed; conditional checks skipped according to their paths. |

The detailed contracts and focused validation commands remain in
`P5-THEME-TRANSACTIONS.md`, `P5-APPEARANCE-INVENTORY.md`,
`P5-FONT-CONTROLS.md`, and `P5-APPEARANCE-CONTROLS.md`. The merged fixes and
user-visible behavior are also recorded under the Unreleased changelog.

## Current Review Boundary

Panel-widget persistence is implemented on
`codex/phase5-panel-persistence`. It adds one versioned user state file, one
root model shared by every monitor, Control Center and Settings integration,
safe migration and fallback behavior, and event-driven updates.

The exact working tree passed the focused panel, Control Center, panel-menu,
nested-X11, QML lint, ShellCheck, shfmt, clean-build, full managed-suite, and
diff checks. Built-in Codex review and independent CodeRabbit review reported
no remaining findings. The branch has been refreshed directly onto the current
checkpoint and is not published. The panel-widget checkbox is complete in this
review boundary but remains unmerged project work.

The exact working tree was synchronized through `scripts/dev-sync-install.sh`.
All managed files match, and rollback backup
`20260828T153709Z-1472673` was created. After a full DWM logout/login, the
active, installed, and checkout DWM binaries matched byte-for-byte. One managed
Quickshell instance exposed the panel, five tray clients, the Control Center,
and Settings Appearance. Settings reached `ready` on Fedora Linux 44 with the
appearance provider available and all five configurable panel widgets enabled
through the shared model. Its installed 1180x760 window displayed all nine
sections and the compact display controls without reducing text scale; closed
idle measured 0.000% CPU over five seconds. The current workstation session had
one active monitor, so real multi-monitor persistence remains untested here;
nested-X11 validation covers the shared-state path.

Next action: publish a ready-for-review pull request, resolve hosted review and
CI, and merge it before starting optional-component qualification.

## Open Task Boundaries

| Boundary | Open checkboxes | Verified current state | Next evidence needed |
| --- | ---: | --- | --- |
| APPEARANCE-001 | 1 | Panel persistence is locally validated but unmerged. Cross-capability optional-component behavior is not yet qualified as one boundary. | Merge the panel slice, then test missing Picom, Feh, toolkit themes, wallpaper directories, and delegated tools without cross-capability failure. |
| ACCESSIBILITY-001 | 4 | No checkbox is complete. Existing text-scale behavior is an appearance control and does not by itself satisfy the accessibility contract. | Define capabilities, implement Settings controls, apply contrast and reduced motion, add notification policy, and validate keyboard-only and fresh-session behavior. |
| P5-UI5 | 4 | No candidate decision record is complete. | Inventory candidates, record adopt/defer/reject decisions, and qualify each adopted X11-native experience independently. |
| P5-VALIDATE | 5 | Individual merged slices and the current panel boundary have focused and full-suite evidence, but the combined Phase 5 product is incomplete. | Run the final Fedora 44, clean build, full suite, QML, shell, install/parity, fresh-login, `startx`, multi-monitor, optional-loss, recovery, and 30-second CPU qualification after all selected Phase 5 work merges. |

## Phase Position

Phase 5 remains active. THEME-001 is complete. APPEARANCE-001 is in progress.
No ACCESSIBILITY-001, P5-UI5, or final Phase 5 qualification checkbox is
complete. Phase 6 must not begin until the Phase 5 exit criteria pass or an
explicit roadmap decision defers named work and records the resulting
limitation.
