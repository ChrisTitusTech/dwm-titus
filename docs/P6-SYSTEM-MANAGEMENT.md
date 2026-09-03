# Phase 6 System Management Contract

<!-- markdownlint-disable MD013 -->

Date: 2026-09-02

## Scope and Ownership

Phase 6 adds bounded Fedora system management without making Quickshell an
administration shell. Settings and all QML remain unprivileged. Each operation
has one fixed owner, and system policy and authorization stay with the Fedora
service or trusted Fedora tool that already owns them.

The implementation boundaries are:

1. PackageKit-backed Fedora update status and transactions.
2. Regional state plus trusted account, printer, and software-source entry
   points.
3. System information, storage, privacy/security status, diagnostics, and
   recovery integration.
4. Combined Fedora 44 and nested-X11 qualification.

No Phase 6 operation expands the project-owned privileged helper allowlist.
An operation that cannot satisfy the project privilege contract remains
delegated or unsupported.

## Capability and Mutation Inventory

| Capability | Read owner | Mutation owner | Class | Cancellation and denial | Phase 6 disposition |
| --- | --- | --- | --- | --- | --- |
| Update status and available packages | Patched PackageKit system D-Bus API using the Fedora DNF5 backend | PackageKit `UpdatePackages` with the fixed `ONLY_TRUSTED` transaction flag and PackageKit polkit policy | Read-only and delegated | Mutation requires upstream PackageKit 1.3.5 or newer, or Fedora's `1.3.4-3.fc44` security backport. Blocked updates remain visible but are excluded from installation. The transaction `AllowCancel` property is authoritative. Cancel is offered only while true. Authorization denial ends the operation without hiding the last readable snapshot. | Implement |
| Package metadata refresh | PackageKit transaction | PackageKit `RefreshCache` transaction | Delegated | Starts only from an explicit Refresh action. PackageKit owns cancellation and repository/network errors. | Implement |
| Update interruption and history | PackageKit active transaction list, transaction signals, and PackageKit transaction history | None | Read-only | An operation journal identifies incomplete local operations. PackageKit remains the source of truth for transaction completion. | Implement |
| Date, timezone, and NTP | `org.freedesktop.timedate1` properties | `SetTimezone` and `SetNTP` with interactive authorization | Read-only and delegated | A pending confirmation can be canceled before the D-Bus call. Denial preserves properties and reports no change. Manual clock setting is not exposed. | Implement |
| System locale | `org.freedesktop.locale1` properties | `SetLocale` with interactive authorization | Read-only and delegated | A pending confirmation can be canceled before the D-Bus call. Denial preserves properties and reports no change. Success includes logout guidance. Keyboard layout remains owned by Input Settings. | Implement |
| User accounts | AccountsService object and user properties | Fedora `lxqt-admin-user` entry point; current-user password uses a fixed terminal `passwd` entry point | Read-only and delegated | Settings never accepts usernames, passwords, group names, or arbitrary account commands. Missing tools leave the account summary readable. | Implement entry points; do not implement account mutation |
| Printers | CUPS service availability | Fedora `system-config-printer` | Read-only and delegated | The trusted tool and CUPS own printer discovery, authentication, cancellation, and device policy. Missing CUPS or tool state is capability-scoped. | Implement entry point |
| Software sources | PackageKit repository records | Fedora `dnfdragora` when installed | Read-only and delegated | Settings does not accept repository identifiers for mutation. The delegated tool owns confirmation and authorization. | Implement entry point |
| System identity and resources | Bounded `/etc/os-release`, `uname(2)`, `org.freedesktop.hostname1`, `/proc/cpuinfo`, `/proc/meminfo`, `CLOCK_BOOTTIME`, and fixed `findmnt --json` records | None | Read-only | Probe failures remain per record. No background poller is added. | Implement |
| Storage overview | Existing `dwm-system-health` structured snapshot | Existing fixed user and installed-helper repairs only | Read-only, user-session, and privileged | Existing confirmation, authorization-denial, and fixed repair allowlists remain unchanged. | Reuse and link |
| Privacy and security status | The fixed sources in the Security Status section below | Trusted Fedora tools or documented recovery guidance | Read-only and delegated | Probe status and semantic value remain distinct: for example, an inaccessible probe is `restricted` with value `unknown`, while a successful disabled probe is `available` with value `disabled`. No firewall, encryption, or SELinux mutation is added. | Implement status and guidance |
| Diagnostics and recovery | Existing `dwm-system-health` and `dwm-diagnostics` records | Existing fixed repair actions and exported evidence | Read-only, user-session, and privileged | Denial leaves the user scan visible. Broad service names and commands remain rejected. | Reuse and link |
| Advanced storage, firewall policy, general services, encryption setup, and factory reset | No narrow provider | Trusted external administration or reinstall/recovery documentation | Delegated | Unsupported status is used where no trusted entry point exists. No generic elevation, command runner, device path, service name, or arbitrary file path crosses QML. | Explicitly exclude |

## Selected Fedora Interfaces

### Package Updates

PackageKit is the Phase 6 update owner. Fedora 44 exposes PackageKit 1.3 with
the DNF5 backend, update discovery, repository discovery, update transactions,
transaction lists, authorization checks, progress signals, error codes,
restart guidance, and cancellation state. The provider consumes the documented
PackageKit GLib/D-Bus API rather than parsing `dnf`, `pkcon`, or terminal text.
Update inventory always calls `SetHints` with the exact read-only hints
`background=true`, `interactive=false`, and `cache-age=4294967295` before
calling `GetUpdates` with PackageKit's `NONE` filter. The maximum unsigned
cache age directs PackageKit to reuse any usable metadata. PackageKit may still
acquire metadata when its backend requires that work to return any result; the
UI presents that as update discovery, never as a user-requested refresh. The
transaction has a 120-second monotonic aggregate deadline from
`CreateTransaction` through `Finished` and accepts at most 4096 unique update
rows. A timeout or additional row uses the same bounded cancel, five-second
grace, and detach sequence defined below, reports `timeout` or `malformed`, and
does not start simulation. The explicit Refresh action calls `RefreshCache`
with `force=true`; passive
discovery never calls that method or starts a mutable update transaction.
Beyond its required read-only `GetUpdates` transaction, it may create only the
separate unjournaled `SIMULATE|ONLY_TRUSTED` read-only transaction defined in
the lifecycle contract below.

The update command grammar is fixed:

```text
dwm-system-management snapshot
dwm-system-management watch-operation OPERATION_ID
dwm-system-management updates-refresh
dwm-system-management updates-install-all GENERATION
dwm-system-management updates-cancel OPERATION_ID
```

`GENERATION` is the exact 64-character lowercase hexadecimal generation emitted
with the confirmed snapshot. It is an opaque provider-created value, not a
package ID or caller-selected transaction parameter. No update command accepts
another option or trailing argument.

`OPERATION_ID` must exactly match the `op-` prefix followed by 32 lowercase
hexadecimal digits emitted for the currently visible operation. The provider
generates and reserves it while holding the exclusive journal lock, using the
kernel CSPRNG. It rejects a collision with the active record, any of the 32
terminal records, or the restart record's last-applied operation ID, and fails
closed after four collision attempts. A
cancel request is accepted only when this ID still equals the active journaled
refresh or update operation and that exact PackageKit transaction currently
reports `AllowCancel=true`. A stale, unknown, terminal, or replaced ID, or an
exact active transaction that no longer reports `AllowCancel=true`, produces a
command-level rejection: the command emits no operation stream, exits with
status 3, and writes only the fixed diagnostic `cancel target is unavailable`
to standard error. The root model maps status 3 directly to a visible
`conflict`, refreshes current state, and never parses the diagnostic. The active
operation and any newer operation remain unchanged. Malformed command syntax,
including an invalid ID shape, exits with status 2 instead. Before matching,
`watch-operation` takes the exclusive journal lock and completes the bounded,
idempotent recovery sequence for any terminalized active payload, including its
restart, terminal-slot, cursor, and empty-active commits. It then requires that
the ID match either the current validated nonterminal PackageKit refresh or
update payload or, when the active payload is empty, the validated PackageKit
terminal record in the ring slot immediately preceding the current cursor. The
latter is the sole terminal handoff candidate because it is the most recently
committed operation, and it is accepted only when its validated kind is
`refresh` or `update`; a regional or delegated terminal kind returns the
status-3 rejection before any stream starts. The command uses only the transaction path bound inside
the matching record. It may recover or replay bounded terminal evidence when
the exact transaction finished after the snapshot, but never accepts an
arbitrary transaction path or an older terminal slot. If terminalized-active
recovery cannot complete, or a correctly shaped ID does not match either
permitted validated identity, the command emits no stream, exits with status 3,
and writes
only the fixed diagnostic `watch target is unavailable` to standard error. The
root model maps that status to `conflict` and immediately requests a fresh
snapshot as the next recovery attempt.

`watch-operation` supports only operation IDs for PackageKit `refresh` and
`update`. Regional and delegated operations remain owned by their finite
originating stream and are recovered by `snapshot`, not watched. Passing any
such correctly shaped but unsupported provider operation ID emits no stream and
uses the same status-3 `watch target is unavailable` rejection.

The PackageKit service is authoritative for package state. The project provider
adds only validation, bounded record formatting, a private operation journal,
and the fixed Settings lifecycle. `UpdatePackages` always uses PackageKit's
`ONLY_TRUSTED` transaction flag. Before exposing update mutation, the provider
uses RPM version comparison and requires upstream PackageKit 1.3.5 or newer, or
the Fedora 44 security-backport floor `1.3.4-3.fc44`; an older or unrecognized
build leaves discovery readable but reports the install action unavailable.
This gate protects the transaction flags from local-client reinvocation. The
provider never runs DNF concurrently, assumes a PackageKit transaction
succeeded from process exit alone, or reports an update complete before the
`Finished` result arrives.

`update-last-refresh` comes only from PackageKit's system-bus
`GetTimeSinceAction(REFRESH_CACHE)` method. A result from 0 through 4294967294 is
`available` and emitted as canonical unsigned decimal seconds; Settings labels
it as the age of the latest successful system metadata refresh, including one
started by another PackageKit client. The reserved `G_MAXUINT` result
`4294967295` means PackageKit has no usable success history and maps to
`partial`/`unknown`, never to an elapsed age. The project neither persists,
updates, nor clears this value, and passive `GetUpdates` does not itself
substitute a timestamp. Missing PackageKit or a call failure is
`unavailable`/`unknown`, an absent method is `unsupported`/`unknown`, and a
malformed reply is `partial`/`unknown`.

### Regional State

