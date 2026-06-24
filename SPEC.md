# dwm-titus Project Specification

## 1. Product Definition

dwm-titus is a maintained, opinionated fork of suckless dwm for X11. It
combines a small C window-manager core with runtime-configurable hotkeys,
themes, and window rules, plus an optional desktop layer built around Polybar,
Rofi, Picom, Dunst, and helper scripts.

The product target is one repository and one documented installation workflow
that works across Debian-family, Arch-family, and RHEL-family Linux
distributions without requiring users to translate package names or repair
distribution-specific paths manually.

## 2. Goals

- Build and run dwm-titus on supported Debian, Arch, and RHEL distribution
  families.
- Provide safe, idempotent dependency installation and system integration.
- Preserve the speed, simplicity, and direct configuration model of dwm.
- Provide consistent defaults and core behavior across distributions.
- Support display-manager login and `startx`.
- Support common x86_64 and ARM Linux systems where the required X11 libraries
  are available.
- Keep user configuration under standard XDG paths and preserve it on upgrade.

## 3. Non-Goals

- A Wayland compositor or Wayland-native session.
- Pixel-identical behavior across every theme, driver, display manager, or
  third-party desktop utility.
- Automatic installation of proprietary GPU drivers.
- Automatic bootloader, Plymouth, SELinux policy, firewall, or kernel changes.
- Bundling every optional desktop application.
- Supporting end-of-life distributions whose repositories no longer provide
  the required build dependencies.

## 4. Supported Distribution Contract

The following families are first-class targets:

| Family | Package interface | Representative systems |
| --- | --- | --- |
| Debian | `apt` / `dpkg` | Debian, Ubuntu, Mint, Pop!_OS |
| Arch | `pacman` | Arch Linux, EndeavourOS, Manjaro, Arch Linux ARM |
| RHEL | `dnf` / RPM | RHEL, Rocky Linux, AlmaLinux, Fedora |

A compatible derivative is supported when it:

- Provides the family's standard package interface.
- Provides X11 and the required development libraries.
- Uses conventional FHS and XDG paths.
- Has not reached end of life.

The installer must report the detected distribution ID and family. Unknown
derivatives may continue through a confirmed compatible-family path, but must
not be silently misidentified.

## 5. Functional Requirements

### 5.1 Window Manager

The installed session must provide:

- Standard dwm tiling, floating, monocle, tagging, focus, and monitor behavior.
- Per-tag layout state and sizing.
- EWMH desktop and active-window integration for external bars and tools.
- Xinerama multi-monitor support.
- Window swallowing.
- Per-client size factors and stack reordering.
- Real and fake fullscreen behavior.
- Window icons from `_NET_WM_ICON`.
- Configured border suppression and cursor-warp behavior.
- Stable handling of applications that omit optional X properties.

### 5.2 Runtime Configuration

The product must load user configuration from:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/
```

The supported runtime files are:

- `hotkeys.toml`
- `themes.toml`
- `window-rules.toml`

Changes to these files must reload without restarting dwm when the existing
inotify-based hot reload path is available. Invalid configuration must produce
an actionable error and retain safe defaults or the last valid state.

Compile-time defaults remain in `config.def.h`. An existing `config.h` is user
owned and must not be overwritten during installation or upgrade.

### 5.3 Session Startup

The project must support:

- A display-manager session installed as `dwm.desktop`.
- A `startx` flow whose `.xinitrc` launches dwm in a D-Bus session.
- Startup without Polybar, Picom, Dunst, a wallpaper, or a polkit agent.
- Detection of common polkit agent locations across `/usr/lib`,
  `/usr/lib64`, and `/usr/libexec` layouts.
- Startup helpers that do not create duplicate long-running processes when the
  session is restarted.

Missing optional components must be logged or skipped without terminating dwm.

### 5.4 Installer

The supported installation flow must:

1. Read `/etc/os-release` and select a Debian, Arch, or RHEL adapter.
2. Resolve family-specific package names from one maintained dependency map.
3. Show required and optional packages before installing them.
4. Install only missing required packages unless the user requests a broader
   desktop setup.
5. Build dwm with the system compiler and detected X11 flags.
6. Install the binary, man page, X session file, scripts, and default
   configuration.
7. Seed missing user configuration while preserving existing files.
8. Set ownership to the invoking user for files in that user's home.
9. Support repeated execution without destructive side effects.
10. Print a summary, skipped optional features, and actionable next steps.

The installer must not require an AUR helper. On RHEL-family systems it may
explain when an optional component requires EPEL or another repository, but it
must not enable third-party repositories without user confirmation.

### 5.5 Build System

The build must:

- Use a C99-capable compiler and `make`.
- Honor standard environment overrides including `CC`, `CFLAGS`, `CPPFLAGS`,
  `LDFLAGS`, `PREFIX`, and `DESTDIR`.
- Discover portable compiler and linker flags with `pkg-config` where
  available.
- Avoid mandatory `/usr/X11R6`, `/usr/lib`, or `/usr/lib64` assumptions.
- Produce a working `dwm` binary from a clean checkout.
- Support staged, unprivileged installation through `DESTDIR`.

Required native interfaces and libraries currently include:

- Xlib
- Xft and Fontconfig
- Xinerama
- Xrender
- Imlib2
- Xlib-XCB
- XCB and XCB RES
- freetype headers
- standard Linux/POSIX process and filesystem interfaces

### 5.6 Dependency Mapping

Package names differ by release and derivative. The maintained dependency map
must cover the equivalent of these capabilities:

| Capability | Debian family examples | Arch family examples | RHEL family examples |
| --- | --- | --- | --- |
| Compiler and make | `build-essential`, `pkg-config` | `base-devel`, `pkgconf` | Development Tools, `pkgconf-pkg-config` |
| Xlib development | `libx11-dev` | `libx11` | `libX11-devel` |
| Xft and fonts | `libxft-dev`, `libfontconfig-dev`, `libfreetype-dev` | `libxft`, `fontconfig`, `freetype2` | `libXft-devel`, `fontconfig-devel`, `freetype-devel` |
| Xinerama | `libxinerama-dev` | `libxinerama` | `libXinerama-devel` |
| Xrender | `libxrender-dev` | `libxrender` | `libXrender-devel` |
| Imlib2 | `libimlib2-dev` | `imlib2` | `imlib2-devel` |
| XCB | `libx11-xcb-dev`, `libxcb1-dev`, `libxcb-res0-dev` | `libxcb`, `xcb-util` | `libxcb-devel`, `xcb-util-devel` |

These are capability mappings, not immutable package lists. Package availability
must be validated against each tested release.

Runtime dependencies are classified as:

- Core: an X11 server/session, D-Bus session support, one usable terminal, and
  the tools required by configured core keybindings.
- Recommended desktop: Polybar, Rofi, Picom, Dunst, Feh, Dex, a polkit agent,
  notification tools, audio controls, screenshot tooling, and Nerd/emoji
  fonts.
- Optional: file manager, network tray, theme utilities, display-manager
  greeter customization, wallpapers, and hardware-specific helpers.

## 6. Filesystem and Installation Contract

Default system installation locations:

```text
${PREFIX}/bin/dwm
${PREFIX}/share/man/man1/dwm.1
/usr/share/xsessions/dwm.desktop
```

Default user locations:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/
${XDG_CONFIG_HOME:-$HOME/.config}/polybar/
${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus/
```

