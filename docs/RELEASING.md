# Release Checklist

Release artifacts are generated from the portable build configuration. Do not
use `make native` for published binaries.

1. Start from a clean checkout on the release commit.
2. Run `make check`.
3. Run the distribution and X11 validation required by `SPEC.md`.
4. Run `make release-check`.
5. Confirm the artifact is named `release/dwm-titus-VERSION.tar.gz`.
6. Record the tested distributions, architectures, X11 environments, known
   limitations, and SHA-256 checksum in the release notes.
7. Tag the release only after all applicable `SPEC.md` acceptance criteria
   pass.

`make release-check` builds the archive twice and verifies identical bytes,
the generated desktop-session path, required archive entries, and the absence
of `config.h` and object files.
