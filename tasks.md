# Quickshell Active Tasks

This file tracks the next reviewable work for the Quickshell migration.
Long-term sequencing lives in `docs/ROADMAP.md`; product requirements remain
in `SPEC.md`.

## Completed Phase: Quickshell Baseline

Goal: install Quickshell and confirm it works reliably under Xorg before
replacing Polybar, Rofi, Dunst, or other existing shell components.

- [x] Install Quickshell.
  - Acceptance: `quickshell --version` or the equivalent package command
    confirms Quickshell is installed.
  - Validation: record the installed version and package source.
  - Result: installed `quickshell-0.2.1^git20260209.dacfa9d-3.fc44` from the
    Fedora updates repository with `jemalloc-5.3.0-14.fc44` as a dependency.
    `quickshell --version` reports `quickshell 0.2.1`, revision
    `dacfa9de829ac7cb173825f593236bf2c21f637e`, distributed by Fedora Project.
- [x] Create the base Quickshell config directory.
  - Acceptance: the config lives under the expected XDG config path and does
    not replace existing dwm, Polybar, Rofi, or Dunst configuration.
  - Validation: inspect the created path and confirm existing config files are
    still present.
  - Result: created `/home/titus/.config/quickshell` under
    `XDG_CONFIG_HOME=/home/titus/.config`. Existing
    `/home/titus/.config/dwm-titus`, `/home/titus/.config/polybar`, and
    `/home/titus/.config/rofi` directories remained present; no existing Dunst
    config directory was present to preserve.
- [x] Launch a minimal Quickshell window manually.
  - Acceptance: a minimal test window starts and exits without breaking the
    current dwm session.
  - Validation: run it from a terminal inside the current Xorg session and
    record any stderr output.
  - Result: created `/home/titus/.config/quickshell/shell.qml` with a minimal
    `ShellRoot` and `FloatingWindow` baseline. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` from the active session exited with status 0 after the test
    timer and reported `Configuration Loaded`. `quickshell list` and
    `pgrep -a quickshell` confirmed no remaining Quickshell process.
- [x] Confirm Quickshell starts correctly inside the current Xorg session.
  - Acceptance: Quickshell starts with `XDG_SESSION_TYPE=x11` and the active
    window manager remains dwm.
  - Validation: record `echo "$XDG_SESSION_TYPE"`, `echo "$DESKTOP_SESSION"`,
    and the Quickshell launch result.
  - Result: `XDG_SESSION_TYPE=x11`, `DESKTOP_SESSION=dwm`, and `DISPLAY=:0`.
    `pgrep -a dwm` showed `/usr/local/bin/dwm`, and `wmctrl -m` reported
    `Name: dwm`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` in that session exited with status 0 and reported
    `Configuration Loaded`.
- [x] Confirm Quickshell does not interfere with the current window manager.
  - Acceptance: dwm focus, tagging, terminal launch, and existing keybindings
    still work while the minimal Quickshell process is running.
  - Validation: manually exercise the core workflow and record the result.
  - Result: with the minimal Quickshell window running, `Super+X` launched an
    Alacritty terminal, `Super+J` moved focus from the terminal back to the
    Quickshell baseline window, `Super+2` changed `_NET_CURRENT_DESKTOP` from
    0 to 1, and `Super+1` returned it to 0. The test terminal was closed with
    `wmctrl -ic`, Quickshell was stopped, `quickshell list` and
    `pgrep -a quickshell` confirmed no remaining instance, and `wmctrl -m`
    still reported `Name: dwm`.
- [x] Add a temporary startup command while keeping Polybar and Rofi enabled.
  - Acceptance: Quickshell can be started with the session without removing
    the current fallback shell tools.
  - Validation: restart the session or startup script in a controlled test and
    confirm Polybar/Rofi still work.
  - Result: added a temporary Quickshell startup block to
    `scripts/autostart.sh` that runs `quickshell --no-duplicate` only when
    `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml` exists. The
    existing Polybar launch remains in place, and Rofi remains installed at
    `/usr/bin/rofi` with the existing app-launcher hotkeys still present in
    `hotkeys.toml`. `make check-session-guards` passed with mocked
    display-manager and `startx` runs, confirming Quickshell starts once while
    Polybar still launches and duplicate guards continue to work. `make
    check-shell`, `make check-format`, and `git diff --check` also passed.

