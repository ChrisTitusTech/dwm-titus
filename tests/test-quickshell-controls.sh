#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"

cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
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
"get-source-mute @DEFAULT_SOURCE@")
	printf 'Mute: %s\n' "${DWM_TEST_SOURCE_MUTE:-no}"
	;;
"subscribe")
	if [ -n "${DWM_TEST_SINK_VOLUME_FILE:-}" ]; then
		printf '45\n' >"$DWM_TEST_SINK_VOLUME_FILE"
	fi
	printf "Event 'change' on sink #1\n"
	;;
"set-sink-volume @DEFAULT_SINK@ +5%")
	printf 'volume up\n' >>"$DWM_TEST_PACTL_LOG"
	;;
"set-sink-volume @DEFAULT_SINK@ -5%")
	printf 'volume down\n' >>"$DWM_TEST_PACTL_LOG"
	;;
"set-sink-mute @DEFAULT_SINK@ toggle")
	printf 'mute toggle\n' >>"$DWM_TEST_PACTL_LOG"
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
*)
	printf 'unexpected bluetoothctl call: %s\n' "$*" >&2
	exit 1
	;;
esac
SH
chmod +x "$work/bin/bluetoothctl"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/volume.out"
grep -Fqx "VOL 40%" "$work/volume.out"

DWM_TEST_SINK_MUTE=yes \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-status >"$work/muted.out"
grep -Fqx "VOL muted 40%" "$work/muted.out"

printf '40\n' >"$work/volume-state"
DWM_TEST_SINK_VOLUME_FILE="$work/volume-state" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-watch >"$work/volume-watch.out"
grep -Fqx "VOL 40%" "$work/volume-watch.out"
grep -Fqx "VOL 45%" "$work/volume-watch.out"

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
	"$repo/scripts/dwm-quickshell-controls" volume-toggle-mute
grep -Fqx "mute toggle" "$work/pactl.log"

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

cat >"$work/bin/wpctl" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$work/bin/wpctl"

PATH="$work/bin:/usr/bin:/bin" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/unavailable.out"
grep -Fqx "VOL unavailable" "$work/unavailable.out"

printf 'Quickshell controls helper: PASS\n'
