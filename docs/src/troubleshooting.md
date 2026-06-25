# Troubleshooting

Run the dependency checker first — it covers most common issues:

```bash
bash scripts/check-deps.sh
```

Or use the [Control Center](./control-center.md) → **System Health**.

---

## dwm Won't Start

**Black screen / returns immediately to login:**
- Verify Xorg: `pacman -Q xorg-server xorg-xinit`
- Check `.xinitrc` exists and ends with `exec dwm`
- Run `startx` from a TTY to see error output in the terminal

**`dwm: cannot open display`:**
- You must launch dwm from a TTY, not an existing X session
- If using a display manager, ensure `dwm.desktop` is in `/usr/share/xsessions/`

---

## No Status Bar / Polybar Missing

- Install polybar: `sudo pacman -S polybar`
- Verify launch script: `ls ~/.config/polybar/launch.sh`
- Run manually: `~/.config/polybar/launch.sh`
- Check fonts: `fc-list | grep -i meslo`

**Missing icons in Polybar:**
```bash
cp -r config/polybar/fonts/* ~/.local/share/fonts/
fc-cache -fv
```

---

## Terminal Won't Open (`Super`+`X`)

- Run `dwm-terminal` from an existing shell to see the exact fallback message
- Install a supported terminal: `ghostty`, `alacritty`, `kitty`, `st`,
  `warp-terminal`, or `xterm`
- Or set a fixed terminal in `config/hotkeys.toml`:
  ```toml
  [vars]
  terminal = "alacritty"
  ```

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

- Tags not syncing across monitors: run `debug/debug_ewmh.sh`
- Polybar only on one monitor: check `~/.config/polybar/launch.sh` uses `xrandr` to detect monitors
- Cursor doesn't follow focus: verify cursor warp is enabled in `config.h` (`cursorwarp = 1`)

---

## NVIDIA / Suspend Issues

- Black screen on wake: run `scripts/nvidia-suspend-test.sh` to diagnose
- DPMS/screensaver issues: run `scripts/disable-powersaving` or add it to autostart

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
