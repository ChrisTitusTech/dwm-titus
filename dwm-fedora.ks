# Fedora mutable installer profile for dwm-titus.
#
# Build an installer ISO with scripts/build-dwm-fedora-installer-iso.sh so the
# local checkout is available at /run/install/repo/dwm-titus during install.
# Storage, locale, keyboard layout, timezone, hostname, root password, and user
# creation are intentionally left to the Anaconda UI.

network --bootproto=dhcp --activate

firstboot --disable
selinux --disabled

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install
repo --name="fedora-cisco-openh264" --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-cisco-openh264-$releasever&arch=$basearch" --install
repo --name="rpmfusion-free" --metalink="https://mirrors.rpmfusion.org/metalink?repo=free-fedora-$releasever&arch=$basearch" --install
repo --name="rpmfusion-free-updates" --metalink="https://mirrors.rpmfusion.org/metalink?repo=free-fedora-updates-released-$releasever&arch=$basearch" --install
repo --name="rpmfusion-free-tainted" --metalink="https://mirrors.rpmfusion.org/metalink?repo=free-fedora-tainted-$releasever&arch=$basearch" --install
repo --name="rpmfusion-nonfree" --metalink="https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-$releasever&arch=$basearch" --install
repo --name="rpmfusion-nonfree-updates" --metalink="https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-updates-released-$releasever&arch=$basearch" --install
repo --name="rpmfusion-nonfree-tainted" --metalink="https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-tainted-$releasever&arch=$basearch" --install
repo --name="brave-browser" --baseurl="https://brave-browser-rpm-release.s3.brave.com/$basearch" --install
repo --name="mwt-packages" --baseurl="https://mirror.mwt.me/shiftkey-desktop/rpm" --install
repo --name="christitustech-copr-fedora" --baseurl="https://download.copr.fedorainfracloud.org/results/christitustech/copr-fedora/fedora-$releasever-x86_64/" --install

bootloader --location=mbr
services --enabled=NetworkManager

%pre --interpreter=/bin/sh
gaming_packages=/tmp/dwm-titus-gaming-packages
case "$(uname -m)" in
x86_64)
	cat >"$gaming_packages" <<'EOF'
steam
gamescope
gamemode.x86_64
gamemode.i686
mangohud.x86_64
mangohud.i686
EOF
	;;
*)
	: >"$gaming_packages"
	;;
esac
%end

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
%include /tmp/dwm-titus-gaming-packages
quickshell
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
bluez
blueman
libnotify
light-locker
xorg-x11-drv-libinput
dconf
arc-theme
adw-gtk3-theme
numix-gtk-theme
yaru-gtk3-theme
yaru-gtk4-theme
deepin-gtk-theme
bluebird-gtk3-theme
qt6ct
qt5ct
google-noto-color-emoji-fonts
google-noto-sans-mono-fonts
NetworkManager
rsync
Thunar
gvfs
gvfs-smb
tumbler
thunar-archive-plugin
file-roller
xdg-user-dirs
xdg-desktop-portal-gtk
gnome-keyring
nwg-look
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

for repo_key in \
	https://raw.githubusercontent.com/rpmfusion/rpmfusion-free-release/master/RPM-GPG-KEY-rpmfusion-free-fedora-2020 \
	https://raw.githubusercontent.com/rpmfusion/rpmfusion-nonfree-release/master/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020 \
	https://brave-browser-rpm-release.s3.brave.com/brave-core.asc \
	https://mirror.mwt.me/shiftkey-desktop/gpgkey; do
	rpm --import "$repo_key" || echo "Could not import repository key: $repo_key" >&2
done

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

if getent group gamemode >/dev/null 2>&1; then
	usermod -aG gamemode "$target_user"
fi

find /usr/share/xsessions -mindepth 1 -maxdepth 1 -type f ! -name dwm.desktop -delete 2>/dev/null || true
find /usr/share/wayland-sessions -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
systemctl disable initial-setup.service initial-setup-graphical.service 2>/dev/null || true
rm -f "$install_sudoers"
rm -rf "$repo_dir"
if ! systemctl list-unit-files lightdm.service >/dev/null 2>&1; then
	echo "LightDM service was not installed." >&2
	exit 1
fi
systemctl enable lightdm.service
systemctl set-default graphical.target
%end
