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
Update inventory always calls `GetUpdates` with PackageKit's `NONE` filter so
the confirmed install-all action operates on the complete unfiltered snapshot.
The explicit Refresh action calls `RefreshCache` with `force=true`; passive
discovery never calls it.

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

### Regional State

`org.freedesktop.timedate1` and `org.freedesktop.locale1` are the stable systemd
D-Bus owners. Settings reads their properties directly and invokes only the
fixed `SetTimezone`, `SetNTP`, or `SetLocale` methods after confirmation. The
interactive-authorization argument remains enabled so systemd and polkit own
the decision. Arbitrary environment variables, keymaps, NTP servers, RTC mode,
or manual timestamps are not accepted.

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
bounded subset. Account creation, deletion, group membership, and administrator
changes remain in the Fedora-packaged `lxqt-admin-user` tool. The current user's
password action opens the fixed `passwd` program in the configured terminal
without transporting a password through QML.

CUPS remains the printer service. Phase 6 reports service/tool availability and
opens Fedora's `system-config-printer`; it does not reproduce printer discovery,
driver, queue, job, or authentication policy.

PackageKit supplies read-only repository records. Repository changes remain in
the Fedora-packaged `dnfdragora` tool when present. Missing optional delegated
tools are reported individually and never hide readable service state.

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
  allowlisted `SELINUX` key in `/etc/selinux/config`; the exact value `disabled`
  is `available`/`disabled`, while `enforcing` or `permissive` without the
  runtime interface is inconsistent and therefore `partial`/`unknown`. If
  neither source establishes state, the result is `unsupported`/`unknown`.
  Read denial is `restricted`/`unknown`; malformed accessible data is
  `partial`/`unknown`. Neither is silently treated as disabled.
- Secure Boot comes from the EFI `SecureBoot-*` variable under
  `/sys/firmware/efi/efivars/`. Its attributes prefix is skipped and the one-byte
  payload must be `0` or `1`; `1` is `available`/`enabled` and `0` is
  `available`/`disabled`. An absent EFI variables filesystem is
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
  `restricted`/`unknown`.
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

```text
system-management-protocol<TAB>1<TAB>0
provider<TAB>id<TAB>status<TAB>class<TAB>owner<TAB>detail
state<TAB>id<TAB>status<TAB>value<TAB>detail
update<TAB>package-id<TAB>severity<TAB>installable|blocked<TAB>name<TAB>version<TAB>summary
repository<TAB>id<TAB>enabled|disabled<TAB>description
account<TAB>object-path<TAB>current|other<TAB>display-name<TAB>login-name
filesystem<TAB>mount-id<TAB>status<TAB>source<TAB>target<TAB>fstype<TAB>size-bytes<TAB>used-bytes<TAB>available-bytes<TAB>detail
action<TAB>id<TAB>available|unavailable<TAB>class<TAB>owner<TAB>label<TAB>detail
operation<TAB>id<TAB>kind<TAB>state<TAB>percent<TAB>cancelable<TAB>detail
audit<TAB>id<TAB>kind<TAB>result<TAB>started<TAB>finished<TAB>detail
error<TAB>capability<TAB>code<TAB>detail
complete<TAB>snapshot|operation
```

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
  use the `unsupported` status.
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
  Security Status. PackageKit `RestartEnum.APPLICATION` maps to `application`.
- Update severity is `critical`, `security`, `important`, `bugfix`,
  `enhancement`, `normal`, `low`, or `unknown`. Update installability is
  `installable` or `blocked`; blocked package IDs are never passed to
  `UpdatePackages`. Repository state is `enabled` or `disabled`. Account scope
  is `current` or `other`. Filesystem status uses the provider-status enum;
  mount ID is an unsigned decimal integer and the unique record ID within the
  snapshot, while source and target remain display-only text. `available`
  requires all three byte fields to be unsigned decimal integers; `partial`
  permits a mix of integers and `unknown`; `restricted`, `unavailable`, or
  `unsupported` requires all three byte fields to be `unknown`.
- Operation kind is `refresh`, `update`, `timezone`, `ntp`, `locale`, or
  `delegate`. Operation state is `pending`, `authorizing`, `running`,
  `cancel-requested`, `permission-denied`, `canceled`, `failed`, `interrupted`,
  or `succeeded`. Percent is `unknown` or an integer from 0 through 100, and
  cancelable is `yes` or `no`. Audit result uses only the terminal operation
  states.
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

