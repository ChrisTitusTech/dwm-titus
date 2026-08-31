# Phase 5 Project Status

Date: 2026-08-30

## Verification Baseline

This checkpoint was reconciled against `origin/main` at
`edb54788acbf93b467568138e4df8f6ce7b0ec66`. The primary checkout matched that
remote revision before the continuation branch was created, and no open pull
request targeted `main`. PR #188 merged the optional-component qualification,
and PR #189 merged the automatic small-PR workflow. Only the primary checkout
remains registered.

The active `TASKS.md` contains 25 implementation checkboxes. Twelve are
complete on `main`. The current accessibility capability boundary validates
one additional checkbox and leaves 12 open in the branch.

The merged APPEARANCE-001 boundaries and their documentation passed:

```text
scripts/run-tests make clean all
scripts/run-tests
mdbook build docs --dest-dir <temporary-output>
git diff --check
```

The managed suite included the appearance provider, inventory, font,
personalization, wallpaper, theme transaction, panel persistence, optional-loss,
nested-X11, staged-install, and repeated-install checks. Quickshell lint retained
only the already-documented `PanelTooltip.qml` qmltypes and
`RunningAppsArea.qml` warnings. Exact-head hosted validation for both merged
boundaries passed before merge.

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
| APPEARANCE-001 panel-widget persistence | Complete | PR #186 | Hosted CI, CodeQL, docs, focused panel, nested-X11, and live-session checks passed. |
| APPEARANCE-001 optional-component isolation | Complete | PR #188 | Focused and full managed suites, nested X11, install, docs, lint, CodeQL, and hosted checks passed. |

The detailed contracts and focused validation commands remain in
`P5-THEME-TRANSACTIONS.md`, `P5-APPEARANCE-INVENTORY.md`,
`P5-FONT-CONTROLS.md`, and `P5-APPEARANCE-CONTROLS.md`. The merged fixes and
user-visible behavior are also recorded under the Unreleased changelog.

## Merged Panel Live Evidence

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

## Current Review Boundary

The current `codex/phase5-accessibility-capabilities` boundary defines five
separate Settings capability records for text scaling, high contrast, reduced
motion, notification policy, and keyboard or pointer access. It replaces the
generic Phase 5 placeholder without introducing a new provider, polling loop,
or mutation path.

Text-scale status and detail are accepted only from a complete version 1
personalization status response. Missing, unresponsive, incomplete, duplicate,
or otherwise unsupported responses degrade only text scaling. The other
records disclose the exact partial or unsupported state of existing managed
shell and X11 facilities so later control work has an explicit contract.
`docs/P5-ACCESSIBILITY-CAPABILITIES.md` records the detailed contract and
validation evidence.

Next action: obtain exact-head review and hosted validation, merge this
boundary, then implement accessible Settings controls as a separate PR.

## Open Task Boundaries

| Boundary | Open checkboxes | Verified current state | Next evidence needed |
| --- | ---: | --- | --- |
| APPEARANCE-001 | 0 | Complete on `main` through PR #188. | Preserve the merged contracts while completing Phase 5. |
| ACCESSIBILITY-001 | 3 in this branch; 4 on `main` | The current boundary defines five distinct read-only records and validates capability-scoped degradation. | Merge this boundary, then implement Settings controls, apply contrast and reduced motion, and add notification policy. |
| P5-UI5 | 4 | No candidate decision record is complete. | Inventory candidates, record adopt/defer/reject decisions, and qualify each adopted X11-native experience independently. |
| P5-VALIDATE | 5 | Individual merged slices have focused and full-suite evidence, but the combined Phase 5 product is incomplete. | Run the final Fedora 44, clean build, full suite, QML, shell, install/parity, fresh-login, `startx`, multi-monitor, optional-loss, recovery, and 30-second CPU qualification after all selected Phase 5 work merges. |

## Phase Position

Phase 5 remains active. THEME-001 and APPEARANCE-001 are complete on `main`.
The first ACCESSIBILITY-001 checkbox is complete in the current review boundary;
no P5-UI5 or final Phase 5 qualification checkbox is complete. Phase 6 must not
begin until the Phase 5 exit criteria pass or an explicit roadmap decision
defers named work and records the resulting limitation.
