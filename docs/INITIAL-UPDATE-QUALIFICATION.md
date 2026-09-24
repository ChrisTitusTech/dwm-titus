# Fedora 0.7.2 qualification

Validation date: 2026-09-24. This is PR evidence, not a release announcement.

## Environment and image

- Fedora 44 x86_64 host and disposable Fedora 44 Docker container.
- Standard image: QEMU/KVM, q35, OVMF UEFI, four vCPUs, 6 GiB RAM, Virtio GPU,
  and a new 50 GiB virtual disk. The test used a dedicated account, SSH key and
  autologin inside the disposable guest; these were not added to the image.
- Base: Fedora Server Network Install 44-1.7, SHA-256
  `ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`.
- Candidate root filesystem: tar.zst, 2,718,625,579 bytes, SHA-256
  `634607b633b71a01e2fa5575a167d041849696dc1188e16477991dce641fc615`.
- Both Kickstarts passed ksvalidator and repository invariants. The standard
  factory completed package installation, capture checks and identity cleanup.
  All 12 enabled repositories retained package signature verification.
- The capture preceded the two helper-only review fixes. The reviewed root
  helper was installed into the fresh guest before transaction qualification;
  no release image was published. Release images must be rebuilt from the
  final merged revision.

## Local and container checks

These commands passed through the managed test workspace:

```sh
scripts/run-tests make clean all
scripts/run-tests
scripts/run-tests make check-initial-update
scripts/run-tests make check-kickstart
scripts/run-tests make check-fedora-packages
scripts/run-tests make check-install-manifest
scripts/run-tests make check-session-guards
scripts/run-tests make check-shell check-format
```

The first full-suite attempt encountered an unchanged Picom startup race. Its
focused retry and the subsequent complete suite passed. The full suite included
689 system-management backend tests, the existing QML/X11 matrices, staged
installation and release-archive validation. Focused tests were repeated after
helper fixes; unchanged full-suite evidence was reused.

The Fedora package map resolved 103 packages. A clean Fedora container built
and staged the desktop and both new helpers, resolved fastfetch and
python3-libdnf5, and ran fastfetch successfully. Disposable-container tests
verified:

- Signed fixture RPM upgrades through both `dnf update` and `dnf upgrade`:
  Enter accepted and No cancelled.
- The installed root helper rejected a repository copy, failed for disabled or
  inaccessible repositories without recording success, retried successfully,
  and skipped subsequent completed runs.
- Lock contention and cancellation left no completion marker. A signed upgrade
  retry recorded success. An explicit administrator `defaultyes=False`
  override made Enter cancel even through the initial-update helper.
- An unprivileged probe accessed real repository metadata through an HTTP
  proxy requiring authentication, using DNF's configured credentials.
- The actual GTK/D-Bus/X11 offer remained hidden offline, responded to a
  NetworkManager signal plus a successful repository probe, launched only
  after confirmation, and stayed hidden after completion.

ShellCheck, shfmt, installed-path checks and `git diff --check` passed. The
documentation build passed with `npm --prefix docs ci` followed by
`npm --prefix docs run build` in a managed temporary copy. Real
DNF5 accepted the generated local metalink after preserving its default XML
namespace. The new unit suite has 19 cases in addition to the GTK test.

## Fresh installation and first update

Anaconda completed the compressed installation with `-nic none` in about
215 seconds. The installed system booted into LightDM/dwm and the managed
Quickshell session without Internet access. A fresh account ran fastfetch
2.60.0 successfully. The pending marker existed, completion did not, and no
update offer appeared while repository access failed.

The guest used a restricted test-management NIC and a separate initially
link-down Internet NIC. Enabling the Internet NIC without restarting the
session produced the update offer and the normal polkit authentication dialog.

A deliberately unavailable test repository caused visible DNF metadata errors.
The updater retried the original mirror defaults, reported failure, and left
completion unrecorded. Removing that test repository and retrying from the
terminal reached DNF's real `[Y/n]` transaction confirmation: 65 installs and
599 upgrades, with about 1 GiB to download. Enter accepted the transaction.

