# dwm-titus v0.7.0

A Fedora-only X11 desktop built around dwm and a managed Quickshell shell.
This release completes the planned desktop and image qualification phases.

## Highlights

- Unified Settings for displays and input, networking and Bluetooth, audio,
  power and session actions, default applications, appearance and accessibility.
- Fedora system updates with confirmation and recovery, regional settings,
  administration tools, system information, storage and diagnostics.
- Integrated panel, launcher, notifications, tray and desktop controls, with
  lazy Settings panes and bounded background work.
- Standard and NVIDIA Fedora 44 installers with dark Anaconda branding,
  corrected BIOS/UEFI Kickstart boot menus and verified embedded media checksums.
- Recommended image provisioning includes Meslo icons and Gear Lever.
  Existing-system updates preserve user configuration; backup, retry and
  restoration procedures cover custom XDG locations and symlink targets.
- Small-display Settings sizing and stale user-autostart recovery fixes found
  during clean-install and upgrade qualification.

See the [full changelog](https://github.com/ChrisTitusTech/dwm-titus/blob/v0.7.0/CHANGELOG.md)
for all changes since v0.6.1.

## Downloads

| Asset | Use |
| --- | --- |
| `dwm-titus.iso` | Standard Fedora 44 x86_64 network installer. |
| `dwm-titus-nvidia.iso` | NVIDIA variant with proprietary driver packages and boot configuration. |
| `dwm-titus-0.7.0.tar.gz` | Portable x86_64 desktop bundle: dwm binary, configuration, helpers and assets. Fedora dependencies are still required; this is not a standalone installer. |
| `dwm-titus-0.7.0-SHA256SUMS` | SHA-256 hashes for all three assets above. |

GitHub also provides source archives for the `v0.7.0` tag. Both ISOs are network
installers based on Fedora Server Network Install 44-1.7 and require internet
access for packages. Use the standard image unless you need the NVIDIA variant.

After downloading the checksum file and your selected assets into one directory:

```sh
sha256sum --ignore-missing -c dwm-titus-0.7.0-SHA256SUMS
```

Check that every asset you downloaded reports `OK`. The embedded media check is
also available from the default installer boot entry.

## Install or update

Follow the [Fedora installation guide](https://github.com/ChrisTitusTech/dwm-titus/blob/v0.7.0/docs/src/content/install.md).
Before updating an existing source checkout, follow its source backup and
recovery procedure and resolve local changes. Run the recommended installer to
add the required desktop packages, then synchronize the installed source:

```sh
./install.sh --non-interactive --yes --profile recommended
./scripts/dev-sync-install.sh
```

Log out, select dwm again, and verify from the updated checkout:

```sh
./scripts/dev-sync-install.sh --check
dwm-diagnostics
```

The dedicated images disable SELinux under the existing image policy.
Existing-system installation preserves the host's SELinux policy.

## Qualification and known limitations

- Standard BIOS/UEFI and NVIDIA-variant UEFI clean installs reached LightDM,
  dwm and one managed Quickshell shell in Fedora 44 KVM guests. Existing-system
  repeat installation, configuration preservation, interrupted-build retry and
  backup restoration passed, including a working startx session with SELinux
  Enforcing. Full repository, nested X11 and local review gates passed.
- **QEMU S3 suspend/resume failed and remains unqualified.** Wake did not
  recover a usable desktop/SSH session; resetting the guest recovered boot.
  The root cause is unproven.
- **Physical NVIDIA acceleration, multi-monitor/hotplug, Wi-Fi/Bluetooth,
  audible input/output, laptop brightness/battery and suspend/resume were not
  tested.** UEFI validation used Secure Boot off. Virtual and nested checks do
  not establish physical-device support.
- NVIDIA module build/version and boot configuration were checked, but the
  guests used virtio graphics. NVIDIA persistence/settings services fail
  without an NVIDIA device; this is not a hardware-verified driver release.
- Herdr remains optional and was intentionally absent in the qualified guests.
  Missing physical audio/Bluetooth devices were checked for graceful handling.
- Network installation resolves current repository packages, so the installed
  package set may change after qualification even with identical ISO bytes.

The [qualification record](https://github.com/ChrisTitusTech/dwm-titus/blob/v0.7.0/docs/P7-QUALIFICATION.md)
contains the matrix, fixes, package inventories and evidence. Release ISOs are
rebuilt from the release commit; Phase 7 install/runtime evidence is reused for
unchanged runtime payloads, with fresh artifact and embedded-checksum validation.