`org.freedesktop.timedate1` and `org.freedesktop.locale1` are the stable systemd
D-Bus owners. Settings reads their properties directly and invokes only the
fixed `SetTimezone`, `SetNTP`, or `SetLocale` methods after confirmation. The
interactive-authorization argument remains enabled so systemd and polkit own
the decision. Arbitrary environment variables, keymaps, NTP servers, RTC mode,
or manual timestamps are not accepted.

The `Locale` array is parsed only as the allowlisted keys `LANG`, `LANGUAGE`,
and `LC_CTYPE`, `LC_NUMERIC`, `LC_TIME`, `LC_COLLATE`, `LC_MONETARY`,
`LC_MESSAGES`, `LC_PAPER`, `LC_NAME`, `LC_ADDRESS`, `LC_TELEPHONE`,
`LC_MEASUREMENT`, and `LC_IDENTIFICATION`. Duplicate, unknown, malformed, or
oversized assignments make the locale state `partial`/`unknown`. The array may
contain at most 14 assignments, each complete `KEY=VALUE` assignment may be at
most 512 UTF-8 bytes, and the sum of assignment byte lengths plus one separator
byte per assignment may be at most 8192 bytes. A value exactly at any limit is
accepted; an entry, count, or aggregate one unit over its limit is oversized.
Otherwise the
`locale` state value is the exact `LANG` value, or `unknown` when `LANG` is not
set, and its bounded detail lists nonempty category overrides in the fixed
order above. Immediately before confirmation and again before the D-Bus call,
`locale-set LANG=LOCALE` rereads locale1's complete `Locale` array, validates
the allowlist and bounds above, replaces only `LANG`, preserves every validated
`LANGUAGE` and `LC_*` assignment, sorts the complete set in the fixed order
above, and revalidates it before passing it to `SetLocale`. A malformed set or
a monitored state change before the method is sent produces `conflict` and
requires fresh confirmation. After the method returns, the provider rereads
`Locale` and compares effective locale values, not raw array equality: `LANG`
must equal the requested locale, every preserved `LANGUAGE` value must remain
equal, and each preserved `LC_*` category must resolve to its prior value after
applying the normal `LANG` fallback. A notification received after the final
pre-call read whose complete effective map equals that expected result is the
notification for this call and is ignored; any non-equivalent notification or
final effective-value mismatch reports `conflict`, refreshes visible state, and
warns that a concurrent writer may have won or been overwritten.

locale1 replaces the full assignment array and exposes no lock or compare-and-
set argument, so no client can make this cross-client read-modify-write fully
atomic. An external writer in the final read-to-method interval can therefore
still be overwritten even though the provider detects its notification when
available. The confirmation states this limitation, shows the preserved
overrides, and explains that applications require a new login to consume the
change. This effective-value comparison permits locale1 to omit a redundant
`LC_*` assignment without producing a false conflict.

Provider-backed regional and delegated actions use this exact command grammar:

```text
dwm-system-management timezone-set ZONE
dwm-system-management ntp-set enabled|disabled
dwm-system-management locale-set LANG=LOCALE
dwm-system-management accounts-open
dwm-system-management password-open
dwm-system-management printers-open
dwm-system-management sources-open
```

`ZONE` is at most 255 ASCII bytes, contains no control characters, empty path
components, `.` or `..` components, and must exactly match a value returned by
the fixed `org.freedesktop.timedate1.ListTimezones` method. Each enumeration has
a ten-second monotonic aggregate deadline, accepts at most 2048 unique values
and 256 KiB of total UTF-8 reply data, and discards any late reply after local
cancellation. A timeout reports a regional `timeout`; a duplicate, over-limit,
non-ASCII, or overlong result reports `malformed`. Either error preserves the
read-only timedate1 properties but leaves `timezone-set` unavailable. The same
bounded enumeration and exact-match check run before confirmation and again
immediately before mutation. `LOCALE` is
at most 128 ASCII bytes, contains no control or whitespace characters, and must
exactly match a name reported by the bounded `locale -a` fallback because
locale1 has no locale enumeration method. `LANG` is the only accepted locale
key. The provider runs a fresh bounded `locale -a` process and exact-match check
before confirmation, then runs a second fresh enumeration with the same bounds
immediately before `SetLocale`; it never reuses the first allowlist. Arguments
are validated at both points. The four no-argument forms reject every positional or
option argument. No other option, key, D-Bus argument, or trailing argument is
accepted by any form.

`health-open` is the sole action with no provider command: the root-scoped QML
model invokes the fixed in-process `SystemHealthModel.openOnScreen` method with
the current screen and accepts no caller-selected target or argument. It is UI
navigation, starts no operation stream, and is not journaled. Every other
advertised action maps one-to-one to an exact command line in this section or
the update command grammar above.

The provider starts `locale -a` in a dedicated process group with a three-second
deadline, sends `TERM` to the group and then `KILL` after one second, caps output
at 2 MiB, and accepts at most 4096 unique nonempty locale names of at most 128
ASCII bytes each. Timeout or termination failure makes `locale-set` unavailable
with a `timeout` error; missing command, nonzero exit, excess output or records,
and malformed names make it unavailable with the corresponding
`missing-provider`, `internal`, or `malformed` error. Readable locale1 state
remains visible and the rest of the regional provider continues to work.

### Accounts, Printers, and Sources

AccountsService supplies read-only account objects and properties. The provider
uses `org.freedesktop.Accounts.ListCachedUsers` for enumeration, then performs
one bounded `FindUserById(os.getuid())` lookup for the invoking user. It adds
that object when absent from the enumeration and de-duplicates the resulting
paths. It reserves one of the 256 record slots for that valid current-user
object, then sorts and accepts at most 255 other objects. It reads only
`UserName`, `RealName`, `SystemAccount`, and `LocalAccount` from
`org.freedesktop.Accounts.User`.
Other objects with `SystemAccount=true`, and any object with a malformed path or
missing `UserName`, are excluded. The current scope is assigned only when the
object returned by `FindUserById(os.getuid())` matches; all other emitted
objects are `other`.
`accounts-count` is the emitted row count. More than 256 candidate paths or an
invalid object makes the accounts provider `partial` while preserving the valid
bounded subset. One aggregate three-second deadline starts before
`ListCachedUsers`; at most eight user-property calls are outstanding at once.
On expiry the provider cancels its outstanding D-Bus cancellables, ignores late
replies, preserves records already validated, and reports `partial` with a
`timeout` error. Signal-coalesced refreshes never overlap this bounded read.
Account creation, deletion, group membership, and administrator changes remain
in the Fedora-packaged `lxqt-admin-user` tool. The current user's password
action opens the fixed `passwd` program in the configured terminal without
transporting a password through QML.

CUPS remains the printer service. Phase 6 reads only the fixed
`cups.service` and `cups.socket` systemd units. `cups-service` is
`available`/`running` whenever the loaded service is active; socket state does
not downgrade that result. When the loaded service is inactive, an
active/listening loaded socket is
`available`/`socket-ready`, while an absent or inactive loaded socket is
`available`/`stopped`. If neither unit exists it is `unsupported`/`unknown`;
bus or property failure is `unavailable`/`unknown`. Every other combination,
including a present socket with an absent service, malformed or transitional
state, a failed service, or a failed socket when the service is not running, is
`partial`/`unknown`. This distinguishes Fedora's healthy idle socket-activated
scheduler and valid service-only configurations from a missing scheduler.
Phase 6 reports service/tool availability and opens Fedora's
`system-config-printer`; it does not reproduce printer discovery, driver,
queue, job, or authentication policy.

PackageKit supplies read-only repository records through `GetRepoList` with the
fixed `NONE` filter, including enabled and disabled repositories. Its aggregate
deadline is 30 monotonic seconds and it accepts at most 512 unique repository
rows; timeout or excess results are provider-scoped errors. Repository changes
remain in the Fedora-packaged `dnfdragora` tool when present. Missing optional
delegated tools are reported individually and never hide readable service
state.

### System Information and Filesystems

The information snapshot uses only these fixed sources:

- `/etc/os-release` is capped at 64 KiB and contributes only `PRETTY_NAME` and
  `VERSION_ID` to the `os-name` and `os-version` states.
- The Python `os.uname()` binding to `uname(2)` contributes `kernel-release` and
  `architecture`. The fixed `HardwareVendor` and `HardwareModel` properties on
  `org.freedesktop.hostname1` contribute the corresponding states when present.
- `/proc/cpuinfo` is capped at 4 MiB. On the supported x86_64 architecture, the
  first `model name` field contributes `cpu-model`; logical processor count
  comes from `os.cpu_count()` and is emitted as `available` with a decimal
  integer. A `None` result is emitted as `partial`/`unknown`.
- `/proc/meminfo` is capped at 1 MiB and accepts only a decimal integer followed
  by the kernel `kB` unit for `MemTotal`, `MemAvailable`, `SwapTotal`, and
  `SwapFree`. Each value is multiplied by exactly 1024 with overflow checking
  and emitted as a decimal byte count. Uptime is a checked whole-second reading
  from `clock_gettime(CLOCK_BOOTTIME)`.
- Mounted real filesystems come from the fixed
  `findmnt --json --bytes --real --uniq --output ID,SOURCE,TARGET,FSTYPE,SIZE,USED,AVAIL`
  interface. `--uniq` selects one record for an effective over-mounted target
  and the kernel mount ID supplies a collision-free record key even when target
  text requires protocol sanitization. The provider starts it in a dedicated
  process group with a three-second wall-clock deadline; on expiry it sends
  `SIGTERM`, waits a bounded grace period, then sends `SIGKILL` to the process
  group and emits `filesystem-summary` as `unavailable`/`unknown`. Output is
  capped at 2 MiB and 256 unique mount-ID records. Source and target are
  display-only values and are never accepted by an action. Every snapshot emits
  exactly one `filesystem-summary` state: `available` carries the number of
  emitted filesystem rows, `partial`/`unknown` accompanies any usable subset,
  and `restricted`, `unavailable`, or `unsupported` carries `unknown` and no
  filesystem rows.

Each failed or malformed source degrades only the states or filesystem records
it owns. A missing hostname1 property does not invalidate OS, kernel, processor,
memory, or filesystem state.

### Security Status

Each probe has a fixed source and emits its own state instead of making the
combined security summary fail. Status describes whether the probe can produce
authoritative data: `available` for a known value, `partial` for accessible but
incomplete or malformed evidence, `restricted` for read denial, `unavailable`
when an expected command or service cannot be reached, and `unsupported` when
the capability or its platform source does not exist. Semantic values are
separate: SELinux uses `enforcing`, `permissive`, `disabled`, or `unknown`;
Secure Boot, firewalld, and screen lock use `enabled`, `disabled`, or `unknown`;
root encryption uses `encrypted`, `unencrypted`, or `unknown`. Every status
other than `available` uses value `unknown`.

The individual mappings are:

