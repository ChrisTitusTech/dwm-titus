#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
helper=$repo/scripts/dwm-accessibility-settings
work=$(mktemp -d)
watch_pid=
race_pid=
lock_pid=

cleanup() {
	for cleanup_pid in "$watch_pid" "$race_pid" "$lock_pid"; do
		[ -n "$cleanup_pid" ] || continue
		kill "$cleanup_pid" 2>/dev/null || true
		wait "$cleanup_pid" 2>/dev/null || true
	done
	rm -rf "$work"
}
trap cleanup EXIT

home=$work/home
config=$work/config
runtime=$work/runtime
mkdir -p "$home" "$config" "$runtime"

run_helper() {
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime "$helper" "$@"
}

wait_for_path() {
	path=$1
	for _ in $(seq 1 200); do
		[ -e "$path" ] && return 0
		sleep 0.01
	done
	return 1
}

wait_for_line() {
	line_file=$1
	line_value=$2
	for _ in $(seq 1 200); do
		grep -Fqx "$line_value" "$line_file" 2>/dev/null && return 0
		sleep 0.01
	done
	return 1
}

status=$(run_helper status)
printf '%s\n' "$status" | grep -Fqx 'accessibility-settings-protocol	1	0'
printf '%s\n' "$status" | grep -Fqx \
	'state	defaults	Using standard contrast and full motion defaults'
printf '%s\n' "$status" | grep -Fqx 'setting	contrast	standard'
printf '%s\n' "$status" | grep -Fqx 'setting	motion	full'
printf '%s\n' "$status" | grep -Fqx 'complete	status'
printf '%s\n' "$status" | grep -Fqx \
	'mutation	available	Accessibility policy can be updated'

HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" watch >"$work/first-watch.out" 2>"$work/first-watch.err" &
watch_pid=$!
wait_for_line "$work/first-watch.out" 'ready	accessibility'
[ -d "$config/dwm-titus" ]
watch_child=$(pgrep -P "$watch_pid" -x inotifywait)
kill "$watch_child"
for _ in $(seq 1 200); do
	! kill -0 "$watch_pid" 2>/dev/null && break
	sleep 0.01
done
if kill -0 "$watch_pid" 2>/dev/null; then
	printf 'Accessibility watcher hid inotifywait termination\n' >&2
	exit 1
fi
if wait "$watch_pid"; then
	printf 'Accessibility watcher unexpectedly succeeded after inotifywait termination\n' >&2
	exit 1
fi
watch_pid=

contrast_action=$(run_helper set contrast high)
printf '%s\n' "$contrast_action" | grep -Fqx 'accessibility-settings-action-protocol	1	0'
printf '%s\n' "$contrast_action" | grep -Fqx 'result	set	contrast	high'
[ "$(stat -c %a "$config/dwm-titus/accessibility.conf")" = 600 ]

motion_action=$(run_helper set motion reduced)
printf '%s\n' "$motion_action" | grep -Fqx 'result	set	motion	reduced'
status=$(run_helper status)
printf '%s\n' "$status" | grep -Fqx \
	'state	available	Persistent managed-shell accessibility policy is active'
printf '%s\n' "$status" | grep -Fqx 'setting	contrast	high'
printf '%s\n' "$status" | grep -Fqx 'setting	motion	reduced'

chmod 640 "$config/dwm-titus/accessibility.conf"
run_helper set contrast standard >/dev/null
[ "$(stat -c %a "$config/dwm-titus/accessibility.conf")" = 640 ]

reset_action=$(run_helper reset)
printf '%s\n' "$reset_action" | grep -Fqx 'result	reset	all	defaults'
grep -Fqx 'contrast	standard' "$config/dwm-titus/accessibility.conf"
grep -Fqx 'motion	full' "$config/dwm-titus/accessibility.conf"

HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" watch >"$work/watch.out" 2>"$work/watch.err" &
watch_pid=$!
wait_for_line "$work/watch.out" 'ready	accessibility'
run_helper set contrast high >/dev/null
for _ in $(seq 1 200); do
	grep -Eq '^changed	' "$work/watch.out" 2>/dev/null && break
	sleep 0.01
done
grep -Eq '^changed	' "$work/watch.out"
rm "$config/dwm-titus/accessibility.conf"
rmdir "$config/dwm-titus"
for _ in $(seq 1 200); do
	grep -Fq 'DELETE_SELF' "$work/watch.out" 2>/dev/null && break
	sleep 0.01
done
grep -Fq 'DELETE_SELF' "$work/watch.out"
kill "$watch_pid" 2>/dev/null || true
wait "$watch_pid" 2>/dev/null || true
watch_pid=
mkdir "$config/dwm-titus"

printf 'broken-protocol\n' >"$config/dwm-titus/accessibility.conf"
malformed_status=$(run_helper status)
printf '%s\n' "$malformed_status" | grep -Fqx \
	'state	partial	Malformed accessibility settings were preserved; using safe defaults'
printf '%s\n' "$malformed_status" | grep -Fqx 'setting	contrast	standard'
printf '%s\n' "$malformed_status" | grep -Fqx 'setting	motion	full'
printf '%s\n' "$malformed_status" | grep -Fqx \
	'mutation	available	Accessibility policy can be updated'
run_helper set motion reduced >/dev/null
grep -Fqx 'contrast	standard' "$config/dwm-titus/accessibility.conf"
grep -Fqx 'motion	reduced' "$config/dwm-titus/accessibility.conf"

printf 'accessibility-settings-protocol	1	0	extra\ncontrast	high\nmotion	reduced\n' \
	>"$config/dwm-titus/accessibility.conf"
