# Pre-Phase 7 maintenance

Phase 6 is complete. This maintenance boundary improves Settings and local
review iteration; it does not start Phase 7 image or release qualification.

## Responsiveness

Settings creates each pane asynchronously on its first visit. Visited panes
stay alive, preserving local drafts and scroll state. Service discovery,
preview rollback and system-operation ownership remain in the existing models.
Repeated search or navigation within the same section no longer reactivates
its providers; opening Settings and explicit refresh remain available.

A nested Fedora 44 X11 fixture measured 1,235 visual items and nine panes while
Settings was closed before the change, versus 63 items and zero panes afterward
(95% fewer visual items in the Settings window). Its repeated search/navigation
sequence went from six section activations to zero. These are structural
measurements, not a claim of a 95% wall-clock or memory improvement. The fixture
uses inert helpers to isolate UI behavior; provider behavior is covered by the
existing Settings integration suite.

## Local review loop

PR #291 moved routine PR validation to local gates, retaining main-branch CI
and manual dispatch. `CONTRIBUTING.md` now supplies an evidence-first review
prompt so an independent reviewer can reuse passing coverage instead of
repeating long native suites without a concrete reason. The focused
`check-quickshell-settings-responsiveness-xvfb` target covers pane creation,
geometry, retained identity/drafts and search activation in a few seconds.
It is also included in the aggregate gate.

## Remaining reports

No Phase 6 implementation checkbox remains open. The following existing issue
reports remain open; automated coverage does not establish that a reporter's
hardware or old installation is fixed:

| Issue | Disposition before Phase 7 |
| --- | --- |
| #192: Wi-Fi after reboot, wallpaper/font reports | Needs current installation diagnostics and reproduction; retain networking and session coverage. |
| #187: AMD mixed-monitor/high-refresh artifacts | Requires physical display/GPU reproduction; include in hardware qualification where available. |
| #130: Quickshell remains after an older startx session | Current session cleanup has regression coverage; the old-install report remains unverified. |
| #108: Older installer/terminal failure | Installer and terminal fixtures pass; a real image installation remains Phase 7 work. |
| #77: Fractional scaling request | Physical scaling qualification remains open; no new scaling guarantee. |
| #68: Alt+Shift layout-toggle request | Separate feature request, outside this maintenance boundary. |

No issues were closed on the strength of unrelated automated tests. Phase 7
remains queued and its tasks remain unchecked. Existing unrelated worktrees
are preserved; the primary checkout must be clean and synchronized with
`origin/main` at handoff.

## Validation

Fedora 44 x86_64, Quickshell 0.2.1 Fedora snapshot (`dacfa9d`), Qt 6.11.2,
nested Xvfb and isolated D-Bus sessions:

- Clean build, configured QML lint and large-surface source contract passed.
- The focused responsiveness fixture passed with all nine pane layouts,
  retained pane identity and an unsaved profile name, deduplicated selection,
  and explicit Display/Input refresh.
- The complete Settings Xvfb lifecycle suite passed, with 0.100% sampled closed
  CPU. The large-surface suite passed with 0.00% sampled closed CPU.
- Settings provider/Input tests, 13 display-profile tests, staged install
  manifest, repeated-install preservation, ShellCheck, shfmt and diff checks
  passed.
- Unchanged backend, system-operation, installer security, package, release
  and documentation-build coverage is reused from merged PR #291. This change
  does not modify those implementations or start image qualification.

The first native run exposed the old test's reliance on same-section selection
for a forced refresh; it now uses explicit Refresh. An initial Input shell test
exited without identifying its assertion; both a command-traced rerun and the
normal complete target passed without a backend change. No claim is made about
unavailable physical hardware, real PackageKit operations, or a newly deployed
live desktop. Exact reviewed content and local log paths are recorded in the PR.
