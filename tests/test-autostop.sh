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
case ${1:-} in
show-session)
	printf 'Name=%s\n' "${TEST_SESSION_OWNER:-test-user}"
	;;
esac
EOF

cat >"$work/bin/id" <<'EOF'
#!/bin/sh
case ${1:-} in
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
	env TEST_LOG="$case_log" PATH="$work/bin:/usr/bin:/bin" "$@" \
		sh "$repo_dir/scripts/autostop.sh"
}

run_case normal env XDG_SESSION_ID=42
cat >"$work/normal.expected" <<'EOF'
systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target
loginctl show-session 42 -p Name
loginctl terminate-session 42
EOF
cmp "$work/normal.expected" "$work/normal.log"

run_case no_session env -u XDG_SESSION_ID
grep -Fqx 'systemctl --user stop xdg-desktop-autostart.target wm-graphical-session.service graphical-session.target' \
	"$work/no_session.log"
if grep -q '^loginctl ' "$work/no_session.log"; then
	printf '%s\n' 'loginctl must not run without a session ID' >&2
	exit 1
fi

run_case wrong_owner env XDG_SESSION_ID=43 TEST_SESSION_OWNER=another-user
grep -Fqx 'loginctl show-session 43 -p Name' "$work/wrong_owner.log"
if grep -q '^loginctl terminate-session ' "$work/wrong_owner.log"; then
	printf '%s\n' 'autostop must not terminate another user session' >&2
	exit 1
fi

run_case systemctl_failure env XDG_SESSION_ID=44 TEST_SYSTEMCTL_STATUS=1
grep -Fqx 'loginctl terminate-session 44' "$work/systemctl_failure.log"

printf '%s\n' 'Autostop graphical target and login session cleanup: PASS'
