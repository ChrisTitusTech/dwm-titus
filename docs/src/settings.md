# Settings

The unified Settings application provides one place to inspect desktop
capabilities and see which features are available, restricted, or planned.

Open Control Center with `Super+F1`, select **Utilities**,
then select **Settings**. You can also run:

```bash
dwm-settings
```

Phase 1 is a read-only foundation. It discovers display, input, network,
Bluetooth, audio, power, default-application, appearance, and system providers
without changing their state. Unsupported sections explain when their controls
are planned, and missing optional services do not prevent other sections from
opening.

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

Phase 2 adds display and input controls. Later phases add connectivity, audio,
power, defaults, personalization, and system-management operations while
preserving the capability and authorization boundaries established here.
