# dwm-titus 0.8.0 - Fedora 45

Release: https://github.com/ChrisTitusTech/dwm-titus/releases/tag/v0.8.0

Standard and NVIDIA images use Fedora 45 Server Network Install 1.4, x86_64.
Fedora 44 remains supported for existing-system installation and source updates.
Both images include NetworkManager-wifi, wpa_supplicant and wireless-regdb.
Fedora 45 uses Thunar and omits the unavailable COPR/Path and retired optional
Numix/Deepin GTK packages. Existing user application preferences are preserved.

## Desktop changes

- Super+Tab opens the searchable window overview. Static thumbnails are
  captured once per opening, with icon/title fallback and cleanup on close.
- Appearance provides visual layout selection, master sizing and per-tag gaps.
- Optional floating-window titlebars provide move/close controls; defaults off.
- Optional Calendar and Weather widgets default off. Weather requests require
  an explicit location and Fetch; no automatic location lookup or refresh.

Feature PRs #425, #424, #423 and #422 merged after local validation and
independent Codex review. The user verified overview thumbnails in a real X11
session. See CHANGELOG.md for the other changes since 0.7.2.

## Provenance and checksums

Qualified build source: `37115915c527b33f4a7786cf197f1c2d739cc214` (PR #427).
Merged release commit: `529e772c808927450080a7fd9fdbc22c113d253f`.
Both have the identical Git tree `1b01586ead1f20bcf7612181e5d93948486ea710`.
The qualified artifacts were retained unchanged after the merge; they were built
before tagging and are not represented as newly built from the tag.

| Image | Bytes | SHA-256 |
| --- | ---: | --- |
| dwm-titus.iso | 4,169,138,176 | `941d6a57915982d4c53f48d1f44a31d8b52faaa3db796f78359acd86f9630d7f` |
| dwm-titus-nvidia.iso | 4,875,681,792 | `133d8cb30666574c4248c734fb4855b221ceaa050f73482eeae01a24a008aee2` |

Download a fresh SHA256SUMS alongside the ISO and run
`sha256sum --ignore-missing -c SHA256SUMS`. Restart older partial downloads.
The manifest records all archive and payload hashes. Both complete public downloads matched these digests, matching metadata and
HTTP 206 byte-range responses. The [publication verification record](https://downloads.christitus.com/iso/PUBLICATION-VERIFICATION.json)
records the results. Merging PR #427 automatically closed #368; its public-media
gate is now verified.

Base ISO SHA-256:
`a1e916f139a05955b943cf183b020780cca9c399b02b8f5ec4354c9e5c1dff1a`.
Fedora 45 signing fingerprint:
`4F50A6114CD5C6976A7F1179655A4B02F577861E`.
The official signed checksum and the source ISO were independently verified.

## Validation

Fedora 45 passed the full managed source gate. Fedora 44 coverage completed in
explicit resumed segments, followed by final rebuilt-SDK package, build,
staged-install, preservation and native X11 checks. An overlong panel-popup IPC
path was fixed before the resumed run; the failed aggregate is retained as such.
ShellCheck/shfmt, configured QML lint, nested X11/UI/backend tests, dependency
resolution, installer preservation, reproducible archives and documentation
builds passed. Independent complete-diff Codex review passed at the build source;
all nine PR feedback threads were resolved and the PR was approved and merged.

The source archive matches all 1,132 tracked paths. The final runtime archive
was reproduced from a clean build; binaries/config/scripts/assets match, and
bytecode and object files are excluded. The first bytecode-contaminated trial
archive was discarded.

Both fresh payloads passed strict package, Wi-Fi plugin/library/regulatory-data,
signed-repository, asset and identity checks. Complete compressed/uncompressed
hashes, tracked source contents, symlink targets and ownership were independently
verified. Factory accounts, temporary sudo rules, machine/storage identity and
SSH host keys were removed. Two long launcher sessions returned 143 after
completed captures; those launchers are not claimed as passing aggregate factory
commands. Independent byte validation, final ISO/media checks and the three
complete installed-VM qualifications below passed.

| Installed VM | Offline install and first desktop | Installer-process interval | Closed Quickshell CPU / 20 s |
| --- | --- | ---: | ---: |
| Standard UEFI | Passed | 192.05 s | 0.05% |
| Standard BIOS | Passed | 209.92 s | 0.00% |
| NVIDIA UEFI, virtio graphics | Passed | 166.49 s | 0.00% |

KVM guests used four vCPUs, 6 GiB RAM and fresh 50 GiB disks. Installation had no
NIC, and disk first boot kept networking down until explicitly enabled. These
intervals reflect shared host load and are not controlled speed comparisons.
LightDM, dwm, managed Quickshell, embedded source copies, distinct machine IDs,
Wi-Fi contents and MIME defaults passed in all three systems. Both final CDs
booted to the branded v0.8.0 Fedora 45 installer; normal installation is the
default and media-check/troubleshooting entries remain available.

The standard UEFI fresh account exercised the themed Starship prompt, Brave
HTTPS browsing, Herdr, Gear Lever offline, sxiv, Thunar and nine static overview
cards. Screenshot hotkeys produced a 1280x800 JPEG, 600x400 JPEG and 600x400 PNG
clipboard readback. PackageKit checked signatures and upgraded actual less and
less-color packages from 704-4.fc45 to 710-2.fc45 after user confirmation. Fedora's
normal active-session policy authorized the update without a password prompt;
no authorization policy changed. A prior confirmation left pending past the
daemon idle timeout did not upgrade and was rejected by version/signature checks.

## Hardware limits

Physical NVIDIA acceleration, Wi-Fi radio association, Secure Boot, physical
audio, monitor hotplug and laptop suspend remain unqualified. NVIDIA VM testing
used virtio graphics without a physical GPU; nvidia-persistenced failed in that
VM and does not constitute a physical driver pass. Installed Wi-Fi packages do
not prove radio association. The live host desktop was not redeployed for QA.
