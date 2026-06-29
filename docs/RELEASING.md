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
