# dwm-titus Project Specification

## 1. Product Definition

dwm-titus is a maintained, opinionated fork of suckless dwm for X11. It
combines a small C window-manager core with runtime-configurable hotkeys,
themes, and window rules, plus a Quickshell shell layer and optional desktop
helpers such as Rofi, Picom, and supporting scripts.

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

Quickshell configuration is a managed shell-layer artifact owned by dwm-titus.
During installation, `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` must be
replaced from the tracked `config/quickshell/` directory so the running shell
does not fall behind repository behavior. User-owned dwm TOML files remain
preserved, but users should not place unrelated personal configuration under
the dwm-titus-managed Quickshell directory. Quickshell integrations must use
event-driven updates whenever a state source provides a signal, subscription,
watch mode, IPC stream, or service API. Polling timers are acceptable only for
inherently sampled values, such as a clock or CPU load, or as documented
fallbacks when no event source exists. The managed Quickshell shell must remain
low overhead while idle: hidden launcher UI must not continuously filter or
render application models, timer-triggered helper processes must not overlap,
and only one shell provider should run in the dwm-titus session. On X11, a
single managed `PanelWindow` is the expected panel shape unless a per-screen
Quickshell `Variants` design is explicitly profiled and shown not to consume
idle CPU.

### 5.3 Session Startup

The project must support:

- A display-manager session installed as `dwm.desktop`.
- A `startx` flow whose `.xinitrc` launches dwm in a D-Bus session.
- Startup without Picom, a wallpaper, or a polkit agent.
- Detection of common polkit agent locations across `/usr/lib`,
  `/usr/lib64`, and `/usr/libexec` layouts.
- Startup helpers that do not create duplicate long-running processes when the
  session is restarted.

Missing optional components must be logged or skipped without terminating dwm.

### 5.4 Quickshell Launcher

The Quickshell shell layer must provide an X11-compatible application launcher
that can become the normal app-launching workflow while Rofi remains available
as a fallback during migration.

The launcher must:

1. Open, close, and toggle through Quickshell IPC so dwm keybindings can
   control it without depending on Wayland global shortcuts.
2. Index desktop applications from the XDG `.desktop` application directories.
3. Ignore hidden, `NoDisplay=true`, and non-application desktop entries.
4. Provide a search-first UI with keyboard focus on open.
5. Filter by application name, generic name, and comment.
6. Support keyboard navigation, mouse activation, Escape-to-close, and
   close-on-launch behavior.
7. Launch applications through a helper that prefers standard desktop-entry
   launchers when available and preserves a terminal fallback for
   `Terminal=true` entries.
8. Avoid Wayland-only shell, compositor, layer-shell, or global-shortcut APIs.
9. Release application-list resources while closed so the launcher does no
   repeated filtering or rendering work when hidden.

The launcher may follow a modular QML structure with small helper scripts,
IPC-facing open/close/toggle functions, and reusable list/delegate patterns,
but X11/EWMH behavior remains the compatibility boundary for this project.

### 5.5 Installer

The supported installation flow must:

1. Read `/etc/os-release` and select a Debian, Arch, or RHEL adapter.
2. Resolve family-specific package names from one maintained dependency map.
3. Show required and optional packages before installing them.
4. Install only missing required packages unless the user requests a broader
   desktop setup.
5. Create a missing `config.h` from guided compile-time questions, or detected
   and documented defaults for an unattended installation. Preserve an
   existing `config.h`.
6. Build dwm with the system compiler and detected X11 flags.
7. Install the binary, man page, X session file, scripts, and default
   configuration.
8. Seed missing user configuration while preserving existing files.
9. Set ownership to the invoking user for files in that user's home.
10. Support repeated execution without destructive side effects.
11. Print a summary, skipped optional features, and actionable next steps.

The installer must not require an AUR helper. On RHEL-family systems it may
explain when an optional component requires EPEL or another repository, but it
must not enable third-party repositories without user confirmation.

### 5.6 Build System

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

### 5.7 Quickshell QML Development Tooling

Quickshell QML files are part of the maintained source tree. Systems used to
edit this project should provide both the stock Qt QML tools and a
Quickshell-aware language server:

- `qmllint` is the baseline syntax/static check for individual QML files.
- `qmlls` is the stock Qt QML language server and remains useful for generic
  Qt/QML projects.
- `qml-language-server` from `cushycush/qml-language-server` is the preferred
  editor language server for this repository because it understands Quickshell
  imports, singletons, types, snippets, and workspace QML components.