- SELinux runtime enforcement comes from the single-byte
  `/sys/fs/selinux/enforce` kernel interface. `1` is enforcing and `0` is
  permissive. When that interface is absent, the provider parses only the
  allowlisted `SELINUX` key in `/etc/selinux/config`. That fixed-path read is
  capped at 64 KiB; a larger file is `partial`/`unknown` and is not parsed. The
  exact value `disabled` is `available`/`disabled`, while `enforcing` or
  `permissive` without the runtime interface is inconsistent and therefore
  `partial`/`unknown`. If neither source establishes state, the result is
  `unsupported`/`unknown`. Read denial is `restricted`/`unknown`; malformed
  accessible data is `partial`/`unknown`. Neither is silently treated as
  disabled.
- Secure Boot comes only from the EFI global-variable path
  `/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c`;
  the provider never enumerates or glob-matches the directory. Its attributes
  prefix is skipped and the one-byte payload must be `0` or `1`; `1` is
  `available`/`enabled` and `0` is `available`/`disabled`. An absent EFI
  variables filesystem is
  `unsupported`/`unknown`; a missing variable or malformed payload on EFI is
  `partial`/`unknown`; read denial is `restricted`/`unknown`.
- Firewalld state comes from the `ActiveState` property for
  `firewalld.service` on `org.freedesktop.systemd1`. An absent unit is
  `unsupported`/`unknown`, a bus or property failure is
  `unavailable`/`unknown`, `active` is `available`/`enabled`, and `inactive` is
  `available`/`disabled`. Failed or transitional active states are
  `partial`/`unknown`. This state describes the firewalld service only; it does
  not claim that direct nftables rules or another firewall manager are absent.
- Root-storage encryption evidence comes from bounded `lsblk --json` output
  with the fixed `NAME,TYPE,FSTYPE,MOUNTPOINTS,PKNAME` columns. A root mount
  backed by a `crypt`/`crypto_LUKS` ancestry is encrypted; a fully resolved root
  ancestry without either is unencrypted. Missing, inaccessible, truncated, or
  internally inconsistent topology is `partial`/`unknown`; an unavailable
  command is `unavailable`/`unknown`, and read denial is
  `restricted`/`unknown`. The provider starts `lsblk` in a dedicated process
  group with the same three-second deadline, bounded termination sequence, and
  2 MiB output cap as `findmnt`, and accepts at most 1024 unique block-device
  records. Timeout or termination failure is `unavailable`/`unknown`; output or
  record truncation is `partial`/`unknown` and can never establish encryption.
- Screen-lock state reuses the `power-lock` record from the versioned power
  protocol documented in `POWER-PROTOCOL.md`; it describes automatic screen
  locking and does not launch a second GSettings or locker probe. An
  `available` record with `ENABLED=no` maps to `available`/`disabled`. An
  `available` record with `ENABLED=yes` and `RUNNING=yes` maps to
  `available`/`enabled`; `ENABLED=yes` with `RUNNING=no`, or malformed boolean
  fields, maps to `partial`/`unknown`. A `partial`, `restricted`, or
  `unavailable` power-lock state retains that status with value `unknown`.
- Update state reuses the PackageKit snapshot from this provider. It never
  starts a refresh merely to populate the security summary.

No status probe accepts a path, unit, property, command, device, or service name
from QML.

## Provider Protocol

`dwm-system-management` owns one append-only, tab-separated protocol. Phase 6
starts at minor version `0`:

This inventory is the preimplementation definition of version 1.0; no earlier
producer or consumer exists. The record field order becomes append-only when
the first implementation boundary lands.

```text
system-management-protocol<TAB>1<TAB>0
snapshot-generation<TAB>lowercase-sha256
provider<TAB>id<TAB>status<TAB>class<TAB>owner<TAB>detail
state<TAB>id<TAB>status<TAB>value<TAB>detail
update<TAB>package-id<TAB>severity<TAB>installable|blocked<TAB>name<TAB>version<TAB>summary
package-change<TAB>package-id<TAB>install|update|remove|obsolete|reinstall|downgrade<TAB>name<TAB>version<TAB>summary
repository<TAB>id<TAB>enabled|disabled<TAB>description
account<TAB>object-path<TAB>current|other<TAB>display-name<TAB>login-name
filesystem<TAB>mount-id<TAB>status<TAB>source<TAB>target<TAB>fstype<TAB>size-bytes<TAB>used-bytes<TAB>available-bytes<TAB>detail
action<TAB>id<TAB>available|unavailable<TAB>class<TAB>owner<TAB>label<TAB>detail
active-operation<TAB>id<TAB>action-id<TAB>kind<TAB>state<TAB>percent<TAB>cancelable<TAB>detail
operation<TAB>id<TAB>action-id<TAB>kind<TAB>state<TAB>percent<TAB>cancelable<TAB>detail
audit<TAB>id<TAB>action-id<TAB>kind<TAB>result<TAB>started<TAB>finished<TAB>detail
error<TAB>capability<TAB>code<TAB>detail
complete<TAB>snapshot|operation
```

The protocol minor selects a cumulative active-ID set so each small Phase 6
implementation boundary can produce a truthful complete snapshot:

| Minor | Providers added | States added | Actions added | Lists enabled |
| --- | --- | --- | --- | --- |
| `0` | `updates`, `recovery` | `update-summary`, `update-last-refresh`, `update-restart` | `updates-refresh`, `updates-install-all`, `updates-cancel` | `update`, `package-change` |
| `1` | `regional`, `accounts`, `printers`, `sources` | `timezone`, `ntp-enabled`, `ntp-synchronized`, `locale`, `accounts-count`, `cups-service` | `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open` | `account`, `repository` |
| `2` | `information`, `storage`, `security`, `diagnostics` | all information states, `filesystem-summary`, `selinux`, `secure-boot`, `firewalld`, `root-encryption`, `screen-lock` | `health-open` | `filesystem` |

The final column contains list-record types, not operation kinds;
`package-change` remains a preview list record owned by updates and never enters
an operation stream.
The `recovery` provider is intentionally status-only and client-facing from
minor 0: it owns journal-integrity errors that have no trustworthy operation
kind, while exposing no section, state, list, or action of its own. Removing it
would leave a malformed whole-journal error without a valid protocol owner.

A producer emits the highest minor whose complete active set it implements and
never emits a later planned ID as `unsupported`. Within that minor, every
active provider, state, and action is mandatory even when its platform source
is absent. A consumer that supports a later minor accepts earlier cumulative
sets; a producer bumps the minor only when the entire next row is implemented.

Required fields are single-line UTF-8 with tabs and line breaks replaced by
spaces. Unknown records and trailing fields are ignored. Consumers reject a
missing header, another major version, duplicate completion, or a known record
with missing required fields. Package IDs and object paths are opaque display
data unless an action contract explicitly validates and owns them.

The initial vocabulary is closed for known record fields:

- Provider IDs are `updates`, `regional`, `accounts`, `printers`, `sources`,
  `information`, `storage`, `security`, `diagnostics`, and `recovery`. Provider
  status is `available`, `partial`, `restricted`, `unavailable`, or
  `unsupported`; class is `read-only`, `user-session`, `privileged`, or
  `delegated`. Capabilities without a provider retain their applicable class and
  use the `unsupported` status. Provider class is fixed: `updates`, `regional`,
  `accounts`, `printers`, and `sources` are `delegated`; `information`,
  `storage`, and `security` are `read-only`; `diagnostics` and `recovery` are
  `user-session`. This field describes the strongest Phase 6 execution boundary
  owned by that provider; individual action rows retain their fixed classes
  below. A producer or consumer rejects a provider row with another class.
- State IDs are `update-summary`, `update-last-refresh`, `update-restart`,
  `timezone`, `ntp-enabled`, `ntp-synchronized`, `locale`, `accounts-count`,
  `cups-service`, `selinux`, `secure-boot`, `firewalld`, `root-encryption`, and
  `screen-lock`, plus information IDs `os-name`, `os-version`,
  `kernel-release`, `architecture`, `hardware-vendor`, `hardware-model`,
  `cpu-model`, `logical-cpus`, `memory-total-bytes`, `memory-available-bytes`,
  `swap-total-bytes`, `swap-free-bytes`, `uptime-seconds`, and
  `filesystem-summary`. State status uses the provider-status enum. Booleans are
  `yes`, `no`, or `unknown`; restart values are `none`, `application`,
  `session`, `system`, `security-session`, `security-system`, or `unknown`.
  Count, byte, uptime, and filesystem-summary values are unsigned decimal
  integers when status is `available` and `unknown` for any other status. Other
  values are bounded display text owned by the named state. Security-state
  values use the exact per-ID enums and status/value mapping defined in
  Security Status. `cups-service` uses only `running`, `socket-ready`,
  `stopped`, or `unknown` with the status mapping defined above. PackageKit
  `RestartEnum.APPLICATION` maps to `application`.
  Repeated PackageKit restart requirements are aggregated across two
  dimensions: maximum scope (`none < application < session < system`) and
  whether any requirement is security-related. `security-session` contributes
  session scope plus the security flag, and `security-system` contributes
  system scope plus that flag. The aggregate maps back to the closed enum, so
  `system` plus `security-session` becomes `security-system`; any unrecognized
  value makes the aggregate `unknown`. The result therefore cannot discard
  either restart scope or security urgency.
- Update severity is `critical`, `security`, `important`, `bugfix`,
  `enhancement`, `normal`, `low`, or `unknown`. Update installability is
  `installable` or `blocked`; blocked package IDs are never passed to
  `UpdatePackages`. An available `update-summary` value equals the total number
  of unique emitted `update` rows, including blocked rows; the install-all
  action is available only when at least one row is installable and all other
  update mutation gates pass. Repository state is `enabled` or `disabled`.
  A `package-change` row is one member of the complete dependency-resolved
  simulation result for those installable update IDs at snapshot time. Its
  action maps PackageKit simulation
  `InfoEnum` values `INSTALLING` to `install`, `UPDATING` to `update`,
  `REMOVING` to `remove`, `OBSOLETING` to `obsolete`, `REINSTALLING` to
  `reinstall`, and `DOWNGRADING` to `downgrade`; another info value makes the
  plan malformed and the install action unavailable. Package IDs are unique
  within the result, and every requested installable update ID must appear
  exactly once with action `update`; another action for a requested ID makes
  the plan malformed. A result containing `reinstall` or `downgrade` remains
  visible but makes `updates-install-all` unavailable with an `unsupported`
  error; Phase 6 never adds PackageKit's `ALLOW_REINSTALL` or
  `ALLOW_DOWNGRADE` flags implicitly.
  Dependency additions, removals, obsoletes, reinstalls, and downgrades are
  therefore visible before confirmation rather than inferred from `GetUpdates`.
  Account scope is `current` or `other`. Filesystem status uses the
  provider-status enum; mount ID is an unsigned decimal integer and the unique
  record ID within the snapshot, while source and target remain display-only
  text. `available`
  requires all three byte fields to be unsigned decimal integers; `partial`
  permits a mix of integers and `unknown`; `restricted`, `unavailable`, or
  `unsupported` requires all three byte fields to be `unknown`.
