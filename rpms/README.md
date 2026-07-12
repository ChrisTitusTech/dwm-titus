# Patched Gamescope RPM

This directory contains a local Fedora 44 rebuild of Gamescope 3.16.23.
It backports ValveSoftware/gamescope pull request 2246, commit
`191c7920ff04f7a92011cc2259b1a5c3e291839b`, to stop and join the SDL backend
thread during shutdown. This addresses the `std::terminate` crash seen when an
SDL-backed Gamescope session exits.

The package is based on Fedora's signed
`gamescope-3.16.23-1.fc44.src.rpm`. No other Gamescope source changes are
included. The rebuilt RPM is locally produced and is not GPG-signed.

Install or upgrade it with:

```sh
sudo dnf install ./rpms/gamescope-3.16.23-2.dwm_titus.fc44.x86_64.rpm
```

Restore Fedora's package with:

```sh
sudo dnf downgrade gamescope-3.16.23-1.fc44
```

Files and SHA-256 checksums:

```text
d6acd683627a85ea98e424a8f8990a1c652cf437b03b4aa5c3f6a698dd7ab4a7  gamescope-3.16.23-2.dwm_titus.fc44.x86_64.rpm
009887d5a9ea3048a73dc829e2281bc01d000a045f464fee5411e6c18e43ca76  gamescope-3.16.23-2.dwm_titus.fc44.src.rpm
```

The source RPM contains the Fedora spec file and the exact upstream patch used
for the rebuild.
