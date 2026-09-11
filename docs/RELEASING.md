# Release Checklist

Release artifacts are generated from the release build configuration. Do not
use `make native` for published binaries.

1. Update `VERSION` in `config.mk` and move the applicable `CHANGELOG.md`
   entries from Unreleased into that version.
2. Commit and push the release source. The helper refuses dirty worktrees,
   version mismatches, and commits that are unavailable on GitHub.
3. Run `scripts/run-tests`.
4. Run `scripts/run-tests make check-xvfb-runtime check-monitor-tags` in isolated X11.
5. Run `scripts/run-tests make check-fedora-packages` on Fedora 44.
6. Run `scripts/run-tests make check-quickshell-qml check-quickshell-health-xvfb
   check-quickshell-settings-xvfb` when QML changed.
7. Run `npm --prefix docs ci` and `npm --prefix docs run build` when published
   documentation changed.
8. Run `scripts/run-tests make release-check` and confirm the artifact is named
   `release/dwm-titus-VERSION.tar.gz`.
9. Record the tested Fedora release, architectures, X11 environments, known
   limitations, and SHA-256 checksum in the release notes.
10. Tag the release only after all applicable `SPEC.md` acceptance criteria
    and required GitHub checks pass.

`scripts/run-tests` creates an isolated directory below
`${DWM_TEST_TMP_ROOT:-$HOME/tmp}` and removes it on success, failure, or
interruption. Store
disposable VM disks and installer logs under a separately named directory in
that same root, then delete that exact directory after qualification. Do not
use `/tmp` for ISO or VM qualification.

To create the GitHub release and bump to the next minor development version:

```sh
scripts/dwm-titus-release --version v0.6.1 --iso ~/Downloads/dwm-titus.iso --notes RELEASE_NOTES.md
```

After publishing `v0.6.1`, the script updates `config.mk` to `VERSION = 0.7.0`
unless `--no-bump` is provided.

The helper validates and hashes local artifacts before it creates a remote tag
or release. `--version` confirms the version already committed in `config.mk`;
it does not rewrite release source.

`make release-check` builds the archive twice and verifies identical bytes,
the generated desktop-session path, required archive entries, and the absence
of `config.h` and object files.

## Fedora installer ISOs

Track Phase 7 procedures, evidence and qualification limits in
[P7-QUALIFICATION.md](P7-QUALIFICATION.md). Build success alone does not qualify
installation or first boot.

The Phase 7 development candidates passed standard BIOS/UEFI and NVIDIA-variant
UEFI installation with virtual graphics. QEMU S3 resume failed and remains
unqualified. Physical NVIDIA acceleration, multi-monitor/hotplug, radios, audio
and laptop power/suspend were not tested. Carry these limitations into release
notes; NVIDIA services failing without a physical GPU are not driver validation.
Use the tested [source backup/update/recovery procedure](src/content/install.md#source-updates-and-recovery)
for existing-system migration. Rebuild and identify authorized tagged artifacts
separately from the development images in the evidence record.

Before building, download the Fedora signing certificates, signed checksum
manifest and netinst ISO from the official Fedora Server download page. Verify
the signing fingerprint against https://fedoraproject.org/security/ and verify
the signature before using the checksum. For the current x86_64 base:

```sh
curl -fLO https://fedoraproject.org/fedora.gpg
curl -fLO https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/iso/Fedora-Server-44-1.7-x86_64-CHECKSUM
curl -fLO https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/iso/Fedora-Server-netinst-x86_64-44-1.7.iso
gpg --show-keys --with-fingerprint ./fedora.gpg
gpgv --keyring ./fedora.gpg --output Fedora-Server-44.verified-checksums Fedora-Server-44-1.7-x86_64-CHECKSUM
# Continue only after gpgv succeeds and its signer matches Fedora 44.
sha256sum -c --ignore-missing Fedora-Server-44.verified-checksums
```

The Fedora 44 fingerprint is
`36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`; the current netinst SHA-256 is
`ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`.
Run downloads and builds in a dedicated directory under `$HOME/tmp`, and set
`TMPDIR` to a staging subdirectory there when invoking the builder.

Build from a clean source checkout without local dependency directories or
generated site files: the builder embeds the checkout payload. It patches both
UEFI and BIOS GRUB menus with the selected Kickstart and variant arguments.

The builder uses `implantisomd5` and `checkisomd5` from `isomd5sum` after
rewriting the ISO so Fedora's default "Test this media & install" entry can
verify it. It replaces the output path only after verification passes. This
embedded checksum detects media corruption; it does not authenticate an image.
Record a separate SHA-256 of each finished artifact and test the default
media-check entry in the VM.

Install the Fedora image-build tools from the shared capability map:

```bash
source scripts/dwm-packages.sh
mapfile -t image_packages < <(dwm_packages fedora image-build)
sudo dnf install "${image_packages[@]}"
```

The builder embeds the dark Anaconda branding as `/images/product.img`.
Pass `--version 0.7.1` (or `--version v0.7.1`) to either build command below
to render that sidebar badge in a temporary staging tree. Omitting the option
uses the checked-in v0.7.0 badge. Versioned builds do not modify the checkout.
The generator uses Pillow and Fontconfig to locate the installed Noto fonts.

For a standalone badge, run:

```sh
scripts/generate-sidebar-logo.py --version 0.7.1 --output sidebar-logo-v0.7.1.png
```

Build the regular Fedora installer ISO from a Fedora netinst ISO:

```sh
scripts/build-dwm-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Server-netinst-x86_64-44-1.7.iso \
  --output release/dwm-titus.iso
```

Build the NVIDIA installer ISO:

```sh
scripts/build-dwm-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Server-netinst-x86_64-44-1.7.iso \
  --output release/dwm-titus-nvidia.iso \
  --variant nvidia
```

Both Kickstart profiles share the Fedora, RPM Fusion, Brave, and MWT repository
declarations used by this project. On x86_64, both also enable the
`christitustech/copr-fedora` repository; other architectures omit that COPR and
its x86-only gaming packages. The ISO builder selects the matching standard or
NVIDIA profile. The NVIDIA profile additionally installs RPM Fusion NVIDIA
driver packages, blacklists Nouveau, and sets NVIDIA DRM modesetting for first
boot.

Install the standard image in a KVM virtual machine before release. Complete
Anaconda, reboot from the installed virtual disk, and verify LightDM, dwm, and
the managed Quickshell shell. Record the source ISO checksum, firmware mode,
architecture, package-resolution result, first-boot result, and untested
hardware. A container can validate package availability and ISO contents, but
it cannot replace the required boot and first-session VM qualification.
