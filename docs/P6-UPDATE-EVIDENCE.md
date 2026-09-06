# Phase 6 Update Backend Evidence

## Scope and Environment

On 2026-09-06, a disposable Fedora 44 x86_64 guest exercised the installed
`dwm-system-management` CLI against real PackageKit, DNF5, polkit, logind, and
the guest RPM database. This is an existing-system backend test, not qualification
of a released dwm image or the installed host desktop.

- Base repository: `66fb5356a7ad51232f49fcce7c0eb2045f71a04a` (PR #240).
- The first refresh/update exercised that base; the second update and action
  availability exercised the initial availability fix, provider SHA-256
  `e948be461166d68bbb51a7fe95f9466a39ed2eb92f4344451786ffde2c34753e`.
- Image: `Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2`, from the
  [official Fedora Cloud download](https://fedoraproject.org/cloud/download/).
- Image SHA-256:
  `28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f`.
- The signed `Fedora-Cloud-44-1.7-x86_64-CHECKSUM` verified with Fedora 44 key
  `36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`, matching both the installed Fedora
  key and the [published fingerprint](https://fedoraproject.org/security/).
- QEMU/KVM, BIOS boot, four virtual CPUs, 4 GiB RAM, 20 GiB disposable qcow2
  overlay. No host filesystem, RPM database, or service-bus mounts.
- User-mode networking exposed SSH only on host loopback. No host firewall,
  SSH-server, security-policy, package, or desktop changes were made.
- Guest: PackageKit `1.3.6-1.fc44`, libdnf5 `5.4.3.0-2.fc44`, polkit
  `127-2.fc44.2`; SELinux remained enforcing. No failed systemd units at exit.
- The default `fedora` SSH PAM session supplied real logind session evidence.
  One verified SSH ControlMaster served all subsequent commands.
- The provider was installed root-owned, mode 0755, at
  `/usr/local/bin/dwm-system-management`. Successful mutations used the guest's
  normal sudo authorization; unprivileged attempts exercised real denial.

## Fixture and Isolation

Guest-only prerequisite installation added PackageKit, Python GObject bindings,
RPM build/signing tools, createrepo_c, and polkit with their dependencies.
Original Fedora repository files were moved to a private guest backup before
the test. The sole test repository used `file:///var/lib/p6-fixture-repo`,
`gpgcheck=1`, and signed packages; no unsigned-install flag was used.
PackageKit was restarted after switching repositories so its cached Fedora
inventory did not become the selected update set.

Four inert noarch RPMs were built with rpmbuild and signed with an ephemeral
guest-only RSA key. They had no scriptlets, services, or executable payloads:

| Package | Relationship and payload |
| --- | --- |
| `p6-fixture-1-1` | Requires `p6-legacy = 1-1`; version file containing `1` |
| `p6-legacy-1-1` | Inert legacy component file |
| `p6-fixture-2-1` | Requires `p6-dependency = 1-1`; obsoletes `p6-legacy < 2`; version file `2` |
| `p6-dependency-1-1` | Inert dependency component file |

The initial guest installation contained only fixture version 1 and the legacy
component. The repository offered version 2 and the new dependency. A later
version 3, with the same dependency relationship as version 2, exercised stale
confirmation rejection and the patched availability path. Only the public
fixture signing key was imported into the guest RPM database; host trust was
not changed.

## Observed Results

1. Passive `snapshot` calls and dependency simulations did not install the
   fixture update. Recovery was `available`, with real boot/session evidence.
2. Before polkit was installed in the minimal cloud guest, explicit refresh
   ended `permission-denied`, exit 1, with matching audit and completion.
   `watch-operation` replayed that denial, and `snapshot` still returned the
   complete two-update/three-change inventory and exact terminal handoff.
3. After installing polkit, refresh
   `op-65a3d144364b1d6d549f3bb58d9aef19` succeeded at `06:00:39Z`, exit 0.
   Exact-ID replay and acknowledgment passed; refresh age became available.
4. The confirmed version-2 generation was
   `aebe93e61a90ef68bd038a078c3621ee03c3ea14c30aff136d4c064bb4213166`.
   The complete preview contained dependency install, fixture update, and
   legacy obsoletion. Update `op-f0bf80de649ea8083ca5076af1c46e3a` succeeded
   at `06:00:52Z`, with terminal, audit, completion, and exit 0. Actual observed
   counts were install=1, update=1, obsolete=1, unknown=0; comparison was
   `different=no`, mismatch-samples=0.
5. RPM queries and payload checks confirmed version 2, the new dependency,
   and removal of the legacy file. A separate provider process replayed the
   durable result. Acknowledgment removed the handoff, and discovery returned
   zero updates. Replay correctly did not claim to retain the in-memory
   package-comparison digest.
6. The patched unprivileged snapshot offered refresh and install for version 3,
   with generation
   `9ac2decf8325a6c7a22a6cf0f6d21a198d432eba7cb4ca082e3fff1d92f1cd89`.
   Reusing the older generation failed before admission with `conflict` and
   explicit fresh-preview guidance, exit 1.
7. Unprivileged SSH refresh and version-3 install attempts ended in real
   `permission-denied` results. No authentication agent was available for the
   remote session. Their exact results replayed, and readable discovery and
   recovery remained available. Origins stayed unavailable until acknowledgment.
8. Authorized version-3 update `op-4f25031885735364f7ff4cb3c383f92d` succeeded
   at `06:04:48Z`, exit 0, with update=1, unknown=0, `different=no`, and a
   matching audit. A fresh process replayed and acknowledged it. Final RPM
   state was `p6-fixture-3-1` plus `p6-dependency-1-1`, with no legacy file.
9. Final unprivileged discovery reported recovery/updates available, zero
   updates, refresh available, and install/cancel unavailable. No active
   operation or terminal handoff remained in either test user's journal.

The focused provider suite added seven availability tests, bringing it to 316
tests. The regression first failed against the old unconditional unavailable
actions, then passed with recovery/security/preview checks. Coverage includes
missing session evidence, active ownership, unacknowledged results, unsafe
backends, failed discovery, and failed/incomplete/unsupported simulations.
A subsequent malformed-inventory regression first failed, then proved both
origins unavailable. This additional fail-closed branch was fixture-tested; the
valid real-service paths above were not repeated after that narrow change.

## Restoration and Limits

The guest was powered off normally. The SSH master closed and the managed test
runner removed the exact guest workspace, overlay, base download, seed image,
private keys, and logs. No guest registration or background QEMU process remains.

This test did not exercise a graphical polkit prompt, real in-flight cancellation,
power loss, crash adoption, repository-network failures, hardware restart
requirements, or the installed host Settings workflow. Cancellation, interrupted
ownership, network/malformed responses, and UI closure/reopening remain covered
by the existing private-bus and nested-X11 fixtures, not by this guest run.
The tiny local transactions never supplied an observable cancelable interval.
Combined Phase 6 installed-file parity, real X11 acceptance, and the remaining
regional/information surfaces are still required before phase completion.