## Completed Phase: Basic Quickshell Panel

Goal: replace Polybar with a simple Quickshell top panel while keeping Polybar
available as the fallback until the Quickshell panel is usable.

- [x] Build a basic `PanelWindow`.
  - Acceptance: a tracked Quickshell config creates a top panel matching the
    current 30px Polybar height.
  - Validation: launch the config in the active Xorg/dwm session and confirm
    Quickshell reports a running X11 instance while dwm remains the active
    window manager.
  - Result: added `config/quickshell/shell.qml` and synced the active user
    config at `/home/titus/.config/quickshell/shell.qml`. The config creates a
    30px top `PanelWindow` for each `Quickshell.screens` entry, uses the
    current Polybar Nord colors, and sets `exclusiveZone: 30`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; `wmctrl -m` still reported `Name: dwm`; and
    `quickshell list` confirmed no running instance after stopping the test
    process.
- [x] Add clock/date.
  - Acceptance: the panel displays a live date/time value without creating one
    process loop per monitor.
  - Validation: launch the config in the active Xorg/dwm session and confirm
    Quickshell loads, remains listed as an X11 instance, and the date command
    used by the panel returns the expected format.
  - Result: added one shared `clockText` property, a `date` process, and a
    repeating timer to `config/quickshell/shell.qml`. The panel now binds its
    right-side text to `root.clockText`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; `date '+%a %b %d  %H:%M'` returned the expected
    format; and `wmctrl -m` still reported `Name: dwm`.
- [x] Add CPU/RAM indicators.
  - Acceptance: the panel displays a lightweight CPU/RAM summary without
    requiring Polybar or a new package dependency.
  - Validation: run the status command directly, then launch the config in the
    active Xorg/dwm session and confirm Quickshell remains running.
  - Result: added one shared `systemText` property, a `/proc/loadavg` and
    `/proc/meminfo` status process, and a 5 second update timer to
    `config/quickshell/shell.qml`. The command returned output in the form
    `CPU 0.59  RAM 10%`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; and `wmctrl -m` still reported `Name: dwm`.
- [x] Add network indicator.
  - Acceptance: the panel displays the default route interface and link state,
    with an offline fallback when no default route exists.
  - Validation: run the network status command directly, then launch the config
    in the active Xorg/dwm session and confirm Quickshell remains running.
  - Result: added one shared `networkText` property, a default-route network
    status process, and a 10 second update timer to
    `config/quickshell/shell.qml`. The command returned `NET wlo1 up` on the
    current session. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; and `wmctrl -m` still reported `Name: dwm`.
- [x] Add volume indicator.
  - Acceptance: the panel displays the default sink volume and muted state,
    with a fallback when `pactl` is unavailable.
  - Validation: verify `pactl` can read the default sink, run the volume status
    command directly, then launch the config in the active Xorg/dwm session.
  - Result: added one shared `volumeText` property, a `pactl` based status
    process, and a 5 second update timer to `config/quickshell/shell.qml`.
    `pactl get-sink-mute @DEFAULT_SINK@` returned `Mute: no`, `pactl
    get-sink-volume @DEFAULT_SINK@` reported 40%, and the panel command
    returned `VOL 40%`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; and `wmctrl -m` still reported `Name: dwm`.
- [x] Add battery/power indicator if needed.
  - Acceptance: if a battery is present, the panel displays battery capacity
    and charging state; otherwise it falls back to AC-only text.
  - Validation: inspect `/sys/class/power_supply`, run the battery status
    command directly, then launch the config in the active Xorg/dwm session.
  - Result: `/sys/class/power_supply` exposes `BAT0`, which reported 71% and
    `Discharging`. Added one shared `powerText` property, a sysfs battery
    status process, and a 30 second update timer to
    `config/quickshell/shell.qml`. The command returned
    `BAT 71% Discharging`. Running
    `quickshell --path /home/titus/.config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`; `quickshell list` showed the
    instance on `x11,:0`; and `wmctrl -m` still reported `Name: dwm`.