malformed_header_status=$(run_helper status)
printf '%s\n' "$malformed_header_status" | grep -Fqx \
	'state	partial	Malformed accessibility settings were preserved; using safe defaults'
run_helper reset >/dev/null
grep -Fqx 'accessibility-settings-protocol	1	0' "$config/dwm-titus/accessibility.conf"
grep -Fqx 'contrast	standard' "$config/dwm-titus/accessibility.conf"
grep -Fqx 'motion	full' "$config/dwm-titus/accessibility.conf"

printf 'accessibility-settings-protocol	2	0\ncontrast	high\nmotion	reduced\n' \
	>"$config/dwm-titus/accessibility.conf"
future_status=$(run_helper status)
printf '%s\n' "$future_status" | grep -Fqx \
	'state	partial	Unsupported accessibility settings version was preserved; using safe defaults'
printf '%s\n' "$future_status" | grep -Fqx \
	'mutation	unavailable	Persistent accessibility state cannot be safely replaced'
grep -Fqx 'accessibility-settings-protocol	2	0' "$config/dwm-titus/accessibility.conf"
cp "$config/dwm-titus/accessibility.conf" "$work/future.before"
if run_helper set contrast high >"$work/future-set.out" 2>"$work/future-set.err"; then
	printf 'Future accessibility state was unexpectedly replaced by set\n' >&2
	exit 1
fi
grep -Fq 'unsupported version' "$work/future-set.err"
cmp "$work/future.before" "$config/dwm-titus/accessibility.conf"
if run_helper reset >"$work/future-reset.out" 2>"$work/future-reset.err"; then
	printf 'Future accessibility state was unexpectedly replaced by reset\n' >&2
	exit 1
fi
grep -Fq 'unsupported version' "$work/future-reset.err"
cmp "$work/future.before" "$config/dwm-titus/accessibility.conf"

printf 'accessibility-settings-protocol	1	0\ncontrast	standard\nmotion	full\n' \
	>"$config/dwm-titus/accessibility.conf"
exchange_ready=$work/exchange.ready
exchange_release=$work/exchange.release
rollback_ready=$work/rollback.ready
rollback_release=$work/rollback.release
DWM_TEST_ACCESSIBILITY_EXCHANGE_READY=$exchange_ready \
	DWM_TEST_ACCESSIBILITY_EXCHANGE_RELEASE=$exchange_release \
	DWM_TEST_ACCESSIBILITY_ROLLBACK_READY=$rollback_ready \
	DWM_TEST_ACCESSIBILITY_ROLLBACK_RELEASE=$rollback_release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set contrast high >"$work/race.out" 2>"$work/race.err" &
race_pid=$!
wait_for_path "$exchange_ready"
printf 'first last-moment edit\n' >"$config/dwm-titus/accessibility.conf"
: >"$exchange_release"
wait_for_path "$rollback_ready"
printf 'second last-moment edit\n' >"$config/dwm-titus/accessibility.conf"
: >"$rollback_release"
if wait "$race_pid"; then
	printf 'Accessibility transaction overwrote a two-edit race\n' >&2
	exit 1
fi
race_pid=
grep -Fq 'accessibility state changed during the transaction' "$work/race.err"
grep -Fqx 'second last-moment edit' "$config/dwm-titus/accessibility.conf"

target=$work/target
printf 'do not replace\n' >"$target"
rm "$config/dwm-titus/accessibility.conf"
ln -s "$target" "$config/dwm-titus/accessibility.conf"
unsafe_status=$(run_helper status)
printf '%s\n' "$unsafe_status" | grep -Fqx \
	'state	unavailable	Persistent accessibility state is unsafe; using safe defaults'
if run_helper set contrast high >"$work/symlink.out" 2>"$work/symlink.err"; then
	printf 'Accessibility mutation unexpectedly followed a symlink\n' >&2
	exit 1
fi
grep -Fqx 'do not replace' "$target"

rm "$config/dwm-titus/accessibility.conf"
printf 'accessibility-settings-protocol	1	0\ncontrast	standard\nmotion	full\n' \
	>"$config/dwm-titus/accessibility.conf"
ln "$config/dwm-titus/accessibility.conf" "$work/accessibility-hardlink.conf"
if run_helper reset >"$work/hardlink.out" 2>"$work/hardlink.err"; then
	printf 'Accessibility mutation unexpectedly replaced a hard-linked file\n' >&2
	exit 1
fi
grep -Fq 'unsafe persistent state' "$work/hardlink.err"
rm "$work/accessibility-hardlink.conf"

if HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=relative \
	"$helper" status >"$work/runtime.out" 2>"$work/runtime.err"; then
	printf 'Relative runtime directory unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'XDG_RUNTIME_DIR must be absolute' "$work/runtime.err"

if run_helper set contrast invalid >"$work/invalid.out" 2>"$work/invalid.err"; then
	printf 'Invalid contrast value unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'unsupported accessibility setting' "$work/invalid.err"

lock_ready=$work/lock.ready
lock_release=$work/lock.release
(
	exec 8>"$runtime/dwm-accessibility-settings.lock"
	flock 8
	: >"$lock_ready"
	while [ ! -e "$lock_release" ]; do
		sleep 0.01
	done
) &
lock_pid=$!
while [ ! -e "$lock_ready" ]; do
	sleep 0.01
done
if run_helper set motion reduced >"$work/lock.out" 2>"$work/lock.err"; then
	printf 'Concurrent accessibility mutation unexpectedly succeeded\n' >&2
	kill "$lock_pid" 2>/dev/null || true
	exit 1
fi
grep -Fq 'another accessibility settings operation is still running' "$work/lock.err"
: >"$lock_release"
wait "$lock_pid"
lock_pid=

printf 'dwm accessibility settings helper: PASS\n'
