# Phase 8 Qualification

Implementation began 2026-09-11 from main `5a511e2897e0f44554e60a87d674240f9a07854f`.
Implementation, repeated performance measurements and available VM qualification
are complete. This report records pre-publication qualification; Git publication
and merge were subsequently authorized. Candidate ISOs remain local.
Local evidence is under `/home/titus/tmp/dwm-p8-20260911/evidence`.

## Environment and immutable baseline

Fedora Server netinst 44-1.7, x86_64, source SHA-256:
`ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`.
Pinned runtime: Anaconda 44.30, GNU tar 1.35, zstd available.
VMs use KVM, Q35, 4 vCPU, 6 GiB RAM, 50 GiB virtio disks and virtio graphics.
UEFI uses OVMF; BIOS uses SeaBIOS. Host: Intel Xeon w5-3435X (16 cores/32
threads), 62 GiB usable RAM, SPCC M.2 PCIe SSD with artifacts/disks on /home.
A separate user VM remains running and untouched. These are VM/NVMe observations,
not USB 3.0 or physical GPU benchmarks.

PR #299 assets remain unchanged at the existing R2 URLs. Standard ISO:
3,635,675,136 bytes, SHA-256
`fe8340bb9ce6a1731e21f88e39efe9ec72d3593d1e797817a96a4d316f8d7763`.
NVIDIA ISO: 4,252,237,824 bytes, SHA-256
`cedd84e952e2b96e713d211e95530fdc6960dd7a1a15d170231f3c8585f59e5e`.
See [original qualification](COMPRESSED-QUALIFICATION.md) for rollback links.

## PackageKit and first-login behavior

The original image shipped PackageKit 1.3.4-3.fc44. As the fresh normal user,
/proc/PID/exe raised PermissionError; this reproduced the screenshot's blocked
backport identity check. The check was correct and has not been weakened.
Both new images ship PackageKit 1.3.6-1.fc44 and libdnf5 5.4.4.0-1.fc44 from
official Fedora repositories. Capture requires an unambiguous epoch-0 PackageKit
>= 1.3.5. Recovery text explains DNF update/reboot when identity is unreadable.

Real Settings tests: metadata refresh, canceled confirmation, temporary polkit
denial with readable discovery preserved, and a signed btop update all passed.
The temporary denial rule was removed. An old-image 638-change upgrade initially
reported a libdnf5 Base::setup assertion after installing packages; restarting
PackageKit restored discovery. This old-image transition is retained as a failed
observation, not silently counted as success. With the newer libdnf5 already
present in the new image, a full 632-change update through Settings succeeded in
166.220 seconds, followed by successful discovery with no remaining updates.
`standard-full-update.txt` records the transaction and RPM versions; pkcon's
exit 5 is its no-updates result. No automatic privileged daemon restart was added.

Standard installed desktop checks passed:

- Starship 1.26.0 appears in the first Alacritty terminal and nested Bash.
  Changing to Dracula updates the terminal/prompt palette. Meslo Nerd Font is
  selected. Custom/symlinked startup files and MIME choices pass preservation tests.
- Brave Origin 1.95.101-1 is the fresh-account HTTP/HTTPS/HTML default. Its normal
  Linux first-run screen is retained. A local HTML page and a network URL open.
- Herdr 0.7.5 launches in Alacritty with the NIC disconnected. Launching a TUI
  without a terminal was an invalid initial harness attempt, not an image defect.
  The binary, license and matching source are bundled. Super+X remains Alacritty.
- sxiv 26-15.fc44 opens JPEG and PNG by default and appears as active in Settings.
  The package's desktop entry is made discoverable; feh still manages wallpaper.
- maim 5.8.1 full capture (1280x800 JPEG), region capture (301x201 JPEG) and
  clipboard capture (301x251 PNG) passed. xclip and selection dependencies work.
- Gear Lever launches successfully with its system Flatpak runtimes; AppImage
  MIME is seeded. Final BIOS evidence `bios-final-apps2.png` shows Gear Lever
  beside Brave Origin rendering https://example.com after normal onboarding.
- Installed NetworkManager obtains DHCP automatically. Installer-only flags do
  not appear in target /proc/cmdline; wait-online remains enabled on the target.
- Unique machine identity and generated SSH host keys are present. No source .env
  is embedded. The test SSH key was injected into the disposable guest only.
- Managed Quickshell with Settings closed used 0.10% CPU over a 10-second sample.

