#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

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
"show-user 1000 -p Sessions --value")
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
-u) printf '%s\n' 1000 ;;
-un) printf '%s\n' test-user ;;
*) exit 1 ;;
esac
EOF

chmod +x "$work/bin/systemctl" "$work/bin/loginctl" "$work/bin/id"

run_case() {
	case_name=$1
	shift
	case_log=$work/$case_name.log
	: >"$case_log"
	env TEST_LOG="$case_log" PATH="$work/bin:/usr/bin:/bin" DISPLAY=:0 "$@" \
		sh "$repo_dir/scripts/autostop.sh"
}

run_case normal env XDG_SESSION_ID=42
cat >"$work/normal.expected" <<'EOF'
loginctl show-session self -p Id --value
loginctl show-session 42 -p Name -p Type -p Class -p Active -p Display
loginctl show-user 1000 -p Sessions --value
systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target
loginctl terminate-session 42
EOF
cmp "$work/normal.expected" "$work/normal.log"

run_case startx env XDG_SESSION_ID=43 TEST_SESSION_TYPE=tty TEST_SESSION_DISPLAY=
grep -Fqx 'systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target' \
	"$work/startx.log"
if grep -q '^loginctl terminate-session ' "$work/startx.log"; then
	printf '%s\n' 'autostop must not terminate a startx TTY session' >&2
	exit 1
fi

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
