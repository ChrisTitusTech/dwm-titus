<div align="center">
  <img src="./dwm-logo-bordered.png" alt="dwm-logo-bordered" width="195" height="90"/>

  # dwm - dynamic window manager
  ### dwm is an extremely ***fast***, ***small***, and ***dynamic*** window manager for X.

</div>

---

This is a **heavily modified** version of dwm based on the original [suckless.org](https://dwm.suckless.org/) dwm. It includes numerous patches and customizations for a productive, user-friendly desktop on Arch Linux with Xorg.

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
cp config.def.h config.h    # Create your personal config
make
sudo make install
```

#### 3. Install Fonts

Polybar icon fonts (MaterialIcons, Feather) are bundled in `polybar/fonts/`:
```bash
mkdir -p ~/.local/share/fonts
cp -r polybar/fonts/* ~/.local/share/fonts/
fc-cache -fv
```

#### Automated Installer

An install script is provided that handles all of the above:
```bash
./install.sh
```

### Post-Install Setup

**Option A — Display Manager** (SDDM, GDM, LightDM):
Log out, select **dwm** from the session menu, and log back in.

**Option B — startx**:
The installer places `.xinitrc` in your home directory. Start with:
```bash
startx
```

The `.xinitrc` disables screen blanking/DPMS (prevents NVIDIA GPU issues on wake), launches Polybar, and starts dwm.

---

## ⌨️ Keybindings

Press <kbd>SUPER</kbd> + <kbd>/</kbd> inside dwm for an **interactive keybind viewer** (via rofi).

See [docs/src/keybinds.md](docs/src/keybinds.md) for the full reference.

### Essential Keybinds

| Keybind | Action |
|---------|--------|
| <kbd>SUPER</kbd> + <kbd>X</kbd> | Open terminal |
| <kbd>SUPER</kbd> + <kbd>R</kbd> | Launch rofi (app launcher) |
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

> **Note:** `config.def.h` is the clean default template. `config.h` is your personal customization. If `config.h` doesn't exist, `make` will create it from `config.def.h` automatically.

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
- Install a terminal emulator (ghostty, alacritty, kitty, or st)
- Or edit `config.h` → `termcmd[]` to use your preferred terminal

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
| `config.h` | Your personal configuration (edit this) |
| `dwm.c` | Main window manager source |
| `Makefile` | Build and install system |
| `.xinitrc` | Startup script for `startx` |
| `dwm.desktop` | Session entry for display managers |
| `install.sh` | Automated installer (Arch Linux) |
| `polybar/` | Polybar config, themes, and fonts |
| `config/` | Terminal, rofi, and app configurations |
| `scripts/` | Helper scripts (keybinds viewer, dep checker, etc.) |
| `docs/src/keybinds.md` | Full keybinding reference |
| `docs/ROADMAP.md` | Project roadmap and planned features |
