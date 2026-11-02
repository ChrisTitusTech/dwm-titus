#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/rpm" <<'RPM'
#!/bin/sh
[ "$1 $2" = '-q --whatprovides' ] || exit 2
case ":${DWM_TEST_CAPABILITIES:-}:" in *":$3:"*) exit 0 ;; *) exit 1 ;; esac
RPM
chmod +x "$work/bin/rpm"
profile() {
	# shellcheck disable=SC2016 # Expand arguments inside the isolated Bash process.
	env PATH="$work/bin" DWM_TEST_CAPABILITIES="${1:-}" /usr/bin/bash -c '
        set -eu
        . "$1/scripts/dwm-packages.sh"
        DISTRO_FAMILY=fedora
        install_packages() { printf "%s\n" "$@"; }
        dwm_install_package_profile "$2"
    ' sh "$repo" "$2"
}
profile ppd-service desktop >"$work/power"
if grep -Fxq power-profiles-daemon "$work/power"; then
	printf 'Existing provider would be replaced\n' >&2
	exit 1
fi
grep -Fxq upower "$work/power"
profile xserver required >"$work/server"
if grep -Fxq xorg-x11-server-Xorg "$work/server"; then
	printf 'Existing provider would be replaced\n' >&2
	exit 1
fi
printf '#!/bin/sh\nexit 0\n' >"$work/bin/Xlibre"
chmod +x "$work/bin/Xlibre"
profile '' required >"$work/command"
if grep -Fxq xorg-x11-server-Xorg "$work/command"; then
	printf 'Existing provider would be replaced\n' >&2
	exit 1
fi
rm "$work/bin/Xlibre" "$work/bin/rpm"
# Without RPM or alternative commands, do not silently omit required packages.
profile '' required >"$work/no-provider"
grep -Fxq xorg-x11-server-Xorg "$work/no-provider"
profile '' desktop >"$work/no-power"
grep -Fxq power-profiles-daemon "$work/no-power"
printf 'Shared package provider retention: PASS\n'
