#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
controls_model=$repo/config/quickshell/controls/ControlsModel.qml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

grep -F 'property string volumeIconState: root.volumeIconStateFor(root.volumePercent, root.volumeMuted)' "$controls_model" >/dev/null
grep -F 'function volumeIconStateFor(percent, muted) {' "$controls_model" >/dev/null
grep -F 'if (muted || percent <= 0) return "mute";' "$controls_model" >/dev/null
grep -F 'if (percent <= 33) return "low";' "$controls_model" >/dev/null
grep -F 'if (percent <= 66) return "medium";' "$controls_model" >/dev/null
grep -F 'return "high";' "$controls_model" >/dev/null

mkdir -p "$work/bin"

cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
"--format=json info")
	if [ "${DWM_TEST_AUDIO_MALFORMED:-0}" = 1 ]; then
		printf '%s\n' '{not-json'
	else
		printf '%s\n' '{"default_sink_name":"sink.one","default_source_name":"source.one"}'
	fi
	;;
"--format=json list sinks")
	output_volume=${DWM_TEST_AUDIO_OUTPUT_VOLUME:-40}
	printf '[{"name":"sink.one","description":"Speakers","mute":false,"volume":{"left":{"value_percent":"%s%%"}}},{"name":"sink.two","description":"Headphones","mute":true,"volume":{"left":{"value_percent":"55%%"}}}]\n' "$output_volume"
	;;
"--format=json list sources")
	printf '%s\n' '[{"name":"source.one","description":"Microphone","mute":false,"volume":{"mono":{"value_percent":"70%"}}},{"name":"sink.one.monitor","description":"Monitor","mute":false,"volume":{"mono":{"value_percent":"100%"}}}]'
	;;
"--format=json list sink-inputs")
	printf '%s\n' '[{"index":21,"name":"Playback","mute":false,"volume":{"left":{"value_percent":"65%"}},"properties":{"application.name":"Browser","media.name":"Video"}}]'
	;;
"get-sink-mute @DEFAULT_SINK@")
	printf 'Mute: %s\n' "${DWM_TEST_SINK_MUTE:-no}"
	;;
"get-sink-volume @DEFAULT_SINK@")
	volume=${DWM_TEST_SINK_VOLUME:-40}
	if [ -n "${DWM_TEST_SINK_VOLUME_FILE:-}" ] && [ -f "$DWM_TEST_SINK_VOLUME_FILE" ]; then
		volume=$(cat "$DWM_TEST_SINK_VOLUME_FILE")
	fi
	printf 'Volume: front-left: 26214 / %s%% / -23.88 dB, front-right: 26214 / %s%% / -23.88 dB\n' "$volume" "$volume"
	;;
info)
	printf 'Server String: /run/user/1000/pulse/native\n'
	printf 'Default Sink: %s\n' "${DWM_TEST_DEFAULT_SINK:-alsa_output.pci-0000_00_1f.3.analog-stereo}"
	;;
list\ sinks)
	cat <<'OUT'
Sink #1
	Name: alsa_output.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
Sink #2
	Name: bluez_output.00_11_22_33_44_55.a2dp-sink
	Description: Wireless Headphones
OUT
	;;
list\ short\ sink-inputs)
	printf '21\t1\t7\tprotocol-native.c\tfloat32le 2ch 48000Hz\n'
	printf '22\t1\t8\tprotocol-native.c\tfloat32le 2ch 48000Hz\n'
	;;
"get-source-mute @DEFAULT_SOURCE@")
	printf 'Mute: %s\n' "${DWM_TEST_SOURCE_MUTE:-no}"
	;;
"subscribe")
	: >"$DWM_TEST_SUBSCRIBE_MARKER"
	;;
"set-sink-volume @DEFAULT_SINK@ +5%")
	printf 'volume up\n' >>"$DWM_TEST_PACTL_LOG"
	;;
"set-sink-volume @DEFAULT_SINK@ -5%")
	printf 'volume down\n' >>"$DWM_TEST_PACTL_LOG"
	;;
"set-sink-volume @DEFAULT_SINK@ 35%")
	printf 'volume set 35%%\n' >>"$DWM_TEST_PACTL_LOG"
	;;
