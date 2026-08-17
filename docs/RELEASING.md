# Release Checklist

Release artifacts are generated from the portable build configuration. Do not
use `make native` for published binaries.

1. Update `VERSION` in `config.mk` and move the applicable `CHANGELOG.md`
   entries from Unreleased into that version.
2. Commit and push the release source. The helper refuses dirty worktrees,
   version mismatches, and commits that are unavailable on GitHub.
3. Run `scripts/run-tests`.
4. Run `scripts/run-tests make check-xvfb-runtime check-monitor-tags` in isolated X11.
5. Run `scripts/run-tests make check-container-smoke` against Fedora 44.
6. Run `scripts/run-tests make check-quickshell-qml check-quickshell-health-xvfb
   check-quickshell-settings-xvfb` when QML changed.
7. Run `scripts/run-tests mdbook build docs` and
   `scripts/run-tests mdbook test docs` when documentation changed.
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
