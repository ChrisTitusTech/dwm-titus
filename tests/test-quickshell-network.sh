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
	status-ethernet)
		printf 'enp2s0:ethernet:connected:Wired connection 1\n'
		printf 'wlan0:wifi:connected:HUAWEI-BY10D8_Wi-Fi5\n'
		;;
	status-wifi)
		printf 'wlan0:wifi:connected:HUAWEI-BY10D8_Wi-Fi5\n'
		;;
	wired)
		printf 'lo:loopback:connected:lo\n'
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
	printf 'Loopback profile:uuid-loopback:loopback:lo\n'
	;;
"connection show")
	printf 'Wired connection 1:uuid-wired:802-3-ethernet\n'
	printf 'Home WiFi:uuid-wifi:802-11-wireless\n'
	printf 'Work VPN:uuid-vpn:vpn\n'
	printf 'lo:uuid-lo-name:802-3-ethernet\n'
	printf 'Loopback profile:uuid-loopback:loopback\n'
	;;
"device wifi list --rescan no")
	if [ "${DWM_TEST_NMCLI_MODE:-}" = status-wifi ]; then
		printf '*:74:wlan0\n'
	else
		printf '*:AA\\:BB\\:CC\\:DD\\:EE\\:01:Cafe\\:WiFi:83:WPA2:6:wlan0\n'
		printf ':AA\\:BB\\:CC\\:DD\\:EE\\:02:Guest WiFi:61:--:11:wlan0\n'
		printf ':AA\\:BB\\:CC\\:DD\\:EE\\:03:Cafe\\:WiFi:50:WPA3:149:wlan0\n'
		printf ':AA\\:BB\\:CC\\:DD\\:EE\\:06:Legacy WiFi:42:WEP:3:wlan0\n'
	fi
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
"connection add type wifi ifname wlan0 con-name Cafe:WiFi ssid Cafe:WiFi 802-11-wireless.bssid AA:BB:CC:DD:EE:01 wifi-sec.key-mgmt wpa-psk connection.uuid "*)
	for argument do
		connection_uuid=$argument
	done
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'profile-add %s\n' "$connection_uuid" >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection add type wifi ifname wlan0 con-name Legacy WiFi ssid Legacy WiFi 802-11-wireless.bssid AA:BB:CC:DD:EE:06 wifi-sec.key-mgmt none wifi-sec.wep-key-type key connection.uuid "*)
	for argument do
		connection_uuid=$argument
	done
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'profile-add %s\n' "$connection_uuid" >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection add type wifi ifname wlan0 con-name Cafe:WiFi ssid Cafe:WiFi 802-11-wireless.bssid AA:BB:CC:DD:EE:03 wifi-sec.key-mgmt sae connection.uuid "*)
	for argument do
		connection_uuid=$argument
	done
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'profile-add %s\n' "$connection_uuid" >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection up uuid "*" ifname wlan0 ap AA:BB:CC:DD:EE:01 passwd-file "*)
	for argument do
		password_file=$argument
	done
	[ "$(stat -c '%a' "$password_file")" = "600" ]
	[ "$(sed -n 's/^802-11-wireless-security\.psk://p' "$password_file")" = "correct horse battery staple" ]
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'password-file %s\n' "$password_file" >>"$DWM_TEST_NMCLI_LOG"
	case "${DWM_TEST_NMCLI_MODE:-}" in
	wifi-fail)
		exit 4
		;;
	wifi-signal)
		kill -TERM "$PPID"
		exit 143
		;;
	esac
	printf 'wifi-secured\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection up uuid "*" ifname wlan0 ap AA:BB:CC:DD:EE:06 passwd-file "*)
	for argument do
		password_file=$argument
	done
	[ "$(stat -c '%a' "$password_file")" = "600" ]
	[ "$(sed -n 's/^802-11-wireless-security\.wep-key0://p' "$password_file")" = "abcde" ]
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'password-file %s\n' "$password_file" >>"$DWM_TEST_NMCLI_LOG"
	printf 'wifi-wep\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection up uuid "*" ifname wlan0 ap AA:BB:CC:DD:EE:03 passwd-file "*)
	for argument do
		password_file=$argument
	done
	[ "$(stat -c '%a' "$password_file")" = "600" ]
	[ "$(sed -n 's/^802-11-wireless-security\.psk://p' "$password_file")" = "wpa3 secret" ]
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'password-file %s\n' "$password_file" >>"$DWM_TEST_NMCLI_LOG"
	printf 'wifi-wpa3\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"connection delete uuid "*)
	printf 'profile-delete %s\n' "$*" >>"$DWM_TEST_NMCLI_LOG"
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

DWM_TEST_NMCLI_MODE=status-ethernet \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" status >"$work/status-ethernet.out"
grep -Fqx "ethernet	enp2s0	Wired connection 1	-1" "$work/status-ethernet.out"

DWM_TEST_NMCLI_MODE=status-wifi \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" status >"$work/status-wifi.out"
grep -Fqx "wifi	wlan0	HUAWEI-BY10D8_Wi-Fi5	74" "$work/status-wifi.out"

DWM_TEST_NMCLI_MODE=offline \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" status >"$work/offline.out"
grep -Fqx "disconnected			-1" "$work/offline.out"

