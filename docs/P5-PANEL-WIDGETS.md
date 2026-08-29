# Phase 5 Panel Widget Persistence Evidence

## Delivered contract

- `dwm-panel-settings` owns the versioned
  `~/.config/dwm-titus/panel-widgets.conf` status, set, and reset protocols.
- One root `PanelSettingsModel` is instantiated in `shell.qml`. Every `DwmPanel`,
  Control Center, and Settings Appearance consumes that same model, so a change
  is immediately consistent across monitors without duplicate providers.
- The five persisted choices are Workspaces, Volume, Bluetooth, Network, and
  Power. Active-window title, status segments, clock, and tray remain outside
  this setting and retain their existing behavior.

## Safety and migration

- An absent file is the one-time migration from the former implicit all-on
  session state. It does not write until the user changes or resets a choice.
- Malformed, incomplete, and unsupported regular files are preserved and read
  as safe all-on defaults. An explicit set or reset replaces them atomically.
- Symlinks, hard links, oversized files, wrong-owner files, unsafe state
  directories, and unsafe locks are not replaced.
- Writes preserve the existing file mode and use no-clobber creation or atomic
  exchange to refuse a concurrent external edit without losing either version.
- State changes are event-driven through one file watch; no polling process or
  per-monitor watcher is added.

## Validation

- `make check-quickshell-panel-settings` covers absent-state migration,
  persistence across helper invocations, malformed/future fallback, explicit
  repair, reset, mode preservation, symlink refusal, and deterministic
  single- and repeated-concurrent-edit races.
- `make check-quickshell-controlcenter check-quickshell-panel-menus` preserves
  the existing Control Center and panel interaction contracts.
- `make check-quickshell-settings-xvfb` changes and resets the shared value
  through the running root model and verifies the persisted file.
- `scripts/quickshell-qmllint --root config/quickshell`, ShellCheck, shfmt, and
  `git diff --check` cover the static QML and shell boundaries.

## Live Activation

The exact working tree was synchronized with `scripts/dev-sync-install.sh` on
Fedora 44. The initial supported path installed the missing `xsettingsd`
dependency. The final exact synchronization created rollback backup
`20260828T153709Z-1472673` and verified that the installed binary, commands,
managed data, and Quickshell tree match the checkout.

After a full DWM logout/login, `/proc` exposed `/usr/local/bin/dwm` without a
deleted-inode suffix and its checksum matched both the installed binary and the
checkout build. The fresh session ran one managed Quickshell instance with a
visible panel and five registered tray clients. Installed IPC opened the
Control Center and Settings Appearance surfaces; Settings reached `ready` on
Fedora Linux 44 with the appearance provider available, and the shared panel
model reported safe defaults with all five configurable widgets enabled. The
installed Settings window opened at 1180x760 with all nine sections visible,
compact display controls, and text-scale-responsive inputs. After closing it,
one Quickshell process retained five tray clients and measured 0.000% CPU over
a five-second live sample.

The workstation exposed one active 1920x1080 monitor during this acceptance
check, so real multi-monitor persistence was not exercised. Shared model and
persistence behavior across panel consumers remains covered by the passing
nested-X11 validation.