- Operation kind is `refresh`, `update`, `timezone`, `ntp`, `locale`, or
  `delegate`. Operation state is `pending`, `authorizing`, `running`,
  `cancel-requested`, `permission-denied`, `canceled`, `failed`, `interrupted`,
  or `succeeded`. Percent is `unknown` or an integer from 0 through 100;
  PackageKit's documented unknown sentinel `Percentage=101` maps to `unknown`
  and is never clamped to 100. Any other out-of-range value also maps to
  `unknown` with bounded malformed-progress detail so an otherwise active
  transaction remains observable. Cancelable is `yes` or `no`. Every terminal
  operation record must use `cancelable=no`. Audit result uses only the
  terminal operation states.
- An `active-operation` row is snapshot-only and has the same closed fields as
  an operation row. It represents the one validated nonterminal PackageKit
  `refresh` or `update` journal record after recovery. Its ID must have the
  required `op-` shape, its action and kind must match the fixed mapping, and
  its state must be nonterminal. A snapshot contains at most one such row. The
  row is omitted when no PackageKit operation remains active; it is never
  synthesized from an unsafe or malformed journal record. `cancelable=yes` is
  emitted only while the exact adopted transaction reports `AllowCancel=true`.
  This bounded row lets the root model restore the visible operation identity
  and pass that exact ID to `updates-cancel` after Settings or the provider
  restarts. Regional and delegated work remains visible through its originating
  operation stream and the kind-specific recovery rules below, never through an
  `active-operation` row.
- Every operation and audit row carries the action ID that originated the
  operation. The fixed action-to-kind mapping is `updates-refresh` to
  `refresh`, `updates-install-all` to `update`, `timezone-set` to `timezone`,
  `ntp-set` to `ntp`, `locale-set` to `locale`, and `accounts-open`,
  `password-open`, `printers-open`, and `sources-open` to `delegate`. As defined
  above, `health-open` is fixed in-process navigation and never appears in an
  operation or audit row.
  `updates-cancel` controls the current update or refresh operation and never
  starts an operation of its own; every record for that operation retains its
  original action ID. Action ownership is also fixed:
  `updates-refresh`, `updates-install-all`, and `updates-cancel` belong to
  `updates`; `timezone-set`, `ntp-set`, and `locale-set` to `regional`;
  `accounts-open` and `password-open` to `accounts`; `printers-open` to
  `printers`; `sources-open` to `sources`; and `health-open` to `diagnostics`.
  The recovery provider owns no action. Every action row must name its fixed
  owner. Action class is fixed as well: every action is `delegated` except
  `health-open`, which is `user-session`. A producer or consumer rejects an
  action row whose class does not match this mapping.
- Action availability is `available` or `unavailable` and action class uses the
  provider class enum. The error capability field is exactly one provider ID,
  which is also its owner. Error codes are the closed normalized enum
  `network`, `repository`, `conflict`, `signature`, `package`, `unsupported`,
  `malformed`, `missing-provider`, `permission-denied`, `canceled`, `timeout`,
  `interrupted`, or `internal`. PackageKit `NO_NETWORK` maps to `network`;
  repository fetch/configuration/not-found and no-cache errors map to
  `repository`; dependency, file, database-lock, and package-conflict errors map
  to `conflict`; GPG, signature, key, and unsigned-repository errors map to
  `signature`; other package download/install/remove/update errors map to
  `package`; `NOT_AUTHORIZED`, `NOT_SUPPORTED`, and transaction cancellation
  map to `permission-denied`, `unsupported`, and `canceled`, respectively.
  systemd `AccessDenied`, missing service/object/unit, invalid-argument,
  timeout, and busy/conflict D-Bus errors map to `permission-denied`,
  `missing-provider`, `malformed`, `timeout`, and `conflict`; every unlisted
  upstream error maps to `internal`. Raw numeric enums, D-Bus error names, and
  localized messages never occupy the code field and may appear only as bounded
  sanitized detail.

A snapshot emits exactly one `snapshot-generation` row, one provider row for
every provider ID active in its header minor, one row for every active action
ID, one state row for every active state ID, all list records enabled by that
minor, zero or one validated `active-operation` row, then one
`complete<TAB>snapshot`. An unavailable, restricted, or unsupported capability
therefore retains an explicit status-bearing state row instead of omitting its
value. The generation is 64 lowercase hexadecimal characters. It is the SHA-256
digest of the ASCII prefix `dwm-titus-update-plan-v1`, followed first by the
exact installable update IDs sorted by unsigned UTF-8 bytes and then by the
complete `package-change` rows sorted by the unsigned UTF-8 tuple
`(action, package-id, name, version, summary)`. Each update ID is encoded as the
ASCII byte `U`, an eight-byte big-endian byte length, and its raw bytes. Each
plan row is encoded as the ASCII byte `P` followed by all five tuple fields in
order, each as an eight-byte big-endian byte length and its raw bytes. Empty
sets therefore have a deterministic generation, while any dependency-resolved
action, identity, version, or displayed plan change invalidates confirmation.
List record IDs (`update`, `package-change`, `repository`, `account`, and
`filesystem`) must be unique within their record type. State and list-record
ownership is fixed as follows:

- `updates` owns `update-summary`, `update-last-refresh`, `update-restart`, and
  every `update` and `package-change` row.
- `regional` owns `timezone`, `ntp-enabled`, `ntp-synchronized`, and `locale`.
- `accounts` owns `accounts-count` and every `account` row; `printers` owns
  `cups-service`; `sources` owns every `repository` row.
- `information` owns the OS, kernel, architecture, hardware, CPU, memory, swap,
  and uptime states. `storage` owns `filesystem-summary` and every `filesystem`
  row.
- `security` owns `selinux`, `secure-boot`, `firewalld`, `root-encryption`, and
  `screen-lock`. `diagnostics` and `recovery` own no state or list rows.

An operation stream emits exactly one operation ID and originating action ID,
exactly one audit row after the terminal operation record, and then one
`complete<TAB>operation`. The action must have the fixed kind defined above.
The audit ID, action ID, and kind must match the operation, its result must
match the terminal state, and no duplicate audit row is accepted.
An operation stream accepts at most one error row. A `failed` terminal operation
requires exactly one preceding error row whose capability is the provider that
owns the operation: `updates` for `refresh` and `update`, `regional` for
`timezone`, `ntp`, and `locale`, and the action's declared provider for
`delegate`. Other terminal results do not require an error row.
The first operation record must be `pending`; consumers reject any other
initial state. Audit timestamps are canonical UTC RFC 3339 whole seconds in the
exact `YYYY-MM-DDTHH:MM:SSZ` form and both are required on the terminal audit
row. Consumers do not compare their wall-clock order: `finished` may precede
`started` when NTP or an administrator moves the system clock backward. Record
order and the validated operation transition sequence remain
authoritative for lifecycle ordering.

Allowed operation transitions are:

| From | Allowed next state |
| --- | --- |
| `pending` | `authorizing`, `running`, `canceled`, `failed`, or `interrupted` |
| `authorizing` | `running`, `permission-denied`, `canceled`, `failed`, or `interrupted` |
| `running` | `running`, `cancel-requested`, `succeeded`, `failed`, or `interrupted` |
| `cancel-requested` | `cancel-requested`, `canceled`, `succeeded`, `failed`, or `interrupted` |
| Any terminal state | None |

Repeated `running` and `cancel-requested` records carry progress or cancellation
updates. `succeeded` after `cancel-requested` is valid because completion can
race cancellation. `permission-denied`, `canceled`, `failed`, `interrupted`,
and `succeeded` are terminal and appear exactly once.

Snapshot record failures are provider-scoped only when a valid known provider,
state, action, or list-record ID still identifies the owner; the consumer marks
that provider invalid and continues parsing unrelated providers. A malformed
header or completion, a missing or unknown owner ID, duplicate ID, illegal enum,
duplicate `active-operation`, operation-ID, action-ID, or action-kind mismatch,
a terminal `active-operation`, transition outside the table,
an operation record after a terminal state, any record after the required
completion, or missing completion rejects the entire stream. Operation and
audit record failures always reject the operation stream. Text fields are
capped at 512 bytes. Fixed per-type list budgets are 4096 `update`, 4096
`package-change`, 512 `repository`, 256 `account`, and 256 `filesystem` rows,
so a snapshot contains at most 9216 list records; the entire stream is capped
at 8 MiB.

The initial actions are a closed enum: `updates-refresh`, `updates-install-all`,
`updates-cancel`, `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`,
`password-open`, `printers-open`, `sources-open`, and `health-open`. QML cannot
select an executable, D-Bus
destination, interface, method, repository ID, package ID, user, unit, device,
path, or elevation mechanism.

## Operation Lifecycle and Audit

- Passive discovery uses the fixed maximum cache-age hint and never calls
  `RefreshCache` or starts a mutable update; after discovery it may invoke only
  the unjournaled `SIMULATE|ONLY_TRUSTED` read-only transaction defined below.
  PackageKit may otherwise perform only backend work required to return
  discovery results as described above.
- Every mutation begins from a visible confirmation describing owner, impact,
  authorization, cancellation limit, and recovery.
- When a bounded `GetUpdates(NONE)` result contains at least one installable
  update ID, discovery creates a separate read-only PackageKit transaction and
  calls `UpdatePackages` with the bitwise `SIMULATE|ONLY_TRUSTED` flags and
  exactly those installable update IDs. Only a successful `Finished` result
  with a complete, valid `Package` signal set
  produces `package-change` rows. This simulation never authorizes or mutates
  packages. One 120-second monotonic aggregate deadline covers its
  `CreateTransaction`, `SetHints`, `UpdatePackages`, and wait for `Finished`.
  On expiry the provider requests `Cancel` only when `AllowCancel=true`, waits
  no more than five additional seconds for `Finished`, then detaches from the
  read-only transaction and completes the snapshot with an `updates` `timeout`
  error and no plan rows. The simulation is never journaled or recovered. It
  accepts at most 4096 unique `Package` results; an additional result follows
  the same bounded cancellation sequence and is a `malformed` error. An empty
  installable update set emits no plan rows and does not call `UpdatePackages`.
  A missing simulation capability, denial, error, malformed or duplicate
  package result, or unrepresented requested update preserves the readable
  `update` rows but leaves `updates-install-all` unavailable with the owning
  typed error.
