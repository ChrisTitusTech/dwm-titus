# Active Tasks

## Phase 7: Fedora Image and Release Qualification

Pre-Phase 7 responsiveness, live maintenance and local validation are complete.
Entry evidence and remaining qualification limits are recorded in
`docs/PRE-P7-MAINTENANCE.md`. Phase 7 remains on hold until explicitly started.

Phase 6 is complete. Its acceptance evidence and remaining hardware/service
limitations are recorded in `docs/P6-QUALIFICATION.md`. Phase 7 is queued;
implementation has not started. Keep each boundary independently reviewable and
preserve the Fedora-only, standard/NVIDIA, user-data and configuration-ownership
contracts in `SPEC.md`.

### P7-BASE: Release Inputs and Qualification Matrix

- [ ] Record the supported Fedora Server Network Install release, official image
  checksum and signature verification, architecture and boot modes.
- [ ] Define the standard and NVIDIA VM/hardware matrix, including explicit
  unavailable hardware and release-blocking versus documented limitations.
- [ ] Inventory release tooling, package sources, repository policy and required
  manual evidence before building images.

Acceptance: release inputs are reproducible and each matrix entry has a named
validation procedure and evidence location.

### P7-IMAGE: Kickstarts, Packages and ISO Construction

- [ ] Validate both Kickstarts and the shared Fedora package map against the
  selected release.
- [ ] Build standard and NVIDIA images through the supported builder, keeping
  proprietary NVIDIA changes confined to the selected variant.
- [ ] Record build commands, package resolution, image checksums and failures.

Acceptance: Kickstart syntax, package resolution and ISO construction succeed
for each release candidate without changing the supported platform contract.

### P7-INSTALL: Installation and First Boot

- [ ] Exercise a clean image install, reboot and usable dwm X11 session in the
  supported boot modes and available matrix entries.
- [ ] Qualify first-boot services, login, managed-shell ownership, required
  providers and desktop features.
- [ ] Exercise the supported existing-system install and repeat-install path.

Acceptance: a clean supported image reaches the documented desktop, and repeated
installation preserves user-owned data and configuration.

### P7-UPGRADE: Migration, Rollback and Recovery

- [ ] Exercise supported upgrade and migration paths with representative
  existing user configuration.
- [ ] Validate backup, rollback and recovery procedures, including interrupted
  installation or upgrade where a safe disposable environment permits it.
- [ ] Record installed-file/runtime parity and restored session behavior.

Acceptance: each supported transition preserves user data and makes failure and
recovery actions explicit; untested transitions are named rather than implied.

### P7-DESKTOP: Hardware and Integrated Desktop Qualification

- [ ] Qualify common display configurations, audio, networking and suspend on the
  available VM/hardware matrix.
- [ ] Record NVIDIA driver, firmware, boot and hardware limitations separately
  from the standard image.
- [ ] Complete UI-6 integrated desktop review with X11 focus, IPC, lifecycle,
  closed-surface resource use and optional-provider isolation evidence.

Acceptance: each release claim maps to passing evidence or an explicit supported
limitation; unavailable hardware is not reported as tested.

### P7-RELEASE: Release Readiness

- [ ] Run the full repository, package-map, image, installation and runtime gates
  required for the selected release candidates.
- [ ] Review release notes, upgrade commands, recovery documentation and the
  completed evidence matrix.
- [ ] Complete independent local review and applicable local validation for each PR;
  verify the published head matches the reviewed content.
- [ ] Request release/publication authorization if it has not already been given.

Acceptance: release artifacts and procedures are reproducible and review-ready,
with unsupported or untested paths stated precisely. Phase 7 work does not imply
permission to publish a release.
