# Fedora mutable installer profile for dwm-titus.
#
# Build an installer ISO with scripts/build-dwm-fedora-installer-iso.sh so the
# local checkout is available at /run/install/repo/dwm-titus during install.
# Storage is intentionally left to the Anaconda UI.

lang en_US.UTF-8
keyboard --xlayouts='us'
timezone America/Chicago --utc
network --bootproto=dhcp --activate

rootpw --lock
user --name=titus --groups=wheel --lock --gecos="dwm-titus user"
firstboot --enable

bootloader --location=mbr
services --enabled=lightdm,NetworkManager

%packages
@core
@base-x
initial-setup
sudo
git
curl
unzip
make
gcc
pkgconf-pkg-config
libX11-devel
libXft-devel
libXinerama-devel
libXrender-devel
imlib2-devel
libxcb-devel
xcb-util-devel
freetype-devel
fontconfig-devel
xorg-x11-server-Xorg
xorg-x11-xinit
xrandr
xset
xsetroot
dbus-x11
procps-ng
psmisc
xclip
xdotool
xprop
xdg-utils
lightdm
slick-greeter
alacritty
kitty
picom
feh
flameshot
dex-autostart
mate-polkit
alsa-utils
brightnessctl
pulseaudio-utils
pipewire
pipewire-pulseaudio
wireplumber
pavucontrol
libnotify
light-locker
xorg-x11-drv-libinput
dconf
google-noto-color-emoji-fonts
google-noto-sans-mono-fonts
NetworkManager
rsync
%end

%post --nochroot --erroronfail --log=/mnt/sysimage/root/dwm-titus-copy.log
set -eu

install -d -m 0755 /mnt/sysimage/home/titus/.local/share
rm -rf /mnt/sysimage/home/titus/.local/share/dwm-titus
cp -a /run/install/repo/dwm-titus /mnt/sysimage/home/titus/.local/share/dwm-titus
%end

%post --erroronfail --log=/root/dwm-titus-kickstart.log
set -eu

repo_dir=/home/titus/.local/share/dwm-titus
install_sudoers=/etc/sudoers.d/90-dwm-titus-install

chown -R titus:titus "$repo_dir"
install -m 0440 /dev/null "$install_sudoers"
printf 'titus ALL=(ALL) NOPASSWD: ALL\n' > "$install_sudoers"

su - titus -c 'cd "$HOME/.local/share/dwm-titus" && ./install.sh --non-interactive --profile core'

rm -f "$install_sudoers"
systemctl enable lightdm.service
systemctl set-default graphical.target
%end