- An install-all confirmation captures the snapshot generation and displays
  every resolved `package-change` action, including dependency additions and
  removals. `UpdatesChanged` or any accepted replacement snapshot invalidates
  an open confirmation. After the user accepts, the provider performs a fresh
  bounded `GetUpdates(NONE)` and a fresh `SIMULATE|ONLY_TRUSTED` transaction
  using the same fixed rules, then recomputes the generation before creating a
  mutable transaction. A mismatch terminates as `failed`/`conflict`, publishes
  the new snapshot, and requires a new confirmation. Only the revalidated exact
  installable update IDs are passed to the real
  `UpdatePackages(ONLY_TRUSTED, ...)`; PackageKit remains the dependency owner,
  while the immediately preceding simulation is the confirmation's current
  resolved preview.

  PackageKit exposes no transaction-scoped prepare/commit token that can bind a
  completed simulation to a later `UpdatePackages` transaction. A package or
  repository change in that final interval can therefore make PackageKit
  resolve a different dependency set even after the generation check. The
  confirmation states this platform limitation and promises a current preview,
  not an atomic frozen plan. Actual PackageKit `Package` signals update bounded
  in-memory action counts, a SHA-256 digest, and at most 128 distinct mismatch
  samples against the preview; they are never emitted one-for-one. The digest
  begins with the ASCII prefix `dwm-titus-update-observed-v1` and then encodes
  each accepted signal in arrival order as the normalized action and package
  ID, each with an eight-byte big-endian byte length followed by its raw bytes.
  `DOWNLOADING` is phase-only and does not enter the observed set or digest.
  Actual `INSTALLING`, `UPDATING`, `REMOVING`, and `OBSOLETING` values map to
  `install`, `update`, `remove`, and `obsolete`. A `CLEANUP` whose package name
  and architecture match an inbound `update` row is the old half of that
  ordinary replacement and is also ignored. Another `CLEANUP` maps to
  `obsolete` only when its exact package ID appears as `obsolete` in the
  preview; otherwise it and every other info value map to `unknown`, mark
  comparison `unknown`, and are digested as the literal `unknown`. These rules
  prevent download and replacement phases from becoming false plan differences
  while failing closed on unexplained actions.

  Operation output always emits each reached lifecycle state once: `pending`,
  `authorizing` when required, initial `running`, and the first
  `cancel-requested` when that transition is valid. Those at most four records
  cannot be displaced by progress. Integer-percentage, cancelability, and
  mismatch-summary changes share a separate cap of 252 coalesced nonterminal
  records. Once that cap is reached, later progress changes update only the
  in-memory aggregate; a later required lifecycle transition is still emitted.
  The required terminal record reports the final bounded counts, digest, and
  `different=yes|no|unknown` summary in its detail. Thus the complete stream
  stays below the 8 MiB limit and the root model retains at most 256
  nonterminal records plus the terminal record. These observed summaries are
  deliberately not journaled; recovery labels them unavailable instead of
  reconstructing or promising per-package detail. The UI never labels the
  preview as the completed set. A simulated `reinstall` or `downgrade` is
  rejected before confirmation, so the real call never requires or silently
  adds `ALLOW_REINSTALL` or `ALLOW_DOWNGRADE`.
- One root-scoped model owns every journaled operation. Refresh, update,
  regional, and delegated operations are mutually exclusive; a
  request to start another operation while one is nonterminal is rejected as
  `failed`/`conflict` before it can write the active record. The fixed
  `updates-cancel` control and `watch-operation` observer do not start an
  operation and retain their exact-ID behavior above.
- Closing Settings stops pane-only discovery but neither kills an active
  PackageKit transaction nor the root-scoped `watch-operation` process. While a
  regional or delegated originating stream is nonterminal, the root model
  defers finite snapshot requests until that stream terminates; event-driven
  read-state refreshes remain coalesced. Thus snapshot recovery terminalizes a
  stranded non-PackageKit journal record under the kind-specific rules below
  before producing output and never emits it as `active-operation`. Under the
  same exclusive-lock path, it also completes any terminalized PackageKit
  active payload before selecting snapshot records. This is journal-only
  completion of an already durable result; it performs no PackageKit lookup,
  history query, or signal wait while holding the lock. An incomplete recovery
  is a recovery error, never a nonterminal row. A
  finite `snapshot` always ends at `complete<TAB>snapshot`; when it contains an
  `active-operation`, its kind is necessarily PackageKit `refresh` or `update`.
  The root model first compares its ID with the one live provider stream it
  already owns. A matching originating refresh or install stream remains the
  sole observer and no watcher is started. Otherwise the root model immediately
  starts exactly one
  `dwm-system-management watch-operation OPERATION_ID` process, and records it
  as that operation's sole live stream before accepting another snapshot. That
  process revalidates one of the two permitted journal identities above. For a
  nonterminal record it adopts only its exact PackageKit object, emits `pending`,
  then `authorizing` when the adopted transaction is known to have reached
  authorization. It emits `running` only after the journal or adopted
  transaction proves that state was reached, followed when applicable by
  `cancel-requested`. Thus an authorization still in progress remains in
  `authorizing` and may terminate directly as `permission-denied`. It emits each
  known reached lifecycle state once and remains subscribed until it emits the
  terminal operation, audit, and `complete<TAB>operation` records.

  If the active payload was cleared in the snapshot-to-watch race, the permitted
  newest-terminal match is replay-only and opens no PackageKit object. It emits
  `pending`, the minimum transition implied by the durable terminal result
  (`authorizing` before `permission-denied`, or `running` before `succeeded`),
  then that exact terminal operation, its audit, and
  `complete<TAB>operation`. The other terminal states are valid directly from
  `pending`. No newer ring record can be consumed as the requested operation.

  Unexpected watcher exit triggers up to three non-overlapping
  snapshot-and-watch recovery attempts in the root model after delays of one,
  two, and four seconds. If the third retry fails, it retains the journaled
  operation and actionable recovery guidance until explicit refresh; it never
  reports success or starts a replacement mutation. Quickshell restart uses the
  same finite snapshot followed by live watch sequence, so Settings closure and
  provider interruption cannot leave an adopted transaction permanently
  unwatched.
- Update cancellation is exposed exactly while PackageKit reports `AllowCancel`.
  Once cancellation becomes unsafe, Settings explains that the RPM transaction
  must finish.
