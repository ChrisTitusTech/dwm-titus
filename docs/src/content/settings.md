---
title: Settings
description: Manage displays, input, network, Bluetooth, audio, power, defaults, startup apps, and appearance from one place.
navLabel: Settings
eyebrow: Desktop control
---

# Settings

The unified Settings application provides one place to inspect desktop
capabilities and see which features are available, restricted, or planned.

Open Control Center with `Super+F1`, then select **Settings** from the main
menu. You can also run:

```bash
dwm-settings open
```

The Displays section discovers connected outputs and their advertised modes,
lets you edit resolution, refresh rate, position, rotation, primary state, and
output enablement, and manages named layouts. Choose **Apply changes** to test
the complete layout for 15 seconds, then **Keep changes** to accept it or
**Revert** to restore the captured layout. Timeout or closing Settings also
restores the prior layout. Saved layouts can be reused later; **Use at next
login** installs the selected layout for future X11 sessions after a separate
confirmation and administrator authorization.
The machine-oriented `dwm-settings-display` helper exposes `discover` and
`watch`, complete-layout `save` and `preview`, named `preview-profile`, timed
`keep`, `revert`, and `preview-status`, plus authorized `install-profile` and
`rollback-system` actions. Named layouts live under the dwm-titus XDG config
directory. Legacy incomplete layouts remain available to
`dwm-display-profile`, but Settings requires them to be resaved as complete
layouts before preview or persistent installation.

The Input section shows each XInput device by a stable hardware identity and
offers only properties its driver exposes. Pointer acceleration, natural
scrolling, tap-to-click, keyboard layout, and modifier options are supported
when available. Changes use a timed preview with Keep and Revert. Reset is a
separate direct action that restores and persists the driver's default. Kept
values are reapplied idempotently at session startup when the device exposes a
stable udev or physical sysfs identity. Devices without one remain
session-configurable and report that persistence is unavailable. Unsupported
per-device properties remain visible with an explanation.

The same section exposes session-wide XKB accessibility shortcuts, sticky keys,
slow keys, bounce keys, and mouse keys when `xkbset` can reach the X11 session.
These controls use the same 15-second preview and reset workflow, but are not
tied to one physical keyboard. Kept choices are restored at the next login.

The Appearance section also manages notification behavior. **Do Not Disturb**
suppresses low and normal urgency popups without discarding their history;
critical notifications remain visible. Choose a four-, six-, or ten-second
ordinary popup duration, or reset both choices to Do Not Disturb off and six
seconds. These choices persist for future managed Quickshell sessions. Settings
keeps them read-only when another notification daemon owns the session D-Bus
name.

Type to search section names and descriptions. Use Up and Down to move through
the filtered sections, Enter to select one, or Escape to close Settings. The
Refresh button runs a new bounded capability snapshot; Settings does not add an
idle polling timer.

Command-line IPC actions are also available:

```bash
dwm-settings open
dwm-settings refresh
dwm-settings status
dwm-settings close
```

Existing `window-rules.toml` files are preserved during upgrades. If your file
predates Settings, add this entry inside its `rules` array:

```toml
{ title="dwm settings", isfloating=1, alwaysontop=1 },
```

Saving the file applies the rule through dwm's normal hot reload. A customized
rule with the same title can be retained instead.

The **Use at next login** display action writes only the managed
`90-dwm-titus-display.conf` fragment after a separate confirmation and polkit
authorization. The installed helper accepts validated display records only,
backs up the previous managed next-login fragment, and offers **Restore login
backup**. It does not capture the live XRandR layout. Later phases add
connectivity, audio, power, defaults, personalization, and system-management
operations.
