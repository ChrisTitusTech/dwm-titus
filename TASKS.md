# Active Tasks

## Compressed system image installer

Authorized 2026-09-11. Replace install-time repository resolution with a
prebuilt Fedora root filesystem while retaining Anaconda disk, locale and
account selection. Preserve standard/NVIDIA separation and existing-system
installation. Phase 7 historical evidence remains in docs/P7-QUALIFICATION.md.

- [x] Build a disposable factory system from the existing package contract.
- [x] Exclude dotenv files recursively from the ISO payload and verify the
      actual rsync filters against root and nested dummy credential files.
- [x] Move required desktop assets into system-wide image storage; remove
      factory accounts, credentials, identifiers, logs and machine-specific state.
- [x] Capture and checksum a compressed filesystem and embed it in the Fedora
      Server installer with a local liveimg Kickstart and offline user setup.
- [x] Verify standard/NVIDIA identity, failure handling and output preservation.
- [x] Require maim, clipboard/region-capture dependencies and all shipped-feature
      commands; exercise screenshots and clipboard ownership after offline install.
- [x] Install with networking disconnected; verify first boot, new user,
      LightDM/dwm/Quickshell, fonts, Gear Lever and template identity cleanup.
- [x] Measure artifact sizes, document the supported build/update workflow and
      limitations, and complete applicable tests and independent local review.

- [x] Upload verified ISOs and checksums to the configured Cloudflare R2 bucket;
      verify uploaded objects by reading them back and comparing SHA-256.

R2 upload authorized 2026-09-11 only after offline installation and desktop
verification. The user subsequently authorized updating the v0.7.0 release,
then publishing the download/install guidance and merging this work into main.

- [x] Verify all public Cloudflare downloads and update the v0.7.0 release links.
- [x] Update README and the installation guide for the offline Cloudflare ISOs.
- [x] Build and inspect the documentation and complete independent review of
      the compressed-image implementation and Cloudflare download guidance.

The user authorized publication and merge into main; GitHub records the merge
state and post-merge documentation deployment.
