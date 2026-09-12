# Compressed system image builds

The compressed-image path prepares the complete desktop once in a disposable
Fedora 44 virtual machine. Anaconda installs its local filesystem archive,
then creates configuration for the account selected by the user. Package
selection and repository downloads happen at image-build time. Disk selection,
partitioning, locale and account creation remain interactive.

The [2026-09-11 qualification record](COMPRESSED-QUALIFICATION.md) covers offline
installation and desktop tests for these compressed builds, with explicit hardware
limits. Download the qualified images from the Cloudflare links in the
[README](../README.md#fedora-iso). The original GitHub-attached v0.7.0 ISOs still
use network installation. Phase 8 changes below are release-candidate build
behavior; the existing download links remain on the qualified September 11
images until replacement qualification and publication are complete.

## Build

Use a clean checkout and the signed, verified Fedora Server netinst base from
[RELEASING.md](RELEASING.md#fedora-installer-isos). The factory builder checks its
pinned SHA-256 before starting. It requires an x86_64 Fedora host with access to
KVM, QEMU, OVMF, libguestfs/guestfish, zstd, xz, GNU time, pykickstart and the existing ISO-build
tools. Allow space for a 50 GiB virtual disk, an uncompressed filesystem archive
and the final artifacts. Factory provisioning requires Internet access.

```bash
source scripts/dwm-packages.sh
mapfile -t factory_packages < <(dwm_packages fedora image-factory)
sudo dnf install "${factory_packages[@]}"

mkdir -p "$HOME/tmp/dwm-compressed/staging" "$HOME/tmp/dwm-compressed/artifacts"
export TMPDIR="$HOME/tmp/dwm-compressed/staging"
export DWM_TEST_TMP_ROOT="$HOME/tmp/dwm-compressed"

scripts/build-dwm-fedora-system-image.py \
  --input "$HOME/tmp/dwm-compressed/Fedora-Server-netinst-x86_64-44-1.7.iso" \
  --output "$HOME/tmp/dwm-compressed/artifacts/standard.tar.zst" \
  --variant standard

scripts/build-dwm-fedora-installer-iso.sh \
  --input "$HOME/tmp/dwm-compressed/Fedora-Server-netinst-x86_64-44-1.7.iso" \
  --system-image "$HOME/tmp/dwm-compressed/artifacts/standard.tar.zst" \
  --output "$HOME/tmp/dwm-compressed/artifacts/dwm-titus.iso" \
  --variant standard
```

Repeat both commands with `--variant nvidia` and distinct `nvidia.tar.zst` and
`dwm-titus-nvidia.iso` outputs. Standard and NVIDIA archives are not
interchangeable. Keep each archive's `.json` manifest beside it: the ISO builder
checks the platform, variant, size and SHA-256 before embedding the payload.
A checksum detects changed bytes; it does not authenticate an untrusted archive.

Zstd captures use `zstd -T0 -19`. Compression wall time and peak memory are
recorded in the adjacent `.logs/compression.txt`; the protocol-2 JSON records
the compression arguments and uncompressed tar size/hash. Existing `.tar.xz`
input and protocol-1 manifests remain supported. The ISO uses a neutral `.tar`
filename because Anaconda 44.30 does not recognize the `.tar.zst` suffix; its
GNU tar detects zstd by content. The builder reads the archive fully before
creating the ISO and preserves an existing output if validation fails.

Compressed ISOs default to entry 0, the normal installation. The optional
"Test this media & install" entry remains available. This skips only the
optional whole-media scan; Anaconda still verifies the liveimg SHA-256 before
extraction. Do not infer install time from decompressor throughput alone.
Offline installer kernels use the pinned network generator's supported
`ip=none`, `systemd.mask=NetworkManager-wait-online.service` and
`rd.systemd.mask=nm-wait-online-initrd.service` options instead of
the unrecognized `inst.nonetwork`. The runtime mask skips only the installer's
initrd/runtime wait-online services; installed NetworkManager remains enabled. Online factory
boot arguments are unchanged. Installed-system networking is a separate
qualification check; this flag is not written to the target bootloader.

The factory uses a fresh virtual disk and a locked temporary account. It never
installs the desktop on the build host. Before capture it removes that account,
its home, temporary sudo access, machine identifiers and storage configuration.
The capture includes `/boot` and the EFI filesystem. The ISO supplies the offline account-setup helper, so installer fixes do not
require downloading all factory packages again. The finished image contains
system-wide fonts, themes and Gear Lever with its Flatpak runtimes, plus the
RPM and Flatpak manifests under `/usr/share/dwm-titus-image/`.
Offline account setup creates the standard XDG directories and seeds
`Pictures/backgrounds` with the bundled default wallpaper. It does not need to
download a wallpaper collection on the installed machine.

Fresh image accounts also receive the shared Starship prompt, verified Herdr,
Brave Origin as the browser, and sxiv for the image formats it advertises.
Starship uses terminal palette colors; custom Bash and MIME files are preserved.
The Alacritty shortcut and Herdr opt-in behavior stay the same. sxiv is visible
in Defaults, and feh remains installed for wallpaper. Tool hashes are recorded
in `tool-sha256.txt`; bundled tool licenses and Herdr source are available under
`/usr/local/share/doc/` on the installed system.

## Desktop dependency gate

Image capture fails if the shared full Fedora package contract is incomplete.
It also checks the executables used by the shipped desktop. Screenshot support
requires `maim`, its shared libraries (including region selection), `xclip`,
`xdotool`, `xrandr`, `notify-send`, XDG helpers and `dwm-screenshot`. The gate
also covers terminal, compositor, wallpaper, locking, audio, networking,
Bluetooth, media, brightness, file management and managed shell helpers.
Hardware-specific integrations such as the optional Looking Glass VM shortcut
still require their separately configured client and virtual machine.

Capture also requires PackageKit >= 1.3.5, so normal desktop users do not need
to inspect a privileged daemon executable to validate an older security backport.
For an older image showing that backport error, update PackageKit through Fedora
DNF, reboot and reload Settings. A failed package transaction must still be
investigated separately; see the in-progress [Phase 8 evidence](P8-QUALIFICATION.md).

After installation, test all three screenshot bindings in the actual X11
session: Super+P saves the active monitor, Super+Shift+P saves a selected region,
and Super+Ctrl+P copies a selected region as `image/png`. A package inventory
alone does not prove a working capture or clipboard owner.

## Qualification and updates

Install onto a new VM disk with no Internet access. Verify Anaconda does not
wait for repository metadata, then verify first boot, a newly created account,
LightDM, dwm, Quickshell, screenshots, clipboard ownership, fonts and Gear Lever.
Record firmware mode, architecture, variant, source checksum, artifact sizes
and untested hardware. Test BIOS and UEFI separately. A virtual NVIDIA-variant
install does not qualify physical NVIDIA acceleration.

Installed machines remain ordinary mutable Fedora systems. Their package
repositories are available for later online updates. Use the existing
[source update and recovery procedure](src/content/install.md#source-updates-and-recovery)
for desktop source updates. To refresh installation media, rebuild the factory
image so the new ISO contains the updated packages and assets; changing the
checkout beside an old archive does not update the archive's installed desktop.

Measure finished files instead of estimating from package download totals:

```sh
stat -c '%n %s bytes' "$HOME/tmp/dwm-compressed/artifacts/"*.tar.zst \
  "$HOME/tmp/dwm-compressed/artifacts/"*.iso
sha256sum "$HOME/tmp/dwm-compressed/artifacts/"*.iso
```

Compressed images are larger than netinstall media. Check the release host's
individual asset limit before publication; do not silently truncate or replace
an oversized ISO. Factory logs are retained beside the archive in `.logs/`;
disposable build disks and temporary archives are removed when the builder exits.
