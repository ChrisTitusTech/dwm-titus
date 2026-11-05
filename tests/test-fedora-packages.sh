#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

for command_name in dnf sort comm awk; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Missing required Fedora package-check command: %s\n' \
			"$command_name" >&2
		exit 1
	fi
done

# shellcheck source=scripts/dwm-utils.sh
source "$repo/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

if [[ $DISTRO_ID != fedora || $DISTRO_FAMILY != fedora ]]; then
	printf 'Fedora package validation requires Fedora; detected %s.\n' \
		"$DISTRO_NAME" >&2
	exit 1
fi

mapfile -t packages < <(
	{
		dwm_packages fedora required
		dwm_packages fedora image-factory
		dwm_packages fedora image-boot
		# Official image additions; brave-origin is resolved by factory repos.
		dwm_packages fedora image-desktop | awk '$0 != "brave-origin"'
		dwm_packages fedora desktop
		dwm_packages fedora recommended
		dwm_packages fedora ci-smoke
		dwm_packages fedora qml-validation
		dwm_packages fedora wifi
		DWM_IMAGE_FEDORA_RELEASE="$VERSION_ID" dwm_packages fedora theme-gtk
		dwm_packages fedora system-management
		dwm_packages fedora system-management-optional
	} | awk 'NF' | sort -u
)
if ((${#packages[@]} == 0)); then
	printf 'Fedora package map returned no required, desktop, or image packages.\n' >&2
	exit 1
fi

printf '%s\n' "${packages[@]}" >"$work/expected"
dnf -q repoquery --available --latest-limit 1 \
	--queryformat $'%{name}\n' "${packages[@]}" |
	sort -u >"$work/available"
comm -23 "$work/expected" "$work/available" >"$work/missing"
if [[ -s $work/missing ]]; then
	printf 'Unavailable Fedora package-map entries:\n' >&2
	sed 's/^/  /' "$work/missing" >&2
	exit 1
fi

mkdir -p "$work/bin"
cat >"$work/bin/rpm" <<'EOF'
#!/bin/sh
[ "$*" = '-q --whatprovides ppd-service' ] || exit 2
[ "${DWM_TEST_PPD_PROVIDER:-0}" = 1 ]
EOF
chmod +x "$work/bin/rpm"

installed_provider_packages=$(PATH="$work/bin:$PATH" DWM_TEST_PPD_PROVIDER=1 bash -c '
	. "$1"
	DISTRO_FAMILY=fedora
	install_packages() { printf "%s\n" "$@"; }
	dwm_install_package_profile desktop
' _ "$repo/scripts/dwm-packages.sh")
if printf '%s\n' "$installed_provider_packages" | grep -Fxq power-profiles-daemon; then
	printf 'Existing Power Profiles provider would be replaced.\n' >&2
	exit 1
fi
printf '%s\n' "$installed_provider_packages" | grep -Fxq upower
printf '%s\n' "$installed_provider_packages" | grep -Fxq dbus-tools
printf '%s\n' "$installed_provider_packages" | grep -Fxq inotify-tools
printf '%s\n' "$installed_provider_packages" | grep -Fxq xsettingsd
# Drain each producer under pipefail; grep -q can close a successful match early.
for package in PackageKit PackageKit-glib python3-gobject python3-rpm accountsservice cups system-config-printer; do
	dwm_packages fedora system-management | grep -Fx "$package" >/dev/null
	dwm_packages fedora recommended | grep -Fx "$package" >/dev/null
done
for package in lxqt-admin dnfdragora; do
	dwm_packages fedora system-management-optional | grep -Fx "$package" >/dev/null
	dwm_packages fedora optional | grep -Fx "$package" >/dev/null
done
for package in xsettingsd xkbset bubblewrap libseccomp NetworkManager-wifi wpa_supplicant wireless-regdb; do
	dwm_packages fedora source-update | grep -Fx "$package" >/dev/null
done
for profile in runtime-required required full source-update; do
	for package in gnome-keyring gnome-keyring-pam; do
		dwm_packages fedora "$profile" | grep -Fx "$package" >/dev/null
	done
done
grep -Fq 'dwm_install_package_profile system-management' "$repo/install.sh"
grep -Fq 'check_cmd "xsettingsd"' "$repo/scripts/check-deps.sh"
grep -Fq 'xsetroot xkbset' "$repo/scripts/check-deps.sh"
if "$repo/scripts/dwm-packages.sh" fedora unsupported >"$work/unsupported"; then
	printf 'Unsupported package-map profile unexpectedly passed.\n' >&2
	exit 1
fi
[[ ! -s $work/unsupported ]]

missing_provider_packages=$(PATH="$work/bin:$PATH" DWM_TEST_PPD_PROVIDER=0 bash -c '
	. "$1"
	DISTRO_FAMILY=fedora
	install_packages() { printf "%s\n" "$@"; }
	dwm_install_package_profile desktop
' _ "$repo/scripts/dwm-packages.sh")
printf '%s\n' "$missing_provider_packages" | grep -Fxq power-profiles-daemon

"$repo/install.sh" --dry-run --non-interactive --profile core >/dev/null

printf 'Fedora required, desktop, and image package map: PASS (%s packages)\n' \
	"${#packages[@]}"

# Checkout installs use detected identity; factory checks can override it.
for release in 44 45; do
	for profile in recommended full; do
		VERSION_ID=$release dwm_packages fedora "$profile" | grep -Fx Thunar >/dev/null
	done
	for profile in desktop-optional theme-gtk; do
		VERSION_ID=$release dwm_packages fedora "$profile" >"$work/profile"
		if [[ $release == 45 ]]; then
			if grep -Ex 'path|numix-gtk-theme|deepin-gtk-theme' "$work/profile"; then
				exit 1
			fi
		else
			grep -Ex 'path|numix-gtk-theme|deepin-gtk-theme' "$work/profile" >/dev/null
		fi
	done
done
VERSION_ID=45 DWM_IMAGE_FEDORA_RELEASE=44 dwm_packages fedora desktop-optional | grep -Fx path >/dev/null
if VERSION_ID=44 DWM_IMAGE_FEDORA_RELEASE=45 dwm_packages fedora desktop-optional | grep -Fx path; then
	exit 1
fi
