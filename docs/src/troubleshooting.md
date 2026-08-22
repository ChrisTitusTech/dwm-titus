# Troubleshooting

## Gear Lever does not open

Gear Lever requires Flatpak's document portal. If launching it prints a
`bwrap: Can't find source path /run/user/.../doc/by-app/...` error, the portal
process has outlived its FUSE mount. Repair the current user session with:

```sh
systemctl --user restart xdg-document-portal.service
flatpak run it.mijorus.gearlever
```

The recommended and full installers include Flatpak, the GTK portal, and a
user-scoped Gear Lever installation from Flathub by default. To repair only the
application setup from an installed dwm-titus checkout, run:

```sh
install-gearlever
```

Run the dependency checker first — it covers most common issues:

```bash
dwm-diagnostics
```

Or use the [Control Center](./control-center.md) → **System Health**.

---

## dwm Won't Start

**Black screen / returns immediately to login:**
- Run `dwm-diagnostics` and resolve any required X11/session failures.
- Preview required packages with `./install.sh --dry-run --profile core`.
- Check `.xinitrc` exists and ends with `exec dwm`
- Run `startx` from a TTY to see error output in the terminal

**`dwm: cannot open display`:**
- You must launch dwm from a TTY, not an existing X session
- If using a display manager, ensure `dwm.desktop` is in `/usr/share/xsessions/`

---

## No Status Bar / Quickshell Missing

- Install the recommended desktop layer: `./install.sh --profile recommended`
- Verify the managed config exists: `ls ~/.config/quickshell/shell.qml`
- Run manually: `quickshell --no-duplicate`
- Check fonts: `fc-list | grep -i meslo`

---

## Terminal Won't Open (`Super`+`X`)

- Run `alacritty` from an existing shell to inspect its error directly
- Install Alacritty with `sudo dnf install alacritty`
- Confirm the fixed terminal in `config/hotkeys.toml`:
  ```toml
  [vars]
  terminal = "alacritty"
  ```

Herdr is an optional terminal workspace, not a graphical terminal emulator.
Install it explicitly and use `DWM_HERDR=1 dwm-terminal` to run it inside
Alacritty. The default `Super`+`X` binding remains plain Alacritty.

## Browser Won't Open (`Super`+`B`)

- Run `dwm-default-apps status` to inspect the current default browser
- Run `dwm-default-apps browsers` to list installed browser desktop files
- Set one with `dwm-default-apps set-browser firefox.desktop`
- Open Settings -> Defaults to inspect provider details, candidates, and the
  Restore Previous action
- Ensure `xdg-utils` is installed so `xdg-settings`, `xdg-mime`, and `xdg-open`
  are available

## Startup Application Change Failed

- Open Settings -> Defaults and inspect the entry origin, effective state, and
  detail. Malformed or conditional vendor entries are intentionally not
  rewritten.
- Changes apply at the next login; Settings does not start or stop the
  application in the current session.
- A stale-revision error means the entry changed after it was displayed. Use
  Refresh and retry.
- Reset to vendor removes only the managed user override. Existing vendor
  desktop files are never edited.

---

## Themes Not Applying

- Confirm `themes.toml` is at `~/.config/dwm-titus/themes.toml`
- Check the `[active]` section has a valid theme name
- Manually trigger: `kill -USR1 $(pidof dwm)`
- Run `theme-apply.sh` directly to see any errors

---

## Keybinds Not Working

- Check `config/hotkeys.toml` for syntax errors — invalid TOML silently fails
- Verify the key name is correct (use `xev` to find X11 key names)
- If a bind still doesn't work, add it as a fallback in `config.h` and recompile

---

## Multi-Monitor Issues

- Tags not syncing across monitors: run `dwm-diagnostics`
- Cursor doesn't follow focus: verify cursor warp is enabled in `config.h` (`cursorwarp = 1`)
- Persistent resolution or positioning: run `dwm-display-setup detect`, then
  `dwm-display-setup`. The wizard previews changes before writing Xorg config.
- Bad persistent layout: run `dwm-display-setup rollback`, then log out and
  back in. From a TTY, remove
  `/etc/X11/xorg.conf.d/90-dwm-titus-display.conf` if Xorg cannot start.
- TearFree is enabled only when the active Xorg driver exposes a compatible
  option or RandR property. Unsupported drivers are left unchanged.
- NVIDIA Full Composition Pipeline is enabled in generated persistence only
  when the relevant output uses the NVIDIA kernel driver and an NVIDIA Xorg
  provider is available, including supported hybrid configurations. Run
  `dwm-display-setup capabilities` to inspect the detected fallback before
  saving a layout.
- Display layout profiles: run `dwm-display-profile dir` and
  `dwm-display-profile template` to create optional `xrandr` profiles

---

## NVIDIA / Suspend Issues

- Black screen on wake: run `scripts/nvidia-suspend-test.sh` to diagnose
- DPMS/screensaver issues: use Control Center -> Power, or run
  `scripts/disable-powersaving` to disable blanking and DPMS for the current
  session

---

## Picom / Compositor Artifacts

Restart picom via the Control Center (**Quick Actions → Restart Picom**) or:
```bash
pkill picom; setsid -f picom --backend xrender
```

If artifacts persist, set a different backend in `~/.config/picom.conf` or run with
`PICOM_BACKEND=glx` or `PICOM_BACKEND=egl`.

---

## Still Stuck?

- Open an issue: [github.com/ChrisTitusTech/dwm-titus/issues](https://github.com/ChrisTitusTech/dwm-titus/issues)
- Run the full check: `bash scripts/check-deps.sh`
