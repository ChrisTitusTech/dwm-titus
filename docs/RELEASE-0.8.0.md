# dwm-titus 0.8.0 release preparation

Status: source and candidate qualification prepared; no 0.8 tag, GitHub release or replacement
public image has been published by this workflow.

## Desktop changes

- Super+Tab opens the searchable window overview. Static thumbnails are
  captured once per opening, with icon/title fallback and cleanup on close.
- Appearance provides visual layout selection, master sizing and per-tag gaps.
- Optional floating-window titlebars provide move/close controls; defaults off.
- Optional Calendar and Weather widgets default off. Weather requests require
  an explicit location and Fetch; no automatic location lookup or refresh.

All four feature PRs (#425, #424, #423, #422) merged after local validation and
independent Codex review. The user verified the overview thumbnails in their
real X11 session. See CHANGELOG.md for the other changes since 0.7.2.

## Platform and Wi-Fi

Primary images: Fedora 45 Server Network Install 1.4, x86_64, separate standard
and NVIDIA variants. Fedora 44 existing-system and desktop compatibility remains
supported. No separate new Fedora 44 image set is planned.

Fedora 45 images use Thunar instead of Path, as the user selected after the
Fedora 45 COPR endpoint returned 404. That unavailable repository is omitted;
gaming packages use distribution/RPM Fusion sources. Fedora 44 retains its
COPR/Path availability. Thunar is the fresh-account default on both versions,
even with Path installed; existing user-selected MIME preferences are preserved.
Fedora 45 also omits the unavailable optional Numix and Deepin GTK theme RPMs;
Fedora 44 retains them. The shipped desktop theme palettes remain available.

Verified upstream source SHA-256:
`a1e916f139a05955b943cf183b020780cca9c399b02b8f5ec4354c9e5c1dff1a`.
Fedora 45 signing fingerprint:
`4F50A6114CD5C6976A7F1179655A4B02F577861E`.
The signed official checksum manifest and ISO digest were independently checked.

#368 is a release gate. Both images explicitly require NetworkManager-wifi,
wpa_supplicant and wireless-regdb. Capture checks the RPMs, Wi-Fi plugin and
libraries, supplicant and regulatory database, and records their versions.
Installed-VM qualification repeated these checks for both variants. Keep the issue open until both replacement
public downloads and their checksums are verified; old 0.7.2 downloads remain
unchanged by a source-only fix.

The factory also preserves Fedora-owned update/OpenH264 repository settings,
including signing keys. Keyless Anaconda overrides must not mask the Fedora 45
vendor definitions in `/usr/share/dnf5/repos.d`. Signature verification stays
enabled; a signed update transaction is part of qualification.

## Qualification record

Required source checks passed on Fedora 44 and 45 in explicitly recorded resumed
segments, including clean builds, ShellCheck/shfmt, configured QML lint, native and
nested X11 tests, backend/UI tests, dependency resolution, staged installs,
preservation checks and reproducible release archives. The updated Fedora 44 SDK
also passed a clean build, native X11 smoke test and staged installation. Managed
documentation builds passed. The release-preparation PR records the final reviewed
commit, commands and evidence paths.

Both clean Fedora 45 factory captures passed without manual repair. Their desktop
source is `ca437d0`; later source changes affect test SDKs, fixtures and documentation.
The final artifact manifest records the separate embedded checkout revision and
checksums. These are preparation candidates, not artifacts built from a published tag.

| Payload | Compressed bytes | SHA-256 |
| --- | ---: | --- |
| Standard | 2871769745 | `734cb674f5cbfa2d006a60ace12fe3fab1c0d0f6a6bcece6d2e3e4f0c4b2051a` |
| NVIDIA | 3577973812 | `94755563691146d9ecb6ac35050920a3f21e6f2d7b3510026d9bcb68819099eb` |

| Installed VM | Result |
| --- | --- |
| Standard, x86_64 UEFI | Offline Anaconda install, disk boot, LightDM, dwm and managed Quickshell passed. |
| Standard, x86_64 BIOS | Offline install, disk boot and the same desktop/Wi-Fi checks passed. |
| NVIDIA, x86_64 UEFI | Offline install and desktop/Wi-Fi checks passed with virtio graphics; this is not physical NVIDIA validation. |

VMs used QEMU/KVM, four vCPUs, 6 GiB RAM and fresh 50 GiB virtual disks. Automated
installs used the actual ISO kernel/initrd and public offline Kickstart with private
QA account/disk selections and a serial console. Installed disks booted through the
named firmware. No NIC was present during installation; first boot kept its link
down until explicitly enabled. All three installed systems had distinct machine IDs.
Anaconda 45.30 extracted the zstd payloads successfully. Compression ran alongside
other work; no controlled end-to-end install-speed comparison is claimed.
Recorded installer-process intervals were 413.87 seconds (standard UEFI), 340.53
seconds (standard BIOS) and 352.04 seconds (NVIDIA UEFI). They include startup,
payload checksum/extraction, post-install work and bootloader creation under shared
host load. Individual stage timings were not collected. The artifact timing record
contains the start/end timestamps; these values are not a firmware or variant comparison.

Separate probes booted the actual ISO through standard BIOS/UEFI and NVIDIA UEFI
to the branded Fedora 45 language-selection screen without disks or networking.
The BIOS menu visibly selected normal installation and retained media-check and
troubleshooting entries. This complements the automated complete-install tests.

Both variants contain NetworkManager/NetworkManager-wifi `1.58.1-3.fc45`,
wpa_supplicant `2.11-13.fc45` and wireless-regdb `2026.09.03-1.fc45`.
Their Wi-Fi plugin dependencies resolved, the supplicant executed and regulatory
data was readable. The guest kernel lacks mac80211_hwsim, so no simulated radio
association was tested. Package inventories accompany the prepared artifacts.

The standard UEFI fresh account exercised the themed Starship prompt, Brave
Origin, Herdr in Alacritty, Gear Lever offline, sxiv and Thunar. MIME discovery
reported `sxiv.desktop` and `thunar.desktop`. The overview displayed eight static
thumbnails. Screenshot shortcuts produced a 1280x800 screen JPEG, 600x400 region
JPEG and a 600x400 PNG clipboard readback. Closed Quickshell used 0.0% CPU
over a 20-second sample in that guest.

After explicitly enabling networking, NetworkManager obtained a DHCP address.
An interactive PackageKit refresh and update required confirmation and normal
authentication. PackageKit `1.4.0-2.fc45` checked signatures and upgraded actual
`less`/`less-color` packages from `704-4.fc45` to `710-2.fc45`. This exercised a real
transaction through pkcon; the Settings QML frontend stayed unprivileged.

Earlier attempts failed on the unavailable COPR and retired theme RPMs, then on
keyless Anaconda repository overrides. The corrected clean captures above supersede
those attempts. A manually repaired prototype is excluded from prepared deliverables.
Test evidence retains initial failures and interrupted runs separately from passing
reruns; the aggregate source gate is completed in resumed segments.

The artifact directory contains SHA256SUMS, BUILD-MANIFEST.json, package inventories
and selected qualification evidence. Public download links remain on 0.7.2 until a
separately authorized publication and full download verification replace them.

Physical NVIDIA acceleration, Secure Boot, physical radios, audio devices,
monitor hotplug and laptop suspend remain unqualified unless new evidence is
recorded. Virtual graphics and installed Wi-Fi packages do not prove those paths.
