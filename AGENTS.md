# AGENTS.md

## Purpose

This repository is a Fedora-first X11 desktop environment built around a
heavily patched fork of suckless dwm and a managed Quickshell shell. The
primary product is a complete desktop installed from Fedora Server Network
Install media. The existing Debian-, Arch-, Fedora-, and RHEL-family installer
remains a supported secondary path for the core desktop experience.

Read `SPEC.md` before making product, portability, installer, dependency, or
packaging changes. Treat `SPEC.md` as the source of truth for project scope and
acceptance criteria.

## Priorities

1. Preserve dwm stability and existing user workflows.
2. Keep the C window-manager core small, understandable, and dependency-light.
3. Build a cohesive Fedora desktop without moving desktop policy into the C
   event loop.
4. Preserve the core install and session contract across the three supported
   distribution families.
5. Keep installation and settings changes safe, repeatable, reversible, and
   explicit.
6. Prefer focused changes that can be reviewed and tested independently.

## Supported Platforms

The platform contract has two tiers:

- Primary desktop image: the current documented Fedora Server Network Install
  release, with separate standard and NVIDIA variants.
- Secondary existing-system install: these distribution families:

- Debian family: Debian, Ubuntu, Linux Mint, Pop!_OS, and compatible
  derivatives using `apt`.
- Arch family: Arch Linux, EndeavourOS, Manjaro, Arch Linux ARM, and compatible
  derivatives using `pacman`.
- RHEL family: RHEL, Rocky Linux, AlmaLinux, Fedora, and compatible
  derivatives using `dnf`.

Do not claim full desktop-environment parity on a secondary platform unless its
settings providers and runtime behavior were tested there. Core support still
requires dependency discovery, installation, X session startup, configuration
deployment, and the core runtime checks in `SPEC.md`; a successful C build is
not sufficient.

## Repository Map

- `dwm.c`, `drw.c`, `util.c`, `tomlparser.c`: window-manager sources.
- `config.def.h`: version-controlled default compile-time configuration.
- `config.h`: local build configuration. Do not overwrite user changes.
- `config.mk`: compiler, include, library, and installation settings.
- `Makefile`: build, install, uninstall, and release targets.
- `config/`: application configuration and default TOML runtime settings.
- `scripts/`: session startup, dependency checks, desktop helpers, and
  operational scripts.
- `install.sh`: supported existing-system installer for all distribution
  families.
- `dwm-fedora.ks`, `dwm-fedora-nvidia.ks`: Fedora image installation profiles.
- `dwm.desktop`: display-manager X session entry.
- `AGENTS.md`: durable engineering and agent-execution rules.
- `SPEC.md`: product scope, interfaces, and acceptance criteria.
- `ROADMAP.md`: ordered desktop-environment outcomes.
- `TASKS.md`: implementation work for the active roadmap phase only.
- `docs/`: user, contributor, and release documentation.

## Planning Workflow

- Use `SPEC.md` for durable product requirements and compatibility contracts.
- Use `ROADMAP.md` for ordered phase objectives and exit criteria.
- Use `TASKS.md` only for detailed work in the active phase. Replace its task
  set when a phase completes instead of accumulating historical checklists.
- Record completed user-visible behavior in `CHANGELOG.md` and releases.
- Do not mark a task or phase complete without its required validation or a
  precise statement of what could not be tested.
- Treat phase boundaries as review and rollback points. Do not begin the next
  phase in a change that was scoped only to complete the current one.

## Fedora Image Rules

- Base released images on the Fedora Server Network Install ISO documented in
  `SPEC.md` and `docs/RELEASING.md`, not on a Fedora Live image.
- Preserve separate standard and NVIDIA Kickstarts. Proprietary NVIDIA changes
  belong only to the explicitly selected NVIDIA image.
- Keep Kickstart package capabilities aligned with the shared dependency map.
- Run `make check-kickstart` for Kickstart or ISO-builder changes, then validate
  a real or virtual install before claiming the image boots or reaches a usable
  desktop.
