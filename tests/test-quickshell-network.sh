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

if [ "${DWM_TEST_NMCLI_CONNECTION_FAIL:-0}" = 1 ]; then
	case "$*" in
	"connection show" | "connection show --active") exit 11 ;;
	esac
fi
if [ "${DWM_TEST_NMCLI_EMPTY_CONNECTIONS:-0}" = 1 ]; then
	case "$*" in
	"connection show" | "connection show --active") exit 0 ;;
	esac
fi
if [ "${DWM_TEST_WIFI_SCAN_FAIL:-0}" = 1 ]; then
	case "$*" in
	"device wifi list "*) exit 12 ;;
	esac
fi

case "$*" in
"device status")
	case "${DWM_TEST_NMCLI_MODE:-wired}" in
	wired)
		printf 'lo:loopback:connected:lo\n'
		printf 'enp6s0:ethernet:connected:Wired connection 1\n'
		printf 'wlan0:wifi:disconnected:--\n'
		;;
	offline)
		printf 'enp6s0:ethernet:disconnected:--\n'
		printf 'lo:loopback:connected:lo\n'
		;;
	service-fail)
		exit 10
		;;
	two-wifi)
		printf 'wlan0:wifi:disconnected:--\n'
		printf 'wlan1:wifi:disconnected:--\n'
		;;
	no-wifi)
		printf 'enp6s0:ethernet:connected:Wired connection 1\n'
		;;
	unmanaged-wifi)
		printf 'wlan1:wifi:unmanaged:--\n'
		printf 'wlan2:wifi:unavailable:--\n'
		printf 'wlan0:wifi:disconnected:--\n'
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
	if [ -n "${DWM_TEST_NMCLI_EXTRA_PROFILE:-}" ]; then
		printf '%s:uuid-extra:802-11-wireless\n' "$DWM_TEST_NMCLI_EXTRA_PROFILE"
	fi
	;;
"device wifi list --rescan no")
	printf '*:AA\\:BB\\:CC\\:DD\\:EE\\:01:Cafe\\:WiFi:83:WPA2:6:wlan0\n'
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:02:Guest WiFi:61:--:11:wlan0\n'
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:03:Cafe\\:WiFi:50:WPA3:149:wlan0\n'
	printf ':AA\\:BB\\:CC\\:DD\\:EE\\:06:Legacy WiFi:42:WEP:3:wlan0\n'
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
"connection add type wifi con-name "*" 802-11-wireless.hidden yes connection.uuid "*)
	case " $* " in
	*" ifname "* | *" 802-11-wireless.bssid "*)
		printf 'hidden profile bound to a device or BSSID: %s\n' "$*" >&2
		exit 1
		;;
	esac
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	printf 'profile-add\n' >>"$DWM_TEST_NMCLI_LOG"
	;;
"device monitor "*)
	if [ "${DWM_TEST_HIDDEN_MODE:-}" = auth ]; then
		printf '%s: connecting (need authentication)\n' "$3"
		sleep 0.2
		printf '%s: connecting (need authentication)\n' "$3"
	fi
	exec sleep 30
	;;
"connection up uuid "*" ifname "*)
	printf '%s\n' "$*" >>"$DWM_TEST_NMCLI_ARGV_LOG"
	password_file=
	previous=
	for argument do
		[ "$previous" != passwd-file ] || password_file=$argument
		previous=$argument
	done
	if [ -n "$password_file" ]; then
		[ "$(stat -c '%a' "$password_file")" = "600" ]
		[ "$(cat "$password_file")" = "$DWM_TEST_HIDDEN_SECRET" ]
		printf 'password-file %s\n' "$password_file" >>"$DWM_TEST_NMCLI_LOG"
	fi
	case "${DWM_TEST_HIDDEN_MODE:-}" in
	fail-53)
		printf 'Error: Connection activation failed: (53) The Wi-Fi network could not be found.\n' >&2
		printf "Hint: use 'journalctl -xe NM_CONNECTION=x' to get more details.\n" >&2
		exit 4
		;;
	fail-7)
		printf 'Error: Connection activation failed: (7) Secrets were required, but not provided.\n' >&2
		exit 4
		;;
	fail-17)
		printf 'Error: Connection activation failed: (17) DHCP client failed.\n' >&2
		exit 4
		;;
	fail-other)
		printf 'Error: Connection activation failed: (36) Something else.\n' >&2
		exit 4
		;;
	hold)
		printf '%s\n' "$$" >"$DWM_TEST_HIDDEN_HOLD"
		exec sleep 30
		;;
	auth)
		exec sleep 30
		;;
	esac
	printf 'Connection successfully activated\n'
	printf 'wifi-hidden\n' >>"$DWM_TEST_NMCLI_LOG"
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
	if [ "${DWM_TEST_MONITOR_HOLD:-0}" = 1 ]; then
		printf '%s\n' "$$" >"$DWM_TEST_MONITOR_CHILD"
		while :; do sleep 1; done
	fi
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

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" snapshot --rescan no >"$work/snapshot.out"
[ "$(grep -Fxc "connectivity-protocol	1	0" "$work/snapshot.out")" -eq 1 ]
grep -Fqx "provider	network	available	delegated	NetworkManager state and user-authorized actions" "$work/snapshot.out"
grep -Fqx "network-device	enp6s0	ethernet	connected	Wired connection 1" "$work/snapshot.out"
grep -Fqx "network-profile	Work VPN	uuid-vpn	vpn	no	-" "$work/snapshot.out"
grep -Fqx "wifi-network	*	AA:BB:CC:DD:EE:01	Cafe:WiFi	83	WPA2	6	wlan0" "$work/snapshot.out"