network_model=$repo/config/quickshell/network/NetworkModel.qml
grep -F 'property string connectionKind: "disconnected"' "$network_model" >/dev/null
grep -F 'property int wifiSignal: -1' "$network_model" >/dev/null
grep -F 'readonly property string barIconState: root.connectionKind' "$network_model" >/dev/null
if ! grep -F 'Component.onCompleted: root.refresh(false)' "$network_model" >/dev/null; then
	printf '%s\n' 'Network model must fetch initial state before the first nmcli monitor event.' >&2
	exit 1
fi
if grep -F 'Timer {' "$network_model" >/dev/null; then
	printf '%s\n' 'Network status refresh must remain event-driven without a polling timer.' >&2
	exit 1
fi

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" devices >"$work/devices.out"
grep -Fqx "enp6s0	ethernet	connected	Wired connection 1" "$work/devices.out"
if grep -Fq "loopback" "$work/devices.out"; then
	exit 1
fi

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" connections >"$work/connections.out"
grep -Fqx "Wired connection 1	uuid-wired	802-3-ethernet	yes	enp6s0" "$work/connections.out"
grep -Fqx "Home WiFi	uuid-wifi	802-11-wireless	no	" "$work/connections.out"
grep -Fqx "Work VPN	uuid-vpn	vpn	no	" "$work/connections.out"
grep -Fqx "lo	uuid-lo-name	802-3-ethernet	no	" "$work/connections.out"
if grep -Fq "loopback" "$work/connections.out"; then
	exit 1
fi

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan >"$work/wifi-scan.out"
grep -Fqx "*	AA:BB:CC:DD:EE:01	Cafe:WiFi	83	WPA2	6	wlan0" "$work/wifi-scan.out"
grep -Fqx "	AA:BB:CC:DD:EE:02	Guest WiFi	61	--	11	wlan0" "$work/wifi-scan.out"
grep -Fqx "	AA:BB:CC:DD:EE:03	Cafe:WiFi	50	WPA3	149	wlan0" "$work/wifi-scan.out"
grep -Fqx "	AA:BB:CC:DD:EE:06	Legacy WiFi	42	WEP	3	wlan0" "$work/wifi-scan.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan --rescan yes >"$work/wifi-rescan.out"
grep -Fqx "	AA:BB:CC:DD:EE:04	New WiFi	74	WPA2	1	wlan0" "$work/wifi-rescan.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" wifi-scan --rescan yes wlan1 >"$work/wifi-ifname.out"
grep -Fqx "	AA:BB:CC:DD:EE:05	Office WiFi	90	WPA2	36	wlan1" "$work/wifi-ifname.out"

DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:02 "Guest WiFi"
grep -Fqx "wifi-open Guest WiFi" "$work/nmcli.log"

: >"$work/nmcli.log"
printf '%s\n' "correct horse battery staple" |
	DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:01 "Cafe:WiFi" --password-stdin WPA2
grep -Fqx "wifi-secured" "$work/nmcli.log"
password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
[ -n "$password_file" ]
[ ! -e "$password_file" ]
if grep -Fq "correct horse battery staple" "$work/nmcli-argv.log"; then
	exit 1
fi

: >"$work/nmcli.log"
: >"$work/nmcli-argv.log"
if printf '%s\n' "correct horse battery staple" |
	DWM_TEST_NMCLI_MODE=wifi-fail \
		DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:01 "Cafe:WiFi" --password-stdin WPA2; then
	exit 1
fi
grep -Fq "profile-delete connection delete uuid " "$work/nmcli.log"
password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
[ -n "$password_file" ]
[ ! -e "$password_file" ]
if grep -Fq "correct horse battery staple" "$work/nmcli-argv.log"; then
	exit 1
fi

: >"$work/nmcli.log"
: >"$work/nmcli-argv.log"
printf '%s\n' "abcde" |
	DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:06 "Legacy WiFi" --password-stdin WEP
grep -Fqx "wifi-wep" "$work/nmcli.log"
password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
[ -n "$password_file" ]
[ ! -e "$password_file" ]
if grep -Fq "abcde" "$work/nmcli-argv.log"; then
	exit 1
fi

: >"$work/nmcli.log"
: >"$work/nmcli-argv.log"
printf '%s\n' "wpa3 secret" |
	DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:03 "Cafe:WiFi" --password-stdin WPA3
grep -Fqx "wifi-wpa3" "$work/nmcli.log"
password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
[ -n "$password_file" ]
[ ! -e "$password_file" ]
if grep -Fq "wpa3 secret" "$work/nmcli-argv.log"; then
	exit 1
fi

: >"$work/nmcli.log"
: >"$work/nmcli-argv.log"
if printf '%s\n' "correct horse battery staple" |
	DWM_TEST_NMCLI_MODE=wifi-signal \
		DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:01 "Cafe:WiFi" --password-stdin WPA2; then
	exit 1
fi
grep -Fq "profile-delete connection delete uuid " "$work/nmcli.log"
password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
[ -n "$password_file" ]
[ ! -e "$password_file" ]

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

set +e
"$repo/tests/test-quickshell-network-refresh-xvfb.sh"
refresh_test_status=$?
set -e
if [ "$refresh_test_status" -ne 0 ] && [ "$refresh_test_status" -ne 77 ]; then
	exit "$refresh_test_status"
fi

printf 'Quickshell network helper: PASS\n'
