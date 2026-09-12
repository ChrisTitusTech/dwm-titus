# Offline compressed-system installation. Rendered by the ISO builder.
# Disk, locale, keyboard, timezone and account selection remain interactive.
firstboot --disable
selinux --disabled
liveimg --url="file:///run/install/repo/images/dwm-rootfs.tar" --checksum="@IMAGE_SHA256@"
bootloader --location=mbr @BOOT_ARGUMENTS@
services --enabled=NetworkManager,lightdm

# Keep the installer bootstrap with the ISO, allowing fixes without rebuilding
# packages. The desktop itself still comes from the checksummed system image.
%post --nochroot --interpreter=/bin/bash --erroronfail --log=/mnt/sysimage/root/dwm-titus-image-bootstrap.log
set -euo pipefail
[[ -f /mnt/sysimage/etc/dwm-titus-image ]]
install -o 0 -g 0 -m 0755 /run/install/repo/dwm-titus/scripts/image/finish-install.sh /mnt/sysimage/usr/share/dwm-titus-image/scripts/image/finish-install.sh
# Refresh seeders only in images that already ship their required tools/config.
# Legacy compressed captures retain their original account defaults.
for helper in seed-terminal.sh seed-apps.sh; do
    target=/mnt/sysimage/usr/share/dwm-titus-image/scripts/image/$helper
    if [[ -f $target ]]; then
        install -o 0 -g 0 -m 0755 /run/install/repo/dwm-titus/scripts/image/$helper "$target"
    fi
done
%end

%post --interpreter=/bin/bash --erroronfail --log=/root/dwm-titus-image-install.log
set -euo pipefail
bash /usr/share/dwm-titus-image/scripts/image/finish-install.sh --installer-target
%end