DWM_TEST_WIFI_SCAN_FAIL=1 PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" snapshot --rescan no >"$work/snapshot-wifi-restricted.out"
grep -Fqx "provider	network	restricted	delegated	Wi-Fi scanning is unavailable; other NetworkManager state remains readable" "$work/snapshot-wifi-restricted.out"
grep -Fqx "network-device	enp6s0	ethernet	connected	Wired connection 1" "$work/snapshot-wifi-restricted.out"
grep -Fqx "network-profile	Work VPN	uuid-vpn	vpn	no	-" "$work/snapshot-wifi-restricted.out"
if grep -Fq "wifi-network	" "$work/snapshot-wifi-restricted.out"; then
	exit 1
fi

DWM_TEST_NMCLI_MODE=service-fail PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" snapshot --rescan no >"$work/snapshot-unavailable.out"
grep -Fqx "provider	network	unavailable	read-only	NetworkManager service is unavailable" "$work/snapshot-unavailable.out"

DWM_TEST_NMCLI_CONNECTION_FAIL=1 PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" snapshot --rescan no >"$work/snapshot-connection-failure.out"
grep -Fqx "provider	network	unavailable	read-only	NetworkManager service is unavailable" "$work/snapshot-connection-failure.out"
if grep -Fq "network-profile	" "$work/snapshot-connection-failure.out"; then
	printf 'Snapshot emitted incomplete profiles after a connection query failure.\n' >&2
	exit 1
fi

DWM_TEST_NMCLI_EMPTY_CONNECTIONS=1 PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" snapshot --rescan no >"$work/snapshot-empty-connections.out"
grep -Fqx "provider	network	available	delegated	NetworkManager state and user-authorized actions" "$work/snapshot-empty-connections.out"
if grep -Fq "network-profile	" "$work/snapshot-empty-connections.out"; then
	printf 'Snapshot serialized a false profile from empty NetworkManager output.\n' >&2
	exit 1
fi

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

if printf '%s\n' "enterprise secret" |
	PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect wlan0 AA:BB:CC:DD:EE:09 "Enterprise WiFi" --password-stdin "WPA2 802.1X" \
		2>"$work/enterprise.err"; then
	exit 1
fi
grep -Fqx "enterprise Wi-Fi must be configured in the delegated NetworkManager editor" "$work/enterprise.err"
if grep -Fq "Enterprise WiFi" "$work/nmcli.log"; then
	exit 1
fi
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

# hidden_connect [NAME=value...] -- ARGS: run wifi-connect-hidden with
# $work/hidden.in on stdin and the given stub settings in its environment.
hidden_connect() {
	: >"$work/nmcli.log"
	: >"$work/nmcli-argv.log"
	hidden_status=0
	(
		while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
			export "${1?}"
			shift
		done
		shift
		DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
			DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
			XDG_RUNTIME_DIR="$work/run" \
			PATH="$work/bin:$PATH" \
			exec "$repo/scripts/dwm-quickshell-network" wifi-connect-hidden "$@"
	) <"$work/hidden.in" >"$work/hidden.out" 2>"$work/hidden.err" || hidden_status=$?
}

hidden_input() {
	printf '%s\n' "$1" >"$work/hidden.in"
}

