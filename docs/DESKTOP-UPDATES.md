# Desktop updates

The first card in **Settings > System** checks the dwm-titus desktop against
official `main`. It covers the managed Quickshell configuration, dwm, installed
commands, managed data, and cursor assets. Fedora package updates below it
continue to manage the Quickshell application and other RPM packages.

![Desktop updates at the top of System Settings](evidence/desktop-updates.png)

Opening System checks once, with a five-minute cache. **Check again** bypasses
that cache. **Update desktop** previews the operation and missing required
packages; **Confirm update** starts it. System-file installation asks for
administrator authorization through polkit. No installation happens just by
opening Settings.

The progress bar is indeterminate during downloading, building, authorization,
and installation because those stages do not provide a reliable percentage.
Verification shows the actual number of system files checked. Closing Settings
does not stop the update. Reopening it reads the saved operation, including
interrupted or completed work. No background polling runs while idle.

## Installation and compatibility

Existing desktops must run the existing
[source update procedure](src/content/install.md#source-updates-and-recovery)
once to install the updater and its root-owned authorization helper. Fresh
installs record managed file hashes automatically. The revision is recorded
when available from the build checkout; older or exported source trees may show
`unknown` until the first confirmed update. Installations without a `.git`
directory can still install and verify a fixed official revision.

The GUI preserves personal TOML files, application configuration, `.xinitrc`,
and compile-time `config.h`. It replaces the project-managed Quickshell tree and
the managed `config` and `scripts` data trees. If the data directory is also a
Git checkout, the updater prepares and validates a fast-forwarded copy before
replacing it. Unrelated files in that directory are retained. Development
branches, tracked or untracked changes, ignored files inside `config` or
`scripts`, linked worktrees, and divergent history are blocked
with instructions to use the source workflow.

The installed manifest fixes the authorized system-file destinations, file
types and modes, cursor link targets, and package capability list. An update
that changes that contract stops before installation and asks for the source
installer. This avoids turning Settings into a general-purpose root installer.
Privileged helpers and the root-executed `dwm-display-setup` and
`dwm-system-health` commands must stay byte-identical; changes to them require
the source installer. Authorization carries the prepared archive's digest and
confirmed revision; the root-owned copy must match both before installation,
preventing archive substitution while the authorization prompt is open.
Missing system directories also require that installer
and are not offered as automatic file repairs. Compiler overrides (`CC`,
`CFLAGS`, `CPPFLAGS`, and `LDFLAGS`) supplied to the updater are carried into its
worker and passed to the build.
Unsafe installed file modes or modified user-owned system files require the
source installer; recovery never restores special or writable mode bits.
Missing known build/source-update packages can be installed after confirmation;
the package manager owns its transaction and package locks.

When the dwm executable changes, **Installed - log out to finish** means the
files are verified but the running session still uses the previous executable.
Log out and back in normally. The next check verifies the active binary and
Quickshell IPC before clearing restart guidance. The updater never logs you out.

## Records

- `${PREFIX}/share/dwm-titus/desktop-install.json`: root-owned revision,
  system-file hashes, destinations, and dependency allowlist.
- `${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/desktop-update/installed.json`:
  user-managed tree hashes and source/build configuration provenance.
- `desktop-update/status.json` and `desktop-update/operations/<id>/`: operation
  status, preview, log, and recovery inventory under that same state directory.
- `/var/lib/dwm-titus/desktop-updates/<id>/`: private root-owned system backup
  and write-ahead installation journal.
- `.dwm-update-<id>-*` beside each managed user directory: retained recovery
  copies. They can contain Git history and private local files; keep them private.

Backups are retained for explicit recovery. Do not remove them while an update
is active or interrupted. After verifying the new session, they may be removed
as part of deliberate backup maintenance; no automatic retention policy deletes
them.

## Recovery

A failed download or build leaves the installation unchanged. Read the displayed
log, fix the reported cause, and use **Check again**. Canceled or denied polkit
authorization does not count as successful installation.

An interrupted installation blocks further updates. Close Settings and use a
terminal, or switch to a TTY with Ctrl+Alt+F3 if the shell is unavailable. Use the
exact operation ID shown by the saved status:

```sh
dwm-desktop-update status
dwm-desktop-update recover OPERATION_ID
```

Recovery requests administrator authorization to restore the system files and
restores the managed user directories from the recorded copies. It refuses to
replace a newer installation or user files changed after the interruption.
Save conflicting changes separately before recovery; do not reset or delete a
checkout to bypass that protection. Log out and back in after restoration, then
check again. Recovery does not undo RPM transactions or downgrade packages.

If the installed updater itself is unavailable, use the existing full
[source recovery procedure](src/content/install.md#source-updates-and-recovery).
Retain the failed operation's log and backups for diagnosis.

## Validation

Run the focused backend and X11 fixture through the managed workspace:

```sh
scripts/run-tests make check-desktop-update
scripts/run-tests make clean all check-install-manifest check-dev-sync-install
scripts/run-tests make check-quickshell-qml
scripts/run-tests
```

`tests/test-desktop-update-security.py` must run as root inside a disposable
Fedora container. It refuses to operate on a host. It tests real installed-helper
ownership, allowlists, bundle integrity, stale previews, installation, and
rollback. GUI fixture tests do not substitute for this privileged coverage or
for a clean Fedora build and staged installation.

`tests/test-desktop-update-integration.py` also requires a disposable Fedora
container. It builds two local source revisions, runs the real unprivileged
worker, authorizes only the test helper through a container-only polkit rule,
and verifies the resulting installation and preserved personal configuration.
It does not contact upstream or modify the host. A separate
`scripts/run-tests python3 tests/test-desktop-update-service.py` checks the real
user-service handoff on a host with an available user systemd manager.
