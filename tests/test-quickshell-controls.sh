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
	printf 'Volume: front-left: 26214 / 40%% / -23.88 dB, front-right: 26214 / 40%% / -23.88 dB\n'
	;;
"get-source-mute @DEFAULT_SOURCE@")
	printf 'Mute: %s\n' "${DWM_TEST_SOURCE_MUTE:-no}"
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

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" volume-status >"$work/volume.out"
grep -Fqx "VOL 40%" "$work/volume.out"

DWM_TEST_SINK_MUTE=yes \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" volume-status >"$work/muted.out"
grep -Fqx "VOL muted 40%" "$work/muted.out"

PATH="$work/bin:$PATH" "$repo/scripts/dwm-quickshell-controls" mic-status >"$work/mic.out"
grep -Fqx "MIC on" "$work/mic.out"

DWM_TEST_SOURCE_MUTE=yes \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-controls" mic-status >"$work/mic-muted.out"
grep -Fqx "MIC muted" "$work/mic-muted.out"

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