hidden_uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
hidden_file="$work/run/dwm-network-hidden[.][A-Za-z0-9]+/password"
mkdir -m 700 "$work/run"

hidden_password_file_removed() {
	password_file=$(sed -n 's/^password-file //p' "$work/nmcli.log")
	[ -n "$password_file" ]
	[ ! -e "$password_file" ]
	if find "$work/run" -mindepth 1 | grep -q .; then
		printf 'Hidden Wi-Fi work files were left behind.\n' >&2
		exit 1
	fi
	if grep -Fq "$1" "$work/nmcli-argv.log"; then
		printf 'Hidden Wi-Fi secret reached nmcli argv.\n' >&2
		exit 1
	fi
}

hidden_input "correct horse battery staple"
hidden_connect "DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:correct horse battery staple" -- \
	wlan0 "Hidden Net" wpa-psk --password-stdin
[ "$hidden_status" -eq 0 ]
[ ! -s "$work/hidden.out" ]
grep -Fqx "wifi-hidden" "$work/nmcli.log"
grep -Eqx "connection add type wifi con-name Hidden Net ssid Hidden Net 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid wifi-sec[.]key-mgmt wpa-psk" "$work/nmcli-argv.log"
grep -Eqx "connection up uuid $hidden_uuid ifname wlan0 passwd-file $hidden_file" "$work/nmcli-argv.log"
hidden_password_file_removed "correct horse battery staple"
if grep -Fq "profile-delete" "$work/nmcli.log"; then
	exit 1
fi

# A 64 digit hex PSK, automatic device choice, and name collisions.
hex_psk=0123456789abcdef0123456789abcdef0123456789ABCDEF0123456789ABCDEF
hidden_input "$hex_psk"
hidden_connect "DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:$hex_psk" -- \
	- "Home WiFi" wpa-psk --password-stdin
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection add type wifi con-name Home WiFi [(]hidden[)] ssid Home WiFi 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid wifi-sec[.]key-mgmt wpa-psk" "$work/nmcli-argv.log"
grep -Eqx "connection up uuid $hidden_uuid ifname wlan0 passwd-file $hidden_file" "$work/nmcli-argv.log"
hidden_password_file_removed "$hex_psk"

hidden_input "correct horse battery staple"
hidden_connect "DWM_TEST_NMCLI_EXTRA_PROFILE=Home WiFi (hidden)" \
	"DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:correct horse battery staple" -- \
	- "Home WiFi" wpa-psk --password-stdin
[ "$hidden_status" -eq 0 ]
grep -Eq "^connection add type wifi con-name Home WiFi [(]hidden 2[)] ssid Home WiFi " "$work/nmcli-argv.log"

hidden_input "wpa3 secret"
hidden_connect DWM_TEST_NMCLI_MODE=unmanaged-wifi \
	"DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:wpa3 secret" -- \
	- "-Hidden:Net" sae --password-stdin
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection add type wifi con-name -Hidden:Net ssid -Hidden:Net 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid wifi-sec[.]key-mgmt sae" "$work/nmcli-argv.log"
grep -Eqx "connection up uuid $hidden_uuid ifname wlan0 passwd-file $hidden_file" "$work/nmcli-argv.log"
hidden_password_file_removed "wpa3 secret"

hidden_input "abcde"
hidden_connect "DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.wep-key0:abcde" -- \
	wlan0 "Old Net" wep --password-stdin
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection add type wifi con-name Old Net ssid Old Net 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid wifi-sec[.]key-mgmt none wifi-sec[.]wep-key-type key" "$work/nmcli-argv.log"
hidden_password_file_removed "abcde"

hidden_input "long wep phrase"
hidden_connect "DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.wep-key0:long wep phrase" -- \
	wlan0 "Old Net" wep --password-stdin
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection add type wifi con-name Old Net ssid Old Net 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid wifi-sec[.]key-mgmt none wifi-sec[.]wep-key-type passphrase" "$work/nmcli-argv.log"
hidden_password_file_removed "long wep phrase"

: >"$work/hidden.in"
hidden_connect -- wlan0 "Open Net" none
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection add type wifi con-name Open Net ssid Open Net 802-11-wireless[.]hidden yes connection[.]uuid $hidden_uuid" "$work/nmcli-argv.log"
grep -Eqx "connection up uuid $hidden_uuid ifname wlan0" "$work/nmcli-argv.log"
grep -Fqx "wifi-hidden" "$work/nmcli.log"

