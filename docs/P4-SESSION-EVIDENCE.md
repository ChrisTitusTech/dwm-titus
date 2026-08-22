# Phase 4 Session Evidence

## Scope

This record covers the SESSION-001 session-action model, fixed helper protocol,
Settings integration, and cleanup-aware current-DWM logout endpoint. Phase-wide
integration and explicit destructive-path limitations are recorded in
`P4-EVIDENCE.md`.

## Implemented Contract

- One root-owned `PowerMenuModel` exposes lock, logout, suspend, reboot, and
  shutdown without storing commands in action rows.
- Logout, suspend, reboot, and shutdown require model-owned confirmation.
- One strict helper process rejects overlaps and attributes progress or failure
  to the initiating surface.
- The helper emits a success record only after a fixed locker, systemd, or
  verified current-DWM endpoint accepts the request.
- DWM publishes `_NET_WM_PID` and handles `SIGUSR2` as a normal main-loop exit,
  preserving cleanup and the bounded autostop hook.

## Automated Evidence

The following focused checks passed on 2026-08-21 in the integrated Phase 4
worktree. The final exact-commit CI status is recorded on the pull request.

<!-- markdownlint-disable MD013 -->

| Check | Coverage | Result |
| --- | --- | --- |
| `tests/test-quickshell-session-actions.sh` | Fixed action IDs, strict success, failures, overlap/model contract, PID/UID/executable/start-time validation, replacement race, deleted executable, real nested-X11 EWMH PID and autostop completion | Pass |
| `tests/test-quickshell-power-model.sh` | Shared power/session model source contract | Pass |
| `tests/test-quickshell-panel-menus.sh` | Five panel actions and shared busy/origin wiring | Pass |
| `tests/test-quickshell-controlcenter.sh` | Existing helper and Control Center compatibility | Pass |
| `tests/test-dwm-lock.sh` and `tests/test-quickshell-command-menu.sh` | Existing locker and command-menu paths | Pass |
| `tests/test-xvfb-runtime.sh` | Existing nested-X11 DWM lifecycle and bounded autostop smoke | Pass |
| `scripts/quickshell-qmllint --root config/quickshell` | Version-matched QML API and type validation | Pass with pre-existing `PanelTooltip.qml` qmltypes and `RunningAppsArea.qml` warnings; no session-action warning |
| `shellcheck` and `shfmt -d` | POSIX helper and focused test safety/formatting | Pass |
| `scripts/run-tests make clean all` | Signal-safety type and EWMH PID property compile | Pass |

<!-- markdownlint-enable MD013 -->

## Runtime Boundaries

Panel and Settings rendering, the five fixed actions, confirmation, failed
locker, denied logind, cross-display isolation, duplicate startup, nested DWM
logout, autostop completion, and the Phase-wide CPU comparison are automated.
Actual lock/unlock, suspend/resume, reboot, shutdown, and repeated destructive
login cycles were not run on the active workstation and remain explicitly
limited in `P4-EVIDENCE.md`.
