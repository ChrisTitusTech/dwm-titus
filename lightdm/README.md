# LightDM Slick Greeter - dwm-titus

A modern LightDM login screen using the distribution's Slick Greeter package
with a Nord colour palette, blurred background, and the MesloLGS NF font.

The main installer selects the distribution-specific package names. Arch uses
`lightdm-slick-greeter`; Fedora and other RHEL-family systems use
`slick-greeter`. The dwm-titus LightDM drop-in selects the `dwm` session while
the distribution package selects the correct greeter session name.

## Files

| File | Destination |
|------|-------------|
| `lightdm.conf` | `/etc/lightdm/lightdm.conf.d/90-dwm-titus.conf` |
| `slick-greeter.conf` | `/etc/lightdm/slick-greeter.conf` |
| `wallpaper.jpg` | `/usr/share/pixmaps/dwm-titus.jpg` |

## Install

The main `install.sh` handles this automatically. To apply manually:

```sh
sudo make install
```

## Customisation

Edit `slick-greeter.conf` before running `sudo make install`:

- **background** — path to a wallpaper image
- **font-name** — any font already installed on the system
- **clock-format** — strftime-style format string
- **theme-name** — GTK theme for the panel (e.g. `Adwaita-dark`)
- **show-clock** / **show-hostname** — toggle status bar items
