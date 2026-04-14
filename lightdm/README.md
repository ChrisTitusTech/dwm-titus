# LightDM GTK Greeter — dwm-titus

A modern LightDM login screen using `lightdm-slick-greeter` with a Nord
colour palette, blurred background, and the MesloLGS NF font.

No extra dependencies beyond what `install.sh` installs
(`lightdm`, `lightdm-slick-greeter`, `ttf-meslo-nerd`).

## Files

| File | Destination |
|------|-------------|
| `lightdm.conf` | `/etc/lightdm/lightdm.conf` |
| `slick-greeter.conf` | `/etc/lightdm/slick-greeter.conf` |
| `wallpaper.jpg` | `/usr/share/pixmaps/dwm-titus.jpg` |

## Install

The main `install.sh` handles this automatically. To apply manually:

```sh
sudo make install
```

## Customisation

Edit `lightdm-gtk-greeter.conf` before running `sudo make install`:

- **background** — path to a wallpaper image
- **font-name** — any font already installed on the system
- **clock-format** — strftime-style format string
- **theme-name** — GTK theme for the panel (e.g. `Adwaita-dark`)
- **show-clock** / **show-hostname** — toggle status bar items
