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
explicit Refresh action calls `RefreshCache` with `force=true`; passive
discovery never calls that method or starts an update transaction.

The update command grammar is fixed:

```text
dwm-system-management snapshot
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
generates it from the kernel CSPRNG, rejects a collision with the active or 32
terminal journal records, and fails closed after four collision attempts. A
cancel request is accepted only when this ID still equals the active journaled
refresh or update operation and that exact PackageKit transaction currently
reports `AllowCancel=true`. A stale, unknown, terminal, or replaced ID, or an
exact active transaction that no longer reports `AllowCancel=true`, produces a
command-level rejection: the command emits no operation stream, exits with
status 3, and writes only the fixed diagnostic `cancel target is unavailable`
to standard error. The root model maps status 3 directly to a visible
`conflict`, refreshes current state, and never parses the diagnostic. The active
operation and any newer operation remain unchanged. Malformed command syntax,
including an invalid ID shape, exits with status 2 instead.

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

The parameterized actions use this exact command grammar:

```text
dwm-system-management timezone-set ZONE
dwm-system-management ntp-set enabled|disabled
dwm-system-management locale-set LANG=LOCALE
```

`ZONE` is at most 255 ASCII bytes, contains no control characters, empty path
components, `.` or `..` components, and must exactly match a value returned by
the fixed `org.freedesktop.timedate1.ListTimezones` method. `LOCALE` is
at most 128 ASCII bytes, contains no control or whitespace characters, and must
exactly match a name reported by the bounded `locale -a` fallback because
locale1 has no locale enumeration method. `LANG` is the only accepted locale
key. Arguments are validated before confirmation and again immediately before
the fixed D-Bus call. No other option, key, D-Bus argument, or trailing argument
is accepted.

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
fixed `NONE` filter, including enabled and disabled repositories. Repository
changes remain in the Fedora-packaged `dnfdragora` tool when present. Missing
optional delegated tools are reported individually and never hide readable
service state.

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
| `0` | `updates`, `recovery` | `update-summary`, `update-last-refresh`, `update-restart` | `updates-refresh`, `updates-install-all`, `updates-cancel`, `recovery-clear-journal-temporaries` | `update` |
| `1` | `regional`, `accounts`, `printers`, `sources` | `timezone`, `ntp-enabled`, `ntp-synchronized`, `locale`, `accounts-count`, `cups-service` | `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open` | `account`, `repository` |
| `2` | `information`, `storage`, `security`, `diagnostics` | all information states, `filesystem-summary`, `selinux`, `secure-boot`, `firewalld`, `root-encryption`, `screen-lock` | `health-open` | `filesystem` |

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
  Account scope is `current` or `other`. Filesystem status uses the
  provider-status enum; mount ID is an unsigned decimal integer and the unique
  record ID within the snapshot, while source and target remain display-only
  text. `available`
  requires all three byte fields to be unsigned decimal integers; `partial`
  permits a mix of integers and `unknown`; `restricted`, `unavailable`, or
  `unsupported` requires all three byte fields to be `unknown`.
- Operation kind is `refresh`, `update`, `timezone`, `ntp`, `locale`,
  `journal-repair`, or `delegate`. Operation state is `pending`, `authorizing`, `running`,
  `cancel-requested`, `permission-denied`, `canceled`, `failed`, `interrupted`,
  or `succeeded`. Percent is `unknown` or an integer from 0 through 100, and
  cancelable is `yes` or `no`. Every terminal operation record must use
  `cancelable=no`. Audit result uses only the terminal operation states.
- An `active-operation` row is snapshot-only and has the same closed fields as
  an operation row. It represents the one validated nonterminal active journal
  record after recovery. Its ID must have the required `op-` shape, its action
  and kind must match the fixed mapping, and its state must be nonterminal. A
  snapshot contains at most one such row. The row is omitted when no operation
  remains active; it is never synthesized from an unsafe or malformed journal
  record. For a recovered PackageKit refresh or update, `cancelable=yes` is
  emitted only while the exact adopted transaction reports `AllowCancel=true`.
  This bounded row lets the root model restore the visible operation identity
  and pass that exact ID to `updates-cancel` after Settings or the provider
  restarts.
- Every operation and audit row carries the action ID that originated the
  operation. The fixed action-to-kind mapping is `updates-refresh` to
  `refresh`, `updates-install-all` to `update`, `timezone-set` to `timezone`,
  `ntp-set` to `ntp`, `locale-set` to `locale`, and `accounts-open`,
  `password-open`, `printers-open`, `sources-open`, and `health-open` to
  `delegate`; `recovery-clear-journal-temporaries` maps to `journal-repair`.
  `updates-cancel` controls the current update or refresh operation and never
  starts an operation of its own; every record for that operation retains its
  original action ID. Action ownership is also fixed:
  `updates-refresh`, `updates-install-all`, and `updates-cancel` belong to
  `updates`; `timezone-set`, `ntp-set`, and `locale-set` to `regional`;
  `accounts-open` and `password-open` to `accounts`; `printers-open` to
  `printers`; `sources-open` to `sources`; and `health-open` to `diagnostics`.
  `recovery-clear-journal-temporaries` belongs to `recovery`. Every action row
  must name that owner. Action class is fixed as well: every action is
  `delegated` except `health-open` and
  `recovery-clear-journal-temporaries`, which are `user-session`. A producer or
  consumer rejects an action row whose class does not match this mapping.
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
digest of the ASCII prefix `dwm-titus-update-set-v1` followed by the exact
installable package-ID set sorted by unsigned UTF-8 bytes, with each ID encoded
as an eight-byte big-endian length followed by its raw bytes. The empty set has
a deterministic generation. List record IDs (`update`, `repository`, `account`,
and `filesystem`) must be unique within their record type. State and list-record
ownership is fixed as follows:

- `updates` owns `update-summary`, `update-last-refresh`, `update-restart`, and
  every `update` row.
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
`timezone`, `ntp`, and `locale`, `recovery` for `journal-repair`, and the
action's declared provider for `delegate`. Other terminal results do not
require an error row.
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
capped at 512 bytes, list records at 10,000 per snapshot, and the entire stream
at 8 MiB.

The initial actions are a closed enum: `updates-refresh`, `updates-install-all`,
`updates-cancel`, `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`,
`password-open`, `printers-open`, `sources-open`, `health-open`, and
`recovery-clear-journal-temporaries`. QML cannot select an executable, D-Bus
destination, interface, method, repository ID, package ID, user, unit, device,
path, or elevation mechanism.

## Operation Lifecycle and Audit

- Passive discovery uses the fixed maximum cache-age hint and never calls
  `RefreshCache` or starts an update; PackageKit may perform only backend work
  required to return discovery results as described above.
- Every mutation begins from a visible confirmation describing owner, impact,
  authorization, cancellation limit, and recovery.
- An install-all confirmation captures the snapshot generation and displays the
  exact installable package set represented by it. `UpdatesChanged` or any
  accepted replacement snapshot invalidates an open confirmation. After the
  user accepts, the provider performs a fresh bounded `GetUpdates(NONE)` using
  the discovery hints and recomputes the generation before creating a mutable
  transaction. A mismatch terminates as `failed`/`conflict`, publishes the new
  snapshot, and requires a new confirmation; only the revalidated exact
  installable IDs are passed to `UpdatePackages`.
- One root-scoped model owns every journaled operation. Refresh, update,
  regional, delegated, and health-open operations are mutually exclusive; a
  request received while any other operation is nonterminal is rejected as
  `failed`/`conflict` before it can replace the active record. The sole exception
  is journal-temporary repair when at least one validated fixed temporary path
  is already blocking journal persistence. It may run while a stranded active
  record remains nonterminal, uses a distinct collision-checked operation ID
  only in its bounded operation stream, and never replaces, adopts, cancels, or
  otherwise mutates that active record. The root model keeps the stranded
  operation visible while presenting repair progress separately, admits no
  other overlapping request, and reruns normal recovery immediately after the
  repair terminates. Journal repair remains exempt from writing a new journal
  record because journal persistence is the capability it restores.
- Closing Settings stops pane-only discovery but does not kill an active
  PackageKit transaction. Reopening reconstructs state from PackageKit and the
  private journal.
- Update cancellation is exposed exactly while PackageKit reports `AllowCancel`.
  Once cancellation becomes unsafe, Settings explains that the RPM transaction
  must finish.
- The journal lives under
  `${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/system-management/`, is mode
  0700, and contains mode-0600 journal files of at most 16 KiB each. The provider
  uses only the fixed `active` path and 32 fixed terminal slots named
  `terminal-00` through `terminal-31`; it never enumerates the directory. It
  reads those 33 paths through a directory file descriptor without following
  symlinks, validates ownership, type, mode, link count, and size, and reports
  an unsafe or malformed owned slot as a recovery error. Before accepting a new
  operation it requires a safe active path and at least one writable terminal
  slot. Terminal persistence replaces the missing or oldest valid slot by the
  required finished timestamp, so the fixed set retains up to the newest 32
  valid terminal records, limited by the number of safe slots. Atomic writes use
  one fixed temporary name beside each owned path and create it exclusively.
  Any existing temporary path is preserved unchanged, reported as a recovery
  error, and disables further system-management mutation other than the fixed
  recovery action. Settings offers the user-session action
  `recovery-clear-journal-temporaries`: it inspects only the 33 known temporary
  paths, previews their count and bounded hashes, requires explicit
  confirmation, then removes only regular files owned by the invoking user with
  mode 0600, link count one, and size at most 16 KiB. An unsafe temporary
  remains untouched with manual path-specific guidance. Because its purpose is
  to restore journal persistence, this repair is the sole operation exempt from
  writing the journal first; it still emits the normal operation and audit
  records and accepts no path or slot argument. Unrelated directory entries are
  never read, followed, or removed and cannot increase recovery work. The
  records contain common IDs, originating action IDs, timestamps, operation
  kinds, terminal results, and sanitized diagnostics, plus three fixed typed
  fields: update snapshot generation, PackageKit transaction object path, and
  aggregate restart requirement. An `update` record requires a valid generation,
  the exact PackageKit path, and a restart value from the protocol enum. A
  `refresh` record requires the exact PackageKit path and uses the literal `-`
  for generation and restart. `timezone`, `ntp`, `locale`, `journal-repair`, and
  `delegate` records require literal `-` in all three fields. A consumer rejects
  any missing field or value that does not match the operation kind. Each
  accepted `RequireRestart` signal durably
  replaces the active record with the newly validated aggregate before any
  later `Finished` signal is consumed; the terminal record carries that same
  aggregate. The durable action ID must have the fixed kind defined by the
  protocol and determines the owning provider used for recovered errors. The
  files never record passwords, environment dumps, repository credentials,
  package payloads, or unbounded output.
- Before any mutation other than the explicit journal-temporary repair above,
  the provider obtains the fixed service transaction or operation ID without
  invoking its mutating method, atomically writes and `fsync`s the pending
  journal record, and `fsync`s the journal directory. For
  PackageKit it calls `CreateTransaction`, persists the returned transaction
  object path, and only then invokes `RefreshCache(force=true)` or
  `UpdatePackages(ONLY_TRUSTED, ...)` on that transaction. Each later state and
  terminal result is atomically and durably replaced in order. Failure to
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
  For a nonterminal record, it attempts to adopt the exact recorded transaction
  object and consume its current or replayed result, then checks the active
  PackageKit transaction list. For an update transaction only, it finally
  calls PackageKit transaction method `GetOldTransactions(64)` on a new
  read-only transaction and consumes at most 64 emitted `Transaction` records.
  That signal supplies the old transaction object path, success flag, role, and
  UID used below; this is not the separate package-oriented
  `GetPackageHistory` method. PackageKit does not record `RefreshCache`
  transactions in old-transaction history. A history result is accepted only
  when its transaction object path exactly matches the journaled path, its role
  is `update-packages`, and its UID is the invoking user's UID.
  Exact active-transaction adoption seeds its restart aggregate from the
  validated nonterminal record, merges every accepted `RequireRestart` signal
  observed during adoption using the aggregation rule above, and durably
  persists that merged aggregate in the terminal record before reporting the
  adopted `Finished` result. Reaching `Finished` without a replayed restart
  signal therefore retains the validated prior aggregate. A valid durable
  terminal record written from `Finished` recovers its persisted restart
  aggregate. A missing or malformed restart field makes either path
  `interrupted`. An old-transaction history match with `succeeded=true`
  recovers only the terminal `succeeded` result and sets the restart aggregate
  to `unknown`, regardless of an earlier journal value, because history cannot
  replay a `RequireRestart` signal that may have been missed before persistence.
  It never substitutes or preserves `none` on that path. An exact history match
  with `succeeded=false` is still
  `interrupted`, because history cannot distinguish cancellation from another
  failure or reconstruct the required typed error row. Duplicate matches,
  malformed identity fields,
  another role or UID, and a success flag without the exact path are ambiguous
  and never consumed as this operation's result.

  A negative bounded lookup is never evidence that PackageKit succeeded or
  failed. If exact adoption or the active transaction list confirms that the
  exact transaction is still active, the provider keeps the operation
  nonterminal and continues consuming its signals through `Finished`. Only
  after that exact transaction is absent and the bounded terminal sources
  cannot recover a result does the provider record `interrupted` to mean that
  its observation was interrupted and the backend outcome is unknown. It
  performs a new read-only discovery and offers diagnostics; it never retries
  the refresh or update automatically. The UI states this ambiguity rather
  than describing the PackageKit transaction itself as failed. Recovery never
  expands to an unbounded history query. A regional operation recovers a
  terminal result only from a valid terminal journal record durably written
  before interruption. Any nonterminal `timezone`, `ntp`, or `locale` record
  becomes `interrupted` after restart regardless of the owning systemd
  service's current value, because the journal intentionally stores no target
  and current state cannot prove this operation caused it. Recovery publishes a
  fresh read-only regional snapshot and explains that the requested mutation's
  outcome is unknown; it never retries or audits it as successful. A delegated
  launch records whether the trusted tool was accepted; the tool owns later
  completion and recovery, and Settings never infers that its internal work
  succeeded.

## Event and Resource Contract

- PackageKit `UpdatesChanged`, `RepoListChanged`, transaction-list, property,
  progress, package, error, restart, and finished signals drive update state.
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
- Other system information, storage, and security probes run on open or
  explicit refresh. They add no idle timer.

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
guidance. Regional fixtures must prove fixed D-Bus destinations and methods.
Delegated-action tests must prove the executable allowlist and missing-tool
behavior. QML tests must prove readable state survives denial and every
section-owned process stops on close.

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
