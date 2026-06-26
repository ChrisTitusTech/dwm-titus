# AGENTS.md

## Purpose

This repository is a heavily patched fork of suckless dwm for X11. The project
must build, install, launch, and provide its documented core desktop experience
on supported Debian-family, Arch-family, and RHEL-family distributions.

Read `SPEC.md` before making product, portability, installer, dependency, or
packaging changes. Treat `SPEC.md` as the source of truth for project scope and
acceptance criteria.

## Priorities

1. Preserve dwm stability and existing user workflows.
2. Keep the C window-manager core small, understandable, and dependency-light.
3. Maintain equivalent behavior across the three supported distribution
   families.
4. Keep installation safe, repeatable, and non-destructive.
5. Prefer focused changes that can be reviewed and tested independently.

## Supported Platforms

Changes must account for these distribution families:

- Debian family: Debian, Ubuntu, Linux Mint, Pop!_OS, and compatible
  derivatives using `apt`.
- Arch family: Arch Linux, EndeavourOS, Manjaro, Arch Linux ARM, and compatible
  derivatives using `pacman`.
- RHEL family: RHEL, Rocky Linux, AlmaLinux, Fedora, and compatible
  derivatives using `dnf`.

Do not claim that a distribution is supported solely because the C binary
compiles. Support includes dependency discovery, installation, X session
startup, configuration deployment, and the core runtime checks in `SPEC.md`.

## Repository Map

- `dwm.c`, `drw.c`, `util.c`, `tomlparser.c`: window-manager sources.
- `config.def.h`: version-controlled default compile-time configuration.
- `config.h`: local build configuration. Do not overwrite user changes.
- `config.mk`: compiler, include, library, and installation settings.
- `Makefile`: build, install, uninstall, and release targets.
- `config/`: application configuration and default TOML runtime settings.
- `scripts/`: session startup, dependency checks, desktop helpers, and
  operational scripts.
- `install.sh`, `install-arm.sh`: existing Arch-focused installers. Any
  portability work must either generalize or replace these without breaking
  documented Arch workflows.
- `dwm.desktop`: display-manager X session entry.
- `docs/`: user documentation and roadmap material.

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
- Keep optional desktop components optional. The absence of Picom,
  Dunst, a wallpaper, or a preferred terminal must not crash dwm.
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
  required feature and is available on all supported distribution families.
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