The real transaction completed and wrote its persistent completion marker. The
terminal displayed restart guidance and waited for Enter; the machine did not
reboot automatically. After a manual reboot, the identical completion marker
remained, LightDM/dwm and the managed Quickshell session started, fastfetch
2.68.1 ran, and the watcher exited without offering another update. DNF history
confirmed the completed transaction.

The second VM measurement run recorded these short metadata-download samples:

| Repository | Baseline KiB/s | Best measured KiB/s |
| --- | ---: | ---: |
| fedora | 2196 | 2763 |
| updates | 3264 | 4118 |
| rpmfusion-free | 557 | 596 |
| rpmfusion-free-updates | 303 | 335 |
| rpmfusion-nonfree | 328 | 486 |
| rpmfusion-nonfree-updates | 242 | 242 |

Changes below 10% retained defaults. Fixed endpoints and insufficient samples
also retained defaults. These are measured metadata samples on this network,
not sustained package-download guarantees or results for other locations.

## Review and limits

CodeRabbit reported one minor issue: preserving an administrator's prompt
choice. It was fixed and verified with a real signed-RPM override case. The
first local Codex review found one transport-probe issue; the native DNF probe
and authenticated-proxy test addressed it. A complete follow-up Codex review
reported no actionable defects.

Not tested: NVIDIA image runtime or physical NVIDIA hardware, BIOS installation,
Secure Boot, another geographic network, real client-certificate authentication,
and power loss during an RPM transaction. A failed repository and retry were
exercised in the VM; signed cancellation/contention and proxy transport were
exercised in disposable Fedora containers. No host installation, merge, tag or
release publication was performed.

## Hosted feedback follow-up

The hosted reviews identified fallback-probe suppression, DNF defaults remaining
after uninstall, and mirror ranking that did not use the recorded latency.
The fixes try three distinct probe endpoints within the shared deadline, track
ownership of installed DNF defaults, and compare a fixed 1 MiB transfer estimate
using TCP connection time and measured payload throughput. Payload timing excludes
connection setup; a 10% estimated-time reduction is required to reorder mirrors.
The original VM measurement table above predates this ranking refinement.

The expanded tests cover unavailable first mirrors, deadline exhaustion,
high-latency candidates, the noise band, payload timing, and seven lifecycle
cases including staged `make uninstall` and administrator replacements. A fresh
live measurement run completed against six Fedora/RPM Fusion repositories.
The user-requested independent skeptic reviewed the complete PR and follow-up
changes with no actionable defects. Earlier signed transaction and standard VM
failure/retry/reboot evidence is reused for unchanged transaction and session
behavior; image artifacts must still be rebuilt from the final merged revision.

The final Codex pass also found non-HTTPS ordinary repositories were excluded
from connectivity probing. HTTP/file sources now use the same bounded native
DNF path as custom transports. All 26 updater unit cases and the GTK test passed;
a clean Fedora 44 container proved both authenticated proxy access and an
ordinary file repository as the unprivileged `nobody` user.

The skeptic also verified mixed HTTPS/HTTP mirror lists: failed HTTPS checks
and discovery now fall back to native DNF within the same deadline, allowing
DNF to use reachable endpoints excluded from mirror measurement.

A subsequent hosted pass identified repository-budget starvation, a trust test
that depended on checkout ownership, the lifecycle helper's elevation path,
and partial-write cleanup. The final fixes share remaining probe time across
repositories, use an explicitly writable trust fixture, invoke the installed
root-owned lifecycle helper, and stage/fsync/close complete files before
no-clobber publication. Tests cover write, close, fsync, ownership-publication
failures, and relative DESTDIR installation/removal. The suite now has 27
updater cases and 13 defaults lifecycle cases.

The additional complete `scripts/run-tests` run passed, including all 689
system-management backend tests, the complete QML/X11 matrix, install
preservation, and release-archive validation. Changed installation and probe
checks were repeated afterward; unchanged full-suite coverage was reused.
The final independent skeptic review reported no actionable findings.