"set-sink-mute @DEFAULT_SINK@ toggle")
	printf 'mute toggle\n' >>"$DWM_TEST_PACTL_LOG"
	;;
set-default-sink\ *)
	printf 'default sink %s\n' "$2" >>"$DWM_TEST_PACTL_LOG"
	;;
set-default-source\ * | set-source-volume\ * | set-source-mute\ * | set-sink-input-volume\ * | set-sink-input-mute\ *)
	printf '%s\n' "$*" >>"$DWM_TEST_PACTL_LOG"
	;;
move-sink-input\ *)
	printf 'move sink input %s %s\n' "$2" "$3" >>"$DWM_TEST_PACTL_LOG"
	;;
*)
	printf 'unexpected pactl call: %s\n' "$*" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/pactl"

cat >"$work/bin/playerctl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
metadata\ --format\ *)
	case "${DWM_TEST_PLAYER_MODE:-playing}" in
	playing)
		printf 'brave\tPlaying\tArtist Name\tTrack Title\n'
		;;
	none)
		exit 1
		;;
	esac
	;;
--follow\ metadata\ --format\ *)
	case "${DWM_TEST_PLAYER_MODE:-playing}" in
	playing)
		printf 'brave\tPlaying\tArtist Name\tTrack Title\n'
		printf 'brave\tPaused\tArtist Name\tTrack Title\n'
		;;
	none)
		exit 1
		;;
	esac
	;;
play-pause)
	printf 'play-pause\n' >>"$DWM_TEST_PLAYERCTL_LOG"
	;;
next)
	printf 'next\n' >>"$DWM_TEST_PLAYERCTL_LOG"
	;;
previous)
	printf 'previous\n' >>"$DWM_TEST_PLAYERCTL_LOG"
	;;
*)
	printf 'unexpected playerctl call: %s\n' "$*" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/playerctl"

cat >"$work/bin/bluetoothctl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
show)
	case "${DWM_TEST_BT_MODE:-on}" in
	on)
		printf 'Controller 00:11:22:33:44:55\n'
		printf '\tPowered: yes\n'
		;;
	off)
		printf 'Controller 00:11:22:33:44:55\n'
		printf '\tPowered: no\n'
		;;
	none)
		exit 1
		;;
	esac
	;;
"devices Connected")
	case "${DWM_TEST_BT_CONNECTED:-0}" in
	0)
		;;
	2)
		printf 'Device AA:BB:CC:DD:EE:01 Headphones\n'
		printf 'Device AA:BB:CC:DD:EE:02 Keyboard\n'
		;;
	esac
	;;
devices)
	printf 'Device AA:BB:CC:DD:EE:01 Headphones\n'
	printf 'Device AA:BB:CC:DD:EE:02 Keyboard\n'
	;;
"info AA:BB:CC:DD:EE:01")
	printf 'Device AA:BB:CC:DD:EE:01\n'
	printf '\tPaired: yes\n'
	printf '\tConnected: yes\n'
	;;
"info AA:BB:CC:DD:EE:02")
	printf 'Device AA:BB:CC:DD:EE:02\n'
	printf '\tPaired: no\n'
	printf '\tConnected: no\n'
	;;
"--timeout 8 scan on")
	printf 'scan\n' >>"$DWM_TEST_BLUETOOTHCTL_LOG"
	;;
"pair AA:BB:CC:DD:EE:02")
	printf '%s\n' "$*" >>"$DWM_TEST_BLUETOOTHCTL_LOG"
	[ "${DWM_TEST_BT_PAIR_FAIL:-0}" != 1 ] || exit 6
	;;
"power on" | "power off" | "trust AA:BB:CC:DD:EE:02" | \
	"disconnect AA:BB:CC:DD:EE:01" | "remove AA:BB:CC:DD:EE:02" | "scan off")
	printf '%s\n' "$*" >>"$DWM_TEST_BLUETOOTHCTL_LOG"
	;;
"connect AA:BB:CC:DD:EE:02")
	printf '%s\n' "$*" >>"$DWM_TEST_BLUETOOTHCTL_LOG"
	[ "${DWM_TEST_BT_ACTION_FAIL:-0}" != 1 ] || exit 5
	;;