- The journal lives under
  `${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/system-management/`, is mode
  0700, and defines exactly 35 provider-owned paths: fixed `active`, `cursor`,
  and `restart` paths plus 32 fixed terminal paths named `terminal-00` through
  `terminal-31`. It never enumerates the directory and ignores unrelated
  entries. Protocol 1.0 is the first shipped provider and has no released
  predecessor to migrate. If a fixed path contains an earlier plain-text
  development record rather than a valid frame file, the provider reports the
  recovery provider `partial` with a `malformed` error and blocks every
  system-management mutation; it never guesses or converts active, restart,
  cursor, or terminal semantics. Guidance requires a reboot first, so any
  unobserved PackageKit work and restart requirement crosses a safe boot
  boundary, and then moving the entire legacy journal directory aside before
  refresh. Journal creation opens the new directory with
  no-replace semantics, creates each path relative to that descriptor with
  `O_CREAT|O_EXCL|O_NOFOLLOW`, mode 0600, and initializes it before the journal
  becomes usable. It creates and syncs every other file, syncs the directory,
  then creates and syncs `cursor` last as the initialization commit marker and
  syncs the directory again. A crash during first initialization leaves a safe
  partial journal that recovery may finish only when the cursor marker is absent
  (the path is missing or is a safe short or torn initial file), every existing
  fixed path passes the owner, type, mode, link-count,
  and at-most-16-KiB checks, and no frame contains a valid advanced or
  noninitial payload. Under the exclusive directory lock, recovery rewrites a
  short or torn initial file through its held descriptor to the exact 16 KiB
  sequence-1 image, syncs and verifies it, and creates missing paths with the
  same exclusive rules. It then commits `cursor` last and syncs the directory.
  This descriptor-bound rewrite is permitted only before the cursor marker;
  normal journal commits never truncate a file. A missing path after that
  marker exists, or beside any advanced or noninitial frame, is malformed and
  is never silently recreated.

  Each persistent path is one fixed 16 KiB file containing frames at byte
  offsets 0 and 8192. Every frame is exactly 8192 bytes and has this canonical
  byte layout:

  | Offset | Size | Encoding |
  | --- | --- | --- |
  | 0 | 8 | Magic bytes `44 57 4d 4a 4e 4c 31 00` (`DWMJNL1` plus NUL) |
  | 8 | 2 | Unsigned little-endian frame major, exactly 1 |
  | 10 | 2 | Unsigned little-endian frame minor, exactly 0 |
  | 12 | 4 | Unsigned little-endian payload length, 0 through 8128 |
  | 16 | 8 | Unsigned little-endian sequence, 1 through 18446744073709551615 |
  | 24 | 8 | Reserved zero bytes |
  | 32 | 32 | SHA-256 digest |
  | 64 | 8128 | Payload followed by zero bytes through the frame end |

  The digest input is exactly header bytes 0 through 31 followed by exactly
  `payload length` bytes from offset 64; it excludes the digest and zero
  padding. A nonempty payload is the exact UTF-8 journal record with no NUL,
  carriage return, or line feed; empty active and terminal payloads have length
  zero. Integers have no native-endian interpretation. Initialization zeroes
  the entire 16 KiB file, writes sequence 1 into frame zero, and syncs the file;
  the all-zero second frame is invalid until its first commit. A reader
  uses bounded `pread` on a held descriptor, validates both complete frames,
  and selects the valid frame with the greater sequence. Equal sequences with
  different bytes, two invalid frames, a nonzero unused region, or sequence
  exhaustion is a recovery error. To commit, the provider writes the complete
  next sequence into the inactive frame through that same held descriptor,
  syncs the file, reads the frame back, and accepts it only if every byte and
  digest match. A provably invalid torn inactive frame leaves the previous frame
  authoritative. A short-write, write, sync, or readback error makes the commit
  indeterminate because either frame may be durable; the live provider stops
  before external mutation or marks an already running operation
  persistence-faulted, and recovery later selects the highest valid sequence and
  applies its operation identity idempotently. Existing journal files and inodes
  are never replaced, renamed, truncated, or unlinked after initialization.
  Logical terminal records are reused after ring wrap by committing their next
  inactive frame, and clearing `active` likewise commits a validated empty
  payload in its inactive frame.

  The provider opens all 35 paths through the held directory descriptor without
  following symlinks and validates device, inode, owner, regular-file type,
  mode, link count, and exact size. A newly initialized cursor payload is `00`,
  `restart` is the validated all-clear record defined below, `active` is empty,
  and terminal payloads are empty. Before accepting an operation it requires a
  safe writable active, cursor, and restart file and at least one safe writable
  terminal slot. Starting at the cursor index, it selects the first qualifying
  slot in ring order and persists that two-digit slot in `active` before the
  external mutation. Terminalization commits that slot, commits the following
  cursor index, then commits an empty active payload. Thus safe fixed slots
  retain the newest terminal records by durable ring position, never by the
  rollback-prone `finished` wall clock.

  Every provider process takes a shared `flock` on the held journal directory
  descriptor for a read and an exclusive lock for one validation-and-commit
  critical section. A writer holds the exclusive lock only until that frame is
  synced, read back, and identity-checked; it never holds the lock while waiting
  for authorization, PackageKit work, or a later signal. Before every later
  state commit it reacquires the exclusive lock and revalidates the complete
  journal plus the expected active operation identity. It retries nonblocking
  acquisition only until a five-second monotonic deadline; timeout returns a
  typed `conflict` before an external mutation starts, or marks an already
  running operation persistence-faulted. A snapshot that must prune restart
  guidance releases its shared lock, acquires the exclusive lock under the same
  bound, and revalidates the complete journal before pruning. Every journal
  writer in this project follows this protocol. The lock serializes cooperating
  providers while allowing snapshots and a replacement watcher to observe a
  long-running operation; descriptor checks remain mandatory because another
  same-user process can ignore advisory locks.

  The absolute state path is opened component-by-component from a held root
  directory descriptor with directory-only, no-symlink semantics; a symlink or
  non-directory component fails closed. The provider retains each parent and
  child descriptor in this bounded chain. Before and after every journal frame
  commit and external mutating D-Bus call, `fstatat` without symlink following
  must resolve each child name from its held parent to the held child device and
  inode, including the `system-management` entry itself. A renamed whole
  journal or ancestor directory therefore fails identity validation instead of
  leaving the provider writing into a detached tree.

  Every read and frame commit remains bound to those locked, validated file
  descriptors. Immediately before and after each descriptor write, and again
  before invoking an external mutating method, `fstatat` with no symlink
  following must still resolve the fixed path to the held descriptor's device
  and inode and must repeat all metadata checks. A mismatch rejects or strands
  the operation without ever writing, truncating, renaming, or unlinking the
  raced replacement. This post-write identity check catches a replacement made
  after the pre-write check: the descriptor commit affected only the originally
  validated inode, and no external mutation starts from a journal that is no
  longer reachable at its fixed path at that check. The provider repeats all 35
  identity checks immediately after sending an external mutating D-Bus call,
  whether or not a reply arrives. A replacement in the irreducible interval
  between the last pre-call check and that send is therefore treated as an
  integrity failure, not as a safely journaled operation. The live provider
  retains the detached descriptors and exact transaction identity, marks the
  operation persistence-faulted, continues observing only that transaction to
  its terminal signal, and never reports durable success.

  If that provider exits, recovery deliberately cannot rediscover a detached
  inode by pathname. An unsafe or malformed replacement is rejected with a
  path-specific recovery error, bounded PackageKit diagnostics, and all mutation
  disabled; recovery never adopts a transaction without a durable exact path and
  identity. A fully well-formed journal forged by another process with the same
  UID is indistinguishable from project-written user state and is outside this
  contract's integrity boundary. The journal provides crash consistency and
  safe path handling, not authentication against its owner. This limitation
  grants no additional authority because the same user can invoke the delegated
  PackageKit interface directly. During a live operation, the retained
  descriptors and path-chain checks still ensure interference cannot redirect a
  descriptor write into the replacement or turn a detected ambiguous outcome
  into success.

  If interruption occurs after the terminal slot commit but before cursor
  advance or active clearing, recovery accepts only the exact matching
  operation and selected slot, completes the idempotent cursor commit, and then
  commits the empty active payload. It never advances the cursor from an
  unmatched record. Unrelated directory entries are never read or followed and
  cannot increase recovery work. Journal records contain common IDs,
  originating action IDs, timestamps, operation
  kinds, terminal results, and sanitized diagnostics, plus eight fixed typed
  fields: update snapshot generation, PackageKit transaction object path,
  system restart contribution, session restart contribution, application
  restart contribution, boot identity, terminal-monotonic timestamp, and the
  required two-digit terminal slot. An `update` record requires a valid
  generation, the exact PackageKit path, a
  `none|system|security-system|unknown` system contribution, a
  `none|session|security-session` session contribution, a `yes|no` application
  contribution, and the lowercase UUID read from the fixed
  `/proc/sys/kernel/random/boot_id` file. The boot file read is capped at 37
  bytes. A nonterminal update or refresh uses the literal `pending` for its
  terminal timestamp. Every update or refresh terminalization commits unsigned decimal
  `CLOCK_MONOTONIC` microseconds: immediately when `Finished` is consumed, or at
  the conservative local decision point when bounded recovery instead obtains a
  history result or records `interrupted`. A `refresh` record requires the exact
  PackageKit path and uses the literal `-` for generation, all three restart
  contributions, and boot; its terminal timestamp follows the rule above.
  `timezone`, `ntp`, `locale`, and
  `delegate` records require literal `-` in the first seven typed fields.
  Every journaled kind requires its selected terminal slot. A consumer rejects
  any missing field or value that does not match the operation kind. Each
  accepted `RequireRestart` signal durably commits the updated active payload
  through its held descriptor before any later `Finished` signal is consumed;
  PackageKit application, session, security-session, system, and
  security-system values merge into their corresponding contribution without
  collapsing scope or security. `NONE` changes no contribution; an unrecognized
  value sets only the system contribution to `unknown`. The terminal record
  carries that same three-part tuple, its boot identity, and its exact
  terminal-monotonic timestamp. If committing or syncing `active` fails, the
  provider records an in-memory persistence fault, requests cancellation only
  when PackageKit permits it, and consumes later signals only to stop observing
  the backend. It neither emits a terminal record nor accepts a later `Finished`
  as durable success while the active journal omits the requirement. The
  stranded active record and recovery error remain visible and block new
  mutation until journal persistence is repaired; subsequent bounded recovery
  treats any otherwise successful result as having restart requirement
  `unknown`.

  The fixed `restart` record is the authority for outstanding guidance. Its
  closed fields are the boot UUID; the last-applied update operation ID or `-`; a
  `none|system|security-system|unknown` system bucket; a
  `none|session|security-session` session bucket and unsigned
  terminal-monotonic cutoff; and a `yes|no` application bucket and unsigned
  terminal-monotonic cutoff. A newly initialized all-clear record uses `-`,
  `none`, `none`, `0`, `no`, and `0` after the UUID. Satisfaction pruning keeps
  the last-applied operation ID unchanged on the same boot. Keeping the two
  lower-scope cutoffs independent lets a login clear an older session
  requirement while retaining a newer application requirement. Before
  committing any update terminal, the provider first prunes requirements
  already satisfied by the rules below. It
  then compares the operation's captured boot UUID with the current boot. A
  mismatch proves that reboot occurred after that operation began, so a terminal
  result recovered from the old boot contributes the all-clear tuple; it is
  never merged back after the boundary cleared it. Otherwise the provider,
  regardless of the result, merges each member of the durable three-part
  contribution into its corresponding restart bucket, using the current
  terminal timestamp for the session and application cutoffs. An update that
  ends `failed`, `canceled`, or `interrupted` when sending or backend execution
  of the mutating `UpdatePackages` method cannot be excluded preserves every
  durable observed contribution and changes only a system contribution of
  `none` to `unknown`. This rule applies regardless of the last persisted
  lifecycle state because packages may have changed before observation stopped.
  With no observed requirement its effective tuple is
  therefore system `unknown`, session `none`, and application `no`; observed
  session and application contributions remain intact, and an observed system
  or security-system contribution remains more specific than `unknown`. A
  failure, conflict, cancellation, or interruption that the provider and journal
  prove occurred before that mutating method was sent contributes the all-clear
  tuple, as does an authorization denial or cancellation that the exact
  transaction proves never reached `running`. An all-clear
  contribution never weakens
  an outstanding requirement; multiple updates before a recovery boundary
  therefore retain every unsatisfied bucket and its latest applicable cutoff.
  An `unknown` contribution is stored only as system bucket `unknown`, never as
  `none` or in a session or application bucket, and remains until a boot change.
  The displayed closed restart enum is recomputed from the remaining buckets by
  maximum scope and security urgency; bucket data is never collapsed back from
  that display value.
  Terminalization is a write-ahead sequence under the exclusive journal lock.
  The provider first durably commits `active` with the final result, effective
  restart contribution tuple, boot UUID, terminal-monotonic timestamp, and
  reserved slot instead of `pending`. It then commits and syncs the inactive `restart`
  frame with the merged buckets and that active operation ID as the
  last-applied ID before committing the terminal slot. Persistence failure at
  either step leaves `active` for recovery and never reports durable success.
  Recovery of a terminalized update active record first compares its captured
  boot UUID with the current boot. A mismatch leaves the new boot's restart
  record all-clear, skips contribution reapplication, and completes only the
  terminal-slot, cursor, and empty-active commits. On the same boot, recovery
  compares the operation ID with the validated restart last-applied ID. A match
  proves the contribution was
  already merged, even if a later snapshot satisfied and pruned its buckets, so
  recovery skips the merge and completes only the idempotent terminal-slot,
  cursor, and empty-active commit steps. A mismatch reapplies the contribution from
  the durable active checkpoint once and records its ID before proceeding. No
  new mutating operation is admitted while `active` exists, so the single
  last-applied ID cannot be displaced before that operation is terminally
  committed. Recovery never reconstructs a later cutoff or changes a durable
  terminal result merely because it resumed after a session boundary.
  Terminalized refresh, timezone, NTP, locale, and delegate records never read,
  merge, or write the restart record; recovery completes only their idempotent
  terminal-slot, cursor, and empty-active commits.

  A changed boot UUID satisfies every bucket and resets `restart` to the
  all-clear record for the new UUID. On the same boot, the application and
  session buckets clear independently only when the current logind session's
  validated `TimestampMonotonic` is strictly greater than that bucket's stored
  cutoff. Under one ten-second aggregate deadline, the provider first calls the
  fixed `org.freedesktop.login1.Manager.GetSessionByPID` method with its own PID,
  validates the returned session object path, and then reads the
  `org.freedesktop.login1.Session.TimestampMonotonic` property from that exact
  object through `org.freedesktop.DBus.Properties.Get`. It accepts only the
  expected unsigned 64-bit D-Bus value. A session that began while an update was
  still running cannot clear its later requirement.
  Missing logind state, timeout, or malformed data retains the guidance with
  `partial` status until a later session or boot boundary proves satisfaction;
  it is never guessed clear. The system bucket clears only after a boot change.
  Every snapshot and journal-recovery load applies these satisfaction rules and
  recomputes the display aggregate before publishing `update-restart`. If any
  bucket changed, it commits and syncs the pruned restart frame before exposing
  the refreshed snapshot. If that persistence
  fails, the provider reports updates `partial` and retains the prior guidance
  instead of claiming it cleared. The durable action ID must have the fixed kind
  defined by the
  protocol and determines the owning provider used for recovered errors. The
  files never record passwords, environment dumps, repository credentials,
  package payloads, or unbounded output.
