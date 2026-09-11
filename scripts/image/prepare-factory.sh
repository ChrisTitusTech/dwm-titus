#!/bin/bash
# Runs only inside the disposable factory installer target, never on the host.
set -euo pipefail
[[ ${1:-} == --factory-target && -f /etc/dwm-titus-factory-target ]]
[[ $(id -u) == 0 && $(getent passwd imagebuilder | cut -d: -f6) == /home/imagebuilder ]]
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]]
variant=$(cat /etc/dwm-titus-factory-target)
[[ $variant == standard || $variant == nvidia ]]
source_dir=/home/imagebuilder/.local/share/dwm-titus
install -d /usr/share/dwm-titus-image /usr/local/share/fonts/dwm-titus
cp -a "$source_dir"/. /usr/share/dwm-titus-image/
cp -a /home/imagebuilder/.local/share/fonts/. /usr/local/share/fonts/dwm-titus/
# User configuration is generated offline for the real account at installation.
# Install the Flatpak system-wide so it is not tied to the factory account.
# Expanded by the private child shell.
# shellcheck disable=SC2016
if ! flatpak --system info it.mijorus.gearlever >/dev/null 2>&1; then
	dbus-run-session -- sh -ec '
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
flatpak --system remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --system install --noninteractive -y flathub it.mijorus.gearlever
flatpak --system info it.mijorus.gearlever
'
fi
fc-cache -f
rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >/usr/share/dwm-titus-image/rpm-manifest.txt
flatpak --system list --columns=ref:full,active:full >/usr/share/dwm-titus-image/flatpak-manifest.txt
printf 'protocol=1\nvariant=%s\nfedora=44\narchitecture=x86_64\n' "$variant" >/etc/dwm-titus-image
[[ -x /usr/local/bin/dwm && -f /usr/share/xsessions/dwm.desktop ]]
[[ -d /var/lib/flatpak/app/it.mijorus.gearlever ]]
printf 'DWM_FACTORY_PREPARED\n'
