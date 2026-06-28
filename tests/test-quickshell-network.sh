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
		printf 'enp6s0:ethernet:connected:Wired connection 1\n'
		printf 'wlan0:wifi:disconnected:--\n'
		;;
	offline)
		printf 'enp6s0:ethernet:disconnected:--\n'
		printf 'lo:loopback:connected:lo\n'
		;;
	esac
	;;
"connection show --active")
	printf 'Wired connection 1:uuid-wired:802-3-ethernet:enp6s0\n'
	;;
"connection show")
	printf 'Wired connection 1:uuid-wired:802-3-ethernet\n'
	printf 'Home WiFi:uuid-wifi:802-11-wireless\n'
	printf 'Work VPN:uuid-vpn:vpn\n'
	;;
"device wifi list --rescan no")
	printf '*:AA\\:BB\\:CC\\:DD\\:EE\\:01:Cafe\\:WiFi:83:WPA2:6:wlan0\n'
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:02:Guest WiFi:61:--:11:wlan0\n'
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:03:Cafe\\:WiFi:50:WPA3:149:wlan0\n'
	;;
"device wifi list --rescan yes")
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:04:New WiFi:74:WPA2:1:wlan0\n'
	;;
"device wifi list ifname wlan1 --rescan yes")
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:05:Office WiFi:90:WPA2:36:wlan1\n'
	;;
"device wifi connect Guest WiFi ifname wlan0 bssid AA:BB:CC:DD:EE:02")
	printf 'wifi-open Guest WiFi\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"device wifi connect Cafe:WiFi password correct horse battery staple ifname wlan0 bssid AA:BB:CC:DD:EE:01")
	printf 'wifi-secured Cafe:WiFi\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection up uuid uuid-wifi")
	printf 'connect uuid-wifi\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"device disconnect enp6s0")
	printf 'disconnect enp6s0\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"monitor")
	printf 'wlan0: connected\n'
	printf 'Networkmanager is now connected\n'
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

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan >"$work/wifi-scan.out"
grep -Fqx "*	AA:BB:CC:DD:EE:01	Cafe:WiFi	83	WPA2	6	wlan0" "$work/wifi-scan.out"
grep -Fqx "	AA:BB:CC:DD:EE:02	Guest WiFi	61	--	11	wlan0" "$work/wifi-scan.out"
grep -Fqx "	AA:BB:CC:DD:EE:03	Cafe:WiFi	50	WPA3	149	wlan0" "$work/wifi-scan.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan --rescan yes >"$work/wifi-rescan.out"
grep -Fqx "	AA:BB:CC:DD:EE:04	New WiFi	74	WPA2	1	wlan0" "$work/wifi-rescan.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan --rescan yes wlan1 >"$work/wifi-ifname.out"
grep -Fqx "	AA:BB:CC:DD:EE:05	Office WiFi	90	WPA2	36	wlan1" "$work/wifi-ifname.out"

DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:02 "Guest WiFi"
grep -Fqx "wifi-open Guest WiFi" "$work/nmcli.log"

: >"$work/nmcli.log"
DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:01 "Cafe:WiFi" "correct horse battery staple"
grep -Fqx "wifi-secured Cafe:WiFi" "$work/nmcli.log"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" monitor >"$work/monitor.out"
grep -Fqx changed "$work/monitor.out"

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