NVIDIA UEFI installation and first login passed using virtio graphics. Package
checks confirm akmod-nvidia 610.57.04-1.fc44 and the same new desktop tools.
This does not qualify a physical NVIDIA GPU, Secure Boot or suspend/resume.

## Offline boot and zstd compatibility

`inst.nonetwork` is absent from the pinned parser/docs. `ip=none` is recognized
by nm-initrd-generator but alone still allows no-NIC waits in
nm-wait-online-initrd.service (3600-second limit) and the runtime
NetworkManager-wait-online.service. Final offline-only arguments are:

```text
ip=none systemd.mask=NetworkManager-wait-online.service rd.systemd.mask=nm-wait-online-initrd.service
```

The runtime masks affect only that boot. They are added after target bootloader
arguments are rendered; factory networking remains unchanged. All four real
functional cases reached the GUI: NIC absent, link disconnected, link up without
DHCP, and working DHCP. Runtime service state was masked-runtime with no pending
jobs. These parallel functional runs are not timing benchmarks. Earlier ip-only
runs that eventually reached the GUI do not establish absence of startup waits.

Real BIOS and UEFI GRUB menus select entry 0 and retain media-check entry 1.
NVIDIA menu boot preserves nouveau blacklists and nvidia-drm.modeset. Embedded
media checks pass for both candidate ISOs. Payload SHA-256 checking remains on.

Anaconda's is_tar suffix check rejects .tar.zst. The builder therefore stores
the payload as /images/dwm-rootfs.tar while artifacts retain .tar.zst. Runtime
GNU tar detects compression by content. A pinned-runtime fixture preserved
numeric ownership, ACL UID 12345 and user.dwm-test xattr; actual standard and
NVIDIA offline installs subsequently passed. Protocol-2 manifests record raw
archive size/hash and compression arguments. Full-stream validation rejects
corruption/truncation, wrong variants and mismatched compression, preserving the
previous output. Legacy xz/protocol-1 inputs remain supported; old captures skip
new account seeders they do not contain.

## Capture resources and candidates

Both captures use zstd -T0 -19. Standard raw tar: 8,094,760,960 bytes; compressed:
2,651,739,746 bytes. Compression wall time 209.93 seconds, peak RSS 2,488,780 KiB.
NVIDIA raw tar: 10,193,745,920 bytes; compressed: 3,293,414,707 bytes. Compression
wall time 279.88 seconds, peak RSS 2,495,372 KiB. Other qualification workloads
were active, so these are observed build costs rather than isolated benchmarks.

Standard candidate ISO: 3,901,816,832 bytes, SHA-256
`6f7db6fd52195e9e18c4c5285a1cdbc8926d324523499b5aaec121bb7ea9d9c0`.
NVIDIA candidate ISO: 4,543,479,808 bytes, SHA-256
`24137139f7eac60b26f0e9590a706b73291fdc7ecc376261f2e4d622b139f531`.
Files are `artifacts/dwm-titus-{standard,nvidia}-p8-rc2.iso` in the evidence
workspace's parent directory. Earlier p8/p8-final/rc prototypes are not release candidates. Portable
SHA256SUMS, ISO JSON manifests and RPM/Flatpak inventories accompany RC2. New packages and refreshed libraries contribute to the size change;
compression comparisons use identical tar data separately. Anaconda scans the
archive with Python tarfile.getnames() to discover kernels after verifying the
checksum, then invokes GNU tar for extraction. Measurements separate that scan
from extraction; attributing their combined time only to disk unpacking would
be misleading.

An initial factory attempt failed because Anaconda chroot PATH omitted
/usr/local/bin. Explicit PATH fixed it; both subsequent factory captures passed.
A missing GNU time preflight also failed cleanly before building; the official
host package was installed and its command verified. Factory logs are retained.

## Repeated installation measurements

Three alternating old/new runs used fresh disks, the same 4-vCPU/6-GiB UEFI VM,
no NIC, the pinned installer kernel/initrd and an external automatic disk/account
Kickstart. Old runs enabled rd.live.check; new runs used the final offline flags.
All six installed and powered off successfully. No factory, compression, desktop
test VM or full regression workload ran concurrently. The unrelated user VM and
normal host applications remained active; host load was recorded. Host caches
were not flushed. This is a small VM/NVMe sample, not a physical USB benchmark.

The total is VM start to completed installer power-off. It excludes GRUB's
countdown, human disk/account entry and the installed-system first login. Stage
values use guest monotonic journal timestamps. Media check is a subset of
startup; stage medians should not be added to reconstruct the total.