- [x] Reserve screen space correctly.
  - Status: validated with a controlled rebuilt dwm launch under Xvfb.
  - Finding: this dwm fork does not reserve space from `_NET_WORKAREA`.
    Instead, `managealtbar()` records an external bar as `m->barwin`, copies
    its window height to `m->bh`, and `updatebarpos()` subtracts `m->bh` from
    `m->wh` while shifting `m->wy` down for a top bar.
  - Implementation: Quickshell's X11 `PanelWindow` does not expose
    `WM_CLASS`, but it does expose `_NET_WM_WINDOW_TYPE_DOCK`. `dwm.c` now
    keeps the existing Polybar `WM_CLASS=Polybar` path and also treats
    bar-shaped dock windows as altbars so Quickshell can enter the same
    `managealtbar()` reservation path after the rebuilt dwm is running.
  - Validation: Quickshell inspection showed no `WM_CLASS` and
    `_NET_WM_WINDOW_TYPE_DOCK`; `make clean`, `make`, and `git diff --check`
    passed. After installing the rebuilt binary with `sudo make
    install-system`, a controlled Xvfb session launched `/usr/local/bin/dwm`,
    then launched Quickshell. `wmctrl -m` reported `Name: dwm`; the
    Quickshell dock window was `1280x30` at `0,0`; and a normal tiled X11 test
    client was placed at `y=60` with height `690`, confirming dwm reserved the
    panel area before tiling clients.
- [x] Match current bar height and monitor placement.
  - Acceptance: the Quickshell panel uses the current top bar placement and
    30px height.
  - Validation: the controlled Xvfb session reported the Quickshell dock as
    `1280x30` at `0,0`, matching the configured top panel height and placement.
- [x] Disable Polybar only after Quickshell panel is usable.
  - Acceptance: normal session startup launches Quickshell as the panel when
    its config exists and keeps Polybar as a fallback when Quickshell is not
    configured.
  - Validation: live X11 session plus autostart guard tests.
  - Result: after adding `aboveWindows: true` to the Quickshell panel and
    restarting Quickshell in the live Fedora X11/dwm session, `xprop` showed
    `_NET_WM_WINDOW_TYPE_DOCK`, `_NET_WM_STATE_ABOVE`,
    `_NET_WM_STRUT`, and `_NET_WM_STRUT_PARTIAL` reserving 30px at the top.
    `xdotool getwindowgeometry` reported the active terminal at `0,30` with
    geometry `2560x1570`, confirming the window manager respected the panel
    reservation. `pgrep -af 'quickshell|polybar'` showed Quickshell running
    and no Polybar process. `scripts/autostart.sh` now starts Quickshell when
    `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml` exists and only
    launches Polybar when that Quickshell config is absent; the autostart test
    covers both paths.

## Completed Phase: Workspace and Window State Integration

Goal: expose dwm workspace/tag state and active-window state to Quickshell
without making Quickshell responsible for primary workspace control.

- [x] Decide how workspace/tag state will be exposed.
  - Acceptance: the bridge uses existing Xorg/EWMH state instead of adding a
    new window-manager IPC dependency.
  - Validation: inspect the implementation and run it in the active Xorg/dwm
    session.
  - Result: `scripts/dwm-quickshell-state` reads `_NET_CURRENT_DESKTOP`,
    `_NET_NUMBER_OF_DESKTOPS`, `_NET_DESKTOP_NAMES`, and `_NET_ACTIVE_WINDOW`
    using `xprop`, with `xdotool getactivewindow` as the primary active-window
    lookup. Its `watch` mode follows `xprop -root -spy` events for the same
    root-window properties instead of polling from QML. `dwm-quickshell-state
    watch` returned `current=0`, `count=9`, `names=1|2|3|4|5|6|7|8|9`, and the
    active window title from the live Fedora X11/dwm session.