System paths must be overridable for packaging and staged installs. User data
must not be written during a package build using `DESTDIR`.

Uninstall must remove only files owned by this project. It must preserve user
configuration and unrelated application configuration by default.

## 7. User Experience Requirements

- The default session must remain usable when optional visual components fail.
- Error messages must identify the missing command, library, package
  capability, or file and provide the next action.
- The terminal command must select an installed supported terminal or provide a
  clear configuration path.
- Font aliases must accommodate common Meslo Nerd Font naming differences.
- Multi-monitor setup must expose EWMH tags correctly to Polybar.
- Defaults should work at 1080p and remain usable at lower and higher
  resolutions.
- Installation output must be readable in both interactive terminals and logs.

## 8. Security and Safety Requirements

- Do not execute remote scripts through a shell as part of the required
  installation path.
- Do not download or execute unverified binaries.
- Do not run user configuration or desktop helpers as root.
- Quote paths and arguments that may contain whitespace.
- Prevent command injection through distribution metadata, configuration
  values, filenames, and environment variables.
- Avoid broad recursive ownership or permission changes outside project-owned
  directories.
- Preserve existing user files or create explicit backups before replacement.

## 9. Validation and Acceptance Criteria

A release is cross-distro ready only when all of the following pass:

### 9.1 Static Validation

- Clean C build with warnings enabled.
- Shell syntax checks for every changed shell script.
- ShellCheck and shfmt checks, with documented justified exceptions.
- No generated build artifacts unintentionally included in the change.

### 9.2 Distribution Validation

On at least one current representative of each family:

- Distro detection selects the correct adapter.
- Required package mapping resolves to installable packages.
- A clean checkout builds successfully.
- `make install DESTDIR=<staging-dir>` installs the expected system files
  without writing to the test user's home.
- The real installer preserves pre-existing user configuration.
- Dependency checks report both missing and satisfied capabilities correctly.

### 9.3 Runtime Validation

In a real or nested X11 session:

- dwm starts and can launch a terminal.
- Tiling, floating, tags, focus, and close-window actions work.
- Runtime TOML configuration loads and reloads.
- A display-manager session and `startx` path both launch.
- Missing optional desktop processes do not terminate the session.
- EWMH integration works with Polybar or an equivalent inspection tool.
- Multi-monitor behavior is tested where suitable hardware or nested displays
  are available.

## 10. Current Gap

The primary installer supports Arch and Fedora/RHEL-family package mappings.
The ARM installer, dependency checker, and some manual README instructions
remain Arch-specific. The build also contains fixed X11 path assumptions.

Therefore, Debian-family support and complete validation on non-Fedora RHEL
derivatives remain project targets. Support may be claimed only after the
acceptance criteria above are met and documented.

## 11. Definition of Done

A portability change is complete when:

- Its behavior is implemented for all three distribution families or is
  explicitly scoped as preparatory work.
- Existing Arch behavior remains functional.
- Relevant automated and manual validation is recorded.
- User-facing installation and troubleshooting documentation is updated.
- No existing user configuration is overwritten.
- Known limitations and untested platforms are stated precisely.
