# Active Tasks

## Phase 8: Performance and fresh-install correctness

Planning requested 2026-09-11. Completed Phase 1-7 and compressed-image tasks
have been cleared from the active list; history remains in Git and the archived
roadmap. Implementation and available VM qualification are complete. See
[qualification results](docs/P8-QUALIFICATION.md) for evidence and hardware limits.

The [implementation plan](docs/P8-IMPLEMENTATION-PLAN.md) is complete through
8E within the available environment. Git publication and merge are authorized; R2 upload remains a separate
release step. Existing release objects and links remain unchanged.

### 8A. Baseline and compatibility

- [x] Reproduce the screenshot's PackageKit error as a fresh unprivileged user;
      collect the installed RPM NEVRA, daemon D-Bus version/owner/PID, procfs
      access result, service state and journal. Distinguish unreadable identity,
      stale daemon, vulnerable version and authorization failure.
- [x] Record the PR #299 ISO hashes and a timed baseline on a fixed VM and, when
      available, USB 3.0/NVMe hardware. Separate media and payload checksum time,
      startup, extraction, post-install, reboot/login and human input time.
- [x] Inspect the pinned Fedora 44 Anaconda/dracut code and runtime for
      `inst.nonetwork` or a supported equivalent; prove network wait behavior.
- [x] Verify liveimg tar.zst recognition and decompressor availability in the
      actual installer, not only the build host. Establish RAM/disk budgets.
- [x] Record package/repository availability and real desktop IDs for stable
      Brave Origin, Starship and sxiv, plus the pinned Herdr artifact/runtime.

### 8B. Fresh-install correctness

- [x] Add image dependencies through the shared package contract and matching
      factory profiles. Require Starship, Brave Origin, Herdr and sxiv in both
      captured images; missing required software must fail qualification.
- [x] Seed Starship configuration and idempotent interactive Bash initialization;
      verify Alacritty imports, Nerd Font glyphs and theme integration. Preserve
      existing custom shell/prompt/theme files and noninteractive shell behavior.
- [x] Install official stable Brave Origin and seed browser URL/HTML associations
      only for a fresh account. Check launch/first-run behavior without applying
      unsupported policy tricks or replacing existing browser profiles/defaults.
- [x] Bundle checksum-verified Herdr at factory build time in a location that
      survives factory-user cleanup; verify it runs offline for the new user.
      Keep Alacritty keybindings and explicit DWM_HERDR activation behavior.
- [x] Add sxiv and discoverable desktop/MIME registration; make it the new-user
      default for supported image formats and visible/selectable in Settings.
      Verify PNG/JPEG and other formats actually advertised by the package;
      retain feh wallpaper behavior and preserve existing MIME choices.
- [x] Fix the PackageKit compatibility/identity failure with the security floor
      intact. Prefer a fixed supported Fedora package; review a narrow trusted
      identity solution only if needed. Improve actionable recovery messaging.
- [x] Test actual PackageKit refresh and a signed update through Settings after
      enabling networking; test denied/canceled authorization, stale/unknown
      daemon identity and recovery. Preserve read-only discovery when blocked.
- [x] Add focused regression coverage for package presence, prompt seeding,
      preserved defaults, MIME discovery and PackageKit identity failure modes.

### 8C. Offline boot path

- [x] Select default GRUB entry 0 for compressed ISOs in both firmware paths;
      retain optional rd.live.check entry 1 and test both real menus.
- [x] Apply the proven installer-only network-wait change to offline media;
      leave online factory builds and installed NetworkManager functional.
- [x] Test NIC absent, cable/link disconnected, link with no DHCP, and working
      DHCP; verify no network wait or remote payload/repository dependency.
      Functional cases passed; controlled timing uses the no-NIC configuration.
- [x] Keep embedded media checksums, published SHA-256 and liveimg payload
      verification. Update the USB guide to describe the new default entry.

### 8D. Zstd payload

- [x] Capture tar.zst with requested `zstd -T0 -19`; record compression time,
      peak memory and output size. Use identical tar contents for the xz/zstd
      comparison so package changes do not distort compression results.
- [x] Update builder arguments, extension/content checks, archive paths,
      checksum/manifests and required tools; retain existing tar.xz input support.
- [x] Reject damaged archives, mismatched variants/manifests and checksum errors;
      preserve a previous output on failure and clean temporary artifacts.
- [x] Verify ownership, ACL/xattr preservation, boot files, new-machine identity,
      dotenv exclusion, and installed package/feature parity after zstd extraction.
- [x] Complete actual offline zstd installs and compare full stage timings;
      do not infer total installation time from standalone decompression speed.

### 8E. Final qualification

- [x] Run focused tests, `scripts/run-tests`, docs build and independent Codex
      review; resolve valid findings and repeat affected checks.
- [x] Qualify standard UEFI/BIOS and NVIDIA UEFI, then verify first-login prompt,
      themes, browser, Herdr, sxiv/defaults, maim full/region/clipboard, Gear Lever,
      and PackageKit update actions. Record screenshots and logs.
- [x] Report at least three comparable runs with median/range and hardware/RAM/
      storage details; report actual size and timing changes against PR #299.
- [x] Update user/build docs and a new qualification record. Keep physical NVIDIA,
      Secure Boot and suspend limits explicit unless newly tested.
- [x] Prepare local ISO candidates, checksums and manifests in the dated
      qualification workspace. Choose new dated R2 object names during the
      separately authorized publication workflow; retain current objects/links.

## Evidence and implementation map

- User screenshot: PackageKit shows 638 available updates, but refresh/install
  are blocked by "Cannot verify the running PackageKit security backport" and
  require 1.3.5+ when executable identity cannot be read. This is fresh-install
  acceptance evidence, not a successful update-action test.
- Existing guard: `scripts/dwm-system-management`,
  `packagekit_security_floor` and `_require_running_backport_identity`; tests in
  `tests/test-system-management.py`. It currently accepts Fedora 44 1.3.4-3+
  only with running executable identity; reproduce the precise exception.
- Package/image files: `scripts/dwm-packages.sh`, `dwm-fedora*.ks`,
  `scripts/build-dwm-fedora-system-image.py`,
  `scripts/build-dwm-fedora-installer-iso.sh`, `scripts/image/`.
- Desktop files: `config/alacritty/`, theme application, user install targets,
  `scripts/install-herdr`, `scripts/dwm-default-apps` and Settings Defaults.
- Preserve existing-system optional Herdr behavior and user-selected apps.
  Default installation of the new software applies to fresh dedicated images.
- User-supplied ~45-70 second total and ~15-25 second extraction are estimates.
  Acceptance requires measured improvements and functional parity, not those
  unverified figures.

## Source checks for implementation

- [Anaconda boot options](https://anaconda-installer.readthedocs.io/en/latest/user-guide/boot-options.html):
  current docs do not list inst.nonetwork; pinned Fedora 44 behavior must be checked.
- [Brave Origin Linux](https://brave.com/origin/linux/): official Origin flavor;
  resolve its current signed RPM package/repository during implementation.
- [PackageKit security advisory](https://github.com/PackageKit/PackageKit/security/advisories/GHSA-f55j-vvr9-69xv):
  preserve the patched-daemon safety boundary while fixing fresh-install usability.
