# Phase 5 Integration Evidence

Date: 2026-09-02

## Qualification Scope

This record qualifies Phase 5 Personalization and Accessibility on Fedora Linux
44 x86_64 under X11. The combined runtime baseline was `main` at
`3770b04dee7b63e4401a391b91d06488018c215f`, after all selected Phase 5 work
and the empty UI-5 adoption decision merged. This closeout changes planning and
evidence only.

## Delivered Workflows

- One shared appearance provider and root model own theme inventory, semantic
  color state, integration status, wallpaper, managed-shell typography, desktop
  font and scale, cursor, icon, GTK, Qt, and panel-widget state.
- Theme, wallpaper, font, toolkit, and accessibility mutations are serialized,
  bounded, rollback-capable, and failure-attributed. Invalid records and missing
  assets preserve the last usable state.
- Managed high contrast and reduced motion update the existing shell surfaces.
  Practical AccessX controls reuse the timed input preview and persistence path.
- The root notification model remains the only delivery and history owner while
  persistent Do Not Disturb and ordinary-popup duration policy preserve history
  and critical-urgency delivery.
- UI-5 adopted no runtime experience. Clipboard history and reminders remain
  deferred; emoji/symbol and general image pickers remain rejected.

## Automated Validation

The exact combined baseline passed:

```text
scripts/run-tests make clean all
scripts/run-tests
scripts/quickshell-qmllint --root config/quickshell
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
npm --prefix docs ci
npm --prefix docs run build
git diff --check
```

The full managed suite covered every Phase 5 provider and helper, safe previews,
keep/revert/reset, interrupted-operation recovery, malformed and missing state,
optional-component isolation, QML lifecycle, nested X11, package and Kickstart
parity, staged install, uninstall symmetry, and repeated install preservation.
The Settings workflow sampled 0.133 percent of one CPU before the workflow and
0.067 percent after it closed, a 0.066 percentage-point delta against the 0.5
point limit. The large-surface run measured 0.00 percent closed CPU.

Quickshell lint retained only the established `PanelTooltip.qml` incomplete
qmltypes warnings and `RunningAppsArea.qml` property warnings. ShellCheck,
shfmt, the Astro check, and the Astro build completed without findings.

## Live Fedora, Restoration, and Parity Evidence

The final checkout was synchronized through `scripts/dev-sync-install.sh`.
The preflight correctly detected a stale installed notification provider and
three stale managed QML files. The supported path created rollback backup
`20260903T015133Z-2738591`, installed the complete system and user state, and
then reported every managed file matching the checkout.

The supported shell restart left one managed Quickshell process with working
IPC, five tray clients, and the notification policy available. After closing
all managed surfaces, a 30-second live sample consumed 0.000 percent CPU. The
running DWM inode, installed binary, and checkout binary were byte-identical at
SHA-256 `95e51d1378feefc9ff2c870ad7167dd335c7e52824ea284677810515ad8cbcbb`.
The active inode retains the normal deleted suffix after same-content install
replacement, so a later logout/login will refresh its pathname even though its
executed bytes already match.

The real X11 session exposed DP-0 at 2560x1440 and HDMI-0 at 1920x1080. It had
one 30-pixel panel on each monitor. Installed IPC opened Settings at 1180x760;
the application reached `ready`, remained keyboard-addressable through the
qualified controls, and closed without adding another shell process.

A live three-second Nord-to-Dracula theme preview converged to Dracula, timed
out to Nord, and restored the exact content, mode, symlink target, or absence of
`themes.toml` plus all 13 integration paths. Preview and recovery state both
ended empty. A live sticky-keys preview changed the selected AccessX value and
explicit revert restored the complete `xkbset q` snapshot byte-for-byte; the
previously absent input settings file remained absent.

## Exit-Criteria Mapping

| Phase 5 exit criterion | Qualification evidence |
| --- | --- |
| Supported applications and shell surfaces follow the selected appearance. | The live transactional theme preview updated the shared provider and integrations, then restored 14 tracked paths exactly. Automated personalization, wallpaper, toolkit, panel, hot-reload, and nested-X11 tests passed. |
| Invalid themes or missing assets cannot prevent login or shell startup. | The full suite passed malformed, duplicate, missing-asset, optional-loss, startup, display-manager, and `startx` fixtures. Existing real LightDM evidence reached the managed desktop, and the final installed shell restarted from the synchronized tree with one healthy owner. |
| Accessibility choices persist and are usable at common display sizes. | Nested X11 passed keyboard navigation, persistence, reset, notification delivery/history, and compact rendering. Live AccessX restoration, two-monitor panels, the 1180x760 Settings surface, and the 30-second closed-idle sample passed. |

## Explicit Limitations

- The exact final documentation revision was not followed by another disruptive
  LightDM logout/login. Earlier Phase 5 activation completed a real fresh
  LightDM login; the final combined suite covers LightDM and `startx` fixtures,
  the active DWM bytes match the final checkout, and the synchronized managed
  Quickshell tree was restarted successfully.
- Actual removal of optional host packages was not performed. Combined missing
  Picom, Feh, toolkit, wallpaper, and delegated-tool behavior is fixture- and
  nested-X11-qualified.
- Several installed GTK theme candidates lack complete GTK 3 or GTK 4 assets.
  Inventory reports those candidates as partial; supported complete candidates
  and the rest of Settings remain available.
- Hardware-specific behavior outside the two observed displays and available
  XKB path is not claimed. Missing tool and extension behavior is covered by
  scoped provider and nested-X11 fixtures.