- Record the Fedora release, source image checksum, architecture, firmware
  mode, image variant, and untested hardware in release evidence.
- The dedicated Fedora images currently set SELinux disabled by explicit
  product policy. Existing-system installs must not change host SELinux state.
  Any change to this policy requires a specification and migration update.

## Desktop Settings Rules

- Keep the Settings frontend and all QML unprivileged.
- Read state through stable service APIs, D-Bus, signals, subscriptions, or
  bounded helpers. Do not parse human-oriented output when a machine interface
  exists.
- Separate read-only state, user-session changes, privileged system changes,
  delegated tools, and unsupported capabilities.
- Privileged helpers must be installed root-owned and non-writable, expose only
  allowlisted operations, validate every argument, and require explicit user
  intent through polkit or an equally narrow authorization path.
- Repository or user-writable helper copies must never be elevated.
- Risky changes require preview, confirmation, rollback, or recovery behavior
  appropriate to their impact. Authorization denial must not hide readable
  state.
- Fedora providers may land first. Secondary platforms must hide or explain
  unavailable capabilities without breaking the rest of Settings.

## Portability Rules

- Never hardcode one package manager in shared logic. Isolate `apt`, `pacman`,
  and `dnf` behavior behind clearly named distro-family functions or adapters.
- Detect the distribution using `/etc/os-release`. Detect package managers only
  as a fallback or validation step.
- Map required capabilities to family-specific package names. Do not scatter
  package-name lists across multiple scripts.
- Use `pkg-config` for X11 and library discovery where available. Avoid relying
  on Arch-specific paths or `/usr/X11R6`.
- Respect `CC`, `CFLAGS`, `CPPFLAGS`, `LDFLAGS`, `PREFIX`, `DESTDIR`,
  `XDG_CONFIG_HOME`, and the invoking user's home directory.
- Do not assume `/usr/lib` versus `/usr/lib64`. Search known executable paths
  only when no stable command or package interface exists.
- Support both display-manager sessions and `startx`.
- Treat Xorg as required. Wayland-native support is outside the current scope.
- Keep optional desktop components optional. The absence of Picom, a wallpaper,
  or a preferred terminal must not crash dwm.
- Use ASCII punctuation in source, scripts, and new documentation unless a
  file's established format requires otherwise.

## Configuration and Compatibility

- Preserve `config.def.h` as the default template.
- Never replace an existing `config.h`, user TOML file, `.xinitrc`, or
  application configuration without explicit user consent or a backup.
- Runtime TOML files live under
  `${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/`.
- Preserve hot reload behavior for `hotkeys.toml`, `themes.toml`, and
  `window-rules.toml`.
- `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` is managed exclusively by
  dwm-titus. Unlike user-owned dwm TOML files, install/update flows may replace
  this directory from tracked `config/quickshell/` to prevent stale shell code.
- Relaunch the managed Quickshell instance through
  `dwm-quickshell-controlcenter action restart-quickshell` or the normal
  autostart path. Do not manually start it with a repo-local `--path`, because
  hotkeys target `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml` and
  Quickshell treats different config paths as different IPC instances.
- Quickshell integration must be event-driven whenever the underlying state has
  a signal, subscription, watch, IPC, or service API. Prefer `xprop -spy`,
  D-Bus/service notifications, process stdout streams, or Quickshell service
  APIs over QML polling timers. Polling is allowed only for inherently sampled
  values such as a clock or CPU load, or when a documented fallback has no
  event source.
- Quickshell must not be an idle resource hog. Avoid resident hidden launcher
  models, overlapping `Process` launches from timers, and duplicate shell
  providers such as running DMS alongside the dwm-titus managed shell. On X11,
  avoid per-screen `Variants { model: Quickshell.screens }` panels unless a
  live CPU sample proves they idle cleanly; prefer a single `PanelWindow` for
  the managed shell. After Quickshell changes, validate `quickshell --no-duplicate`
  in a real or nested X11 session and confirm the Quickshell process is near
  idle when the launcher is closed.