| Stage (seconds, median [min-max]) | PR #299 xz | Phase 8 zstd |
| --- | ---: | ---: |
| VM start to installer power-off | 268.15 [261.35-278.82] | 204.61 [203.30-208.47] |
| Kernel boot to install queue, including media check | 54.50 [51.46-59.97] | 44.13 [43.38-48.34] |
| Optional media check only | 7.66 [7.14-9.90] | 0.00 [0.00-0.00] |
| Storage setup before payload | 7.90 [6.88-8.01] | 7.81 [7.26-10.05] |
| Payload SHA-256 | 6.10 [5.56-6.11] | 7.01 [6.66-7.80] |
| Kernel discovery archive scan | 67.58 [67.56-73.00] | 18.01 [17.92-18.79] |
| GNU tar extraction | 24.15 [23.99-24.28] | 18.14 [17.99-18.23] |
| After extraction through power-off | 105.70 [104.22-106.53] | 106.50 [105.78-108.17] |

Total median improved from 268.15 to 204.61 seconds: 63.55 seconds (23.7%).
The archive scan accounts for most of the saving. Bootloader/BLS setup and
initramfs/rescue generation remain the dominant unchanged cost after extraction.
These data do not support the earlier 45-70 second total estimate.

Measured standard RC SHA-256:
`3a21906a26d837472d6512af794d7ee83a05633b1387a428ec0e48d78a4591f6`.
The measured RC and final RC2 differ only in conservative startup-file
preservation (custom login files/.bashrc.d). Fresh accounts have stock profiles
and no fragments, so their defaults and benchmark paths are unchanged. The
additional guard passed focused interactive and root-container-style tests and
independent review. RC2 passed separate full standard BIOS, standard UEFI and
NVIDIA UEFI offline installations. Both final UEFI first logins verified the
new prompt, package versions, MIME defaults and automatic DHCP. Their target
kernel arguments contain no installer network masks. A final BIOS first login showed the new prompt and
automatic DHCP. Systemd reported 7.154 seconds kernel+initrd+userspace; the old
UEFI baseline reported 9.185 seconds. These single observations occurred during
parallel functional qualification and exclude firmware/GRUB and manual login;
they are not a controlled boot-speed comparison or added to the install medians.

## Identical-tar compression comparison

Both codecs contain the same 7,598,796,800-byte tar, raw SHA-256
`5ceb960e87824c527f5964eab156e9d5e36fd746354c0c9a29d3ba01f1608859`. Re-decoding zstd reproduced that digest. XZ occupies
2,385,740,288 bytes; zstd -T0 -19 occupies 2,481,735,169 bytes
(4.02% larger). Recompression took 194.09 seconds and 2,481,064 KiB peak RSS
while functional qualification workloads were active.

Three alternating decode-to-/dev/null runs used CPU affinity 0-3. XZ 5.8.2
used explicit -T4; zstd 1.5.7 used its normal decoder. No XZ_DEFAULTS, XZ_OPT
or ZSTD_NBTHREADS overrides were set. XZ median: 14.83 seconds [14.70-15.65];
zstd median: 6.94 seconds [6.80-7.02]. The latter is about 1.09 GB/s of raw tar.
This host-only throughput measurement excludes filesystem extraction and is not
substituted for the real installation timings above. The current XZ CLI defaults
to multiple threads; the original single-threaded-XZ assumption was incomplete.

## Validation and limits

Passing: full scripts/run-tests; clean build; focused system-management (689
Python cases and native/Xvfb lifecycle); terminal/default-apps preservation;
image package floor; final Kickstart/ISO builder tests; package map; ShellCheck;
shfmt; docs build. Independent review found a nested-shell prompt guard issue,
which was fixed and retested. The final review with evidence found no actionable
source defects. Logs are in the local evidence directory. Final documentation
build and git diff check passed after recording measurements.

Identical-tar decompression and all three final firmware installations passed.
Optional media-check boots completed successfully in BIOS and UEFI (8.205 and
8.288 seconds on this NVMe host). Final UEFI rechecks ran concurrently and are
functional evidence, not additional benchmark samples.
Physical NVIDIA, Secure Boot, suspend and USB/NVMe hardware timing remain outside
the available validation environment. Complete installer logs were scanned for failures. Optional Kdump/subscription
modules, absent EDD/iSCSI/multipath hardware, unaccelerated kiosk rendering, and
chroot user-systemd migration warnings also occur in the original baseline;
installation and first login succeed. No GitHub/R2 release was changed.