A snapshot emits exactly one provider row for every provider ID, exactly one
row for every action ID, exactly one `filesystem-summary` state, zero or one of
every other singleton state ID, then one `complete<TAB>snapshot`. List record IDs
(`update`, `repository`, `account`, and `filesystem`) must be unique within their
record type. An operation stream emits exactly one operation ID, exactly one
audit row after the terminal operation record, and then one
`complete<TAB>operation`. The audit ID and kind must match the operation, its
result must match the terminal state, and no duplicate audit row is accepted.
The first operation record must be `pending`; consumers reject any other
initial state. Audit timestamps are canonical UTC RFC 3339 whole seconds in the
exact `YYYY-MM-DDTHH:MM:SSZ` form. `started` must be no later than `finished`,
and both are required on the terminal audit row.

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
operation-ID mismatch, transition outside the table, an operation record after
a terminal state, any record after the required completion, or missing
completion rejects the entire stream. Operation and audit record failures
always reject the operation stream. Text fields are capped at 512 bytes, list
records at 10,000 per snapshot, and the entire stream at 8 MiB.

The initial actions are a closed enum: `updates-refresh`, `updates-install-all`,
`updates-cancel`, `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`,
`password-open`, `printers-open`, `sources-open`, and `health-open`. QML cannot
select an executable, D-Bus destination, interface, method, repository ID,
package ID, user, unit, device, path, or elevation mechanism.

## Operation Lifecycle and Audit

- Passive discovery never refreshes metadata or starts an update.
- Every mutation begins from a visible confirmation describing owner, impact,
  authorization, cancellation limit, and recovery.
- One root-scoped model owns update and regional operations. Overlap is rejected.
- Closing Settings stops pane-only discovery but does not kill an active
  PackageKit transaction. Reopening reconstructs state from PackageKit and the
  private journal.
- Update cancellation is exposed exactly while PackageKit reports `AllowCancel`.
  Once cancellation becomes unsafe, Settings explains that the RPM transaction
  must finish.
- The journal lives under
  `${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/system-management/`, is mode
  0700, and contains bounded mode-0600 journal files. The files record IDs,
  timestamps, operation kinds, terminal results, and sanitized diagnostics. They
  never record passwords, environment dumps, repository credentials, package
  payloads, or unbounded output.
- Before any mutation, the provider obtains the fixed service transaction or
  operation ID without invoking its mutating method, atomically writes and
  `fsync`s the pending journal record, and `fsync`s the journal directory. For
  PackageKit it calls `CreateTransaction`, persists the returned transaction
  object path, and only then invokes `RefreshCache(force=true)` or
  `UpdatePackages(ONLY_TRUSTED, ...)` on that transaction. Each later state and
  terminal result is atomically and durably replaced in order. Failure to
  create or persist the record prevents the mutation from starting.
- A PackageKit-backed `refresh` or `update` operation in any nonterminal state
  that lacks a terminal PackageKit result is `interrupted`, not successful.
  The transition table permits this recovery result before and after the
  operation begins running. Recovery first checks PackageKit activity/history,
  then directs the user to retry discovery or open System Health. Regional
  operations use the terminal result and current state from systemd's owning
  service. A delegated launch records whether the trusted tool was accepted;
  the tool owns later completion and recovery, and Settings never infers that
  its internal work succeeded.

## Event and Resource Contract

- PackageKit `UpdatesChanged`, `RepoListChanged`, transaction-list, property,
  progress, package, error, restart, and finished signals drive update state.
- systemd D-Bus property changes drive time and locale refresh while the System
  section is open. Because timedate1 marks `NTPSynchronized` and `CanNTP` as not
  emitting change signals, one non-overlapping bounded read of only those
  properties runs every 30 seconds while the section is open and immediately
  after an NTP action. The fallback stops on section close. A bounded snapshot
  remains available without a monitor.
- AccountsService user-added, user-deleted, and property signals may refresh
  the account summary only while the section is open.
- CUPS and delegated-tool availability are bounded snapshots. Phase 6 adds no
  CUPS polling loop.
- System information, storage, and security probes run on open or explicit
  refresh. They add no idle timer.

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
