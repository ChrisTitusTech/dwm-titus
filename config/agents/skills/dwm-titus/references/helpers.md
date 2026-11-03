# dwm-titus helpers

Helpers install to `/usr/local/bin` (privileged parts to
`/usr/local/libexec/dwm-titus/`). Read the source before running one: most have
no `--help`, and several subcommands change state. List the installed set with
`ls /usr/local/bin/dwm-* /usr/local/bin/*.sh`.

## Read-only commands

Safe to run during inspection:

```bash
dwm-diagnostics                  # dependency and session report
dwm-system-health scan-user      # TSV health scan, no changes
dwm-panel-settings status
dwm-settings-picom status
dwm-settings-wallpaper status --read-only
dwm-default-apps status
dwm-xsettings status
dwm-accessibility-settings status
dwm-display-profile list
dwm-display-setup detect
dwm-xdg-autostart snapshot
dwm-quickshell-controlcenter power-status
dwm-desktop-update data-directories
```

Not read-only despite the name: plain `dwm-settings-wallpaper status` and
`dwm-settings-theme preview-status` can reconcile or revert previews.
`dwm-desktop-update check` contacts upstream and writes state.

## Settings (user-level, no root)

| Helper | Use |
|---|---|
| `dwm-settings-theme` | `apply <theme>`, `reset`, `personalize {font,text-size,cursor,icon,gtk,qt} <value>`, `personalize-reset <cap>` |
| `dwm-settings-wallpaper` | `apply <path> <center\|fill\|max\|scale\|tile>`, `randomize`, `reset`; images in `~/Pictures/backgrounds` |
| `dwm-settings-font` | `apply <family> <scale>`, `reset` |
| `dwm-settings-picom` | `start`, `restart`, `reload`, `stop`, `toggle`, `set-opacity`, `set-backend`, `copy-config` (mutations take the `revision` from `status`); JSON output |
| `dwm-settings-input` | per-device xinput settings; Settings UI is the normal front end |
| `dwm-settings-display`, `dwm-display-profile` | xrandr layouts and saved profiles in `~/.config/dwm-titus/display-profiles/` |
| `dwm-display-setup` | Xorg display fragment wizard; `install` and `rollback` use sudo |
| `dwm-accessibility-settings` | `set contrast standard\|high`, `set motion full\|reduced`, `reset` |
| `dwm-default-apps` | `set-browser <id.desktop>`, `set-role <browser\|terminal\|file-manager> <id>`, `set-mime <mime> <id>`, `browsers`, `open [url]` |
| `dwm-xdg-autostart` | enable or disable XDG autostart entries for the next login |
| `dwm-panel-settings` | `set <widget> enabled\|disabled`, `reset` (see `panel.md`) |
| `theme-apply.sh` | re-applies the active theme to apps; dwm runs it on every reload |

The preview/keep/revert/abandon subcommands and `*-ready` checks exist for the
Settings UI. Use the plain `apply` forms from the command line.

## Panel and session

| Helper | Use |
|---|---|
| `dwm-quickshell-controlcenter` | `action restart-quickshell`, `action restart-picom`, `action reload-wallpaper`, `themes`, `theme-set <name>`, `power-*`, `session-action lock\|logout\|suspend\|reboot\|shutdown` |
| `dwm-settings`, `dwm-controlcenter`, `dwm-keybinds` | open the Settings window, Control Center, or keybind cheatsheet over IPC |
| `dwm-session-launch` | wrapper dwm uses for every `spawn`; refreshes theme env, then execs |
| `dwm-terminal` | starts the first available terminal; `--print-command` prints it |
| `dwm-lock`, `dwm-lock-watch` | lock now; watcher for logind Lock requests |
| `dwm-screenshot` | `screen`, `full`, `gui` (region), `clip` (region to clipboard) |
| `dwm-status` | writes the root window name (power and volume) |
| `webapp-create`, `webapp-launch` | create or launch web-app windows; pass the browser command explicitly to `webapp-create` |

## System and updates (ask first)

- `dwm-desktop-update`, `dwm-initial-update`, and `dwm-system-management`
  change packages or system state; run them only when the user asks.
- `dwm-system-health repair-user <id>` restarts picom, Quickshell, or audio,
  manages user services, or installs dependencies.
- `dwm-quickshell-controlcenter session-action logout|suspend|reboot|shutdown`
  ends or suspends the session.
- `scan-privileged`, `repair-privileged`, and `repair-system` prompt for root.
- `install.sh` and `dev-sync-install.sh` live in the source checkout. The
  update steps are `git pull --ff-only`, then
  `./install.sh --non-interactive --yes --profile recommended`, then
  `./scripts/dev-sync-install.sh`, then a re-login.
