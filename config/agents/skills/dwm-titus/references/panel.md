# dwm-titus panel (Quickshell)

The bar, launcher, notifications, Control Center, Settings, network,
Bluetooth, power menu, and tray are one Quickshell instance loaded from
`~/.config/quickshell/shell.qml`. dwm's own bar is not used.

## Managed directory

- `~/.config/quickshell/` is replaced on every `make install-user`, update, or
  `dev-sync-install.sh`. Edits there are lost. Tell the user this before any
  QML change.
- The supported user customization is per-widget on/off, stored in
  `~/.config/dwm-titus/panel-widgets.conf`:

  ```bash
  dwm-panel-settings status
  dwm-panel-settings set <workspaces|volume|bluetooth|network|power> disabled
  dwm-panel-settings reset
  ```

- There is no supported way to change panel layout, widget order, or add
  custom widgets. Changes like that are upstream work in
  `config/quickshell/` of the dwm-titus repository; use `$quickshell` for the
  QML and follow that repository's `AGENTS.md`.

## IPC

All calls target the managed config path:

```bash
qs_ipc() {
  quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" \
    call "$@"
}
qs_ipc launcher toggle
qs_ipc controlcenter openKeybinds
qs_ipc notifications toggleHistory
qs_ipc tray count
```

Targets: `launcher`, `menu`, `power`, `network`, `controls`,
`notifications`, `controlcenter`, `systemhealth`, `settings`, `tray`. Read the
`IpcHandler` blocks in `~/.config/quickshell/shell.qml` for each target's
functions before calling one.

Over SSH, import `DISPLAY` and `XAUTHORITY` from the running dwm first (see
`session.md`); without them `quickshell list` and `quickshell log` report no
running instances.

## Restart

```bash
dwm-quickshell-controlcenter action restart-quickshell
```

Do not run `quickshell --path <repo>/config/quickshell` against a live
session. Quickshell treats each config path as a separate IPC instance, so
hotkeys stop reaching the panel.
