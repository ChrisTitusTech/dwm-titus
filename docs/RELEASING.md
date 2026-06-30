# Release Checklist

Release artifacts are generated from the portable build configuration. Do not
use `make native` for published binaries.

1. Start from a clean checkout on the release commit.
2. Set `VERSION` in `config.mk` to the release version, such as `0.5.0`.
   `scripts/dwm-titus-release --version v0.5.0` can also set it for the
   release run.
3. Run `make check`.
4. Run the distribution and X11 validation required by `SPEC.md`.
5. Run `make release-check`.
6. Confirm the artifact is named `release/dwm-titus-VERSION.tar.gz`.
7. Record the tested distributions, architectures, X11 environments, known
   limitations, and SHA-256 checksum in the release notes.
8. Tag the release only after all applicable `SPEC.md` acceptance criteria
   pass.

To create the GitHub release and bump to the next minor development version:

```sh
scripts/dwm-titus-release --version v0.5.0 --iso ~/Downloads/dwm-titus.iso --notes RELEASE_NOTES.md
```

After publishing `v0.5.0`, the script updates `config.mk` to `VERSION = 0.6.0`
unless `--no-bump` is provided.

`make release-check` builds the archive twice and verifies identical bytes,
the generated desktop-session path, required archive entries, and the absence
of `config.h` and object files.

## Fedora installer ISOs

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

Both spins install the enabled Fedora, RPM Fusion, Brave, and MWT package
repositories used by this project. The NVIDIA spin additionally enables RPM
Fusion NVIDIA driver packages, blacklists Nouveau, and sets NVIDIA DRM
modesetting for first boot.
