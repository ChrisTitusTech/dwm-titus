# Phase 7 qualification

Phase 7 software and image qualification is complete with the limitations below.
This records development test media and source qualification, not a published
release or physical-hardware certification. Validation ran on 2026-09-10/11.

## Inputs and artifacts

- Fedora 44 Server Network Install, x86_64, build 1.7.
- Source: `Fedora-Server-netinst-x86_64-44-1.7.iso`, 1,228,384,256 bytes.
- SHA-256: `ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`.
- Signed manifest: `Fedora-Server-44-1.7-x86_64-CHECKSUM`; verified signer
  `36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`, matching the
  [Fedora security page](https://fedoraproject.org/security/).
- Final development images: `dwm-titus-standard-ui6.iso` and
  `dwm-titus-nvidia-ui6.iso`. Exact image hashes and per-file payload hashes are
  in [completion/ui6-images.sha256](evidence/p7/completion/ui6-images.sha256) and
  [source-ui6-manifest.json](evidence/p7/completion/source-ui6-manifest.json).
  Later qualification-record edits do not change the tested runtime payload.
- Images were built from a tracked-file snapshot, excluding generated objects,
  local configuration, documentation dependencies and guest credentials.
  Earlier `-rc` and `-p7` images identify intermediate validation stages; they
  are not the final artifacts or published releases.

Build from the intended source snapshot, with a dedicated temporary directory:

```sh
scripts/build-dwm-fedora-installer-iso.sh --input Fedora-Server-netinst-x86_64-44-1.7.iso --output dwm-titus-standard-ui6.iso
scripts/build-dwm-fedora-installer-iso.sh --input Fedora-Server-netinst-x86_64-44-1.7.iso --output dwm-titus-nvidia-ui6.iso --variant nvidia
sha256sum dwm-titus-standard-ui6.iso dwm-titus-nvidia-ui6.iso
```

Both builders passed embedded `checkisomd5` verification. Signed source
verification, package-map resolution (73 entries), both Kickstarts, both GRUB
menus and output-preservation regressions passed. Network-install package
versions are captured in each guest RPM inventory; future repository changes
can change the installed package set even with identical media.

## Qualification matrix

All VMs used KVM/Q35, two host-model vCPUs, 4 GiB RAM, a fresh 50 GiB qcow2
virtio disk, QEMU user networking with virtio-net, virtio graphics, and a USB
tablet. UEFI used OVMF with private variable storage and Secure Boot off; BIOS
omitted pflash. No host disk or GPU was attached. Anaconda storage, locale and
regular-user choices were entered through the shipped interactive UI.

| Path | Result and evidence |
| --- | --- |
| Standard BIOS | Clean `-p7` install, normal first reboot, LightDM/dwm and one managed Quickshell passed. `bios-desktop.log`, RPM inventory and install screenshot. Latest UI-6 changes affect desktop code; their UEFI and nested-X11 coverage is reused for BIOS. |
| Standard UEFI | Clean `-p7` and final `-ui6` installs, normal first reboot and desktop passed. `final-desktop.log`, final post log and RPM inventory. |
| NVIDIA UEFI, virtual GPU | Clean `-p7` and final `-ui6` installs and desktop passed. `nvidia-driver.log` records akmod/module version 610.57.04 and variant boot arguments. Virtio graphics cannot establish proprietary driver operation on NVIDIA hardware. |
| Existing Fedora 44 | Stock Server install, core installation, core repeat, recommended upgrade and restoration passed. SELinux remained Enforcing. Installed files, running dwm and managed-shell IPC matched after a fresh startx session. |
| Configuration preservation | Seeded config.h, TOML, .xinitrc, user desktop/autostart entries, file ownership/modes and existing MIME default survived repeated install and upgrade. Gear Lever added the previously unset AppImage association; unrelated MIME defaults remained unchanged. |
| Interrupted update and recovery | Controlled TERM after the source clean step left installed dwm intact; retry rebuilt and restored parity. No RPM transaction was interrupted. Saved source/configuration restored into a separate checkout and a working startx session. |
| UI-6 | Real guest tags/focus, Alacritty launch, panel ownership, notification delivery/history, Settings open/close, display discovery and network after reboot passed. Nested gates cover TOML reload, tray registration and optional-provider isolation. Closed launcher index/consumers return to zero; one managed shell idles below 3% over 30 seconds. |
| Small display | Real 1024x768 guest Settings fits at 992x736 and remains usable after close/reopen. Bounded Xvfb regression checks both IPC open and toggle. `uefi-settings-small-fixed.png`. |
| Suspend/resume | FAIL in the QEMU S3 fixture: guest entered suspend, but wake did not restore a usable desktop/SSH session; reset was required. Seen with the image guest and the stock-Fedora existing-system guest. Root cause is unproven. This path is unqualified. |
| Physical hardware | NVIDIA acceleration, physical multi-monitor/hotplug, Wi-Fi/Bluetooth radios, audible input/output, laptop brightness/battery and suspend/resume were not tested. VM provider availability and nested mocks do not qualify these devices. |

The image policy disables SELinux; existing-system installation preserved its
Enforcing policy. Temporary installation and test sudoers files were absent at
completion. Herdr was intentionally absent and reported as optional degradation;
required diagnostics had zero failures. NVIDIA-only services (`nvidia-persistenced`
and the nvidia-settings autostart entry) failed without an NVIDIA device in the
virtual-GPU fixture; their logs are retained, not counted as driver success.
Guests had no physical audio or
Bluetooth devices: graceful absence and provider state were checked, not sound
quality, pairing or radio behavior.

## Defects found and corrected

1. Repacked media retained a stale embedded checksum and failed the default
   media-test boot. The builder now implants and verifies before atomically
   replacing the output; failures preserve the previous image.
2. BIOS GRUB lacked the Kickstart argument. Both independent GRUB menus are now
   patched and tested without replacing one menu with the other.
3. Core-only image provisioning omitted Meslo/Gear Lever. Recommended-profile
   provisioning now runs on a private D-Bus so Anaconda's AccountsService does
   not misidentify the target user. Clean installations confirmed both assets.
4. Temporary post-install sudoers authorization now has exit and interruption
   cleanup, covered by extracted-post exit-73 and TERM fixtures.
5. Settings IPC opened with no target screen and overflowed small displays.
   It now uses the focused screen, with real and nested X11 geometry evidence.
6. Existing user managers could retain vendor Picom/Light Locker autostart units
   after user exclusions were installed. Autostart now refreshes generators
   before starting the graphical session. A deliberately stale-generator guest
   reproduced the old failure and passed with the correction.
7. Independent review found that recovery instructions missed custom XDG paths
   and external symlink targets. The corrected backup/restore recipe was tested
   with both, including changed target contents and a replaced file symlink.

Earlier BIOS testing force-ejected media during reboot and hung; clean reruns
kept the media attached through first boot and passed. Earlier partial-post and
failed installation logs remain historical evidence, not successful final-media
coverage. Private chroot D-Bus cannot activate a systemd user manager; these
nonfatal provisioning messages were inspected separately from package/post
failures. Gear Lever rendered despite a virtual DRI3 warning.

## Validation and evidence

Selected sanitized logs, source/image manifests, RPM inventories and screenshots
are in [evidence/p7/completion](evidence/p7/completion). Full local evidence is
retained under `/home/titus/tmp/dwm-p7-finish/evidence/`; earlier defect evidence
is under `/home/titus/tmp/dwm-p7-20260910/evidence/` and `evidence/p7/`.
Password-bearing lines and hashes were removed before retaining guest logs.
Repository log copies normalize trailing whitespace; original command output
remains in the local evidence directory. All six task VMs, their disks, SSH
masters, credentials and task staging were removed after validation.

- Full `scripts/run-tests`: passed (exit 0), including the complete Settings lifecycle, small-screen regression, native/nested X11, configured QML lint, installation preservation, package map and reproducible release archive.
- Focused `scripts/run-tests make check-session-guards check-session-migration check-xdg-autostart`: passed after the autostart fix, which followed that portion of the aggregate run.
- Configured QML lint, ShellCheck and shfmt: passing repository gates. The skill's generic qmllint invocation emitted pre-existing type warnings and is not claimed as a clean result.
- `npm --prefix docs ci` and `npm --prefix docs run build`: passed.
- Both image builds/media checks and actual installed desktops: passed as scoped above.
- Independent local review: review two completed with no actionable findings. Review one found the two recovery-documentation issues above; both corrected. The final qualification-record review is recorded with the completion evidence.

The small-screen full fixture was invalidated by editing its shell script while
it ran. Its syntax error is discarded evidence, not a passing result. The stable
aggregate Settings fixture and dedicated small-screen regression replace it.

## Recovery and release boundary

Use the tested [source update and recovery procedure](src/content/install.md#source-updates-and-recovery).
It saves source/Git state, effective XDG configuration and writable symlink
targets; retry and restoration preserve the failed checkout for inspection.
It does not roll back RPM transactions or external firmware/service changes.

Carry the exact failed/unqualified hardware paths above into any release notes.
QEMU S3 and physical hardware support must not be advertised as verified.
Version selection, rebuilding tagged release artifacts, merge, tag and release
publication are separate authorized actions. Phase completion does not authorize
them; only this source branch is being committed and pushed.