The Qt tools are installed from distribution packages:

| Family | Package examples |
| --- | --- |
| Debian | `qt6-declarative-dev-tools` |
| Arch | `qt6-declarative` |
| RHEL/Fedora | `qt6-qtdeclarative-devel` |

Some distributions install Qt helper binaries outside the default `PATH`, such
as `/usr/lib/qt6/bin`. Development environments should either add that
directory to `PATH` or create user/system symlinks for `qmllint` and `qmlls`.
On Fedora/RHEL-family systems the executable may also be named `qmllint-qt6`.

`qmllint` must be run with explicit Qt and Quickshell QML import roots. Without
those roots it can report false import failures for modules such as
`Quickshell`, even when the shell runs correctly. Typical roots are:

| Family | Common QML import roots |
| --- | --- |
| Debian | `/usr/lib/*/qt6/qml`, `/usr/lib/qt6/qml` |
| Arch | `/usr/lib/qt6/qml` |
| RHEL/Fedora | `/usr/lib64/qt6/qml`, `/usr/lib/qt6/qml` |
| Nix | `${qtdeclarative}/lib/qt-6/qml`, `${quickshell}/lib/qt-6/qml` |

Language-server environments should expose the same roots:

```sh
export QMLLS_BUILD_DIRS="/usr/lib64/qt6/qml:/usr/lib/qt6/qml"
export QML_IMPORT_PATH="$PWD/config/quickshell"
```

The repository uses `import qs.core` for local shared QML helpers under
`config/quickshell/core/`. Quickshell resolves that module at runtime from the
configuration root, but stock `qmllint` may require a `qmldir` module map. Use
a temporary lint-only import tree rather than changing the runtime layout:

```sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/qs/core"
ln -s "$PWD/config/quickshell/core/Commands.qml" "$tmp/qs/core/Commands.qml"
ln -s "$PWD/config/quickshell/core/Icons.qml" "$tmp/qs/core/Icons.qml"
ln -s "$PWD/config/quickshell/core/Theme.qml" "$tmp/qs/core/Theme.qml"
ln -s "$PWD/config/quickshell/core/ShellButton.qml" "$tmp/qs/core/ShellButton.qml"
ln -s "$PWD/config/quickshell/core/ShellSurface.qml" "$tmp/qs/core/ShellSurface.qml"
ln -s "$PWD/config/quickshell/core/SectionLabel.qml" "$tmp/qs/core/SectionLabel.qml"
cat >"$tmp/qs/core/qmldir" <<'EOF'
module qs.core
singleton Commands 1.0 Commands.qml
singleton Icons 1.0 Icons.qml
singleton Theme 1.0 Theme.qml
ShellButton 1.0 ShellButton.qml
ShellSurface 1.0 ShellSurface.qml
SectionLabel 1.0 SectionLabel.qml
EOF

QMLLS_BUILD_DIRS="/usr/lib64/qt6/qml:/usr/lib/qt6/qml" \
QML_IMPORT_PATH="$PWD/config/quickshell" \
qmllint-qt6 \
  -I /usr/lib64/qt6/qml \
  -I /usr/lib/qt6/qml \
  -I "$tmp" \
  -I config/quickshell \
  config/quickshell/controls/ControlsModel.qml
```

When using Nix, the same rule applies: include both the Qt declarative QML root
and the Quickshell QML root in the lint command or `QMLLS_BUILD_DIRS`. This
matches the known workaround for `qmllint`/`qmlls` not discovering Quickshell
type declarations automatically.

Install the Quickshell-aware server with one of these supported methods:

```sh
# Arch-family systems with a working AUR helper
yay -S qml-language-server-bin

# Nix systems
nix run github:cushycush/qml-language-server

# Source build on any system with Go 1.26.1 or newer
git clone https://github.com/cushycush/qml-language-server.git
cd qml-language-server
make build
make install
```

For non-AUR systems that do not use Nix, install the matching prebuilt release
archive from `https://github.com/cushycush/qml-language-server/releases` and
place the binary in a developer `PATH` directory such as
`${HOME}/.local/bin/qml-language-server` or `/usr/local/bin/qml-language-server`.

Editor configuration must prefer `qml-language-server` for this repository's
QML files. Zed users should install the QML extension for language registration,
copy `.zed/settings.example.json` to `.zed/settings.json`, and configure its
`qml` language server binary to the absolute local path of
`qml-language-server`; Zed requires an absolute `lsp.qml.binary.path`. The
active `.zed/settings.json` file is intentionally local-only because that path
differs by machine. Other LSP-capable editors should run `qml-language-server`
for `*.qml` files and use the repository root, `shell.qml`, or `.git` as the
workspace root marker.