# Device selection fails before any profile is created.
hidden_device_error() {
	: >"$work/hidden.in"
	hidden_connect "DWM_TEST_NMCLI_MODE=$2" -- "$3" "Open Net" none
	[ "$hidden_status" -eq 3 ]
	grep -Fqx "$1" "$work/hidden.err"
	[ ! -s "$work/nmcli-argv.log" ]
}
hidden_device_error "several Wi-Fi devices are available; choose one" two-wifi -
hidden_device_error "no Wi-Fi device is available" no-wifi -
hidden_device_error "Wi-Fi device wlan9 was not found" wired wlan9
hidden_device_error "Wi-Fi device enp6s0 was not found" wired enp6s0
hidden_connect DWM_TEST_NMCLI_MODE=two-wifi -- wlan1 "Open Net" none
[ "$hidden_status" -eq 0 ]
grep -Eqx "connection up uuid $hidden_uuid ifname wlan1" "$work/nmcli-argv.log"

# Validation rejects bad input before NetworkManager is touched.
hidden_rejects() {
	expected=$1
	hidden_input "$2"
	shift 2
	hidden_connect -- "$@"
	if [ "$hidden_status" -ne 2 ]; then
		printf 'Hidden Wi-Fi input was not rejected: %s\n' "$*" >&2
		exit 1
	fi
	grep -Fqx "$expected" "$work/hidden.err"
	[ ! -s "$work/nmcli-argv.log" ]
	[ ! -s "$work/nmcli.log" ]
}
long_ssid=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
utf8_ssid=$(printf '\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251')
tab_ssid=$(printf 'Hidden\tNet')
hidden_rejects "network name must be 1 to 32 bytes" unused wlan0 "$long_ssid" none
hidden_rejects "network name must be 1 to 32 bytes" unused wlan0 "$utf8_ssid" none
hidden_rejects "network name must be 1 to 32 bytes" unused wlan0 "" none
hidden_rejects "network name must not contain control characters" unused wlan0 "$tab_ssid" none
hidden_rejects "WPA password must be 8 to 63 characters or 64 hex digits" "1234567" \
	wlan0 "Hidden Net" wpa-psk --password-stdin
hidden_rejects "WPA password must be 8 to 63 characters or 64 hex digits" \
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg" \
	wlan0 "Hidden Net" wpa-psk --password-stdin
hidden_rejects "WPA password must be 8 to 63 characters or 64 hex digits" \
	"$(printf 'p\303\244sswort')" wlan0 "Hidden Net" wpa-psk --password-stdin
hidden_rejects "Wi-Fi password required on stdin" "" wlan0 "Hidden Net" sae --password-stdin
hidden_rejects "Wi-Fi password required on stdin" unused wlan0 "Hidden Net" sae
hidden_rejects "open networks do not take a password" unused wlan0 "Hidden Net" none --password-stdin
hidden_rejects "enterprise Wi-Fi must be configured in the delegated NetworkManager editor" unused \
	wlan0 "Hidden Net" "WPA2 802.1X" --password-stdin
hidden_rejects "unknown security type: wpa9" unused wlan0 "Hidden Net" wpa9 --password-stdin
if grep -Fq "1234567" "$work/hidden.err"; then
	exit 1
fi

# Activation failures print one mapped line and remove the new profile.
hidden_failure() {
	hidden_input "correct horse battery staple"
	hidden_connect "DWM_TEST_HIDDEN_MODE=$2" \
		"DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:correct horse battery staple" -- \
		wlan0 "Hidden Net" wpa-psk --password-stdin
	[ "$hidden_status" -eq 4 ]
	[ "$(cat "$work/hidden.err")" = "$1" ]
	grep -Fq "profile-delete connection delete uuid " "$work/nmcli.log"
	hidden_password_file_removed "correct horse battery staple"
}
hidden_failure "hidden network Hidden Net was not found; check the name and security type" fail-53
hidden_failure "authentication to Hidden Net failed; check the password and security type" fail-7
hidden_failure "joined Hidden Net but no IP address was received" fail-17
hidden_failure "Connection activation failed: (36) Something else." fail-other

# A rejected secret makes NetworkManager ask again; the helper stops there.
hidden_input "correct horse battery staple"
hidden_connect DWM_TEST_HIDDEN_MODE=auth \
	"DWM_TEST_HIDDEN_SECRET=802-11-wireless-security.psk:correct horse battery staple" -- \
	wlan0 "Hidden Net" wpa-psk --password-stdin
