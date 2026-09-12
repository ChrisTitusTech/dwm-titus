# Phase 8 Implementation Plan

Status: implementation and available VM qualification complete; Git publication and merge authorized.
Artifact publication remains a separate release step. This plan expands [ROADMAP.md](../ROADMAP.md) and
[TASKS.md](../TASKS.md); [SPEC.md](../SPEC.md) defines acceptance requirements.
Evidence is recorded in [P8-QUALIFICATION.md](P8-QUALIFICATION.md).

## Scope and chosen defaults

- Target Fedora 44 x86_64 dedicated images, standard and NVIDIA. Keep the
  official Fedora Server installer base and offline, interactive disk/user setup.
- New image accounts receive Starship, a prompt using the managed desktop
  palette, working Alacritty colors and Nerd Font, stable Brave Origin as browser,
  verified Herdr, and sxiv for supported image MIME types. Keep feh for wallpaper.
- Bash is the initial shell-integration target. Initialize Starship once in an
  interactive shell; leave noninteractive output and exit status unchanged.
  Do not replace user-owned startup files or existing prompt configuration.
- Herdr is installed by default in the images, but Super+X still opens Alacritty.
  Existing DWM_HERDR opt-in and explicit-command bypass behavior remain intact.
- Existing-system installs retain their profile/opt-in behavior. Upgrades must
  preserve shell customizations, browser profiles, MIME choices and user themes.
- Default boot skips the optional full-media test. It does not skip the liveimg
  payload checksum. Keep a selectable media-test entry and published hashes.
- New compression starts with `zstd -T0 -19`, subject to measured build resource
  use and actual Fedora installer compatibility. Continue accepting old xz input.

## Ordered implementation slices

Use a topic branch based on the verified current main for each review boundary,
with explicit dependency bases if any work is stacked. Do not merge or publish
without authorization for that workflow. No subagents are needed.

| Slice | Dependencies | Implementation surface | Required outcome |
| --- | --- | --- | --- |
| 8A Baseline and compatibility | None | Disposable VMs, pinned installer inspection, evidence | Reproduced failures, stage timings, package/format/network decisions |
| 8B.1 PackageKit | 8A | scripts/dwm-system-management, package contract, tests/test-system-management.py | A safe real update works as a normal desktop user |
| 8B.2 Terminal and Herdr | 8A | config/alacritty, new Starship config, Makefile user install, scripts/theme-apply.sh, scripts/install-herdr, scripts/image | Themed first terminal and offline Herdr, preserved custom user files |
| 8B.3 Browser and images | 8A | Shared packages/Kickstarts, scripts/dwm-default-apps, Settings Defaults, offline user setup | Brave Origin and sxiv installed, discoverable and default for new accounts |
| 8C Boot path | 8A | ISO builder GRUB transformation and tests | Regular install defaults on BIOS/UEFI, no offline network wait, optional media check |
| 8D Compression | 8A, 8C | Factory builder, liveimg template, manifests, ISO builder, validation | Real tar.zst installation with preserved metadata and measured improvement |
| 8E Combined qualification | All preceding slices | Final builds, clean VMs, docs, evidence | Both variants qualified, measured report and release candidates prepared |

Execute in table order so results are easy to attribute. Keep packaging changes
in the shared map and matching image profiles rather than duplicating lists.

## 8A decision record

Create `docs/P8-QUALIFICATION.md` when implementation begins. Record each decision
with observed command output/log paths, exact package versions and installer
version; do not turn assumptions below into claims without evidence.

| Question | Evidence to collect | Decision rule |
| --- | --- | --- |
| Why do PackageKit actions fail? | RPM NEVRA, D-Bus daemon version/owner/PID, installed/running executable identity, exact exception as a normal user | Distinguish inaccessible procfs, stale daemon, unsafe package and authorization failure before changing the gate |
| Which PackageKit can the image ship? | Current official Fedora 44 signed package availability and running version after clean boot | Prefer the supported fixed package satisfying the security floor; if unavailable, investigate secure backport identity rather than bypassing validation |
| Does inst.nonetwork work here? | Pinned Anaconda/dracut parser/source plus a boot with a present NIC but no DHCP server | Use it only if recognized and effective; otherwise use the supported installer-only mechanism and record it |
| Can liveimg extract tar.zst? | Actual Fedora installer archive detection, decompressor availability, small metadata fixture and full install | Enable zstd only after successful runtime extraction; resolve unsupported-format handling before changing defaults |
| What are the correct app packages and desktop IDs? | Official Brave Origin RPM metadata, Fedora Starship/sxiv metadata, installed desktop files | Use stable official packages and their real MIME/Exec identities; do not substitute another browser/viewer silently |
| How does Herdr survive capture? | Existing pinned installer/binary checksums, license/runtime files, installed command lookup after factory cleanup | Install the verified binary into shared image storage or seed it offline per user; fail capture when missing or unverifiable |

Baseline artifact names/hashes are recorded in
[COMPRESSED-QUALIFICATION.md](COMPRESSED-QUALIFICATION.md). Preserve the existing
R2 artifacts and use them as immutable comparisons. Inspect logs in full for
genuine failures; keep benign warnings separate from acceptance failures.

## Acceptance scenarios

### PackageKit

Reproduce the screenshot on a fresh unprivileged account: discovery can show
updates while refresh/install are blocked. After the fix, launch Settings,
refresh metadata, preview a signed update, confirm through polkit, complete the
transaction and verify installed RPM state plus restart guidance. Use a snapshot
or dedicated VM with an actual pending signed update; do not downgrade the host
or accept unsigned packages to manufacture a test.

