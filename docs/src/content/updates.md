---
title: Updates
description: Keep dwm-titus, Fedora packages, Flatpak applications, and mise tools current from the panel Update Center or Settings.
navLabel: Updates
eyebrow: Stay current
---

# Updates

dwm-titus has two update surfaces: the **Update Center** in the panel and the
**Desktop updates** card in Settings > System. Both preview work before it
starts and report failures instead of claiming success.

## Panel Update Center

Click the update indicator beside the clock to open the Update Center popup.
It lists the providers that are available on the machine:

- Fedora packages
- the managed dwm-titus desktop
- Flatpak applications
- mise-managed tools, when mise is installed

Expand a provider to inspect its available updates, then choose **Update** for
that provider. Updates run in a dedicated terminal using the saved window mode.
Closing the popup leaves the operation running. **Progress** reopens the desktop
update progress window while desktop work is active or needs attention. Read the
terminal result and press a key to close it.

In the Update Center's Settings tab, **Float update terminal** controls whether
the next update or recovery terminal floats. It does not change the Update
Center popup itself. Refresh preferences set the periodic repository check and
whether the indicator stays visible when everything is current. Reconnecting a
network triggers a fresh check; manual refresh still works offline.

Fedora updates run the installed DNF5 directly, with its normal transaction
plan and confirmation prompt. No automatic Yes is supplied, and nothing
reboots the machine automatically. PackageKit provides read-only update
discovery; an existing PackageKit operation must finish before a new DNF
transaction starts.

Choosing **Recover** reattaches to desktop work that is still running. For an
interrupted DNF update it retries the normal DNF workflow under DNF's lock with
a fresh plan and confirmation. Recovery is not a rollback and does not prove the
earlier attempt succeeded.

## Desktop updates in Settings

The first card in **Settings > System** checks the desktop against official
`main`. It covers the managed Quickshell configuration, dwm, installed commands,
managed data, and cursor assets. Fedora package updates below it continue to
manage the Quickshell RPM and other packages.

Opening System checks once with a five-minute cache; **Check again** bypasses it.
**Update desktop** previews the operation and any missing required packages.
**Confirm update** installs them with one administrator authorization for the
whole operation. Settings closes while the password dialog is shown, and a
separate progress window stays open through shell restarts with the current
stage and elapsed time. **Hide** keeps the update running; **View log** opens a
bounded log viewer. Nothing is installed just by opening Settings.

An interrupted desktop update blocks further updates until it is recovered or
completed. Closing Settings does not stop an update. Reopening Settings reads
the saved operation and resumes progress reporting.

Updates preserve personal TOML files, application configuration, `.xinitrc`,
and `config.h`. They replace the managed Quickshell tree and the managed
`config` and `scripts` data trees. Development branches, tracked or untracked
changes in managed trees, and divergent history are blocked with instructions to
use the source workflow instead.

## Initial Fedora update

Fresh images from 0.7.2 offer an initial package update once repositories become
reachable. Choose **Later** to defer it, or run:

```bash
dwm-initial-update
```

The helper requests authorization, measures mirrors, validates the enabled
repositories, and shows DNF's proposed upgrade. Enter accepts the `[Y/n]` prompt
and `n` cancels. It does not enable repositories, change image variants, or
reboot automatically. Completion is recorded in
`/var/lib/dwm-titus/initial-update/complete.json`; retry with `dwm-initial-update`
after a repository, authorization, download, or transaction failure.

Updating an existing desktop from source does not opt it into the initial-update
offer.

## Existing installations

An older source installation must run the
[source update procedure](/install.html#source-updates-and-recovery) once to
install the desktop updater and its root-owned authorization helper. After that,
the Update Center and Settings > System can manage later updates.

For the complete contracts, see
[Desktop updates and recovery](https://github.com/ChrisTitusTech/dwm-titus/blob/main/docs/DESKTOP-UPDATES.md)
and [Initial update and DNF defaults](https://github.com/ChrisTitusTech/dwm-titus/blob/main/docs/INITIAL-UPDATE.md).
