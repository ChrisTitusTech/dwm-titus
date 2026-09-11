# DWM-Titus compressed installers - 2026-09-11

These Fedora 44 x86_64 installers contain a preinstalled compressed desktop.
Anaconda retains disk, partition, language, timezone, keyboard and account
selection. Installation needs no package selection or Internet connection.
The installed systems remain ordinary, updatable Fedora installations.

| Image | Size | Verification |
| --- | --- | --- |
| dwm-titus-fedora44-x86_64-20260911.iso | 3.39 GiB | Offline UEFI and BIOS installation, LVM first boot, LightDM and desktop |
| dwm-titus-fedora44-x86_64-20260911-nvidia.iso | 3.96 GiB | Offline UEFI installation and desktop using a virtual GPU; physical NVIDIA validation outstanding |

Both variants reached dwm and Quickshell with a new administrator account,
Meslo fonts, the default wallpaper and Gear Lever running offline. The standard
image contains no proprietary NVIDIA driver; the NVIDIA image includes the
610.57.04 driver and its built module for kernel 6.19.10-300.fc44.x86_64.

All three screenshot shortcuts were exercised with the default compositor:

- Super+P: monitor JPEG, verified at 1280x800.
- Super+Shift+P: region JPEG, verified at 600x400.
- Super+Ctrl+P: region PNG clipboard, read back and verified at 600x400.

The six saved captures decoded successfully and contained nonblank image data.
The three installed VMs had distinct machine identities. Factory account and
temporary sudo access were removed, and shared system assets are root-owned.
The captured filesystems and final ISO source payloads were checked for dotenv
filenames. Credentials are not part of these images.

## Verify downloads

Place both ISOs beside SHA256SUMS and run:

```sh
sha256sum -c SHA256SUMS
```

The RPM and Flatpak inventories describe the bundled packages. BUILD-MANIFEST.json
records the exact ISO and source filesystem checksums and the Fedora base checksum.
These are compressed-image builds based on the v0.7.0 desktop, not replacements
for the previously published GitHub v0.7.0 netinstall release assets.

## Qualification limits and observed logs

Tests used fresh 50 GiB virtual disks, QEMU/KVM, virtio graphics and no network
adapter. Standard firmware coverage includes UEFI and BIOS; NVIDIA coverage is
UEFI with a virtual GPU. Physical NVIDIA acceleration, Secure Boot, TPM-backed
unlocking, physical devices and suspend/resume are not qualified by these tests.

The standard installs reported no failed system services. Early boot logged TPM
rule/account warnings, and the UEFI tests also logged a graphics connector cleanup
warning. The installed root contains the tss account/group. First login logged a
keyring control-file message. Desktop, compositor, fonts, Gear Lever and captures
worked after those messages.

The NVIDIA VM reported nvidia-persistenced.service failed because it has no
NVIDIA device or /dev/nvidia nodes. This is not a successful NVIDIA hardware test;
the NVIDIA image still needs validation on a real NVIDIA system. Its offline
installation, generic desktop and screenshot tests passed.

The full repository test suite passed. Independent local reviews found no
remaining actionable code findings, including the final offline user-setup fix.

## Exact artifacts and local gates

- `dwm-titus-fedora44-x86_64-20260911.iso`: 3635675136 bytes; SHA-256 `fe8340bb9ce6a1731e21f88e39efe9ec72d3593d1e797817a96a4d316f8d7763`.
- `dwm-titus-fedora44-x86_64-20260911-nvidia.iso`: 4252237824 bytes; SHA-256 `cedd84e952e2b96e713d211e95530fdc6960dd7a1a15d170231f3c8585f59e5e`.

Fedora Server netinst base SHA-256: `ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`.

Validation commands: `scripts/run-tests` (complete suite, exit 0), `scripts/run-tests make check-kickstart check-fedora-packages` (92 package capabilities), ShellCheck and shfmt on image scripts, real factory captures, final ISO media checks, and independent local Codex reviews. The final user-setup change also passed its focused checks and review before new offline installations.

Screenshots and full local logs are retained in the build evidence directory. All test VMs had no network adapter. No physical GPU was assigned or borrowed for these tests.

## R2 upload verification

Uploaded both ISOs, SHA256SUMS, build notes, build manifest, and the four RPM/Flatpak
manifests to bucket `titusos` under `iso/2026-09-11/`. All nine objects passed a
complete authenticated download and SHA-256 comparison against the qualified
local artifacts. The upload receipt is retained as
`/home/titus/tmp/dwm-compressed-20260911/evidence/upload-qualification.uploaded.json`.
After the user connected `downloads.christitus.com`, all nine complete public
downloads passed SHA-256 verification against the qualified artifacts. An ISO
byte-range request returned HTTP 206 with the requested 1024 bytes. Evidence is
retained as `public-download-verification.json` in the same directory.

The existing GitHub `v0.7.0` release was updated with these public links,
qualification limits, and build provenance on 2026-09-11. The published notes
were read back and matched the prepared body; existing assets were preserved.
The tag and source archives remain unchanged. Public downloads are under
`https://downloads.christitus.com/iso/2026-09-11/`.

The Cloudflare download/install documentation passed `npm --prefix docs ci`
and `npm --prefix docs run build` (zero Astro errors/warnings, 11 pages). The
rendered installation page was inspected in a browser; both installation and
home-page download links matched the publicly verified artifacts. Final
independent Codex review found no actionable defects in the complete change,
reusing the unchanged installer and VM coverage above.