Negative tests cover an unsafe package, unreadable/mismatched executable,
changed bus owner, stale daemon after package replacement, missing RPM bindings,
denied authorization and canceled confirmation. Unknown identity remains
blocked with a useful recovery instruction. Keep Settings unprivileged; a new
privileged identity mechanism, if necessary, needs its own threat/argument review
and the normal narrow-helper ownership/authorization tests.

### First terminal and Herdr

On a new account, Super+X shows the intended palette, readable Nerd Font glyphs
and Starship prompt. Opening a nested interactive shell does not duplicate init;
a noninteractive shell produces no prompt decoration. Change the managed theme
and verify terminal/prompt consistency. Exercise symlinked/custom XDG locations
and repeat installation without resetting user configuration. Herdr must launch
offline with its pinned version; explicit terminal command execution still works.
Check shell startup responsiveness so prompt work does not introduce visible lag.

### Brave Origin and sxiv

Launch Brave Origin from the application menu and the browser default action.
Check the installed package/desktop identity, first-run behavior and HTTP/HTTPS/
HTML associations; test a local page offline and a network URL after networking
is enabled. Do not embed a factory browser profile or suppress licensing/onboarding
with unsupported settings.

Open PNG and JPEG images with `xdg-open`; verify sxiv is selected and appears in
Settings Defaults. Test other MIME types only where sxiv advertises support.
Choose a different viewer/browser, repeat user setup and confirm the choice
survives. Verify feh still sets wallpaper and screenshot files open correctly.

### Boot and payload

Boot default and optional media-test entries under BIOS and UEFI. Confirm the
selected entry's actual kernel command line, local stage2/Kickstart/payload paths
and optional media verification. Test no NIC, disconnected link, link without
DHCP, and successful DHCP. Once installed, connect networking and prove it works
without undoing persistent installer-created disablement.

For zstd, retain the same tar content as the xz comparison, including ACLs,
xattrs, numeric owners and boot files. Test old xz compatibility, new zstd,
variant mismatch, malformed metadata, truncation, checksum mismatch, unsupported
compression and output preservation on failure. Verify unique machine identities,
factory-account removal, sanitized credentials and required feature manifests.

## Measurement protocol

Start with the previous qualification VM dimensions: 4 vCPUs, 6 GiB RAM, a fresh
50 GiB disk, virtio storage/graphics, and recorded firmware. Keep the same host,
CPU mode, storage cache policy and source image location across comparisons.
Record host load and whether caches are warm; use independent cold boots and
fresh target disks rather than cherry-picking warm results. Do not change host
cache/kernel settings just to create a benchmark.

Record timestamps for boot selection, optional media-check start/end, Anaconda
UI ready, Begin Installation, payload checksum start/end, extraction start/end,
post-install/bootloader completion, reboot and usable desktop. Record user-entry
pauses separately; report both automated time and observed wall-clock time.
If logs cannot separate overlapping stages, state that instead of adding their
times as though they were sequential.

Compare baseline, boot-only changes, same-content zstd and the final expanded
package image. Use at least three comparable runs per timed configuration and
report median plus minimum/maximum. Include archive/ISO bytes, uncompressed
bytes, compressor options/version, build duration and peak RAM. A larger final
package set must not be presented as the same-payload compression comparison.

An NVMe/USB 3.0 claim requires that actual hardware. VM results must be labeled
as such. The quoted 45-70 second total remains a stretch estimate. Acceptance
requires measured stage improvements, no unexplained overall regression and full
functional parity; do not claim a fixed decompression speed or total time.

## Validation commands and evidence

Run affected targets first through the managed test workspace:

```sh
scripts/run-tests make check-system-management check-quickshell-system-management
scripts/run-tests make check-terminal check-herdr-install check-appearance check-install-preservation
scripts/run-tests make check-default-apps check-quickshell-defaults-model
scripts/run-tests make check-kickstart check-fedora-iso-builder check-fedora-packages
```

These existing targets are starting gates, not substitutes for new meaningful
regression coverage or the real scenarios above. Run only applicable groups for
each slice. Apply ShellCheck/shfmt to changed shell files and syntax/appropriate
unit checks to changed Python. If QML changes, run configured QML lint and nested
Settings/runtime checks.

After integration, run:

```sh
scripts/run-tests make clean all
scripts/run-tests
npm --prefix docs ci
npm --prefix docs run build
git diff --check
```

Complete an independent local Codex review with recorded evidence; resolve valid
findings and rerun affected checks. Record commits, commands, exit codes, logs,
VM configuration, screenshots, package versions and exact artifact hashes in
`docs/P8-QUALIFICATION.md`. Keep detailed logs outside the checkout under a named
`$HOME/tmp` run directory; remove disposable VM disks after extracting evidence.
Never put credentials, .env contents, machine keys or browser profiles in evidence.

## Rollback and completion

- Keep user files backed up before any managed migration. A failed setup must
  preserve the previous shell, terminal and application defaults.
- Use guest snapshots/disposable disks for PackageKit and install tests. Preserve
  safety gates if a compatibility fix cannot establish trustworthy identity.
- Retain xz input and optional media-check paths. Keep current verified ISO bytes
  and R2 keys intact until new candidates pass all applicable tests.
- Prepare standard/NVIDIA ISOs, checksums, build and RPM/Flatpak manifests, package
  inventory and measured qualification notes. Use a distinct dated/versioned
  prefix; never overwrite the existing verified objects as an experiment.
- Before promoting future downloads, verify full uploaded/public-download hashes
  and range requests, then update release/README/install links together within
  the authorized publication workflow. Record physical NVIDIA, Secure Boot and
  suspend limits unless those paths have actually been tested.

Implementation and desktop checks are complete. Final performance/firmware
evidence is being recorded in P8-QUALIFICATION.md. Publication requires separate authorization.