Plain `qmllint` is not considered a complete Quickshell validation pass because
it does not understand every Quickshell-specific module shape. Runtime
validation still requires loading the managed shell with `quickshell --path`
and exercising the relevant IPC targets.

### 5.8 Dependency Mapping

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
- Recommended desktop: Quickshell, Rofi, Picom, Feh, Dex, a polkit agent,
  notification tools, audio controls, screenshot tooling, and Nerd/emoji fonts.
- Optional: file manager, network tray, theme utilities, display-manager
  greeter customization, wallpapers, and hardware-specific helpers.

### 5.9 System Health Dashboard

The Control Center must open System Health as a separate full-screen
Quickshell window on the selected X11 monitor. The dashboard must remain
on-demand: opening or explicitly refreshing it starts a bounded snapshot, and
closing it stops active diagnostics. It must not add idle polling.

The snapshot must provide an overall state and categorized details for:

- Current-boot journal and kernel errors, with `journalctl` preferred and
  privileged `dmesg` used as a fallback.
- Failed system and user services, time synchronization, networking, audio,
  and the dwm-titus desktop session.
- Memory, pressure, load, swap, local filesystem capacity, inode use,
  read-only mounts, and available battery, thermal, and drive-health data.
- Required and optional dwm-titus commands, libraries, configuration, and the
  distribution package database.

The dashboard must begin user-readable checks immediately and request a
privileged read-only scan. It must first use non-interactive `sudo` when the
session already has cached or `NOPASSWD` authorization; otherwise it must use
the running polkit agent and trusted installed helper for graphical
authorization. Denied, cancelled, or unavailable authorization must produce a
clearly incomplete report rather than prevent the dashboard from opening.
Journal evidence must be bounded while retaining the total matching count.

Boot-journal and kernel-error rows with matching entries must provide Copy and
Export actions. Copy uses the X11 clipboard through `xclip`. Export writes the
displayed bounded evidence to a private, non-overwriting timestamped file in
the invoking user's home directory, using `boot$DATE.txt` or
`kernel-errors$DATE.txt` naming.

Repairs require an explicit confirmation. User repairs are limited to known
desktop and audio components plus launching the interactive dependency flow.
Failed user and system services are displayed as individual rows with Start,
Stop, Restart, Disable, and Enable actions. A service action is allowed only
while that exact `.service` unit is in the corresponding failed-unit set;
system actions require polkit authorization. Other privileged repairs are
limited to NetworkManager, Bluetooth, and the detected systemd
time-synchronization provider. Filesystem repair, cleanup, reboot, and
unattended package changes are not allowed.
Only a root-owned, non-writable system installation of the health helper may
itself be executed through `sudo` or `pkexec`; repository and XDG copies must
never be elevated. Without an installed helper, the unprivileged copy may use
non-interactive `sudo` to execute only validated root-owned system commands
needed for a bounded scan or confirmed repair.

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
- Multi-monitor setup must expose EWMH tags correctly to Quickshell and EWMH
  inspection tools.
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
- EWMH integration works with Quickshell or an equivalent inspection tool.
- With the launcher closed, the managed Quickshell process remains near idle
  in a short CPU sample, and no second Quickshell-based shell provider is
  running in the same session.
- Multi-monitor behavior is tested where suitable hardware or nested displays
  are available.

## 10. Current Gap

The primary installer contains Debian-, Arch-, and Fedora/RHEL-family package
mappings. The build uses `pkg-config`, supports staged installation with
`DESTDIR`, and avoids writing user configuration during package builds.

Arch ARM handling is part of the primary installer; some manual package
examples remain Arch-specific. Debian package resolution and clean compilation
have been validated in a Debian 13 container, but a real Debian X11 session has
not been tested. Complete runtime validation on Debian and non-Fedora RHEL
derivatives remains required before describing those environments as
universally verified.

## 11. Definition of Done

A portability change is complete when:

- Its behavior is implemented for all three distribution families or is
  explicitly scoped as preparatory work.
- Existing Arch behavior remains functional.
- Relevant automated and manual validation is recorded.
- User-facing installation and troubleshooting documentation is updated.
- No existing user configuration is overwritten.
- Known limitations and untested platforms are stated precisely.
