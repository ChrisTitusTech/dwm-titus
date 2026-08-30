# Phase 5 Project Status

Date: 2026-08-30

## Verification Baseline

This checkpoint was reconciled against `origin/main` at
`37600c1160198a0a5297d2fa9b2a608b63f3ddda`. The primary checkout matched that
remote revision before the continuation branch was created, and no open pull
request targeted `main`. The obsolete Phase 2 worktree was clean and removed;
only the primary checkout remains registered.

The active `TASKS.md` contains 25 implementation checkboxes. Eleven are
complete on `main`. The current optional-component boundary validates one
additional checkbox and leaves 13 open in the branch. Panel-widget persistence
merged in PR #186 and now counts as merged project work.

The panel merge head and its documentation passed:

```text
scripts/run-tests make clean all
scripts/run-tests
mdbook build docs --dest-dir <temporary-output>
git diff --check
```

The managed suite included the current appearance provider, inventory, font,
personalization, wallpaper, theme transaction, panel persistence, nested-X11,
staged-install, and repeated-install checks. Quickshell lint retained only the
already-documented `PanelTooltip.qml` qmltypes and `RunningAppsArea.qml`
warnings. A later compact-display change left one geometry source assertion
stale, causing the latest `main` CI run to fail in
`check-quickshell-appearance-model`; the continuation branch updates that
assertion to the shipped compact geometry. Exact-head hosted validation remains
pending.

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

The current `codex/phase5-optional-components` boundary updates the stale
compact-display test assertion to match the merged 88-pixel source layout and
qualifies optional-component failure isolation.
Simultaneous missing Picom, Feh, toolkit assets, the wallpaper directory, and
the Qt editor retain an available inventory provider and independent font
state. Missing delegated GTK and Qt editors leave personalization state and
ordinary apply/reset readiness available while only delegation is disabled.

The exact working tree passed the focused optional-component target, clean
build, full managed repository suite, Quickshell lint, ShellCheck, shfmt,
nested-X11 Settings workflow, documentation build, staged and repeated install,
release archive, and diff checks. The final full-suite nested Settings sample
measured 0.067 percent CPU before and after closure, a 0.000 percentage-point
absolute delta. `docs/P5-OPTIONAL-COMPONENTS.md` records the detailed evidence
and the fixture-qualified host-package-removal limitation.

Next action: publish and merge this boundary, then begin the ordered
accessibility and notification-policy work.

## Open Task Boundaries

| Boundary | Open checkboxes | Verified current state | Next evidence needed |
| --- | ---: | --- | --- |
| APPEARANCE-001 | 0 in this branch; 1 on `main` | Panel persistence is merged. Cross-capability optional-component behavior is locally qualified and documented. | Obtain hosted review and CI, then merge the optional-component boundary. |
| ACCESSIBILITY-001 | 4 | No checkbox is complete. Existing text-scale behavior is an appearance control and does not by itself satisfy the accessibility contract. | Define capabilities, implement Settings controls, apply contrast and reduced motion, add notification policy, and validate keyboard-only and fresh-session behavior. |
| P5-UI5 | 4 | No candidate decision record is complete. | Inventory candidates, record adopt/defer/reject decisions, and qualify each adopted X11-native experience independently. |
| P5-VALIDATE | 5 | Individual merged slices and the current optional-component boundary have focused and full-suite evidence, but the combined Phase 5 product is incomplete. | Run the final Fedora 44, clean build, full suite, QML, shell, install/parity, fresh-login, `startx`, multi-monitor, optional-loss, recovery, and 30-second CPU qualification after all selected Phase 5 work merges. |

## Phase Position

Phase 5 remains active. THEME-001 is complete. APPEARANCE-001 is complete in
the current review boundary but remains in progress on `main` until that
boundary merges. No ACCESSIBILITY-001, P5-UI5, or final Phase 5 qualification
checkbox is complete. Phase 6 must not begin until the Phase 5 exit criteria
pass or an explicit roadmap decision defers named work and records the
resulting limitation.
