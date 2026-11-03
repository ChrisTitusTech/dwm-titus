---
name: dwm-titus
description: Customize the dwm-titus X11 desktop, including TOML keybindings, themes, window rules, panel widgets, autostart, wallpaper, picom, lock, and LightDM. Use for end-user changes, not diagnosis.
---

# dwm-titus

dwm-titus is Chris Titus Tech's Fedora/X11 desktop: patched dwm plus a managed
Quickshell panel and `dwm-*` helpers. Upstream:
https://github.com/ChrisTitusTech/dwm-titus. Route failures ("X is broken",
"why did Y stop") to `$dwm-titus-debug`.

## Workflow

1. Identify the owning layer before editing:
   - keys, mouse, themes, window rules: `~/.config/dwm-titus/*.toml`
   - modifier key, fonts, tags, layouts, mfact: `config.h` in the source
     checkout (rebuild required)
   - panel widgets: `dwm-panel-settings`; settings with a helper:
     `dwm-settings-*`, `dwm-xdg-autostart`, `dwm-default-apps`
   - login screen: `/etc/lightdm/slick-greeter.conf` (root)
2. Read the user file and its packaged default in
   `~/.local/share/dwm-titus/config/`. Discover helpers with
   `ls /usr/local/bin/dwm-*` and read a helper's source for its subcommands;
   most helpers have no `--help`.
3. Prefer a helper or Settings backend when one owns the setting. Otherwise
   back up the file, then make the smallest edit inside the existing structure.
4. Apply: TOML saves hot-reload (or `kill -USR1 "$(pidof dwm)"`); restart the
   panel only with `dwm-quickshell-controlcenter action restart-quickshell`;
   `config.h` changes need `./scripts/dev-sync-install.sh` in the checkout
   (it uses sudo; ask first) and a new dwm session.
5. Verify the result: check the newest `dwm: loaded N ...` lines in
   `~/.xsession-errors` and watch for a critical "dwm: bad config"
   notification. Capture a screenshot for visual changes.

## Resources

- Read `references/config.md` for hotkeys, themes, window rules, `config.h`,
  and generated files.
- Read `references/helpers.md` before running any `dwm-*` helper.
- Read `references/panel.md` for Quickshell panel, IPC, and widget changes.
- Read `references/session.md` for autostart, wallpaper, picom, display,
  input, lock, idle, LightDM, and screenshots.

## Diagnostics

```bash
echo "$XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP"
ls -la ~/.config/dwm-titus/
grep 'dwm: ' ~/.xsession-errors | tail -n 8
xdotool getactivewindow getwindowclassname
dwm-panel-settings status
```

Over SSH, first import `DISPLAY` and `XAUTHORITY` from the running dwm (see
`references/session.md`, "Screenshots"). Run only what the change needs.

## Safety Rules

- Never edit `/usr/local/bin`, `/usr/local/libexec/dwm-titus`, or
  `~/.config/quickshell`; installs replace them.
- Never overwrite `config.h`, user TOML files, or `~/.xinitrc`; back up first.
- Never hand-edit generated files such as `theme-env.sh`, `xsettingsd.conf`,
  or `cursor.Xresources`; change the source setting instead.
- Do not edit `~/.local/share/dwm-titus/scripts/autostart.sh`; installs replace
  it. Use XDG autostart entries.
- Use `dnf` only. Ask before root changes such as LightDM or Xorg files; use
  `$linux-sysadmin` for host-level work when available.
- Use `$quickshell` for QML work and `$bash-scripting` for shell scripts when
  available. Otherwise follow the checkout's `AGENTS.md`, configured QML lint,
  ShellCheck, and focused runtime tests.
- Do not start Quickshell with a repo-local `--path`; IPC targets the managed
  `~/.config/quickshell/shell.qml` instance.
- Do not drive the live session with `xdotool type` or `xdotool key`; a held
  or remapped modifier turns text into MODKEY bindings. Use helpers and IPC.

## Validation

- The `dwm: loaded N ...` counts match the intended change, with no
  `unknown keysym`, `unknown func`, or "bad config" messages.
- The new binding, rule, or theme works in the live session.
- Unrelated keybindings, the panel, and the tray still work.
- Report changes that need a re-login or rebuild separately from verified ones.

## AI assistance

Read `references/ai-assist.md` when using the packaged agent launcher, crash
notifications, or optional hang detection.