- Before any mutation, the provider obtains the fixed service transaction or
  operation ID without invoking its mutating method, commits and syncs the
  pending active payload, and completes the post-write path-identity check. For
  PackageKit it calls `CreateTransaction`, persists the returned transaction
  object path, and only then invokes `RefreshCache(force=true)` or
  `UpdatePackages(ONLY_TRUSTED, ...)` on that transaction. Each later state and
  terminal result is committed and synced in order. Failure to
  create or persist the record prevents the mutation from starting.
- A PackageKit-backed `refresh` or `update` operation in any nonterminal state
  that lacks a terminal PackageKit result is `interrupted`, not successful.
  The transition table permits this recovery result before and after the
  operation begins running. Recovery first accepts a valid durable terminal
  journal record that the provider wrote from PackageKit's `Finished` signal
  only when its operation ID, originating action ID, operation kind, and
  persisted PackageKit transaction object path exactly match the active
  record. A missing, malformed, duplicate, or mismatched identity is never
  consumed as that operation's result.
  For a nonterminal record, recovery validates and copies the bounded record
  under a shared journal lock, releases that lock, and only then attempts to
  adopt the exact recorded transaction object and consume its current or
  replayed result before checking the active
  PackageKit transaction list. For an update transaction only, it finally
  calls PackageKit transaction method `GetOldTransactions(64)` on a new
  read-only transaction and consumes at most 64 emitted `Transaction` records.
  That signal supplies the old transaction object path, success flag, role, and
  UID used below; this is not the separate package-oriented
  `GetPackageHistory` method. PackageKit does not record `RefreshCache`
  transactions in old-transaction history. A history result is accepted only
  when its transaction object path exactly matches the journaled path, its role
  is `update-packages`, and its UID is the invoking user's UID.
  Before either adoption or history assigns a restart contribution, it compares
  the active record's captured boot UUID with the current boot. A mismatch uses
  the all-clear tuple for every external result and never reintroduces unknown or
  observed guidance from the previous boot.
  Exact active-transaction adoption seeds its three restart contributions from
  the validated nonterminal record, merges every accepted `RequireRestart`
  signal observed during adoption using the per-scope rule above, and durably
  persists that tuple in the terminal record before reporting the adopted
  `Finished` result. If adoption reaches `Finished` without replaying any
  `RequireRestart` signal, a permission denial or cancellation that the journal
  and adopted transaction both prove never reached `running` uses the all-clear
  tuple. Every succeeded result, failed result, or cancellation whose execution
  cannot be excluded sets the system contribution to `unknown` while retaining
  the validated session and application contributions already in `active`; a
  restart signal may have occurred after the last successful active-frame
  commit. A valid durable
  terminal record written from `Finished` recovers its persisted tuple. A
  missing, malformed, or kind-incompatible contribution field in the active or
  terminal record is a `malformed` recovery error that preserves the record and
  blocks mutation; it is never downgraded to `interrupted`. That terminal state
  is used only after the journal record is valid and exact bounded external
  evidence still cannot supply a trustworthy result. An old-transaction history
  match with `succeeded=true`
  recovers only the terminal `succeeded` result and sets the system contribution
  to `unknown` while retaining validated session and application contributions,
  because history cannot
  replay a `RequireRestart` signal that may have been missed before persistence.
  It never substitutes or preserves `none` on that path. An exact history match
  with `succeeded=false` is still `interrupted`, because history cannot
  distinguish cancellation from another failure or reconstruct the required
  typed error row. It uses the same conservative system `unknown` contribution
  while retaining validated session and application evidence regardless of the
  active record's last persisted lifecycle state, because the D-Bus method may have begun package
  changes before that state was synced. Duplicate matches,
  malformed identity fields,
  another role or UID, and a success flag without the exact path are ambiguous
  and never consumed as this operation's result. After any unlocked PackageKit
  interaction, recovery reacquires the exclusive journal lock, revalidates the
  full path chain, fixed files, and exact active operation identity, and only
  then commits recovered state. A mismatch discards the stale D-Bus result and
  changes no journal frame. No D-Bus method, signal wait, or bounded history
  collection runs while either journal lock is held.

  A negative bounded lookup is never evidence that PackageKit succeeded or
  failed. If exact adoption or the active transaction list confirms that the
  exact transaction is still active, the finite snapshot emits its validated
  `active-operation` row. The matching live originating refresh or install
  stream remains its sole observer; only when no such stream is owned does the
  root model start the required `watch-operation` process to keep the operation
  nonterminal while consuming signals through `Finished`. Only after that exact
  transaction is absent and the bounded terminal sources
  cannot recover a result does the provider record `interrupted` to mean that
  its observation was interrupted and the backend outcome is unknown. It
  performs a new read-only discovery and offers diagnostics; it never retries
  the refresh or update automatically. The UI states this ambiguity rather
  than describing the PackageKit transaction itself as failed. Recovery never
  expands to an unbounded history query. A regional operation recovers a
  terminal result only from a valid terminal journal record durably written
  before interruption. Any nonterminal `timezone`, `ntp`, or `locale` record
  encountered by snapshot recovery becomes `interrupted` regardless of the owning systemd
  service's current value, because the journal intentionally stores no target
  and current state cannot prove this operation caused it. Recovery publishes a
  fresh read-only regional snapshot and explains that the requested mutation's
  outcome is unknown; it never retries or audits it as successful. A delegated
  launch records its terminal `succeeded` result as soon as the trusted tool is
  accepted; the tool owns all later internal work. A nonterminal delegated
  record encountered by snapshot recovery becomes `interrupted`, while a valid
  durable terminal record replays its exact launch result. Settings never
  infers that the delegated tool's internal work succeeded.

## Event and Resource Contract

- PackageKit `UpdatesChanged` and `InstalledChanged` invalidate update
  discovery; `RepoListChanged` invalidates both repository and update discovery
  because enabled sources determine inventory, simulation, and generation.
  Transaction-list signals are consumed only for bounded
  active-operation recovery; they never mark discovery dirty. Property,
  progress, package, error, restart, and finished signals are consumed only by
  the owner of their exact discovery, simulation, refresh, or update transaction.
  Transaction-scoped creation, progress, and `Finished` for the provider's own
  read-only transactions, and their accompanying `TransactionListChanged`,
  cannot schedule another discovery. Global `UpdatesChanged`,
  `InstalledChanged`, and `RepoListChanged` received while such a transaction is
  active do participate in the bounded dirty-bit settling cycle below, whether
  they arose from backend work or an external actor, because the global signal
  carries no transaction identity. The root model permits only one bounded
  PackageKit discovery/repository refresh at a time. Invalidations received while
  it is in flight set one dirty bit. Its serialized completion handler atomically
  tests and clears that bit while reserving at most one coalesced rerun before it
  exposes the provider as idle; an invalidation arriving on either side of that
  handoff therefore attaches to the reserved rerun or starts a new refresh and
  is never lost. That reserved rerun is the settling read for the burst.
  Every global invalidation received during that settling read, including at
  its atomic completion handoff, sets a separate unresolved-dirty bit. Because
  the signal has no transaction identity, the provider neither assumes it was
  self-generated nor schedules an unbounded third read. If the bit is clear,
  the provider publishes clean idle and a later signal starts a new cycle. If
  it is set, the provider retains it, publishes updates or repositories as
  `partial` with explicit-refresh guidance, and suppresses automatic reruns from
  further global signals until an explicit refresh or a section close/reopen
  starts a new bounded cycle. A cycle clears unresolved-dirty only when its
  settling read completes without another invalidation. Thus external dirty
  state is never silently discarded and a backend that emits on every passive
  read cannot form a refresh loop. Bursts never accumulate provider processes
  or overlapping PackageKit transactions.
- Consuming `Finished` for every journaled, non-simulated `UpdatePackages`
  transaction whose mutating method was sent and whose backend execution cannot
  be excluded marks update discovery dirty before terminal persistence,
  regardless of its last persisted lifecycle state or terminal result, because
  a failed, canceled, or interrupted backend may still have changed packages.
  The unjournaled
  `SIMULATE|ONLY_TRUSTED` transaction never marks discovery dirty. A successful
  or unsuccessful `RefreshCache` whose method was sent and whose backend work
  cannot be excluded does the same because it may have refreshed a subset of
  repositories. These provider-owned
  invalidations use the same serialized dirty bit as `UpdatesChanged`, so
  observing both causes exactly one rerun and absence of that signal cannot
  leave post-transaction discovery stale. Transaction-list signals remain
  excluded from discovery invalidation.
- The root model also marks discovery dirty when an owned journaled refresh or
  update stream exits without a terminal record after its external method was
  sent and backend work cannot be excluded. Every recovery of a nonterminal
  refresh or update reserves the same coalesced discovery rerun before it
  publishes an idle provider, whether recovery adopts a transaction, finds
  history, or records `interrupted`. These fallbacks make invalidation independent
  of terminal-frame success while preserving the simulation exclusion.
- systemd D-Bus property changes drive time and locale refresh while the System
  section is open. Because timedate1 marks `NTPSynchronized` and `CanNTP` as not
  emitting change signals, one non-overlapping bounded read of only those
  properties runs every 30 seconds while the section is open and immediately
  after an NTP action. The fallback stops on section close. A bounded snapshot
  remains available without a monitor.
- AccountsService manager `UserAdded` and `UserDeleted` signals and the `Changed`
  signal on every valid de-duplicated candidate object selected within the
  256-object bound trigger one bounded, coalesced account-summary refresh while
  the section is open. Candidate signals are subscribed before filtering
  `SystemAccount`, so an excluded object becoming eligible refreshes the list.
  The subscriptions and pending refresh stop when the section closes; an
  over-limit enumeration remains explicitly `partial`.
- The systemd manager's `UnitNew` and `UnitRemoved` signals for the fixed
  `cups.service`, `cups.socket`, and `firewalld.service` names, plus
  `PropertiesChanged` for each loaded unit's `ActiveState` and the CUPS
  socket's `SubState`, trigger one bounded, coalesced refresh of the owning
  state while the section is open. Those subscriptions stop on section close.
  Delegated-tool availability remains a bounded snapshot; Phase 6 adds no CUPS
  or firewalld polling loop.
