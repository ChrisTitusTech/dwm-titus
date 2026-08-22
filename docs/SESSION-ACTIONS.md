# Session Action Contract

## Purpose

The managed Quickshell exposes lock, logout, suspend, reboot, and shutdown
through one root-scoped `PowerMenuModel`. The panel, Control Center, and
Settings use the same action inventory, confirmation state, helper process,
and result state.

QML never owns a system command, shell fragment, D-Bus destination, or
elevated helper path. It passes one fixed action ID to the existing managed
Control Center helper.

## Helper Protocol

The fixed interface is:

```text
dwm-quickshell-controlcenter session-action lock|logout|suspend|reboot|shutdown
```

After the selected provider accepts the request, the helper emits exactly:

```text
session-action  ACTION  accepted
```

Records are tab-separated. Missing, extra, or unknown arguments fail. A
missing provider, timeout, authorization denial, locker failure, malformed X11
owner, or failed signal emits no success record. The QML model requires the
exact expected record and treats every other result as failure.

`accepted` describes provider acceptance, not completion of a reboot,
shutdown, suspend/resume cycle, or logout teardown.

## Action Ownership

- Lock runs the managed `dwm-lock` chain and succeeds only when a supported
  locker accepts the request. A foreground locker may keep the model busy
  until unlock.
- Suspend, reboot, and shutdown use fixed, bounded `systemctl --no-block`
  operations. systemd-logind and polkit retain service and authorization
  policy.
- Logout signals only the current verified dwm process. DWM exits its normal
  event loop, performs cleanup, and runs the existing bounded autostop hook.
  The helper does not terminate a logind session directly.

No action uses `sudo`, `pkexec`, a generic command runner, or a writable helper
selected by QML.

## Confirmation and Origin Lifecycle

Logout, suspend, reboot, and shutdown are destructive and always require
confirmation. Lock does not. Confirmation records the initiating surface and
cannot be accepted from a different surface.

Only one action process may run. A request received while it is active is
rejected without replacing the original action, generation, or origin.
Progress and failures remain attributed to the initiating surface. Closing a
surface cancels only its unexecuted confirmation; an accepted action remains
root-owned and is not killed midway.

The model has no polling timer, event subscription, or resident helper.

## Graceful Current-DWM Logout

DWM publishes its PID as `_NET_WM_PID` on the
`_NET_SUPPORTING_WM_CHECK` window and handles `SIGUSR2` by setting its main-loop
run flag to false. Before signaling, the helper verifies all of the following
twice:

1. The current X11 root has one syntactically valid supporting-window ID.
2. The support window points to itself and identifies itself as `dwm`.
3. `_NET_WM_PID` is a valid non-system PID owned by the invoking UID.
4. `/proc/PID/exe` has basename `dwm`; the literal kernel `(deleted)` suffix,
   preceded by one space, is accepted for a safely replaced installed
   executable.
5. The process is not a zombie and its start time is unchanged.

The second complete resolution prevents a concurrent window-manager
replacement from being folded into the captured identity. No broad process
name signal is used, so other dwm processes, nested displays, Quickshell
instances, and unrelated shell providers are outside the target.

Display-manager and `startx` behavior then remains owned by `autostop.sh`:
display-manager X11 sessions may terminate their verified logind scope, while
`startx` returns to its inherited TTY.

## Recovery

### Failed locker

The session remains active and the initiating surface shows the `dwm-lock`
failure. Install or start a supported locker, then retry Lock. Do not interpret
an absent locker as a locked screen.

### Denied or unavailable logind action

The helper emits no success record and the session remains active. Verify the
user polkit agent and `systemd-logind`, then retry from the same surface. There
is no sudo fallback.

### Incomplete graphical-session startup

Check the managed Quickshell tray IPC endpoint and inspect:

```sh
systemctl --user status wm-graphical-session.service
systemctl --user status graphical-session.target xdg-desktop-autostart.target
systemctl --user show-environment
```

The display and D-Bus environment must be imported before the graphical target
starts. A missing optional component must not terminate dwm. Use the supported
login or `startx` path again after correcting the failing component; do not
start a second repository-local Quickshell instance.

### Installed DWM not active yet

Installing a new binary does not replace a running process image. An older DWM
without `_NET_WM_PID` and the graceful signal endpoint causes Logout to fail
with an explicit restart message. Use the existing `Super+Shift+Q` normal quit,
log in or run `startx` again, and verify `/proc/PID/exe` resolves to the new
installed binary before retrying.

## Validation Boundary

The session-action core does not add a new startx process registry. Existing
display-scoped Quickshell recovery, graphical-target cleanup, parent-bound
watchers, and autostop rules must be qualified through repeated real
display-manager and `startx` login/logout cycles. Any residual Quickshell,
locker, portal, status, watcher, or XDG autostart process is a release blocker,
not an accepted limitation.