- For Quickshell QML linting, stock `qmllint` must be given explicit Qt and
  Quickshell QML import roots, such as `/usr/lib64/qt6/qml` or
  `/usr/lib/qt6/qml`, and a lint-only `qs.core/qmldir` module map when checking
  files that import this repository's `qs.core` helpers. `QMLLS_BUILD_DIRS`
  and `QML_IMPORT_PATH` should mirror those roots for language-server tooling.
  Do not treat plain `qmllint` import failures as runtime failures until the
  configured import paths have been verified.
- Keep existing keybindings, window rules, EWMH behavior, multi-monitor
  behavior, and autostart behavior unless the task explicitly changes them.
- When changing defaults, update the relevant documentation and migration
  notes in the same change.

## Shell and Installer Standards

- Use Bash only when Bash features are needed; otherwise use POSIX `sh`.
- For Bash scripts, use `set -euo pipefail` unless a documented reason prevents
  it. For POSIX scripts, use `set -eu`.
- Quote variable expansions, use `command -v`, and avoid parsing human-oriented
  command output when a stable machine interface exists.
- Privilege escalation must be limited to package installation and system-wide
  file installation. Do not run the full installer as root.
- Installation must be idempotent. Re-running it must not duplicate services,
  corrupt configuration, or reset user choices.
- Package installation and service enablement must be visible to the user.
  Do not silently alter bootloader, display-manager, firewall, SELinux, or
  security policy settings.
- Network downloads must be optional, clearly reported, and failure-tolerant
  unless the downloaded artifact is explicitly required.
- Run ShellCheck and shfmt on changed shell scripts when available.

## Build and Code Standards

- Keep the existing C99 style and compile with warnings enabled.
- Avoid adding a new library dependency unless it materially improves a
  required feature. Dependencies for the core desktop must remain portable;
  Fedora-first Settings dependencies must have explicit fallback behavior on
  secondary platforms.
- Check allocation, file, Xlib/XCB, parser, and process-launch failures.
- Do not introduce blocking work into the X event loop.
- Keep Linux-specific functionality, such as inotify, explicit and documented.
- Do not commit generated objects, binaries, release archives, or local
  configuration changes unless the task specifically requires release assets.

## Required Validation

Run the smallest applicable set first, then the full relevant set:

```sh
make clean
make
```

For shell changes:

```sh
shellcheck install.sh install-arm.sh scripts/*.sh
shfmt -d install.sh install-arm.sh scripts/*.sh
```

For Quickshell QML changes, run `qmllint` with the explicit Qt/Quickshell QML
module roots documented in `SPEC.md`, and validate the managed shell in a real
or nested X11 session before declaring runtime behavior verified.

For installer or portability changes, validate in clean containers or virtual
machines representing:

- One currently supported Debian or Ubuntu release.
- One current Arch-family installation.
- One currently supported Fedora, Rocky Linux, AlmaLinux, or RHEL release.

At minimum, verify dependency resolution, a clean build, staged installation
with `DESTDIR`, installed file paths, and script syntax. A real X11 session or
nested X server is required before declaring runtime behavior fully validated.

If a required platform cannot be tested, state exactly what was not tested and
do not describe the change as universally verified.

For Fedora image changes, follow the complete validation contract in
[SPEC.md Section 9.4](SPEC.md#94-fedora-image-validation). Static validation
alone does not prove package resolution, `%post` behavior, first boot, or
hardware support.

## Change Discipline

- Inspect `git status` and relevant files before editing.
- Preserve unrelated user changes.
- Keep commits and patches narrowly scoped.
- Update `SPEC.md` only when requirements intentionally change.
- Update README and user-facing docs when commands, dependencies, defaults, or
  supported platforms change.
- Do not perform destructive Git or filesystem operations without explicit
  authorization.
- Never expose credentials, tokens, private keys, or secret file contents.
