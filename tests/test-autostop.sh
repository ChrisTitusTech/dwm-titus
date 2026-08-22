#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
TEST_REAL_UID=$(id -u)
export TEST_REAL_UID
status_pids=
status_identities=

track_status_pid() {
	tracked_pid=$1
	tracked_starttime=$(awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			if (fields[1] != "Z" && fields[20] ~ /^[0-9]+$/)
				print fields[20]
		}
	' "/proc/$tracked_pid/stat" 2>/dev/null || true)
	[ -n "$tracked_starttime" ]
	status_pids="$status_pids $tracked_pid"
	status_identities="$status_identities $tracked_pid:$tracked_starttime"
}

forget_status_pid() {
	forgotten_pid=$1
	remaining_pids=
	for recorded_pid in $status_pids; do
		[ "$recorded_pid" = "$forgotten_pid" ] || remaining_pids="$remaining_pids $recorded_pid"
	done
	status_pids=$remaining_pids
	remaining_identities=
	for recorded_identity in $status_identities; do
		[ "${recorded_identity%%:*}" = "$forgotten_pid" ] ||
			remaining_identities="$remaining_identities $recorded_identity"
	done
	status_identities=$remaining_identities
}

status_identity_is_live() {
	test_identity=$1
	test_pid=${test_identity%%:*}
	test_starttime=${test_identity#*:}
	test_record=$(awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			if (fields[1] != "Z" && fields[20] ~ /^[0-9]+$/)
				print fields[20]
		}
	' "/proc/$test_pid/stat" 2>/dev/null || true)
	[ "$test_record" = "$test_starttime" ]
}

cleanup() {
	set +e
	for cleanup_identity in $status_identities; do
		status_identity_is_live "$cleanup_identity" || continue
		kill -TERM "${cleanup_identity%%:*}" 2>/dev/null || true
	done
	cleanup_attempt=0
	while [ "$cleanup_attempt" -lt 20 ]; do
		cleanup_live=0
		for cleanup_identity in $status_identities; do
			status_identity_is_live "$cleanup_identity" && cleanup_live=1
		done
		[ "$cleanup_live" -eq 1 ] || break
		cleanup_attempt=$((cleanup_attempt + 1))
		sleep 0.05
	done
	for cleanup_identity in $status_identities; do
		status_identity_is_live "$cleanup_identity" || continue
		kill -KILL "${cleanup_identity%%:*}" 2>/dev/null || true
	done
	for cleanup_pid in $status_pids; do
		wait "$cleanup_pid" 2>/dev/null || true
	done
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work/bin"

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >>"${TEST_LOG:?}"
exit "${TEST_SYSTEMCTL_STATUS:-0}"
EOF

cat >"$work/bin/loginctl" <<'EOF'
#!/bin/sh
printf 'loginctl %s\n' "$*" >>"${TEST_LOG:?}"
case "$*" in
"show-session self -p Id --value")
	self_session=${TEST_SELF_SESSION-${XDG_SESSION_ID:-}}
	[ -n "$self_session" ] || exit 1
	printf '%s\n' "$self_session"
	;;
"show-session "*" -p Name -p Type -p Class -p Active -p Display")
	if [ "${2:-}" = "${TEST_OTHER_SESSION_ID:-not-an-id}" ]; then
		printf 'Name=%s\nType=%s\nClass=%s\nActive=%s\nDisplay=%s\n' \
			"${TEST_OTHER_SESSION_OWNER:-test-user}" \
			"${TEST_OTHER_SESSION_TYPE:-x11}" \
			"${TEST_OTHER_SESSION_CLASS:-user}" \
			"${TEST_OTHER_SESSION_ACTIVE:-yes}" \
			"${TEST_OTHER_SESSION_DISPLAY-:1}"
	else
		printf 'Name=%s\nType=%s\nClass=%s\nActive=%s\nDisplay=%s\n' \
			"${TEST_SESSION_OWNER:-test-user}" \
			"${TEST_SESSION_TYPE:-x11}" \
			"${TEST_SESSION_CLASS:-user}" \
			"${TEST_SESSION_ACTIVE:-yes}" \
			"${TEST_SESSION_DISPLAY-:0}"
	fi
	;;
"show-session "*" -p Name -p Type -p Class -p Active")
	[ "${TEST_OTHER_SESSION_STATUS:-0}" -eq 0 ] || exit "$TEST_OTHER_SESSION_STATUS"
	printf 'Name=%s\nType=%s\nClass=%s\nActive=%s\n' \
		"${TEST_OTHER_SESSION_OWNER:-test-user}" \
		"${TEST_OTHER_SESSION_TYPE:-x11}" \
		"${TEST_OTHER_SESSION_CLASS:-user}" \
		"${TEST_OTHER_SESSION_ACTIVE:-yes}"
	;;
"show-user ${TEST_REAL_UID:?} -p Sessions --value")
	[ "${TEST_SHOW_USER_STATUS:-0}" -eq 0 ] || exit "$TEST_SHOW_USER_STATUS"
	printf '%s\n' "${TEST_USER_SESSIONS:-${XDG_SESSION_ID:-${TEST_SELF_SESSION:-}}}"
	;;
