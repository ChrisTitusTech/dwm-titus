# LightDM Slick Greeter - dwm-titus

A modern LightDM login screen using the distribution's Slick Greeter package
with a Nord colour palette, blurred background, and the MesloLGS NF font.

The main installer selects the distribution-specific package names. Arch uses
`lightdm-slick-greeter`; Fedora and other RHEL-family systems use
`slick-greeter`. The dwm-titus LightDM install target renders
`lightdm.conf` with the matching greeter session name for the detected
distribution family.

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

The direct `make install` default is Arch-compatible. For Fedora, Rocky,
AlmaLinux, or RHEL, use `install.sh` so the installer passes the RHEL-family
LightDM settings.

## Customisation

Edit `slick-greeter.conf` before running `sudo make install`:

- **background** — path to a wallpaper image
- **font-name** — any font already installed on the system
- **clock-format** — strftime-style format string
- **theme-name** — GTK theme for the panel (e.g. `Adwaita-dark`)
- **show-clock** / **show-hostname** — toggle status bar items
- **activate-numlock** — enable only when `numlockx` is installed
