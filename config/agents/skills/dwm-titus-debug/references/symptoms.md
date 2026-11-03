# dwm-titus symptoms and evidence

Collect only the rows that match the symptom. Paths assume the default
LightDM session on Fedora; confirm them on the target system.

## Evidence sources

| Source | Where | Notes |
|---|---|---|
| dwm and app stderr | `~/.xsession-errors`, previous session in `~/.xsession-errors.old` | Apps launched by keybinds inherit dwm's stderr |
| Xorg | `/var/log/Xorg.0.log` | `(EE)` lines; fbdev or vesa module errors are common in VMs |
| LightDM | `/var/log/lightdm/*.log` | Root-only |
| Quickshell | `quickshell log --tail 100`, `quickshell list --all` | Needs `DISPLAY`; files in `/run/user/$UID/quickshell/by-id/` (`log.log` covers startup only) |
| User services | `journalctl --user -b`, `systemctl --user --failed` | XDG autostart entries run as `app-*@autostart.service` |
| Picom | `~/.local/state/dwm-titus/picom/session.log`, `dwm-settings-picom status` | Log truncates at each picom start |
| Updates | `~/.local/state/dwm-titus/desktop-update/status.json` | Shows pending or failed desktop updates |
| Notifications | `~/.cache/dwm-titus/notification-history.json` | Includes "dwm: bad config" alerts |
| Crashes | `coredumpctl list`, `coredumpctl info <pid>` | gdb may be missing; installing it (`dnf install gdb`) is a change, so ask first |

## Symptoms

| Symptom | Collect | Usual causes |
|---|---|---|
| dwm session will not start or drops back to the greeter | `~/.xsession-errors.old`, Xorg log, `dwm-diagnostics` | Missing dependency, broken `/usr/local/bin/dwm` build, wrong session in `/usr/share/xsessions/dwm.desktop` |
| No panel, launcher, or tray | `pgrep -a quickshell`, `quickshell log`, `dwm-quickshell-version-check; echo $?` | Unsupported Quickshell (0.3.0 or the compatible Fedora 44 snapshot is required), QML error after an edit in `~/.config/quickshell`, missing Meslo Nerd Font |
| Keybinding does nothing | `dwm: loaded N keybinds` count, `unknown keysym` or `unknown func` lines, the binding in `hotkeys.toml` | Binding outside the `keys = [ ... ]` array, wrong field name, `SUPER` mapped to a different `MODKEY` in `config.h`, empty user file; a duplicate `mod`+`key` fires both actions instead |
| App launches from a terminal but not from a keybind or the launcher | `~/.xsession-errors` around the launch time, the `exec`/`cmd` value, `command -v <app>` | Command not on dwm's PATH, quoting in `cmd`, Flatpak app id needed |
| Window opens on the wrong tag, floats, or does not | `xprop WM_CLASS WM_NAME` on the window, matching rules in `window-rules.toml` | `float` instead of `isfloating`, later rule resetting `isfloating`, `tags` treated as 1-based |
| Theme only partly applied | `[active]` in `themes.toml`, `theme-apply.sh` output, the apps' generated theme files | Unknown theme name (Nord fallback), app started before the change, hand-edited generated files |
| Startup app missing | `systemctl --user list-units 'app-*autostart*'`, the entry's `OnlyShowIn`/`NotShowIn` | Entry hidden for `X-DWM`, user override from `dwm-xdg-autostart`, change applies only after re-login |
| Portal-dependent app fails (file pickers, screen share, Flatpak) | `journalctl --user -b -u xdg-desktop-portal`, `systemctl --user status graphical-session.target` | Early "Dependency failed" at login is expected until `wm-graphical-session.service` starts; persistent failure is not |
| Tearing, black windows, or transparency problems | `dwm-settings-picom status`, picom log | Backend choice (`xrender` vs `glx`), GPU driver, custom picom config |
| Screen never locks | `dwm-quickshell-controlcenter power-status`, `pgrep -a light-locker`, `xset q` | Idle lock and DPMS are off by default; suspend from the power menu does not lock first |
| Monitor layout wrong after login | `xrandr --listmonitors`, `dwm-display-setup status`, `/etc/X11/xorg.conf.d/90-dwm-titus-display.conf` | Stale Xorg fragment; `dwm-display-setup rollback` restores (root) |
| Process crashed | `coredumpctl info <pid>`, journal around the timestamp, `free -h` and OOM kills | `/usr/local/bin/dwm` is a local build, so Fedora debuginfod has no symbols for it; other Fedora packages resolve through `DEBUGINFOD_URLS` |

## Reporting upstream

Bugs in dwm-titus itself go to https://github.com/ChrisTitusTech/dwm-titus/issues
with `dwm-diagnostics` output, the relevant log lines, the Fedora version, and
whether the install is a git checkout (`git -C <checkout> rev-parse HEAD`). A
screenshot or the exact error text helps. Read that repository's
`CONTRIBUTING.md` before opening a pull request.