"terminate-session "*) ;;
*) exit 1 ;;
esac
EOF

cat >"$work/bin/id" <<'EOF'
#!/bin/sh
case "${1:-}" in
-u) printf '%s\n' "${TEST_REAL_UID:?}" ;;
-un) printf '%s\n' test-user ;;
*) exit 1 ;;
esac
EOF

cat >"$work/bin/dwm-status" <<'EOF'
#!/bin/sh
: >"${TEST_STATUS_READY:?}"
replace_identity() {
	if [ -n "${TEST_STATUS_REPLACEMENT_IDENTITY:-}" ]; then
		printf '%s\n' "$TEST_STATUS_REPLACEMENT_IDENTITY" >"${TEST_STATUS_IDENTITY_FILE:?}"
	fi
	exit 0
}
trap replace_identity HUP INT
if [ "${TEST_STATUS_IGNORE_TERM:-0}" = 1 ]; then
	trap '' TERM
else
	trap replace_identity TERM
fi
while :; do
	sleep 0.1
done
EOF

chmod +x "$work/bin/systemctl" "$work/bin/loginctl" "$work/bin/id" "$work/bin/dwm-status"

run_case() {
	case_name=$1
	shift
	case_log=$work/$case_name.log
	: >"$case_log"
	env TEST_LOG="$case_log" PATH="$work/bin:/usr/bin:/bin" DISPLAY=:0 "$@" \
		sh "$repo_dir/scripts/autostop.sh"
}

run_case normal env XDG_SESSION_ID=42
cat >"$work/normal.expected" <<EOF
loginctl show-session self -p Id --value
loginctl show-session 42 -p Name -p Type -p Class -p Active -p Display
loginctl show-user $TEST_REAL_UID -p Sessions --value
systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target
loginctl terminate-session 42
EOF
cmp "$work/normal.expected" "$work/normal.log"

mkdir -p "$work/status-runtime/dwm-titus"
chmod 700 "$work/status-runtime"
DISPLAY=:0 XDG_RUNTIME_DIR="$work/status-runtime" \
	TEST_STATUS_READY="$work/status.ready" "$work/bin/dwm-status" &
status_pid=$!
track_status_pid "$status_pid"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -e "$work/status.ready" ] && break
	sleep 0.02
done
status_starttime=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$status_pid/stat")
status_key=$(printf '%s' :0 | sha256sum | awk '{ print $1 }')
status_identity=$work/status-runtime/dwm-titus/dwm-status.$status_key.identity
printf '%s:%s\n' "$status_pid" "$status_starttime" >"$status_identity"

run_case startx env XDG_SESSION_ID=43 TEST_SESSION_TYPE=tty TEST_SESSION_DISPLAY= \
	XDG_RUNTIME_DIR="$work/status-runtime"
grep -Fqx 'systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target' \
	"$work/startx.log"
if grep -q '^loginctl terminate-session ' "$work/startx.log"; then
	printf '%s\n' 'autostop must not terminate a startx TTY session' >&2
	exit 1
fi
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	status_state=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[1] }' "/proc/$status_pid/stat" 2>/dev/null || true)
	[ -z "$status_state" ] || [ "$status_state" = Z ] && break
	sleep 0.02
done
[ -z "$status_state" ] || [ "$status_state" = Z ]
wait "$status_pid" 2>/dev/null || true
forget_status_pid "$status_pid"
[ ! -e "$status_identity" ]

DISPLAY=:0 XDG_RUNTIME_DIR="$work/status-runtime" \
	TEST_STATUS_READY="$work/status-race.ready" "$work/bin/dwm-status" &
replacement_pid=$!
track_status_pid "$replacement_pid"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -e "$work/status-race.ready" ] && break
	sleep 0.02
done
replacement_starttime=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$replacement_pid/stat")
replacement_identity=$replacement_pid:$replacement_starttime
DISPLAY=:0 XDG_RUNTIME_DIR="$work/status-runtime" \
	TEST_STATUS_READY="$work/status-old.ready" \
	TEST_STATUS_REPLACEMENT_IDENTITY="$replacement_identity" \
	TEST_STATUS_IDENTITY_FILE="$status_identity" "$work/bin/dwm-status" &
old_status_pid=$!
track_status_pid "$old_status_pid"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -e "$work/status-old.ready" ] && break
	sleep 0.02
done
old_status_starttime=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$old_status_pid/stat")
printf '%s:%s\n' "$old_status_pid" "$old_status_starttime" >"$status_identity"
run_case replacement_identity env XDG_SESSION_ID=43 TEST_SESSION_TYPE=tty TEST_SESSION_DISPLAY= \
	XDG_RUNTIME_DIR="$work/status-runtime"
wait "$old_status_pid" 2>/dev/null || true
forget_status_pid "$old_status_pid"
status_identity_is_live "$replacement_identity"
[ "$(cat "$status_identity")" = "$replacement_identity" ]