*)
	printf 'unexpected bluetoothctl call: %s\n' "$*" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/bluetoothctl"

cat >"$work/bin/busctl" <<'SH'
#!/bin/sh
set -eu

case "${DWM_TEST_BLUEZ_MODE:-available}" in
available)
	cat <<'JSON'
{"type":"a{oa{sa{sv}}}","data":[{"/org/bluez/hci0":{"org.bluez.Adapter1":{"Address":{"type":"s","data":"00:11:22:33:44:55"},"Alias":{"type":"s","data":"Test Adapter"},"Powered":{"type":"b","data":true},"Discovering":{"type":"b","data":false},"Pairable":{"type":"b","data":true}}},"/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02":{"org.bluez.Device1":{"Address":{"type":"s","data":"AA:BB:CC:DD:EE:02"},"Alias":{"type":"s","data":"Keyboard"},"Paired":{"type":"b","data":true},"Trusted":{"type":"b","data":false},"Connected":{"type":"b","data":false},"Adapter":{"type":"o","data":"/org/bluez/hci0"}}}}]}
JSON
	;;
restricted)
	printf '%s\n' '{"type":"a{oa{sa{sv}}}","data":[{"/org/bluez":{}}]}'
	;;
unavailable)
	exit 1
	;;
malformed)
	printf '%s\n' '{not-json'
	;;
esac
SH
chmod +x "$work/bin/busctl"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" audio-snapshot >"$work/audio-snapshot.out"
grep -Fqx "audio-protocol	1	0" "$work/audio-snapshot.out"
grep -Fqx "provider	audio	available	delegated	PipeWire state and user-session actions" "$work/audio-snapshot.out"
grep -Fqx "audio-output	sink.one	Speakers	yes	no	40" "$work/audio-snapshot.out"
grep -Fqx "audio-input	source.one	Microphone	yes	no	70" "$work/audio-snapshot.out"
grep -Fqx "audio-stream	21	Browser	Video	no	65" "$work/audio-snapshot.out"
if grep -Fq "sink.one.monitor" "$work/audio-snapshot.out"; then
	exit 1
fi
DWM_TEST_AUDIO_OUTPUT_VOLUME=140 PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" audio-snapshot >"$work/audio-bounded.out"
grep -Fqx "audio-output	sink.one	Speakers	yes	no	100" "$work/audio-bounded.out"
DWM_TEST_AUDIO_MALFORMED=1 PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" audio-snapshot >"$work/audio-malformed.out"
grep -Fqx "provider	audio	unavailable	read-only	Malformed audio provider response" "$work/audio-malformed.out"

DWM_TEST_SUBSCRIBE_MARKER="$work/audio-subscribed" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" audio-watch
[ -e "$work/audio-subscribed" ]

: >"$work/pactl.log"
DWM_TEST_PACTL_LOG="$work/pactl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" input-set-default source.one
DWM_TEST_PACTL_LOG="$work/pactl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" input-volume-set source.one 72%
DWM_TEST_PACTL_LOG="$work/pactl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" input-toggle-mute source.one
DWM_TEST_PACTL_LOG="$work/pactl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" stream-volume-set 21 64%
DWM_TEST_PACTL_LOG="$work/pactl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" stream-toggle-mute 21
grep -Fqx "set-default-source source.one" "$work/pactl.log"
grep -Fqx "set-source-volume source.one 72%" "$work/pactl.log"
grep -Fqx "set-source-mute source.one toggle" "$work/pactl.log"
grep -Fqx "set-sink-input-volume 21 64%" "$work/pactl.log"
grep -Fqx "set-sink-input-mute 21 toggle" "$work/pactl.log"

if PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" 2>"$work/usage.out"; then
	printf 'Control helper accepted a missing subcommand.\n' >&2
	exit 1
fi
grep -Fq 'bluetooth-power <on|off>|bluetooth-pair <address>' "$work/usage.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/volume.out"
grep -Fqx "VOL 40%" "$work/volume.out"

