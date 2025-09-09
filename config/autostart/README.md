## Notes on XDG Autostart

Recommend using Flatpak to install programs on startup:

```
flatpak install flathub io.github.flattool.Ignition
```

or you can create your own .desktop file in ~/.config/autostart/

`set-refresh.desktop` Example:

```
[Desktop Entry]
Type=Application
Exec=xrandr --output HDMI-0 --primary --mode 1920x1080 --pos 0x0 --rotate normal --rate 120 --output DP-0 --off --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Set Refresh
```
