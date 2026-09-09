# Phase 6 System Management Qualification

## Scope

Qualification targets the supported Fedora 44 X11 desktop and the Phase 6
System Settings contracts. It does not qualify a new Fedora installation image;
that is Phase 7. The implementation and protocol reference is
[P6-SYSTEM-MANAGEMENT.md](P6-SYSTEM-MANAGEMENT.md).

## Acceptance evidence

| Phase 6 requirement | Evidence and limits |
| --- | --- |
| Explicit Fedora update preview, installation, logs and restart guidance | Private-bus and QML operation fixtures cover preview generations, fixed actions, cancellation windows, typed terminal outcomes, durable replay, acknowledgment and conservative restart guidance. The disposable Fedora 44 real-PackageKit run in [P6-UPDATE-EVIDENCE.md](P6-UPDATE-EVIDENCE.md) installed signed fixture updates and verified RPM state and audit results. |
| Regional and trusted administration entry points | Fixed timezone, NTP and locale service actions, plus fixed account/password/printer/source launches, have backend and nested-X11 success, denial, unavailable, failed, interrupted and closure fixtures. All controls are tested at 640x480, 780x580 and 1000x740. The three regional actions clearly warn that dispatched changes cannot be canceled; ambiguous results require a fresh read and confirmation. |
| Readable information after denied or unsupported changes | Cumulative protocol tests preserve independently valid information, storage and security records when mutation admission or a peer provider fails. Filesystem row and byte budgets reject over-limit lists atomically; byte values remain exact decimal strings. |
| Event-driven, bounded storage and security state | Real findmnt descriptor/readiness and owned-child tests, mount namespace event checks, and QML generation/readiness/closure fixtures cover initialization races, bounded settling, immutable per-launch callbacks, consumer loss and explicit stale-data retention. Blocked storage cannot be reread by unrelated provider events; failed core recovery reads preserve optional information through successful retries. No periodic information poller is added. |
| Diagnostics, recovery and reset guidance | The fixed Health navigation opens the existing scan owner. Repairs retain their existing confirmation and trusted-helper checks. Visible guidance names scope and owner, explains diagnostic sharing, and excludes broad disk, firewall, encryption, service and factory-reset operations. |
| Allowlisted and auditable privilege boundaries | Backend tests reject repository/user-writable elevated helpers, invalid arguments and unsafe executable identities. Authorization denial preserves readable state. Graphical polkit evidence below is authorization-only and does not substitute for a real service mutation. |
| Build and installation | The complete combined managed suite passed with 679 backend tests, build, lint, nested-X11, staged/repeated installation, preservation and release-archive checks. Later backend fixes pass 60 focused checks; later subscription/recovery fixes pass the complete affected QML, ShellCheck and formatting gate, with 544 parser, 119 retained-callback and 66/69/66 root lifecycle assertions. The final diagnostic-retention follow-up passes 544 parser and 67/70/67 root lifecycle assertions. The unchanged information view passes 25 assertions at each of three sizes. Independent review and documentation builds pass. |
| Installed X11 runtime | Final installed revision `61d9f52ecdfe1798f09312067872f889f62b6802` passed file/binary parity, System lifecycle and restoration on Fedora 44 X11. Settings-to-Health navigation was qualified on the unchanged view at `fc5eedab2bc09892dc968d0dcfc613d68e0b26ea`. Quickshell ran in logind session 2 with five tray items. Closed Settings/Health left no System helpers; Quickshell used 0.200% CPU over five seconds. |

## Real session observations

The development host runs Fedora 44 (`fedora-release-44-18`), kernel
`7.1.13-200.fc44.x86_64`, Quickshell
`0.2.1^git20260209.dacfa9d-5.fc44`, PackageKit `1.3.6-1.fc44`, polkit
`127-2.fc44.2`, and util-linux `2.41.5-1.fc44`. Logind reports an active
X11 user session; the managed Quickshell process belongs to its session scope. A bounded
read-only information probe, started after the real mount monitor acknowledged
its persistent baseline, completed in 0.756 seconds with all nineteen state
records, eight filesystems, and available information, storage, security and
diagnostics providers. It performed no mount or security changes.

The existing MATE polkit agent displayed the authentication prompt for
`org.freedesktop.timedate1.set-timezone`. An authorization-only `pkcheck` request
was canceled using the dialog's Cancel button; it exited 3 with
`Authentication request was dismissed` and `polkit.dismissed=true`. No timezone
setter was called and no password was entered. The [prompt capture](evidence/p6-polkit-timezone-prompt.png)
records this graphical path. Actual typed service denial, interrupted operation
recovery and readable-state preservation are separately covered by private-bus
and nested-X11 tests.

A managed shell restarted from the Codex application initially inherited its
application scope instead of the desktop's logind session. Invoking the existing
desktop restart binding (`Super+Shift+r`) restored normal session ownership.
Final qualification verifies the running Quickshell PID through logind and
installed-file/runtime parity after that normal desktop restart path.

## Restoration and limits

No host PackageKit update transaction, timezone, locale, NTP, firewall,
encryption, account or disk mutation was used for the final UI qualification.
The requested development-install preparation installed the required PackageKit,
Python bindings and printing dependencies; CUPS socket/path activation remains
part of that prepared installation. Optional administration launchers remain
optional. Private-bus, Xvfb, process and
mount-namespace fixtures own and clean up their test processes and data. The
real signed-package update guest and its cleanup are documented separately.

Real in-flight PackageKit cancellation, power loss, crash adoption, hardware
restart requirements and repository-network failures were not induced on the
host or during the tiny signed-package guest transactions; their protocol and
lifecycle behavior is covered by fixtures. Firmware and hardware probes report
Unknown when supported evidence is absent. Optional LXQt account administration
and DNFDragora source tools may be unavailable without breaking readable state.

The existing local `config.h` from the main checkout was preserved for the live
build. An initial build using the worktree's generated defaults correctly
triggered the binary-parity check; rebuilding with the existing configuration
restored exact equality with running dwm. No logout was required. The prior
Settings section (`displays`), closed Settings/Health windows, pointer position
and focused application were restored. The final repeated install check passed
for managed files, running dwm, Quickshell IPC and all five tray items.

The installed System pane reached `ready` with available PackageKit discovery,
an idle operation owner and acknowledged subscriptions. Its only provider
errors were the two absent optional administration/source launchers. Real
information, filesystem byte counts and security observations were visually
checked at 1180x760; public captures elsewhere use synthetic values to avoid
publishing host paths and device details. The actual Health button closed
Settings and opened the existing diagnostic owner; System subscriptions became
inactive. The privileged current-boot scan completed with zero errors and five
warnings. Those warnings cover boot/kernel log records, the existing failed
user document-portal service, kernel taint and the bounded package audit. The
portal failure was recorded earlier in the session, at 14:31 CDT. A separate
cache-only package consistency check succeeded with no output in 16.522 seconds;
Health's existing 12-second budget reports a warning for that slower check.
This is a scan-time limit, not evidence of a corrupt package database. No repair
or security-policy change was applied during this qualification.
