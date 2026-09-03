# Phase 5 Project Status

Date: 2026-09-02

## Verification Baseline

This checkpoint was reconciled against `origin/main` at
`ad47c209ef67bfc462ad9a847ef4d41b524e9257`. PR #204 merged notification
policy after PR #203 merged practical XKB accessibility controls and PR #202
merged dedicated high-contrast and reduced-motion Settings controls. The
primary checkout matched the remote revision before this UI-5 decision branch
was created, no pull request remained open, and only the primary checkout was
registered.

The active `TASKS.md` contains 25 implementation checkboxes. Sixteen are
complete on `main`; this boundary closes four optional UI-5 checkboxes with an
empty adopted set, leaving the five combined qualification checks after merge.

The merged APPEARANCE-001 boundaries and their documentation passed. The
historical documentation build has since been replaced by the current Astro
validation shown here:

```text
scripts/run-tests make clean all
scripts/run-tests
npm --prefix docs ci
npm --prefix docs run build
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
| ACCESSIBILITY-001 capability contract | Complete | PR #190 | Five hosted checks and exact-head Codex and CodeRabbit review passed; one conditional check skipped. |
| ACCESSIBILITY-001 managed Settings controls | Complete | PRs #191, #201, and #202 | Capability grouping, managed contrast and motion policy, Settings mutations, nested-X11 persistence, hosted checks, and review loops passed. |
| ACCESSIBILITY-001 practical input controls | Complete | PR #203 | AccessX preview, rollback, persistence, replay, reset, real-session rollback, hosted gates, and exact-head review passed. |
| ACCESSIBILITY-001 notification policy | Complete | PR #204 | Persistent Do Not Disturb, bounded popup duration, owner-PID matching, history retention, urgency bypass, transient-save recovery, installed-session evidence, hosted gates, and exact-head reviews passed. |
| P5-UI5 candidate decisions | Current | Current branch | Four candidates have explicit defer or reject decisions and the adopted set is empty, so no runtime or package boundary follows. |

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

## Merged Notification Evidence

PR #204 kept the root NotificationModel as the sole delivery and history owner
while adding user-owned Do Not Disturb and fixed popup-duration state without
a poller or privilege boundary. Capability discovery resolves the D-Bus
owner's machine-readable PID and verifies the Quickshell executable and managed
configuration identity before exposing mutations.

Focused provider, shell, QML, nested-X11, clean-build, and full managed-suite
checks passed. The large-surface session retained suppressed notifications in
history, allowed critical urgency through Do Not Disturb, recovered after a
forced save failure, preserved visible popups across self-writes, and sampled
0.00% closed idle CPU. The exact checkout was installed with rollback backup
`20260902T203714Z-3846857`; the supported restart path left one healthy managed
shell and five tray items. The live policy persisted 4,000 ms, suppressed an
ordinary popup while retaining it in history, allowed a critical popup, reset
to Do Not Disturb off at 6,000 ms, and measured 0.000% CPU over 30 seconds.
Hosted validation passed on the exact merged head after one unrelated Settings
Xvfb appearance-baseline flake passed unchanged on rerun. Exact-head Codex and
CodeRabbit reviews completed without outstanding findings.

## Current Review Boundary

`docs/P5-UI5-DECISIONS.md` inventories event-driven clipboard history, an
emoji/symbol picker, a reminder or timer overlay, and a general image picker.
Clipboard history and reminders are deferred pending explicit data-retention,
privacy, lifecycle, and recovery contracts. The two generic pickers are
rejected because no current product workflow requires them. No candidate is
adopted, so this decision-only branch changes no provider, resident process,
package, IPC name, keybinding, focus rule, monitor behavior, or X11 surface.

## Open Task Boundaries

| Boundary | Open checkboxes | Verified current state | Next evidence needed |
| --- | ---: | --- | --- |
| APPEARANCE-001 | 0 | Complete on `main` through PR #188. | Preserve the merged contracts while completing Phase 5. |
| ACCESSIBILITY-001 | 0 | Five capability records, text-scale grouping, managed contrast and motion policy, practical XKB input controls, and notification policy are merged through PR #204. | Preserve the merged contracts during final qualification. |
| P5-UI5 | 0 | Four candidates have explicit decisions; none is adopted. This boundary adds no runtime or package work. | Preserve the recorded limitations and empty adopted set. |
| P5-VALIDATE | 5 | Individual merged slices have focused and full-suite evidence, but the combined Phase 5 product is incomplete. | Run the final Fedora 44, clean build, full suite, QML, shell, install/parity, fresh-login, `startx`, multi-monitor, optional-loss, recovery, and 30-second CPU qualification after all selected Phase 5 work merges. |

## Phase Position

Phase 5 remains active. THEME-001, APPEARANCE-001, and ACCESSIBILITY-001 are
complete on `main`. This boundary closes P5-UI5 with no adopted experience.
Only the five final Phase 5 qualification checkboxes remain. Phase 6 must not
begin until the Phase 5 exit criteria pass and the resulting evidence and
limitations are recorded.
