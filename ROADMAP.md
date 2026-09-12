# Performance and Fresh-Install Roadmap

## Current scope

Phase 8: reduce offline ISO boot/install time and fix the fresh-install gaps
reported on 2026-09-11. Status: implementation and available VM qualification are complete.
See [measured results and hardware limits](docs/P8-QUALIFICATION.md). See the [implementation plan](docs/P8-IMPLEMENTATION-PLAN.md) for
ordered slices, decision rules, acceptance scenarios and rollback.

Phases 1-7 and compressed-image delivery are closed. Their roadmap is archived
in [COMPLETED-ROADMAP-20260911.md](docs/COMPLETED-ROADMAP-20260911.md); runtime
limits remain in [P7-QUALIFICATION.md](docs/P7-QUALIFICATION.md) and
[COMPRESSED-QUALIFICATION.md](docs/COMPRESSED-QUALIFICATION.md). PR #299 merged
at `5a511e2897e0f44554e60a87d674240f9a07854f`; CI, CodeQL and documentation
deployment passed. Closed work does not imply physical NVIDIA, Secure Boot or
suspend/resume qualification.

## Phase 8: Performance and a Complete First Login

The new images must install without network access, start a themed terminal,
include Brave Origin and Herdr, open images in sxiv, and permit safe PackageKit
updates on the supported Fedora package set. Standard and NVIDIA remain separate.
Existing user configuration and application choices must survive upgrades.

### 8A. Baseline and compatibility

Reproduce the user's first-login issues and record package versions and runtime
state on a clean installed system. Measure boot/media check, Anaconda startup,
payload checksum, extraction, bootloader/post-install, reboot and desktop-ready
separately. Compare the same machine/storage and filesystem contents; exclude
human interaction from automated timing and record it separately. Use at least
three runs per comparable baseline/candidate configuration and report medians
and ranges, not theoretical decompression rates.

Inspect the actual Fedora 44 installer runtime for supported network-disable
arguments and tar.zst extraction. The current Anaconda documentation does not
list `inst.nonetwork`; verify rather than append an unrecognized argument.

Exit: reproducible baseline, compatibility evidence, and concrete PackageKit
failure cause recorded. The proposed 45-70 second total is an unverified stretch
estimate, not an accepted benchmark or release promise.

### 8B. Fix fresh-install defaults and updates

- Ship Starship with a prompt matching the managed desktop palette, correct
  Alacritty theme/font and one interactive-shell initialization. Preserve
  existing shell startup files, custom prompts and themes on upgrades.
- Ship stable Brave Origin from the official signed Fedora RPM source, and
  seed it as the new account's web browser. Verify its actual desktop ID,
  first-run behavior and HTTP/HTTPS/HTML defaults.
- Include the verified Herdr binary and required runtime files in both images.
  Factory downloads happen at build time; first-login availability works offline.
  Alacritty remains the terminal binding and Herdr activation stays explicit.
- Install sxiv, expose it in Settings Defaults, and seed supported image MIME
  associations for new accounts. Keep feh for wallpaper and preserve user choices.
- Fix the PackageKit update-action block shown in the screenshot. Discovery
  succeeds but the running-backport identity check fails; diagnose as the actual
  desktop user. Prefer a supported fixed Fedora package satisfying the security
  floor. If a backport must be supported, design and review trustworthy running
  daemon verification. Do not remove the gate or run Settings as root.

Exit: fresh-account GUI and command checks pass, a real signed-package update
works with confirmation and polkit, rejection/recovery remain safe, and an
existing-account upgrade preserves custom settings.

### 8C. Faster offline boot

For compressed-image media, select install entry 0 rather than media-check
entry 1 in both BIOS and UEFI GRUB menus. Keep a clearly named optional
media-test entry with `rd.live.check`, embedded media checksum and published
SHA-256 checksums. Do not change the online factory/netinstall path accidentally.

Eliminate installer-only DHCP/network waits using arguments/configuration
proven to work with the pinned installer. Test with a disconnected NIC, link up
without DHCP, working DHCP, and no NIC. Local Kickstart/stage2/payload must remain
local; the installed system must retain normal NetworkManager behavior.

Exit: default entry reaches Anaconda without a full media scan or network wait;
optional media checking still works and first-boot networking is unaffected.

### 8D. Faster payload extraction

Make tar.zst the new output after confirming installer support. Start with the
requested `zstd -T0 -19`; measure build time, peak memory, archive/ISO size,
checksum time and end-to-end extraction on the supported test memory budget.
Retain xz input compatibility for existing archives and rollback. Update suffix
handling, archive detection, manifests, validation and documentation together.
Preserve numeric ownership, ACLs, xattrs, boot files, identity cleanup and dotenv
exclusion. Preserve the liveimg payload checksum.

Exit: real offline installation from zstd works on both variants, required
metadata survives, and measured extraction/total time improves under identical
conditions without an unexplained size or memory regression. If the pinned
installer cannot read zstd, resolve that compatibility boundary explicitly
before changing the released format.

### 8E. Combined qualification and release preparation

Rebuild both variants and repeat offline installation/first-login qualification:
standard UEFI and BIOS, NVIDIA UEFI with explicit physical-GPU limits. Exercise
terminal prompt/theme, Brave Origin, Herdr, sxiv/Defaults, all screenshot paths,
Gear Lever and real PackageKit refresh/update with networking enabled after
installation. Validate boot menu selection and the optional media test.

Publish a comparison of per-stage timings, machine/storage details, artifact
sizes, compression settings and package versions. Run focused checks, the full
repository suite, documentation build and independent review. Keep the current
verified Cloudflare objects as rollback; use new dated object names for any
future release. Artifact upload, link promotion and Git publication occur only
within their authorized implementation/release workflow.

## Boundaries

Implementation is authorized. Follow the ordered review boundaries above;
record validation before marking each slice complete. Git publication, artifact
upload and merge remain separate authorization boundaries. No parallel agent
work is required. Fedora/X11, user-data preservation, the
PackageKit security floor and the existing image SELinux policy remain intact.