DWM_TEST_SINK_MUTE=yes \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-status >"$work/muted.out"
grep -Fqx "VOL muted 40%" "$work/muted.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" output-devices >"$work/output-devices.out"
grep -Fqx "alsa_output.pci-0000_00_1f.3.analog-stereo	Built-in Audio Analog Stereo	1" "$work/output-devices.out"
grep -Fqx "bluez_output.00_11_22_33_44_55.a2dp-sink	Wireless Headphones	0" "$work/output-devices.out"

DWM_TEST_DEFAULT_SINK=bluez_output.00_11_22_33_44_55.a2dp-sink \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" output-devices >"$work/output-devices-bluez.out"
grep -Fqx "alsa_output.pci-0000_00_1f.3.analog-stereo	Built-in Audio Analog Stereo	0" "$work/output-devices-bluez.out"
grep -Fqx "bluez_output.00_11_22_33_44_55.a2dp-sink	Wireless Headphones	1" "$work/output-devices-bluez.out"

printf '40\n' >"$work/volume-state"
DWM_TEST_SUBSCRIBE_MARKER="$work/subscribed" \
	DWM_TEST_SINK_VOLUME_FILE="$work/volume-state" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-watch >"$work/volume-watch.out"
grep -Fqx "VOL 40%" "$work/volume-watch.out"
[ ! -e "$work/subscribed" ]

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" mic-status >"$work/mic.out"
grep -Fqx "MIC on" "$work/mic.out"

DWM_TEST_SOURCE_MUTE=yes \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" mic-status >"$work/mic-muted.out"
grep -Fqx "MIC muted" "$work/mic-muted.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" media-status >"$work/media.out"
grep -Fqx "brave	Playing	Artist Name	Track Title" "$work/media.out"

DWM_TEST_PLAYER_MODE=none \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" media-status >"$work/media-none.out"
grep -Fqx "MEDIA none" "$work/media-none.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" media-watch >"$work/media-watch.out"
grep -Fqx "brave	Playing	Artist Name	Track Title" "$work/media-watch.out"
grep -Fqx "brave	Paused	Artist Name	Track Title" "$work/media-watch.out"

DWM_TEST_PLAYER_MODE=none \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" media-watch >"$work/media-watch-none.out"
grep -Fqx "MEDIA none" "$work/media-watch-none.out"

DWM_TEST_PLAYERCTL_LOG="$work/playerctl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" media-play-pause
grep -Fqx "play-pause" "$work/playerctl.log"

: >"$work/playerctl.log"
DWM_TEST_PLAYERCTL_LOG="$work/playerctl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" media-next
grep -Fqx "next" "$work/playerctl.log"

: >"$work/playerctl.log"
DWM_TEST_PLAYERCTL_LOG="$work/playerctl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" media-previous
grep -Fqx "previous" "$work/playerctl.log"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" bluetooth-status >"$work/bluetooth.out"
grep -Fqx "BT 0" "$work/bluetooth.out"

DWM_TEST_BT_CONNECTED=2 \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-status >"$work/bluetooth-connected.out"
grep -Fqx "BT 2" "$work/bluetooth-connected.out"

DWM_TEST_BT_MODE=off \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-status >"$work/bluetooth-off.out"
grep -Fqx "BT off" "$work/bluetooth-off.out"

DWM_TEST_BT_MODE=none \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-status >"$work/bluetooth-none.out"
grep -Fqx "BT unavailable" "$work/bluetooth-none.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" bluetooth-snapshot >"$work/bluetooth-snapshot.out"
grep -Fqx "connectivity-protocol	1	0" "$work/bluetooth-snapshot.out"
grep -Fqx "provider	bluetooth	available	delegated	BlueZ state and user-authorized device actions" "$work/bluetooth-snapshot.out"
grep -Fqx "bluetooth-support	daemon	available	BlueZ ObjectManager is reachable" "$work/bluetooth-snapshot.out"
grep -Fqx "bluetooth-support	adapter	available	A BlueZ adapter object is present" "$work/bluetooth-snapshot.out"
grep -Fqx "bluetooth-support	operations	delegated	Fixed bluetoothctl actions are available" "$work/bluetooth-snapshot.out"
grep -Fqx "bluetooth-adapter	/org/bluez/hci0	00:11:22:33:44:55	Test Adapter	yes	no	yes" "$work/bluetooth-snapshot.out"
grep -Fqx "bluetooth-device	/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02	AA:BB:CC:DD:EE:02	Keyboard	yes	no	no	/org/bluez/hci0" "$work/bluetooth-snapshot.out"