[ "$hidden_status" -eq 4 ]
[ "$(cat "$work/hidden.err")" = "authentication to Hidden Net failed; check the password and security type" ]
grep -Fq "profile-delete connection delete uuid " "$work/nmcli.log"
hidden_password_file_removed "correct horse battery staple"

# A terminated helper still removes the profile and the password file.
: >"$work/nmcli.log"
: >"$work/nmcli-argv.log"
rm -f "$work/hidden-hold.pid"
printf '%s\n' "correct horse battery staple" |
	DWM_TEST_HIDDEN_MODE=hold \
		DWM_TEST_HIDDEN_HOLD="$work/hidden-hold.pid" \
		DWM_TEST_HIDDEN_SECRET="802-11-wireless-security.psk:correct horse battery staple" \
		DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
		DWM_TEST_NMCLI_ARGV_LOG="$work/nmcli-argv.log" \
		XDG_RUNTIME_DIR="$work/run" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-quickshell-network" wifi-connect-hidden wlan0 "Hidden Net" wpa-psk --password-stdin \
		2>/dev/null &
hidden_helper=$!
i=0
while [ "$i" -lt 250 ] && [ ! -s "$work/hidden-hold.pid" ]; do
	i=$((i + 1))
	sleep 0.02
done
[ -s "$work/hidden-hold.pid" ]
kill -TERM "$hidden_helper"
hidden_status=0
wait "$hidden_helper" || hidden_status=$?
[ "$hidden_status" -ne 0 ]
grep -Fq "profile-delete connection delete uuid " "$work/nmcli.log"
hidden_password_file_removed "correct horse battery staple"
hidden_hold=$(cat "$work/hidden-hold.pid")
i=0
while [ "$i" -lt 150 ] && [ -e "/proc/$hidden_hold" ]; do
	i=$((i + 1))
	sleep 0.02
done
if [ -e "/proc/$hidden_hold" ]; then
	printf 'Hidden Wi-Fi activation survived the terminated helper.\n' >&2
	kill -KILL "$hidden_hold" 2>/dev/null || :
	exit 1
fi

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-network" monitor >"$work/monitor.out"
grep -Fqx "wlan0: connected" "$work/monitor.out"
grep -Fqx "Networkmanager is now connected" "$work/monitor.out"

DWM_TEST_MONITOR_HOLD=1 DWM_TEST_MONITOR_CHILD="$work/monitor-child.pid" \
	PATH="$work/bin:$PATH" sh -c '"$1" monitor & echo $! >"$2"; wait' sh \
	"$repo/scripts/dwm-quickshell-network" "$work/monitor-helper.pid" &
monitor_owner=$!
i=0
while [ "$i" -lt 100 ]; do
	[ -s "$work/monitor-helper.pid" ] && [ -s "$work/monitor-child.pid" ] && break
	i=$((i + 1))
	sleep 0.02
done
[ -s "$work/monitor-helper.pid" ]
[ -s "$work/monitor-child.pid" ]
monitor_helper=$(cat "$work/monitor-helper.pid")
monitor_child=$(cat "$work/monitor-child.pid")
pid_running() {
	[ -r "/proc/$1/stat" ] || return 1
	state=$(sed 's/^.*) //' "/proc/$1/stat" | awk '{ print $1 }')
	[ "$state" != Z ]
}
kill -KILL "$monitor_owner"
wait "$monitor_owner" 2>/dev/null || :
i=0
while [ "$i" -lt 100 ]; do
	if ! pid_running "$monitor_helper" && ! pid_running "$monitor_child"; then
		break
	fi
	i=$((i + 1))
	sleep 0.02
done
if pid_running "$monitor_helper" || pid_running "$monitor_child"; then
	printf 'Parent-bound NetworkManager monitor survived its owner.\n' >&2
	kill -TERM "$monitor_helper" "$monitor_child" 2>/dev/null || :
	exit 1
fi

DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" connect uuid-wifi
grep -Fqx "connect uuid-wifi" "$work/nmcli.log"

: >"$work/nmcli.log"
DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" disconnect enp6s0
grep -Fqx "disconnect enp6s0" "$work/nmcli.log"

: >"$work/nmcli.log"
DWM_TEST_NMCLI_LOG="$work/nmcli.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-network" forget uuid-wifi
grep -Fqx "profile-delete connection delete uuid uuid-wifi" "$work/nmcli.log"

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
