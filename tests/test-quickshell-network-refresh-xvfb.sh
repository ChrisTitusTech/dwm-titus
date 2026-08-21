#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable for NetworkModel refresh test\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_NETWORK_REFRESH_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_NETWORK_REFRESH_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
cleanup() {
	set +e
	for child_pid in "${quickshell_pid:-}" "${xvfb_pid:-}"; do
		[ -n "$child_pid" ] && kill "$child_pid" 2>/dev/null
	done
	for child_pid in "${quickshell_pid:-}" "${xvfb_pid:-}"; do
		[ -n "$child_pid" ] && wait "$child_pid" 2>/dev/null
	done
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

home=$work/home
runtime=$work/runtime
config_home=$home/.config
data_home=$home/.local/share
network_test_dir=$work/network-test
mkdir -p "$config_home/quickshell" "$data_home/dwm-titus/scripts" \
	"$runtime" "$network_test_dir"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
mkfifo "$network_test_dir/monitor"
printf '%s\n' ethernet >"$network_test_dir/state"
printf '%s\n' 0 >"$network_test_dir/status-count"

cat >"$config_home/quickshell/shell.qml" <<'QML'
//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import qs.network

ShellRoot {
    NetworkModel { id: networkModel }

    IpcHandler {
        target: "network-refresh-test"

        function icon(): string { return networkModel.barIconState; }
        function refresh(): void { networkModel.refresh(false); }
    }
}
QML

cat >"$data_home/dwm-titus/scripts/dwm-quickshell-network" <<'SH'
#!/bin/sh
set -eu

test_dir=${DWM_TEST_NETWORK_DIR:?}

case "${1:-}" in
status)
	count=$(cat "$test_dir/status-count")
	count=$((count + 1))
	printf '%s\n' "$count" >"$test_dir/status-count"
	snapshot=$(cat "$test_dir/state")
	if [ -e "$test_dir/block-next" ]; then
		rm -f "$test_dir/block-next"
		: >"$test_dir/status-blocked"
		while [ ! -e "$test_dir/release" ]; do sleep 0.02; done
	fi
	case "$snapshot" in
	ethernet) printf 'ethernet\tenp2s0\tWired connection 1\t-1\n' ;;
	wifi) printf 'wifi\twlan0\tTest Wi-Fi\t74\n' ;;
	*) printf 'disconnected\t\t\t-1\n' ;;
	esac
	;;
devices | connections | wifi-scan)
	:
	;;
monitor)
	: >"$test_dir/monitor-ready"
	while IFS= read -r event; do printf '%s\n' "$event"; done <"$test_dir/monitor"
	;;
editor)
	exit 127
	;;
*)
	exit 2
	;;
esac
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-quickshell-network"

Xvfb -displayfd 3 -screen 0 640x480x24 -nolisten tcp -extension GLX \
	3>"$work/display-number" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
index=0
while [ "$index" -lt 100 ] && [ ! -s "$work/display-number" ]; do
	if ! kill -0 "$xvfb_pid" 2>/dev/null; then
		cat "$work/xvfb.log" >&2
		exit 1
	fi
	index=$((index + 1))
	sleep 0.05
done
[ -s "$work/display-number" ]
display=":$(cat "$work/display-number")"
kill -0 "$xvfb_pid"

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	DWM_TEST_NETWORK_DIR="$network_test_dir" \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

config=$config_home/quickshell/shell.qml
index=0
while [ "$index" -lt 200 ]; do
	initial_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call network-refresh-test icon 2>/dev/null || true)
	[ "$initial_state" = ethernet ] && [ -e "$network_test_dir/monitor-ready" ] && break
	index=$((index + 1))
	sleep 0.05
done
if [ "${initial_state:-}" != ethernet ] || [ ! -e "$network_test_dir/monitor-ready" ]; then
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

baseline_status_count=$(cat "$network_test_dir/status-count")
: >"$network_test_dir/block-next"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" \
	call network-refresh-test refresh >/dev/null
index=0
while [ "$index" -lt 100 ] && [ ! -e "$network_test_dir/status-blocked" ]; do
	index=$((index + 1))
	sleep 0.05
done
[ -e "$network_test_dir/status-blocked" ]
printf '%s\n' wifi >"$network_test_dir/state"
printf 'changed-1\nchanged-2\nchanged-3\n' >"$network_test_dir/monitor"
sleep 0.2
: >"$network_test_dir/release"

expected_status_count=$((baseline_status_count + 2))
index=0
while [ "$index" -lt 20 ]; do
	trailing_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call network-refresh-test icon 2>/dev/null || true)
	status_count=$(cat "$network_test_dir/status-count")
	[ "$trailing_state" = wifi ] && [ "$status_count" -eq "$expected_status_count" ] && break
	index=$((index + 1))
	sleep 0.05
done
[ "${trailing_state:-}" = wifi ]
[ "$(cat "$network_test_dir/status-count")" -eq "$expected_status_count" ]

printf 'NetworkModel coalesced trailing refresh: PASS\n'