mkdir -p "$work/read-only-bin"
ln -s "$work/bin/busctl" "$work/read-only-bin/busctl"
for command_name in cat jq timeout; do
	ln -s "$(command -v "$command_name")" "$work/read-only-bin/$command_name"
done
PATH="$work/read-only-bin" "$repo/scripts/dwm-quickshell-controls" bluetooth-snapshot >"$work/bluetooth-read-only.out"
grep -Fqx "provider	bluetooth	available	read-only	BlueZ state is readable but bluetoothctl actions are unavailable" "$work/bluetooth-read-only.out"
grep -Fqx "bluetooth-support	operations	unavailable	bluetoothctl is not installed" "$work/bluetooth-read-only.out"

DWM_TEST_BLUEZ_MODE=restricted PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-snapshot >"$work/bluetooth-restricted.out"
grep -Fqx "provider	bluetooth	restricted	read-only	BlueZ is available but no adapter is present" "$work/bluetooth-restricted.out"
grep -Fqx "bluetooth-support	adapter	unavailable	No BlueZ adapter object is present" "$work/bluetooth-restricted.out"

DWM_TEST_BLUEZ_MODE=unavailable PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-snapshot >"$work/bluetooth-unavailable.out"
grep -Fqx "provider	bluetooth	unavailable	read-only	BlueZ daemon is unavailable" "$work/bluetooth-unavailable.out"
grep -Fqx "bluetooth-support	daemon	unavailable	BlueZ ObjectManager is unreachable" "$work/bluetooth-unavailable.out"

DWM_TEST_BLUEZ_MODE=malformed PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-snapshot >"$work/bluetooth-malformed.out" 2>/dev/null
grep -Fqx "provider	bluetooth	unavailable	read-only	BlueZ returned an invalid ObjectManager response" "$work/bluetooth-malformed.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" bluetooth-devices >"$work/bluetooth-devices.out"
grep -Fqx "$(printf 'AA:BB:CC:DD:EE:01\tHeadphones\tyes\tyes')" "$work/bluetooth-devices.out"
grep -Fqx "$(printf 'AA:BB:CC:DD:EE:02\tKeyboard\tno\tno')" "$work/bluetooth-devices.out"

: >"$work/bluetoothctl.log"
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-scan >"$work/bluetooth-scan.out"
grep -Fqx "scan" "$work/bluetoothctl.log"
grep -Fqx "$(printf 'AA:BB:CC:DD:EE:01\tHeadphones\tyes\tyes')" "$work/bluetooth-scan.out"

: >"$work/bluetoothctl.log"
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-power on
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-power off
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-pair AA:BB:CC:DD:EE:02
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-connect AA:BB:CC:DD:EE:02
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-disconnect AA:BB:CC:DD:EE:01
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-trust AA:BB:CC:DD:EE:02
DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-remove AA:BB:CC:DD:EE:02
grep -Fqx "power on" "$work/bluetoothctl.log"
grep -Fqx "power off" "$work/bluetoothctl.log"
grep -Fqx "pair AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"
grep -Fqx "trust AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"
grep -Fqx "connect AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"
grep -Fqx "disconnect AA:BB:CC:DD:EE:01" "$work/bluetoothctl.log"
grep -Fqx "trust AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"
grep -Fqx "remove AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"

: >"$work/bluetoothctl.log"
if DWM_TEST_BT_PAIR_FAIL=1 DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-pair AA:BB:CC:DD:EE:02; then
	printf 'Bluetooth helper continued after a pair failure.\n' >&2
	exit 1
fi
grep -Fqx "pair AA:BB:CC:DD:EE:02" "$work/bluetoothctl.log"
if grep -Eq '^(trust|connect) ' "$work/bluetoothctl.log"; then
	exit 1
fi

if DWM_TEST_BT_ACTION_FAIL=1 DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-connect AA:BB:CC:DD:EE:02; then
	printf 'Bluetooth helper hid an attributed action failure.\n' >&2
	exit 1
