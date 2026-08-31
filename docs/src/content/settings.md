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
output enablement, and manages named profiles. Preview applies the complete
layout for 15 seconds. Choose Keep to accept it or Revert to restore the
captured layout; timeout or closing Settings also restores the prior layout.
The machine-oriented `dwm-settings-display` helper exposes `discover` and
`watch`, complete-layout `save` and `preview`, named `preview-profile`, timed
`keep`, `revert`, and `preview-status`, plus authorized `install-profile` and
`rollback-system` actions. Named profiles live under the dwm-titus XDG config
directory. Legacy incomplete profiles remain available to
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

Persistent display installation writes only the managed
`90-dwm-titus-display.conf` fragment after a separate confirmation and polkit
authorization. The installed helper accepts validated display records only,
creates a backup, and offers a system rollback. Later phases add connectivity,
audio, power, defaults, personalization, and system-management operations.
