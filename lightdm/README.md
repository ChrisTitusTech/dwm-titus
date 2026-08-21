# LightDM Slick Greeter - dwm-titus

A modern Fedora LightDM login screen using Slick Greeter with a Nord colour
palette, blurred background, and the MesloLGS NF font.

The Fedora installer uses `slick-greeter`. The dwm-titus LightDM install target
renders the matching Fedora `lightdm.conf`.

## Files

| File | Destination |
|------|-------------|
| `lightdm.conf` | `/etc/lightdm/lightdm.conf` |
| `slick-greeter.conf` | `/etc/lightdm/slick-greeter.conf` |
| `wallpaper.png` | `/usr/share/pixmaps/dwm-titus.png` |

## Install

The main `install.sh` handles this automatically. To apply manually:

```sh
sudo make install
```

The direct `make install` defaults match Fedora. Prefer the top-level
`install.sh` for a complete installation.

## Customisation

Edit `slick-greeter.conf` before running `sudo make install`:

- **background** — path to a wallpaper image
- **font-name** — any font already installed on the system
- **clock-format** — strftime-style format string
- **theme-name** — GTK theme for the panel (e.g. `Adwaita-dark`)
- **show-clock** / **show-hostname** — toggle status bar items
- **activate-numlock** — enable only when `numlockx` is installed