fi
if DWM_TEST_BLUETOOTHCTL_LOG="$work/bluetoothctl.log" PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" bluetooth-connect not-an-address 2>"$work/bluetooth-address.err"; then
	printf 'Bluetooth helper accepted a non-canonical device address.\n' >&2
	exit 1
fi

DWM_TEST_PACTL_LOG="$work/pactl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-up 5%
grep -Fqx "volume up" "$work/pactl.log"

: >"$work/pactl.log"
DWM_TEST_PACTL_LOG="$work/pactl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-down 5%
grep -Fqx "volume down" "$work/pactl.log"

: >"$work/pactl.log"
DWM_TEST_PACTL_LOG="$work/pactl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-set 35%
grep -Fqx "volume set 35%" "$work/pactl.log"

: >"$work/pactl.log"
DWM_TEST_PACTL_LOG="$work/pactl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-toggle-mute
grep -Fqx "mute toggle" "$work/pactl.log"

: >"$work/pactl.log"
DWM_TEST_PACTL_LOG="$work/pactl.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" output-set-default bluez_output.00_11_22_33_44_55.a2dp-sink
grep -Fqx "default sink bluez_output.00_11_22_33_44_55.a2dp-sink" "$work/pactl.log"
grep -Fqx "move sink input 21 bluez_output.00_11_22_33_44_55.a2dp-sink" "$work/pactl.log"
grep -Fqx "move sink input 22 bluez_output.00_11_22_33_44_55.a2dp-sink" "$work/pactl.log"

rm -f "$work/bin/pactl"
cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$work/bin/pactl"

cat >"$work/bin/wpctl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
"get-volume @DEFAULT_AUDIO_SINK@")
	printf 'Volume: 0.55%s\n' "${DWM_TEST_WPCTL_MUTED:-}"
	;;
"get-volume @DEFAULT_AUDIO_SOURCE@")
	printf 'Volume: 0.70%s\n' "${DWM_TEST_WPCTL_SOURCE_MUTED:-}"
	;;
status)
	cat <<'OUT'
PipeWire 'pipewire-0'

Audio
 ├─ Devices:
 │      49. Built-in Audio [alsa]
 │
 ├─ Sinks:
 │      47. Built-in Audio Analog Stereo [vol: 0.24]
 │  *   59. USB Headphones [vol: 1.00]
 │
 ├─ Sources:
 │      42. Built-in Audio Analog Stereo [vol: 1.00]
OUT
	;;
set-default\ *)
	printf 'wpctl default %s\n' "$2" >>"$DWM_TEST_WPCTL_LOG"
	;;
*)
	printf 'unexpected wpctl call: %s\n' "$*" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/wpctl"

PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/wpctl.out"
grep -Fqx "VOL 55%" "$work/wpctl.out"

DWM_TEST_WPCTL_MUTED=" [MUTED]" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-quickshell-controls" volume-status >"$work/wpctl-muted.out"
grep -Fqx "VOL muted 55%" "$work/wpctl-muted.out"

PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" mic-status >"$work/wpctl-mic.out"
grep -Fqx "MIC on" "$work/wpctl-mic.out"

DWM_TEST_WPCTL_SOURCE_MUTED=" [MUTED]" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-quickshell-controls" mic-status >"$work/wpctl-mic-muted.out"
grep -Fqx "MIC muted" "$work/wpctl-mic-muted.out"

PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" output-devices >"$work/wpctl-output-devices.out"
grep -Fqx "47	Built-in Audio Analog Stereo	0" "$work/wpctl-output-devices.out"
grep -Fqx "59	USB Headphones	1" "$work/wpctl-output-devices.out"

DWM_TEST_WPCTL_LOG="$work/wpctl.log" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-quickshell-controls" output-set-default 47
grep -Fqx "wpctl default 47" "$work/wpctl.log"

cat >"$work/bin/wpctl" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$work/bin/wpctl"

PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/unavailable.out"
grep -Fqx "VOL unavailable" "$work/unavailable.out"
PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" audio-snapshot >"$work/audio-unavailable.out"
grep -Fqx "provider	audio	unavailable	read-only	PipeWire PulseAudio interface is unavailable" "$work/audio-unavailable.out"

printf 'Quickshell controls helper: PASS\n'
