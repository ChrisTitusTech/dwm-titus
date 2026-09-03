# Phase 5 Project Status

Date: 2026-09-02

## Verification Baseline

This checkpoint was reconciled against `origin/main` at
`8b846fb9594eb46587ce54281a31776284121552`. PR #203 merged practical XKB
accessibility controls after PR #202 merged dedicated high-contrast and
reduced-motion Settings controls. The primary checkout matched the remote
revision before this notification-policy branch was created, no pull request
remained open, and only the primary checkout was registered.

The active `TASKS.md` contains 25 implementation checkboxes. Fifteen are
complete on `main`; this boundary completes the sixteenth, leaving nine after
merge.

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
| ACCESSIBILITY-001 notification policy | Current | Current branch | Persistent Do Not Disturb, bounded popup duration, owner-PID matching, history retention, urgency bypass, and reset are under review. |

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

The current `codex/phase5-notification-policy` boundary keeps the root
NotificationModel as the sole delivery and history owner. It adds user-owned
Do Not Disturb and fixed popup-duration state without a poller or privilege
boundary. Capability discovery resolves the D-Bus owner's machine-readable PID
and verifies the Quickshell executable and managed configuration identity
before exposing mutations.

Focused provider, shell, QML, and nested-X11 checks pass. The clean managed
build and full managed repository suite pass. The Settings session persisted
policy through restart and reset. The large-surface session delivered an
ordinary notification, retained a suppressed notification in history, allowed
a critical notification through Do Not Disturb, recovered the last confirmed
state after a forced save failure, and sampled 0.00% closed idle CPU.

The exact checkout was installed with rollback backup
`20260902T203714Z-3846857`. The supported restart path removed two stale
managed Quickshell instances, leaving one instance with healthy IPC and five
tray items. Settings reported the notification capability available. The live
policy persisted 4,000 ms, suppressed an ordinary popup while retaining it as
the newest history entry, allowed a critical popup, and reset to Do Not Disturb
off at 6,000 ms. Closed CPU measured 0.000% over 30 seconds. The previously
absent policy migrated to its versioned default file. Installed files match the
checkout; the newly installed `dwm` binary requires the expected logout and
login before runtime parity can pass. Exact-head hosted validation remains
required before merge.

## Open Task Boundaries

| Boundary | Open checkboxes | Verified current state | Next evidence needed |
| --- | ---: | --- | --- |
| APPEARANCE-001 | 0 | Complete on `main` through PR #188. | Preserve the merged contracts while completing Phase 5. |
| ACCESSIBILITY-001 | 0 | Five capability records, text-scale grouping, managed contrast and motion policy, and practical XKB input controls are merged. This boundary completes notification policy behavior plus nested-X11 and installed-session evidence. | Finish exact-head hosted review and validation. |
| P5-UI5 | 4 | No candidate decision record is complete. | Inventory candidates, record adopt/defer/reject decisions, and qualify each adopted X11-native experience independently. |
| P5-VALIDATE | 5 | Individual merged slices have focused and full-suite evidence, but the combined Phase 5 product is incomplete. | Run the final Fedora 44, clean build, full suite, QML, shell, install/parity, fresh-login, `startx`, multi-monitor, optional-loss, recovery, and 30-second CPU qualification after all selected Phase 5 work merges. |

## Phase Position

Phase 5 remains active. THEME-001 and APPEARANCE-001 are complete on `main`.
All ACCESSIBILITY-001 implementation checkboxes are complete with this
boundary. No P5-UI5 or final Phase 5 qualification checkbox is complete. Phase
6 must not begin until the Phase 5 exit criteria pass or an explicit roadmap
decision defers named work and records the resulting limitation.
