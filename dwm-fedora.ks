# Fedora mutable installer profile for dwm-titus.
#
# Build an installer ISO with scripts/build-dwm-fedora-installer-iso.sh so the
# local checkout is available at /run/install/repo/dwm-titus during install.
# Storage, locale, keyboard layout, timezone, hostname, root password, and user
# creation are intentionally left to the Anaconda UI.

network --bootproto=dhcp --activate

firstboot --disable

bootloader --location=mbr
services --enabled=lightdm,NetworkManager

%packages
@core
@base-x
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

install -d -m 0755 /mnt/sysimage/opt
rm -rf /mnt/sysimage/opt/dwm-titus
cp -a /run/install/repo/dwm-titus /mnt/sysimage/opt/dwm-titus
%end

%post --erroronfail --log=/root/dwm-titus-kickstart.log
set -eu

repo_dir=/opt/dwm-titus
install_sudoers=/etc/sudoers.d/90-dwm-titus-install
target_user=$(
	awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ { print $1; exit }' /etc/passwd
)

if [ -z "$target_user" ]; then
	echo "No installer-created regular user was found. Create a regular user in Anaconda before starting installation." >&2
	exit 1
fi

target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
target_repo_dir="$target_home/.local/share/dwm-titus"

install -d -m 0755 "$target_home/.local/share"
rm -rf "$target_repo_dir"
cp -a "$repo_dir" "$target_repo_dir"
chown -R "$target_user:$target_group" "$target_repo_dir"

install -m 0440 /dev/null "$install_sudoers"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$target_user" > "$install_sudoers"

su - "$target_user" -c 'cd "$HOME/.local/share/dwm-titus" && ./install.sh --non-interactive --profile core'

find /usr/share/xsessions -mindepth 1 -maxdepth 1 -type f ! -name dwm.desktop -delete 2>/dev/null || true
find /usr/share/wayland-sessions -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
systemctl disable initial-setup.service initial-setup-graphical.service 2>/dev/null || true
rm -f "$install_sudoers"
rm -rf "$repo_dir"
systemctl enable lightdm.service
systemctl set-default graphical.target
%end
