<div align="center">
  <img src="./dwm-logo-bordered.png" alt="dwm-logo-bordered" width="195" height="90"/>

  # dwm - dynamic window manager
  ### dwm is an extremely ***fast***, ***small***, and ***dynamic*** window manager for X.

</div>

---

This is a **heavily modified** version of dwm based on the original [suckless.org](https://dwm.suckless.org/) dwm. It includes numerous patches and customizations for a productive, user-friendly X11 desktop on Debian-, Arch-, and Fedora/RHEL-family distributions.

### Patches & Features

- **Quickshell** panel and application launcher for the normal desktop workflow
- **Window swallowing** — terminals absorb child GUI windows
- **EWMH** compliance — proper desktop/tag reporting for external tools
- **Pertag** — independent layouts, master counts, and sizing per tag
- **Cfact** — per-window sizing in tiled layouts
- **Movestack** — reorder windows in the stack with keybinds
- **Systray** — built-in system tray
- **Fullscreen** — actual and fake fullscreen toggle (3-state)
- **Window icons** — title bar icons via `_NET_WM_ICON`
- **Cursor warp** — cursor follows focus across windows/monitors
- **Noborder** — auto-remove borders when only one window is visible
- **Multi-monitor** — Xinerama support with EWMH-aware tags

---

## Install

Choose the path that matches what you are installing:

| Path | Best for | Result |
|------|----------|--------|
| `install.sh` | Existing Debian-, Arch-, Fedora-, or RHEL-family system | Installs dependencies, builds dwm, installs the session, and preserves local config |
| Fedora ISO | Fresh Fedora install | Boots a Fedora installer with dwm-titus Kickstart and this repo embedded |

### Option 1: Install on an Existing System

```bash
git clone https://github.com/ChrisTitusTech/dwm-titus.git
cd dwm-titus

./install.sh --dry-run --non-interactive --profile recommended
./install.sh --profile recommended
```

Profiles:

| Profile | Use when you want |
|---------|-------------------|
| `core` | dwm, required X11/session packages, and one terminal |
| `recommended` | `core` plus Quickshell, Picom, fonts, theming, screenshots, audio, and brightness tools |
| `full` | `recommended` plus optional extras such as file manager integration, portals, wallpapers, and display-manager setup |

The installer detects the distribution from `/etc/os-release`, resolves package
names for the detected family, preserves existing `config.h` and user TOML
files, and installs the managed Quickshell config.

For unattended runs:

```bash
./install.sh --non-interactive --yes --profile recommended
```

### Option 2: Install from the Fedora ISO

Download the latest installer image from the GitHub release:

| ISO | Download |
|-----|----------|
| Standard | [`dwm-titus.iso`](https://github.com/ChrisTitusTech/dwm-titus/releases/latest/download/dwm-titus.iso) |
| NVIDIA | [`dwm-titus-nvidia.iso`](https://github.com/ChrisTitusTech/dwm-titus/releases/latest/download/dwm-titus-nvidia.iso) |
| Checksums | [latest release assets](https://github.com/ChrisTitusTech/dwm-titus/releases/latest) |

Use the NVIDIA ISO when the machine needs the NVIDIA Kickstart and installer
boot arguments. Otherwise use the standard ISO.

Basic flow:

1. Write the ISO to a USB drive.
2. Boot the machine from the USB drive.
3. Choose the Fedora install entry.
4. Complete the installer.
5. Reboot and select the `dwm` session if your display manager asks.

The ISO exposes the embedded checkout at `/run/install/repo/dwm-titus` during
installation and uses the included Fedora Kickstart.

### Starting dwm

With a display manager, log out, select the `dwm` session, and log back in.

With `startx`, run:

```bash
startx
```

After login, use these first:

| Keybind | Action |
|---------|--------|
| <kbd>SUPER</kbd> + <kbd>X</kbd> | Open terminal |
| <kbd>SUPER</kbd> + <kbd>R</kbd> | Toggle Quickshell launcher |
| <kbd>SUPER</kbd> + <kbd>F1</kbd> | Open control center |
| <kbd>SUPER</kbd> + <kbd>/</kbd> | Open keybind viewer |

---

## ⌨️ Keybindings

Press <kbd>SUPER</kbd> + <kbd>/</kbd> inside dwm for an **interactive keybind viewer**.

See [docs/src/keybinds.md](docs/src/keybinds.md) for the full reference.

### Essential Keybinds

| Keybind | Action |
|---------|--------|
| <kbd>SUPER</kbd> + <kbd>X</kbd> | Open terminal |
| <kbd>SUPER</kbd> + <kbd>R</kbd> | Toggle Quickshell launcher |
| <kbd>SUPER</kbd> + <kbd>Q</kbd> | Close window |
| <kbd>SUPER</kbd> + <kbd>J</kbd> / <kbd>K</kbd> | Focus next / previous window |
| <kbd>SUPER</kbd> + <kbd>H</kbd> / <kbd>L</kbd> | Resize master area |
| <kbd>SUPER</kbd> + <kbd>1-9</kbd> / <kbd>0</kbd> | Switch to tag (workspace 10 uses <kbd>0</kbd>) |
| <kbd>SUPER</kbd> + <kbd>Shift</kbd> + <kbd>1-9</kbd> / <kbd>0</kbd> | Move window to tag (workspace 10 uses <kbd>0</kbd>) |
| <kbd>SUPER</kbd> + <kbd>T</kbd> | Tile layout |
| <kbd>SUPER</kbd> + <kbd>F</kbd> | Floating layout |
| <kbd>SUPER</kbd> + <kbd>M</kbd> | Fullscreen |
| <kbd>SUPER</kbd> + <kbd>Space</kbd> | Toggle floating |
| <kbd>SUPER</kbd> + <kbd>Shift</kbd> + <kbd>Q</kbd> | Quit dwm |
| <kbd>SUPER</kbd> + <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Power menu |

---

## 🔧 Configuration

dwm is configured by editing `config.h` and recompiling:

```bash
$EDITOR config.h
make && sudo make install
```

> **Note:** `config.def.h` is the tracked default template. `config.h` is
> ignored by Git and belongs to the local user. If it does not exist, `make`
> creates it from `config.def.h`; pulls and upgrades do not replace it.
> The installer creates it interactively on first installation, asking for
> stable compile-time preferences such as refresh rate, font size, modifier
> key, layout ratio, cursor warp, swallowing, and resize hints.

For unattended installation, the same values can be supplied with
`DWM_REFRESH_RATE`, `DWM_FONT_SIZE`, `DWM_MODKEY`, `DWM_MFACT`, `DWM_NMASTER`,
`DWM_CURSORWARP`, `DWM_SWALLOWFLOATING`, and `DWM_RESIZEHINTS`. Existing
`config.h` files are always preserved.

Key things to customize in `config.h`:
- **`refresh_rate`** — match your monitor (default: 60, set to 120 for high-refresh)
- **`fonts[]`** — font family and size
- **`colors[]`** — color scheme (Nord theme by default in config.h)
- **`autostart[]`** — programs launched on startup
- **`rules[]`** — per-application window rules (floating, tags, terminal detection)
- **`keys[]`** — all keybindings
- **`MODKEY`** — modifier key (`Mod4Mask` = Super, `Mod1Mask` = Alt)

---

## 🔍 Troubleshooting

**Black screen / dwm doesn't start:**
- Run `dwm-diagnostics` and resolve any required X11/session failures.
- Preview required packages with `./install.sh --dry-run --profile core`.
- Check `.xinitrc` exists and ends with `exec dwm`
- Try `startx` from a TTY to see error output

**No status bar / Quickshell missing:**
- Install the recommended desktop layer: `./install.sh --profile recommended`
- Verify the managed shell config exists: `ls ~/.config/quickshell/shell.qml`
- Run manually: `quickshell --no-duplicate`

**Terminal doesn't open (SUPER+X):**
- Install a terminal emulator (`alacritty`, `kitty`, `st`,
  `warp-terminal`, or `xterm`)
- Or set `DWM_TERMINAL` / edit `hotkeys.toml` to use your preferred terminal
- Browser defaults: run `dwm-default-apps browsers`, then
  `dwm-default-apps set-browser <desktop-id>`
- Display profiles: run `dwm-display-profile template` and save optional
  profiles under `~/.config/dwm-titus/display-profiles/`
- Diagnostics: run `dwm-diagnostics` to separate required failures from
  optional degraded desktop features

**Multi-monitor issues:**
- If tags don't switch correctly across monitors, run `dwm-diagnostics`

**Dependency check:**
```bash
bash scripts/check-deps.sh
```

---

## 📁 Project Structure

| Path | Purpose |
|------|---------|
| `config.def.h` | Default configuration template |
| `config.h` | Generated, untracked personal configuration (edit this) |
| `dwm.c` | Main window manager source |
| `Makefile` | Build and install system |
| `.xinitrc` | Startup script for `startx` |
| `dwm.desktop` | Session entry for display managers |
| `install.sh` | Automated installer for Debian, Arch, and Fedora/RHEL families |
| `config/` | Quickshell, terminal, and app configurations |
| `scripts/` | Helper scripts (keybinds viewer, dep checker, etc.) |
| `docs/src/keybinds.md` | Full keybinding reference |
| `docs/ROADMAP.md` | Quickshell migration roadmap |
| `tasks.md` | Active Quickshell migration tasks |
| `docs/RELEASING.md` | Release validation and publication checklist |

---

## Development

Run the repository checks before submitting a change:

```bash
make check
```

This performs a clean portable build, ShellCheck and shfmt validation,
autostart guard tests, staged install/uninstall checks, and release artifact
validation. Use `make native` only for a binary intended for the current
machine; normal builds remain portable across compatible CPUs.

Current implementation tasks are tracked in `tasks.md`. Product scope and
acceptance criteria remain in `SPEC.md`.