- A single pane-scoped `dwm-system-management watch-mounts` process monitors
  mount-table changes while the System section is open. This fixed private
  minor-2 command accepts no arguments and is not an action or operation
  stream. Its supervisor starts exactly
  `findmnt --poll --raw --noheadings --output ACTION` in a dedicated process
  group. The child marks every inherited nonstandard descriptor close-on-exec
  before executing the fixed program. Before emitting anything, the supervisor
  waits under a one-second monotonic deadline until the live child's descriptor
  table contains the open `/proc/CHILD_PID/mountinfo` baseline. The readiness
  probe walks every numeric entry beneath that exact `/proc/CHILD_PID/fd`
  directory until it finds a symlink target equal to
  `/proc/CHILD_PID/mountinfo`, the child exits, its proc identity changes, or
  the deadline expires. It then emits the exact line
  `mount-monitor-ready`; subsequent bounded nonempty findmnt lines are emitted
  as `mount-change<TAB>ACTION`. Any other standard-output line, a line over 256
  bytes, a missed readiness deadline, or an unexpected supervisor or child exit
  marks storage `partial` with explicit-refresh guidance.

  The root model starts the initial bounded JSON filesystem snapshot only after
  receiving `mount-monitor-ready`. The first snapshot is authoritative for the
  mount-table state that exists when it reads; the contract does not promise an
  event for a transient change completed before findmnt opens its baseline. A
  change observed by the already-live monitor produces `mount-change`; neither
  findmnt nor this interface is a lossless mount-event history. Each emitted
  `mount-change` line triggers one coalesced rerun of the normal bounded
  snapshot; a line received before or while that read is active sets only one
  dirty bit. The snapshot
  completion handler atomically tests and clears that bit while reserving at
  most one rerun before it publishes completion or an idle provider, matching
  the PackageKit handoff above. An event on either side of the boundary
  therefore attaches to the reserved rerun or starts the next snapshot. That
  rerun is the settling read. A further mount event during its read or
  completion handoff sets unresolved-dirty, publishes storage `partial` with
  explicit-refresh guidance, and suppresses more automatic filesystem
  snapshots until explicit refresh or section close/reopen starts a new bounded
  cycle. Continuous mount churn therefore cannot create an unbounded process
  loop or be falsely published as clean.

  Each open allocates a monotonically increasing monitor generation; ready,
  line, exit, and queued-rerun callbacks verify both that the section is still
  open and that their captured generation is current before changing state or
  launching work. Section close invalidates the generation, removes the pending
  rerun, closes every monitor pipe, sends `TERM` to the dedicated process group,
  and uses nonblocking wait/waitpid checks for at most one second. If either
  process remains, it sends `KILL` to the group and continues nonblocking checks
  for at most one further second. A child still unreaped at that two-second
  close deadline is handed to the root-scoped SIGCHLD-driven reaper, which
  performs the eventual wait without blocking close or invoking the invalidated
  pane callbacks. This is an event stream, not an idle timer. Other system
  information and security probes run on open or explicit refresh and add no
  idle timer.

## Authorization and Recovery Rules

- PackageKit, systemd, AccountsService, CUPS, and delegated tools keep their own
  polkit or authentication policy. QML is never elevated.
- An authorization denial is `permission-denied`, not `unavailable`, and keeps
  the last validated read-only state visible.
- Network, metadata, repository, dependency, package, and signature failures
  remain distinct typed errors with the owning provider named.
- A completed update reports restart guidance from PackageKit restart data. It
  never initiates reboot; the existing confirmed session-action model owns that.
- High-risk storage, firewall, service, encryption, account, and repository
  operations remain delegated or unsupported until a separate specification
  defines a narrow interface.

## Validation and Rollback

Each implementation boundary must cover valid, malformed, missing-provider,
authorization-denied, canceled, interrupted, overlapping, and failed states.
PackageKit fixtures must exercise cancellation before and after `AllowCancel`
changes, all terminal results, recovery after Settings closure, and reboot
guidance. They terminate updates as `failed` from both `pending` and
`authorizing` after the mutating method send cannot be excluded and, without an
observed restart signal, prove the effective tuple is system `unknown`, session
`none`, and application `no`. A pre-call `failed`/`conflict` fixture proves the
all-clear tuple. Failed, post-running canceled, and interrupted fixtures seed
security-session and application contributions and prove those lower-scope
buckets remain intact when the system contribution becomes `unknown`. They
also terminate failed, canceled, and interrupted updates from `pending` and
`authorizing` after method execution becomes ambiguous, omit both global update
signals, and prove provider-owned invalidation schedules the discovery rerun.
They inject both `UpdatesChanged` and `InstalledChanged` at the
discovery-completion boundary and prove exactly one coalesced rerun is scheduled.
Self-scheduling fixtures emit all three global invalidations during both the
initial and settling reads, prove the cycle stops after two reads in visible
`partial` state, and prove further signals do not launch work. An invalidation
at the settling completion handoff remains dirty; a later explicit refresh with
a quiet settling read clears it and returns the provider to clean idle.
Terminal fixtures omit
`UpdatesChanged` after successful install, failed post-running install, and
failed post-running refresh, and prove provider-owned invalidation refreshes
discovery; a duplicate signal still coalesces to one rerun. Simulation fixtures
prove completion schedules no rerun. Persistence-failure and provider-exit
fixtures prove post-running operations still reserve that rerun without a
terminal frame. Recovery fixtures
match `succeeded=false` history while active is still `pending` and prove system
restart guidance becomes `unknown` while seeded security-session and application
contributions remain intact; refresh fixtures validate live and recovered
monotonic terminal timestamps and reject malformed values. An adoption fixture
crashes before an active contribution commit, omits replayed restart signals,
and proves a possibly running `Finished` yields the conservative unknown tuple
without clearing seeded lower-scope contributions, while a provably pre-running
denial or cancellation remains all-clear. A
previous-boot adoption and history fixture proves every result remains all-clear.
Watch fixtures reject both active and preceding-cursor terminal regional or
delegated operation IDs with status 3 and no stream. Regional fixtures must prove
fixed D-Bus destinations and methods. Logind fixtures cover both the manager
lookup and session-property read under their shared aggregate deadline,
including a malformed object path, wrong property type, and timeout after the
first reply.
Locale fixtures change the enumerated allowlist after confirmation and prove the
second bounded enumeration rejects the stale requested name before `SetLocale`.
Malformed contribution fixtures prove active and terminal records fail closed
without becoming `interrupted`.
Delegated-action tests must prove the executable allowlist and missing-tool
behavior. QML tests must prove readable state survives denial and every
section-owned process stops on close. Mount-monitor fixtures delay readiness and
prove no filesystem snapshot starts, then change the persistent final mount
state before the child's baseline opens and prove the first snapshot captures
it. An event emitted by the monitor after baseline-open must set the dirty bit
through a `mount-change` line. The fixtures make no event-observability
assertion for a transient change that findmnt does not emit. They cover clean
descriptor inheritance, the one-second readiness bound, child exit,
proc-identity change, malformed monitor output, and complete process-group
cleanup. QML fixtures close
and reopen the section with a new generation, invoke ready, mount-change, exit,
and queued-rerun callbacks captured from the prior generation, and prove those
callbacks schedule no work or state change while current-generation callbacks
still work. A mount event at the initial filesystem snapshot completion boundary
must reserve exactly one settling rerun. Events during that read and its handoff
must end in visible `partial` state, launch no third read, and clear only after a
quiet explicit refresh. Journal fixtures
run two provider writers concurrently and prove the directory lock serializes
validation and commit. Collision fixtures reject IDs present only in the
restart last-applied field while that lock is held. They tear each inactive
frame into a provably invalid image at every write boundary and prove the prior
valid frame remains authoritative. Injected short-write, sync, and readback
errors cover both outcomes: recovery selects and idempotently replays a valid
higher-sequence frame, or selects the previous frame when the higher sequence is
invalid. Golden byte fixtures
cover both offsets, integer endianness, empty and maximum payloads, padding,
digest coverage, invalid versions, and sequence exhaustion. Crash fixtures
exercise every terminalization step, including simultaneous system plus
security-session contributions, invoke `snapshot` and `watch-operation` from
each intermediate state, and prove each scope is applied exactly once before
terminal replay. Terminalized refresh, regional, and delegate fixtures prove
the restart frame remains byte-for-byte unchanged.
A terminalized-update fixture crashes after the active checkpoint, changes the
boot UUID, and proves recovery completes without reapplying its contribution.
Initialization fixtures tear and short-write every file before the cursor
marker and prove bounded recovery completes it, while the same damage after the
marker fails closed. Separate plain-text legacy active, restart, cursor, and
terminal fixtures each prove `malformed`, mutation blocking, no conversion, and
reboot-before-move-aside guidance. A long-running PackageKit fixture proves snapshots and a
replacement watcher can acquire the lock and restore the active operation. A
blocked adoption/history mock proves another reader can acquire the lock during
the D-Bus wait, and a changed active identity causes the later commit to be
discarded.
Directory-race fixtures rename the whole journal and each user-writable ancestor
between identity checks and prove the root-anchored chain rejects it. They also
replace each fixed path after its pre-write identity check but
before the descriptor commit from a process that ignores the advisory lock.
The provider must leave the replacement byte-for-byte unchanged, reject the
post-write identity check, and never invoke the external mutating method. A
separate fixture replaces a path after the last pre-call check, proves the
post-call check marks the live operation persistence-faulted, then terminates
the provider and proves a fresh snapshot blocks mutation without adopting an
unidentified PackageKit transaction or reporting success.

The complete phase runs the clean build, managed suite, Quickshell lint,
ShellCheck, shfmt, staged and repeated installation, nested X11, installed-file
parity, and a real Fedora 44 X11 exercise. Rollback for this inventory boundary
removes the contract and package-map/Kickstart entries together; it does not
automatically remove packages already installed by an image or recommended
installer run. Runtime boundaries remove their new provider, model, and pane
together without changing existing health or session-action contracts.

## Authoritative Interface References

- PackageKit D-Bus API: <https://packagekit.freedesktop.org/gtk-doc/api-reference.html>
- PackageKit transaction API: <https://packagekit.freedesktop.org/gtk-doc/Transaction.html>
- systemd timedate1 API: <https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.timedate1.html>
- systemd locale1 API: <https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.locale1.html>
- AccountsService manager D-Bus XML: <https://gitlab.freedesktop.org/accountsservice/accountsservice/-/raw/main/data/org.freedesktop.Accounts.xml>
- AccountsService user D-Bus XML: <https://gitlab.freedesktop.org/accountsservice/accountsservice/-/raw/main/data/org.freedesktop.Accounts.User.xml>
- CUPS administration guidance: <https://openprinting.github.io/cups/doc/admin.html>