cat >"$work/bin/sh" <<'EOF'
#!/usr/bin/env bash
kill() {
	if [[ ${1:-} == -KILL && ${2:-} == "${TEST_AUTOSTOP_STUBBORN_PID:-}" ]]; then
		return 0
	fi
	builtin kill "$@"
}
script=$1
shift
. "$script" "$@"
EOF
chmod +x "$work/bin/sh"

DISPLAY=:0 XDG_RUNTIME_DIR="$work/status-runtime" \
	TEST_STATUS_READY="$work/status-stubborn.ready" TEST_STATUS_IGNORE_TERM=1 \
	"$work/bin/dwm-status" &
stubborn_pid=$!
track_status_pid "$stubborn_pid"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -e "$work/status-stubborn.ready" ] && break
	sleep 0.02
done
stubborn_starttime=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$stubborn_pid/stat")
stubborn_identity=$stubborn_pid:$stubborn_starttime
printf '%s\n' "$stubborn_identity" >"$status_identity"
run_case stubborn_survivor env XDG_SESSION_ID=43 TEST_SESSION_TYPE=tty TEST_SESSION_DISPLAY= \
	XDG_RUNTIME_DIR="$work/status-runtime" TEST_AUTOSTOP_STUBBORN_PID="$stubborn_pid"
status_identity_is_live "$stubborn_identity"
[ "$(cat "$status_identity")" = "$stubborn_identity" ]
kill -KILL "$stubborn_pid"
wait "$stubborn_pid" 2>/dev/null || true
forget_status_pid "$stubborn_pid"
rm -f "$work/bin/sh" "$status_identity"

run_case other_graphical env \
	XDG_SESSION_ID=44 \
	TEST_USER_SESSIONS='44 45' \
	TEST_OTHER_SESSION_ID=45
grep -Fqx 'loginctl show-session 45 -p Name -p Type -p Class -p Active' \
	"$work/other_graphical.log"
grep -Fqx 'loginctl terminate-session 44' "$work/other_graphical.log"
if grep -q '^systemctl ' "$work/other_graphical.log"; then
	printf '%s\n' 'autostop must preserve shared targets for another graphical login' >&2
	exit 1
fi

run_case fallback_session env \
	-u XDG_SESSION_ID \
	TEST_SELF_SESSION=46 \
	TEST_USER_SESSIONS=46
grep -Fqx 'loginctl show-session self -p Id --value' "$work/fallback_session.log"
grep -Fqx 'loginctl terminate-session 46' "$work/fallback_session.log"

run_case no_session env -u XDG_SESSION_ID TEST_SELF_SESSION=
grep -Fqx 'loginctl show-session self -p Id --value' "$work/no_session.log"
if grep -q '^systemctl \|^loginctl terminate-session ' "$work/no_session.log"; then
	printf '%s\n' 'autostop must not clean up without a verified session' >&2
	exit 1
fi

run_case mismatched_session env XDG_SESSION_ID=47 TEST_SELF_SESSION=48
grep -Fqx 'loginctl show-session self -p Id --value' "$work/mismatched_session.log"
if grep -q '^systemctl \|^loginctl terminate-session ' "$work/mismatched_session.log"; then
	printf '%s\n' 'autostop must not clean up a mismatched environment session' >&2
	exit 1
fi

run_case mismatched_display env XDG_SESSION_ID=48 DISPLAY=:150
grep -Fqx 'loginctl show-session 48 -p Name -p Type -p Class -p Active -p Display' \
	"$work/mismatched_display.log"
if grep -q '^systemctl \|^loginctl terminate-session ' "$work/mismatched_display.log"; then
	printf '%s\n' 'autostop must not clean up a login from a nested X display' >&2
	exit 1
fi

run_case screen_suffix env XDG_SESSION_ID=48 DISPLAY=:0.1
grep -Fqx 'loginctl terminate-session 48' "$work/screen_suffix.log"

run_case wrong_owner env XDG_SESSION_ID=49 TEST_SESSION_OWNER=another-user
grep -Fqx 'loginctl show-session 49 -p Name -p Type -p Class -p Active -p Display' \
	"$work/wrong_owner.log"
if grep -q '^systemctl \|^loginctl terminate-session ' "$work/wrong_owner.log"; then
	printf '%s\n' 'autostop must not clean up another user session' >&2
	exit 1
fi

run_case topology_failure env XDG_SESSION_ID=50 TEST_SHOW_USER_STATUS=1
grep -Fqx 'loginctl terminate-session 50' "$work/topology_failure.log"
if grep -q '^systemctl ' "$work/topology_failure.log"; then
	printf '%s\n' 'autostop must preserve shared targets when session discovery fails' >&2
	exit 1
fi

run_case systemctl_failure env XDG_SESSION_ID=51 TEST_SYSTEMCTL_STATUS=1
grep -Fqx 'loginctl terminate-session 51' "$work/systemctl_failure.log"

printf '%s\n' 'Autostop graphical target and login session cleanup: PASS'
