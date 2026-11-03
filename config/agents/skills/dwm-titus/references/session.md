# dwm-titus session, login, and lock

## Startup chain

1. LightDM starts `/usr/share/xsessions/dwm.desktop` (`/usr/local/bin/dwm`)
   through the Fedora Xsession wrapper; stdout and stderr go to
   `~/.xsession-errors`. `~/.xinitrc` is only for `startx`.
2. dwm runs `~/.local/share/dwm-titus/scripts/autostart.sh` on start and
   `autostop.sh` on exit.
3. autostart applies power and input settings, theme env, xsettingsd, starts
   Quickshell, then starts `wm-graphical-session.service` (user unit), which
   brings up `graphical-session.target` and XDG autostart. Wallpaper, picom,
   `dwm-status`, `dwm-lock-watch`, and a polkit agent follow in the
   background.

## Autostart programs

- Add a `.desktop` file to `~/.config/autostart/`. If it uses `OnlyShowIn`,
  include `X-DWM`. It runs at the next login through systemd's XDG autostart.
- Enable or disable existing entries with `dwm-xdg-autostart` or Settings >
  Defaults. Vendor files are never edited; a user override is written instead.
- Do not edit `autostart.sh`; installs replace the data directory scripts.

## Wallpaper and picom

- Wallpaper: `dwm-settings-wallpaper apply <path> fill`, `randomize`, or
  `reset`. Pool directory: `~/Pictures/backgrounds`.
- Picom config resolution: `$DWM_PICOM_CONFIG`, the running picom's
  `--config`, `~/.config/picom.conf`, `~/.config/picom/picom.conf`, then
  `/etc/xdg`. With no file, picom runs on defaults. To seed a user copy, read
  `revision` from `dwm-settings-picom status` (JSON) and pass it to
  `dwm-settings-picom copy-config <revision>`; then `reload` or `restart`.
  Log: `~/.local/state/dwm-titus/picom/session.log`.

## Display and input

- Session layouts: `dwm-display-profile list|apply <name>|template`; profiles
  in `~/.config/dwm-titus/display-profiles/`.
- Persistent Xorg layout (root): `dwm-display-setup wizard`, writes
  `/etc/X11/xorg.conf.d/90-dwm-titus-display.conf`; undo with
  `dwm-display-setup rollback`.
- Input devices: Settings > Input, backed by `dwm-settings-input` and
  `~/.config/dwm-titus/input-settings.conf`.

## Lock, idle, and DPMS

- `dwm-lock` locks now (light-locker first, then fallbacks). `dwm-lock-watch`
  turns logind Lock requests (`loginctl lock-session`) into `dwm-lock`.
- Idle lock and DPMS are off by default. Settings live in
  `~/.config/dwm-titus/power.conf`; each setter writes the file and applies it:

  ```bash
  dwm-quickshell-controlcenter power-status
  dwm-quickshell-controlcenter power-lock on
  dwm-quickshell-controlcenter power-lock-timeout 600
  dwm-quickshell-controlcenter power-dpms on
  dwm-quickshell-controlcenter power-dpms-timeout 900
  ```

- Suspend from the power menu does not call `dwm-lock` first; lock-on-suspend
  depends on light-locker running with idle lock enabled.

## LightDM greeter (root)

- Installed by the repository's `lightdm/Makefile`: `/etc/lightdm/lightdm.conf`
  (generated), `/etc/lightdm/slick-greeter.conf`, and images in
  `/usr/share/pixmaps/dwm-titus*`.
- To change the background or theme, edit `/etc/lightdm/slick-greeter.conf`
  (`background=`, `theme-name=`, `font-name=`) with root after a backup. Put a
  custom image outside `/usr/share/pixmaps/dwm-titus.jpg`. `install.sh` runs
  `make -C lightdm install`, which overwrites `slick-greeter.conf` and that
  image without a backup; tell the user that edits must be re-applied after a
  reinstall. Restore SELinux labels with `restorecon` on changed
  files. The change shows at the next greeter start.
- Logs in `/var/log/lightdm/` are root-only.

## Screenshots

- `dwm-screenshot screen|full|gui|clip`; files go to
  `$(xdg-user-dir PICTURES)/Screenshots/`.
- From SSH or an agent without a picker, import the session display from the
  running dwm, then capture with `maim`:

  ```bash
  pid=$(pidof -s dwm) &&
    while IFS= read -r -d '' kv; do
      case $kv in DISPLAY=* | XAUTHORITY=*) export "$kv" ;; esac
    done <"/proc/$pid/environ"
  echo "DISPLAY=${DISPLAY:-unset} XAUTHORITY=${XAUTHORITY:-unset}"
  maim "$HOME/dwm-debug.png"
  ```

  LightDM keeps the authority file in `/run/lightdm/<username>/xauthority`.
