#!/bin/bash
# Sanitize the powered-off factory filesystem and validate before capture.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[[ -f /etc/dwm-titus-image && $(id -u) == 0 ]]
[[ $(getent passwd imagebuilder | cut -d: -f6) == /home/imagebuilder ]]
factory_uid=$(id -u imagebuilder)
factory_gid=$(id -g imagebuilder)
userdel --remove imagebuilder
# Factory storage and identities must never be copied onto installed machines.
: >/etc/fstab
: >/etc/machine-id
rm -f /var/lib/dbus/machine-id /var/lib/systemd/random-seed /etc/ssh/ssh_host_*
rm -f /etc/sudoers.d/90-dwm-titus-install /etc/dwm-titus-factory-target
rm -f /etc/adjtime /etc/kernel/cmdline /etc/kernel/entry-token
rm -f /etc/passwd- /etc/shadow- /etc/group- /etc/gshadow-
rm -f /var/lib/systemd/credential.secret
rm -f /etc/pki/akmods/private/private_key.priv /etc/pki/akmods/certs/public_key.der
rm -rf /var/lib/AccountsService/users/* /var/lib/AccountsService/icons/*
rm -rf /etc/NetworkManager/system-connections/* /var/lib/NetworkManager/*
rm -rf /boot/loader/entries/* /boot/grub2/grub.cfg /boot/grub2/grubenv /boot/efi/EFI/fedora/grub.cfg
rm -rf /opt/dwm-titus
rm -rf /root/* /root/.[!.]* /root/..?* /tmp/* /var/tmp/* /var/log/*
rm -rf /var/cache/dnf /var/cache/libdnf5 /var/cache/akmods
printf 'localhost\n' >/etc/hostname
# The factory account owned these files before capture. Never give the first
# installed account write access to system assets or the root-run finish helper.
find /etc /usr /opt /var /boot \( -uid "$factory_uid" -o -gid "$factory_gid" \) -exec chown -h root:root {} +
shared_assets=(/usr/share/dwm-titus-image /usr/local/share/fonts/dwm-titus
	/usr/share/themes/Nordic /usr/share/icons/Capitaine-Cursors*)
chown -R root:root "${shared_assets[@]}"
chmod -R go-w "${shared_assets[@]}"
[[ -z $(find /etc /usr /opt /var /boot \( -uid "$factory_uid" -o -gid "$factory_gid" \) -print -quit) ]]
[[ -z $(find "${shared_assets[@]}" \( ! -user root -o ! -group root -o \( ! -type l -a -perm /022 \) \) -print -quit) ]]
# Reuse the package contract instead of maintaining a second RPM list.
# Loaded from the installed image, not the build host.
# shellcheck disable=SC1091
source /usr/share/dwm-titus-image/scripts/dwm-packages.sh
mapfile -t packages < <({
	dwm_packages fedora full
	dwm_packages fedora terminal
	dwm_packages fedora lightdm
	dwm_packages fedora image-boot
	dwm_packages fedora image-desktop
} | sort -u)
rpm -q "${packages[@]}" >/dev/null
python3 /usr/share/dwm-titus-image/scripts/image/check-packagekit.py
[[ -z $(find /usr/share/dwm-titus-image \( -name '.env' -o -name '.env.*' -o -name '.envrc' \) -print -quit) ]]
missing=0
# maim uses libslop for region selection; RPM resolves its shared dependencies.
for command in dwm quickshell alacritty starship herdr brave-origin sxiv maim xclip xdotool xrandr xset xinput \
	setxkbmap xkbset notify-send xdg-open xdg-mime xdg-user-dir \
	picom feh dex-autostart xsettingsd light-locker light-locker-command \
	nmcli bluetoothctl wpctl pactl playerctl brightnessctl amixer protonrestart \
	flatpak pavucontrol thunar file-roller dconf gsettings \
	busctl systemctl loginctl pkexec jq python3 \
	dwm-screenshot dwm-terminal dwm-default-apps dwm-lock dwm-diagnostics \
	dwm-quickshell-launcher dwm-quickshell-controlcenter; do
	if ! command -v "$command" >/dev/null; then
		printf 'Missing shipped-feature command: %s\n' "$command" >&2
		missing=1
	fi
done
((missing == 0))
sha256sum --check /usr/share/dwm-titus-image/tool-sha256.txt
for command in maim dwm; do
	libraries=$(ldd "$(command -v "$command")")
	if [[ $libraries == *'not found'* ]]; then
		printf '%s\n' "$libraries" >&2
		exit 1
	fi
done
flatpak --system info it.mijorus.gearlever >/dev/null
[[ $(fc-match -f '%{family}' 'MesloLGS Nerd Font Mono') == *Meslo* ]]
[[ -n $(find /boot -maxdepth 1 -name 'vmlinuz-*' -print -quit) ]]
[[ -x /usr/libexec/polkit-mate-authentication-agent-1 ]]
[[ -d /usr/share/themes/Nordic && -f /usr/share/xsessions/dwm.desktop ]]
[[ ! -s /etc/machine-id && ! -s /etc/fstab ]]
[[ -z $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd) ]]
[[ ! -e /etc/sudoers.d/90-dwm-titus-install ]]
if compgen -G '/etc/ssh/ssh_host_*' >/dev/null; then exit 1; fi
printf 'Offline image feature dependencies and factory identity: PASS\n'