- [x] Create a script or IPC bridge for current workspace/tag.
  - Acceptance: the bridge is tracked, executable, installed in the normal
    command path, and has fallback output when EWMH data is missing.
  - Validation: compare the installed command with the repository copy and run
    lint/format checks.
  - Result: `/usr/local/bin/dwm-quickshell-state` matched
    `scripts/dwm-quickshell-state`. `shellcheck scripts/dwm-quickshell-state`,
    `shfmt -d scripts/dwm-quickshell-state`, and `git diff --check` passed.
- [x] Display active workspace/tag in Quickshell.
  - Acceptance: the tracked Quickshell config consumes bridge output and marks
    the active workspace distinctly.
  - Validation: inspect `config/quickshell/shell.qml` and launch it directly.
  - Result: `config/quickshell/shell.qml` runs `dwm-quickshell-state watch`,
    parses state blocks with `SplitParser`, renders workspace labels with a
    `Repeater`, and highlights the current workspace. Running
    `timeout 6s quickshell --path config/quickshell/shell.qml --no-color
    --log-times` reported `Configuration Loaded`.
- [x] Add clickable workspace/tag switching if practical.
  - Acceptance: clicking a workspace label invokes a safe switch command while
    existing dwm keybindings remain the primary control path.
  - Validation: inspect the click handler and perform a no-op switch to the
    current workspace.
  - Result: each workspace label has a `MouseArea` that runs
    `dwm-quickshell-state switch <index>`, and the bridge uses `wmctrl -s`.
    Running the switch command against the current workspace completed
    successfully and left `_NET_CURRENT_DESKTOP` unchanged at `0`.
- [x] Display active window title.
  - Acceptance: Quickshell displays the active window title from the bridge and
    bounds the label so long titles do not consume the full panel.
  - Validation: run the bridge in the live session and inspect the panel label.
  - Result: `scripts/dwm-quickshell-state` returned the current active window
    title, and `config/quickshell/shell.qml` binds it to a `Text` element with
    `Layout.maximumWidth: 360` and `elide: Text.ElideRight`.
- [x] Add fallback behavior when no active window exists.
  - Acceptance: missing active-window data does not leave an empty or invalid
    panel label.
  - Validation: inspect the script and QML fallback paths.
  - Result: the bridge falls back from `xdotool getactivewindow` to
    `_NET_ACTIVE_WINDOW`, then emits `title=Desktop` when no title is
    available. The QML parser also falls back to `Desktop` for an empty title.

Validation notes:

- `make clean`, `make`, `make check-shell`, `make check-format`,
  `make check-install-preservation`, `make check-session-guards`,
  `make check-install`, `make check-xvfb-runtime`, and
  `make check-monitor-tags` passed after the Phase 3 cleanup.
- `sudo make install` passed on the live Fedora X11 host and printed
  `Replacing managed Quickshell config`, confirming the normal privileged
  install path refreshes `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/`.
- `wmctrl -m` reported `Name: dwm` with `DISPLAY=:0`,
  `XDG_SESSION_TYPE=x11`, and `DESKTOP_SESSION=dwm`.
- The live managed config at `/home/titus/.config/quickshell/shell.qml` was
  synced with tracked `config/quickshell/shell.qml`, and the default Quickshell
  instance was restarted with `quickshell --no-duplicate --daemonize`.
- `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` is treated as a managed
  dwm-titus directory. `install-user` replaces it from tracked
  `config/quickshell/` so `sudo make install` cannot leave stale Quickshell
  code in the active session config.

## Backlog

- [ ] Replace the Rofi app launcher.
- [ ] Add a Quickshell power/user menu.
- [ ] Replace Dunst or other notification UI.
- [ ] Move tray functionality into Quickshell.
- [ ] Add media, audio, and quick controls.
- [ ] Centralize Quickshell styling and reusable components.
- [ ] Remove old dependencies only after Quickshell replacements are stable.
- [ ] Document rollback steps and keep the old shell stack available until the
      migration is proven stable.

## Validation Policy

A task is complete only when its acceptance criteria pass or the exact skipped
environment is recorded. Do not remove Polybar, Rofi, or Dunst from the normal
startup path until the Quickshell replacement for that component has been
validated and rollback steps are documented.
