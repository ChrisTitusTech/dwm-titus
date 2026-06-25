<div align="center">
  <img src="./dwm-logo-bordered.png" alt="dwm-logo-bordered" width="195" height="90"/>

  # dwm - dynamic window manager
  ### dwm is an extremely ***fast***, ***small***, and ***dynamic*** window manager for X.

</div>

---

This is a **heavily modified** version of dwm based on the original [suckless.org](https://dwm.suckless.org/) dwm. It includes numerous patches and customizations for a productive, user-friendly X11 desktop on Debian-, Arch-, and Fedora/RHEL-family distributions.

### Patches & Features

- **Polybar** integration (replaces dwm built-in bar)
- **Window swallowing** — terminals absorb child GUI windows
- **EWMH** compliance — proper desktop/tag reporting for external tools
- **Pertag** — independent layouts, master counts, and sizing per tag
- **Cfact** — per-window sizing in tiled layouts
- **Movestack** — reorder windows in the stack with keybinds
- **Systray** — built-in system tray (disabled by default when using Polybar)
- **Fullscreen** — actual and fake fullscreen toggle (3-state)
- **Window icons** — title bar icons via `_NET_WM_ICON`
- **Cursor warp** — cursor follows focus across windows/monitors
- **Noborder** — auto-remove borders when only one window is visible
- **Multi-monitor** — Xinerama support with per-monitor Polybar bars

---

## 📋 Install

### Quick Install (Recommended)

Use [Linutil](https://christitus.com/linux) for automated setup:

```bash
curl -fsSL https://christitus.com/linux | sh
```

<img width="1839" height="1000" alt="image" src="https://github.com/user-attachments/assets/314f9a40-4ccb-4c34-b3d2-dcfee63c278b" />

Select `dwm`, `rofi`, `bash prompt`, and `ghostty` using the `v` key, then press `Enter`.

### Manual Install

#### 1. Install Dependencies

**Build dependencies** (required to compile):
```bash
sudo pacman -S --needed base-devel libx11 libxft libxinerama imlib2 libxcb xcb-util freetype2 fontconfig
```

**Xorg**:
```bash
sudo pacman -S --needed xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset
```

**Runtime dependencies** (desktop experience):
```bash
sudo pacman -S --needed rofi picom dunst feh flameshot dex mate-polkit alsa-utils noto-fonts-emoji ttf-meslo-nerd
```

**Terminal emulator** (at least one):
```bash
# Pick one — ghostty is the default in config.h
sudo pacman -S ghostty   # or: alacritty, kitty
```

**Polybar** (status bar):
```bash
sudo pacman -S polybar
```

#### 2. Clone and Build

```bash
git clone https://github.com/ChrisTitusTech/dwm-titus.git
cd dwm-titus
make                       # Creates config.h from config.def.h when missing
sudo make install
```

#### 3. Install Fonts

Polybar icon fonts (MaterialIcons, Feather) are bundled in `polybar/fonts/`:
```bash
mkdir -p ~/.local/share/fonts
cp -r polybar/fonts/* ~/.local/share/fonts/
fc-cache -fv
```

`make install` now also writes a local fontconfig alias file so both naming variants
`MesloLGS NF` and `MesloLGS Nerd Font` resolve correctly across different Linux distributions.
It also installs the bundled Capitaine dark and light cursor themes. Theme reloads
select `Capitaine-Cursors-White` for dark themes and `Capitaine-Cursors` for light themes.

#### Automated Installer

The installer detects Debian-, Arch-, and Fedora/RHEL-family systems:
```bash
./install.sh
```

On Fedora it installs the required X11 development libraries and desktop
packages with `dnf`. MesloLGS Nerd Font is downloaded from the pinned Nerd
Fonts v3.4.0 release, checksum-verified, and installed under
`~/.local/share/fonts/Meslo/`. If no supported terminal is installed, the
installer selects Alacritty or Kitty from the enabled distribution
repositories. It does not enable third-party repositories.

### Post-Install Setup

**Option A — Display Manager** (SDDM, GDM, LightDM):
Log out, select **dwm** from the session menu, and log back in.

**Option B — startx**:
The installer places `.xinitrc` in your home directory. Start with:
```bash
startx
```

The `.xinitrc` disables screen blanking/DPMS (prevents NVIDIA GPU issues on wake), launches Polybar, and starts dwm.

On x86_64, the installer downloads the latest Vicinae AppImage from the
official GitHub release, verifies the release-provided SHA-256 digest, extracts
it, enables `vicinae.service` for the current user, and uses Vicinae for
<kbd>SUPER</kbd> + <kbd>R</kbd>. Rofi remains available on
<kbd>SUPER</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd> and is still used by the
control center and keybind viewer. If the optional download fails, installation
continues without Vicinae.

---

## ⌨️ Keybindings

Press <kbd>SUPER</kbd> + <kbd>/</kbd> inside dwm for an **interactive keybind viewer** (via rofi).

See [docs/src/keybinds.md](docs/src/keybinds.md) for the full reference.

### Essential Keybinds

| Keybind | Action |
|---------|--------|
| <kbd>SUPER</kbd> + <kbd>X</kbd> | Open terminal |
| <kbd>SUPER</kbd> + <kbd>R</kbd> | Toggle Vicinae |
| <kbd>SUPER</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd> | Launch rofi |
| <kbd>SUPER</kbd> + <kbd>Q</kbd> | Close window |
| <kbd>SUPER</kbd> + <kbd>J</kbd> / <kbd>K</kbd> | Focus next / previous window |
| <kbd>SUPER</kbd> + <kbd>H</kbd> / <kbd>L</kbd> | Resize master area |
| <kbd>SUPER</kbd> + <kbd>1-9</kbd> | Switch to tag (workspace) |
| <kbd>SUPER</kbd> + <kbd>Shift</kbd> + <kbd>1-9</kbd> | Move window to tag |
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
- Verify Xorg is installed: `pacman -Q xorg-server xorg-xinit`
- Check `.xinitrc` exists and ends with `exec dwm`
- Try `startx` from a TTY to see error output

**No status bar / Polybar missing:**
- Install polybar: `sudo pacman -S polybar`
- Check fonts are installed: `fc-list | grep -i meslo`
- Verify polybar config: `ls ~/.config/polybar/`

**Missing icons in Polybar:**
- Install icon fonts: `cp -r polybar/fonts/* ~/.local/share/fonts/ && fc-cache -fv`

**Terminal doesn't open (SUPER+X):**
- Install a terminal emulator (`ghostty`, `alacritty`, `kitty`, `st`,
  `warp-terminal`, or `xterm`)
- Or set `DWM_TERMINAL` / edit `hotkeys.toml` to use your preferred terminal

**Multi-monitor issues:**
- Polybar auto-detects monitors via `xrandr`
- Primary monitor gets systray + EWMH tags; secondary monitors get a simpler bar
- If tags don't switch correctly across monitors, check `debug_ewmh.sh`

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
| `polybar/` | Polybar config, themes, and fonts |
| `config/` | Terminal, rofi, and app configurations |
| `scripts/` | Helper scripts (keybinds viewer, dep checker, etc.) |
| `docs/src/keybinds.md` | Full keybinding reference |
| `docs/ROADMAP.md` | Project roadmap and planned features |
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

Current implementation tasks are tracked in `TASKS.md`. Product scope and
acceptance criteria remain in `SPEC.md`.
