# Phase 5 Optional-Component Qualification

## Scope

This `APPEARANCE-001` review boundary qualifies optional appearance failures
as capability-scoped. Missing Picom, Feh, wallpaper directories, cursor, icon,
or GTK assets, Qt configuration tools, and delegated GTK or Qt editors must not
make the shared appearance provider, unrelated selections, Settings, or the
managed shell unavailable.

This boundary adds qualification coverage rather than a new runtime provider.
The existing versioned appearance, wallpaper, and personalization protocols
remain authoritative.

## Automated Contract

`make check-phase5-optional-components` covers the helper and source-contract
portion of the combined boundary, while `make check-quickshell-settings-xvfb`
drives the same loss state through the live Settings model:

- one inventory snapshot removes Picom, Feh, `qt6ct`, the wallpaper directory,
  and all discovered cursor, icon, and GTK asset roots at the same time;
- the inventory provider remains available, emits exactly one selection for
  every capability, and keeps the independent Fontconfig selection available;
- wallpaper, cursor, icon, GTK, Qt, and compositor failures retain their own
  unavailable or partial state and explanatory detail;
- a direct wallpaper status probe without Feh remains read-only, creates no
  state, and reports only wallpaper mutation as unavailable;
- removing all allowlisted GTK and Qt editors leaves the personalization
  provider, ordinary selections, and transaction readiness available while
  both delegate records and delegate actions fail safely; and
- the nested-X11 Settings workflow receives one valid combined-loss snapshot,
  keeps Font and personalization available, presents wallpaper, cursor, icon,
  GTK, and Qt state per capability, and keeps the managed shell alive.

## Validation Evidence

The exact continuation working tree passed on Fedora 44:

```text
scripts/run-tests make check-phase5-optional-components
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests make clean all
scripts/run-tests
scripts/run-tests scripts/quickshell-qmllint --root config/quickshell
shellcheck tests/test-dwm-settings-appearance-inventory.sh \
  tests/test-dwm-settings-personalization.sh \
  tests/test-dwm-settings-wallpaper.sh \
  tests/test-quickshell-appearance-model.sh \
  tests/test-quickshell-settings-xvfb.sh
shfmt -d tests/test-dwm-settings-appearance-inventory.sh \
  tests/test-dwm-settings-personalization.sh \
  tests/test-dwm-settings-wallpaper.sh \
  tests/test-quickshell-appearance-model.sh \
  tests/test-quickshell-settings-xvfb.sh
mdbook build docs --dest-dir <temporary-output>
git diff --check
```

The serial nested-X11 Settings workflow passed appearance preview,
persistence, invalid and missing-asset recovery, and closed-window lifecycle
checks. The final focused run sampled 0.067 percent CPU before and after
closure, a 0.000 percentage-point absolute delta. The full managed-suite
rerun sampled 0.067 percent before and after closure, a 0.000 percentage-point
absolute delta. Quickshell lint retained only the
already-recorded `PanelTooltip.qml` qmltypes and `RunningAppsArea.qml` property
warnings.

Runtime QML changed only to add read-only Settings IPC observability methods;
the nested-X11 workflow loaded the exact tracked QML and exercised those
methods. The production wallpaper helper now waits up to approximately one
second, instead of 0.2 seconds, for a detached rollback watchdog to expose its
verified process identity. Helper tests and the nested-X11 workflow exercised
the exact tracked helper's preview, watchdog termination, writable rearm, and
rollback paths. Installer manifests and session-startup behavior did not
change. Copying the checkout into the live installed data directory and
activating it through a fresh logout/login were not manually tested at this
qualification boundary; normal install/update propagation will copy the
tracked helper and QML after merge. Actual removal of optional host packages
was not performed; the combined missing-component path is fixture- and
nested-X11-qualified.
