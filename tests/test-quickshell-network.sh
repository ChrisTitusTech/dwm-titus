#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"

cat >"$work/bin/nmcli" <<'SH'
#!/bin/sh
set -eu

while [ "$#" -gt 0 ]; do
	case "$1" in
	--terse)
		shift
		;;
	--escape)
		shift
		[ "$#" -gt 0 ] && shift
		;;
	--separator)
		shift 2
		;;
	-f)
		fields=$2
		shift 2
		;;
	*)
		break
		;;
	esac
done

case "$*" in
"device status")
	case "${DWM_TEST_NMCLI_MODE:-wired}" in
	wired)
		printf 'enp6s0\tethernet\tconnected\tWired connection 1\n'
		printf 'wlan0\twifi\tdisconnected\t--\n'
		;;
	offline)
		printf 'enp6s0\tethernet\tdisconnected\t--\n'
		printf 'lo\tloopback\tconnected\tlo\n'
		;;
	esac
	;;
"connection show --active")
	printf 'Wired connection 1\tuuid-wired\t802-3-ethernet\tenp6s0\n'
	;;
"connection show")
	printf 'Wired connection 1\tuuid-wired\t802-3-ethernet\n'
	printf 'Home WiFi\tuuid-wifi\t802-11-wireless\n'
	printf 'Work VPN\tuuid-vpn\tvpn\n'
	;;
"connection up uuid uuid-wifi")
	printf 'connect uuid-wifi\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"device disconnect enp6s0")
	printf 'disconnect enp6s0\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
*)
	printf 'unexpected nmcli call: %s fields=%s\n' "$*" "${fields:-}" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/nmcli"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" status >"$work/status.out"
grep -Fqx "NET enp6s0" "$work/status.out"

DWM_TEST_NMCLI_MODE=offline \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" status >"$work/offline.out"
grep -Fqx "NET offline" "$work/offline.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" devices >"$work/devices.out"
grep -Fqx "enp6s0	ethernet	connected	Wired connection 1" "$work/devices.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" connections >"$work/connections.out"
grep -Fqx "Wired connection 1	uuid-wired	802-3-ethernet	yes	enp6s0" "$work/connections.out"
grep -Fqx "Home WiFi	uuid-wifi	802-11-wireless	no	" "$work/connections.out"
grep -Fqx "Work VPN	uuid-vpn	vpn	no	" "$work/connections.out"

DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" connect uuid-wifi
grep -Fqx "connect uuid-wifi" "$work/nmcli.log"

: >"$work/nmcli.log"
DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" disconnect enp6s0
grep -Fqx "disconnect enp6s0" "$work/nmcli.log"

if PATH="$work/bin" "$repo/scripts/dwm-quickshell-network" editor 2>"$work/editor.err"; then
	exit 1
fi
grep -Fqx "nm-connection-editor not found" "$work/editor.err"

cat >"$work/bin/nm-connection-editor" <<'SH'
#!/bin/sh
printf '%s\n' editor >"$DWM_TEST_EDITOR_LOG"
SH
chmod +x "$work/bin/nm-connection-editor"

DWM_TEST_EDITOR_LOG="$work/editor.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" editor
grep -Fqx editor "$work/editor.log"

printf 'Quickshell network helper: PASS\n'
