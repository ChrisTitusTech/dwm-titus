#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-default-apps"
BASH_BIN=${BASH:-/usr/bin/bash}
REAL_MV=$(command -v mv)
REAL_CHMOD=$(command -v chmod)

work=$(mktemp -d)
watch_pid=
watch_owner_pid=
cleanup() {
	[[ -z $watch_owner_pid ]] || kill -KILL "$watch_owner_pid" 2>/dev/null || true
	[[ -z $watch_owner_pid ]] || wait "$watch_owner_pid" 2>/dev/null || true
	[[ -z $watch_pid ]] || kill "$watch_pid" 2>/dev/null || true
	[[ -z $watch_pid ]] || wait "$watch_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/fail-bin" "$work/data/applications/vendor" "$work/home/.config/dwm-titus" \
	"$work/home/.local/state" "$work/empty"

cat >"$work/fail-bin/mv" <<'SCRIPT'
#!/bin/sh
set -eu
destination=
for argument do
	destination=$argument
done
if [ -n "${DWM_TEST_FAIL_JOURNAL_META:-}" ] &&
	[ "$destination" = "$DWM_TEST_FAIL_JOURNAL_META" ]; then
	exit 1
fi
"${DWM_TEST_REAL_MV:?}" "$@"
if [ -n "${DWM_TEST_SIGNAL_JOURNAL_META:-}" ] &&
	[ "$destination" = "$DWM_TEST_SIGNAL_JOURNAL_META" ] &&
	[ ! -e "${DWM_TEST_SIGNAL_MARKER:?}" ]; then
	: >"$DWM_TEST_SIGNAL_MARKER"
	kill -TERM "$PPID"
fi
if [ -n "${DWM_TEST_SIGNAL_RESET_TARGET:-}" ] &&
	[ "$destination" = "$DWM_TEST_SIGNAL_RESET_TARGET" ] &&
	[ ! -e "${DWM_TEST_SIGNAL_MARKER:?}" ]; then
	: >"$DWM_TEST_SIGNAL_MARKER"
	kill -TERM "$PPID"
fi
SCRIPT

cat >"$work/fail-bin/chmod" <<'SCRIPT'
#!/bin/sh
set -eu
target=
for argument do
	target=$argument
done
case $target in
*.dwm-default-apps.restore.*)
	[ "${DWM_TEST_FAIL_RESET_CHMOD:-0}" -ne 1 ] || exit 1
	;;
esac
exec "${DWM_TEST_REAL_CHMOD:?}" "$@"
SCRIPT
chmod +x "$work/fail-bin/mv" "$work/fail-bin/chmod"

cat >"$work/data/applications/firefox.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Firefox
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Exec=firefox %u
DESKTOP

cat >"$work/data/applications/brave.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Brave
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Exec=brave %u
DESKTOP

cat >"$work/data/applications/org.example.Files.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Files
Categories=System;FileManager;
MimeType=inode/directory;
Exec=files %U
DESKTOP

cat >"$work/data/applications/org.example.Editor.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Editor
Categories=Utility;TextEditor;
MimeType=text/plain;
Exec=editor %F
DESKTOP

cat >"$work/data/applications/Alacritty.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Alacritty
Categories=System;TerminalEmulator;
TryExec=alacritty
Exec=alacritty
DESKTOP

cat >"$work/data/applications/kitty.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=kitty
Categories=System;TerminalEmulator;
TryExec=kitty
Exec=kitty
DESKTOP

cat >"$work/data/applications/hidden.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Hidden Browser
Hidden=true
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;
Exec=hidden
DESKTOP

cat >"$work/data/applications/not-an-app.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Link
Name=Not an app
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;
DESKTOP

cat >"$work/data/applications/chromium.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Stale Chromium
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Exec=/usr/bin/missing-dwm-test-chromium %U
DESKTOP

cat >"$work/data/applications/duplicate.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Type=Link
Name=Duplicate Browser
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;
Exec=firefox %u
DESKTOP

{
	printf '%s\n' \
		'[Desktop Entry]' \
		'Type=Application' \
		'Name=Oversized Browser' \
		'Categories=Network;WebBrowser;' \
		'MimeType=text/html;x-scheme-handler/http;' \
		'Exec=firefox %u'
	dd if=/dev/zero bs=262145 count=1 status=none | tr '\0' x
} >"$work/data/applications/oversized.desktop"

printf '[Desktop Entry]\nType=Application\nName=Control\001Browser\nCategories=Network;WebBrowser;\nMimeType=text/html;x-scheme-handler/http;\nExec=firefox %%u\n' \
	>"$work/data/applications/control.desktop"

cat >"$work/data/applications/st.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=st
Categories=System;TerminalEmulator;
Exec=/usr/bin/missing-dwm-test-st
DESKTOP

cat >"$work/data/applications/vendor/nested.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Nested Browser
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;
Exec=firefox %u
DESKTOP

mkdir -p "$work/outside-applications"
cp "$work/data/applications/firefox.desktop" "$work/outside-applications/escaped.desktop"
ln -s "$work/outside-applications" "$work/data/applications/linked"
ln -s "$work/data/applications/firefox.desktop" \
	"$work/data/applications/linked-leaf.desktop"
mkdir -p "$work/symlink-data"
ln -s "$work/outside-applications" "$work/symlink-data/applications"

cat >"$work/bin/xdg-mime" <<'SCRIPT'
#!/bin/sh
set -eu
mime_file=${XDG_CONFIG_HOME:?}/mimeapps.list
log=${DWM_TEST_STATE:?}/log
query_default() {
	awk -F= -v mime="$1" '
		$0 == "[Default Applications]" { in_defaults = 1; next }
		in_defaults && /^\[/ { exit }
		in_defaults && $1 == mime {
			value = substr($0, index($0, "=") + 1)
			sub(/;.*/, "", value)
			print value
			exit
		}
	' "$mime_file" 2>/dev/null || true
}
case ${1:-}:${2:-} in
query:default)
	query_default "${3:-}"
	;;
default:*)
	application=${2:-}
	mime=${3:-}
	count=0
	[ ! -f "$DWM_TEST_STATE/count" ] || count=$(cat "$DWM_TEST_STATE/count")
	count=$((count + 1))
	printf '%s\n' "$count" >"$DWM_TEST_STATE/count"
	printf 'xdg-mime default %s %s\n' "$application" "$mime" >>"$log"
	[ "${DWM_TEST_FAIL_AT:-}" != "$count" ] || exit 1
	[ "${DWM_TEST_NONCONVERGE_MIME:-}" != "$mime" ] || application=brave.desktop
	mkdir -p "${mime_file%/*}"
	tmp=$(mktemp "${mime_file%/*}/.mimeapps.mock.XXXXXX")
	awk -v mime="$mime" -v application="$application" '
		BEGIN { in_defaults = 0; found_section = 0; written = 0 }
		$0 == "[Default Applications]" {
			in_defaults = 1
			found_section = 1
			print
			next
		}
		in_defaults && /^\[/ {
			if (!written) print mime "=" application
			written = 1
			in_defaults = 0
		}
		in_defaults && index($0, mime "=") == 1 {
			if (!written) print mime "=" application
			written = 1
			next
		}
		{ print }
		END {
			if (!found_section) print "[Default Applications]"
			if (!written) print mime "=" application
		}
	' "$mime_file" 2>/dev/null >"$tmp" || {
		printf '[Default Applications]\n%s=%s\n' "$mime" "$application" >"$tmp"
	}
	mv "$tmp" "$mime_file"
	;;
*) exit 2 ;;
esac
SCRIPT

cat >"$work/bin/xdg-settings" <<'SCRIPT'
#!/bin/sh
set -eu
printf 'xdg-settings %s\n' "$*" >>"${DWM_TEST_STATE:?}/settings-log"
if [ "$#" -eq 2 ] && [ "$1" = get ] && [ "$2" = default-web-browser ]; then
	exec xdg-mime query default x-scheme-handler/http
fi
exit 2
SCRIPT

cat >"$work/bin/xdg-open" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$1" >"${DWM_TEST_STATE:?}/opened"
SCRIPT

for command_name in alacritty kitty firefox brave files editor; do
	cat >"$work/bin/$command_name" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
done
chmod +x "$work/bin/"*

cat >"$work/home/.config/mimeapps.list" <<'EOF'
# user comment
[Default Applications]
x-scheme-handler/http=brave.desktop
x-scheme-handler/https=brave.desktop
text/html=brave.desktop
application/xhtml+xml=brave.desktop
inode/directory=org.example.Files.desktop
text/plain=org.example.Editor.desktop
application/x-unrelated=keep.desktop

[Added Associations]
application/x-unrelated=other.desktop;
EOF
chmod 640 "$work/home/.config/mimeapps.list"

cat >"$work/home/.config/dwm-titus/hotkeys.toml" <<'EOF'
[vars]
terminal = "alacritty"
webapp = "webapp-launch"

keys = [
  { mod="SUPER", key="x", desc="Terminal", func="spawn", exec=["$terminal"] },
  { mod="SUPER", key="b", desc="Browser", func="spawn", exec=["dwm-default-apps", "open", "https://"] },
  { mod="SUPER", key="e", desc="File manager", func="spawn", cmd="xdg-open ." },
]
EOF
chmod 640 "$work/home/.config/dwm-titus/hotkeys.toml"

env_common=(
	DWM_TEST_STATE="$work"
	HOME="$work/home"
	PATH="$work/bin:/usr/bin:/bin"
	XDG_CONFIG_HOME="$work/home/.config"
	XDG_DATA_HOME="$work/data"
	XDG_DATA_DIRS="$work/empty"
	XDG_STATE_HOME="$work/home/.local/state"
)

run_helper() {
	env "${env_common[@]}" "$BASH_BIN" "$HELPER" "$@"
}

recovery_backup_path() {
	local scope=$1
	local state_dir=$work/home/.local/state/dwm-titus/default-apps
	local name
	name=$(awk -F= '$1 == "before_file" { print substr($0, 13); exit }' \
		"$state_dir/$scope.meta")
	if [[ -n $name ]]; then
		printf '%s\n' "$state_dir/$name"
	else
		printf '%s\n' "$state_dir/$scope.before"
	fi
}

watch_descendant_pids() {
	local root=$1 child
	[[ -r /proc/$root/task/$root/children ]] || return 0
	for child in $(<"/proc/$root/task/$root/children"); do
		printf '%s\n' "$child"
		watch_descendant_pids "$child"
	done
}

watch_child_for_path() {
	local helper_pid=$1 path=$2 pid
	while IFS= read -r pid; do
		[[ -n $pid ]] || continue
		if [[ $(cat "/proc/$pid/comm" 2>/dev/null || true) == inotifywait ]] &&
			tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | grep -Fqx -- "$path"; then
			printf '%s\n' "$pid"
			return 0
		fi
	done < <(watch_descendant_pids "$helper_pid")
	return 1
}

watch_child_has_argument() {
	local pid=$1 argument=$2
	tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | grep -Fqx -- "$argument"
}

process_identity() {
	local pid=$1 stat rest
	local -a fields=()
	IFS= read -r stat <"/proc/$pid/stat" || return 1
	rest=${stat##*) }
	read -r -a fields <<<"$rest"
	[[ ${#fields[@]} -ge 20 && ${fields[0]} != Z && ${fields[19]} =~ ^[0-9]+$ ]] || return 1
	printf '%s:%s\n' "$pid" "${fields[19]}"
}

process_identity_is_live() {
	local pid=${1%%:*} expected=${1#*:} current
	current=$(process_identity "$pid" 2>/dev/null) || return 1
	[[ $current == "$pid:$expected" ]]
}

expect_status() {
	local expected=$1
	shift
	local status=0
	"$@" >"$work/failure.out" 2>"$work/failure.err" || status=$?
	if [[ $status -ne $expected ]]; then
		printf 'Expected status %s, got %s: %s\n' "$expected" "$status" "$*" >&2
		cat "$work/failure.err" >&2
		exit 1
	fi
}

snapshot=$(run_helper snapshot)
[[ ${snapshot%%$'\n'*} == $'defaults-protocol\t1\t0' ]]
grep -Fqx $'provider\tdefaults\tavailable\tuser-session\tDefault applications and MIME state' <<<"$snapshot"
grep -Fqx $'role\tbrowser\tavailable\tbrave.desktop\tBrave\txdg-settings\tDefault browser is readable' <<<"$snapshot"
grep -Fqx $'role\tterminal\tavailable\tAlacritty.desktop\tAlacritty\thotkeys.toml\tTerminal hotkey selection is readable' <<<"$snapshot"
grep -Fqx $'role\tfile-manager\tavailable\torg.example.Files.desktop\tFiles\txdg-mime\tDefault file manager is readable' <<<"$snapshot"
grep -Fqx $'candidate\tbrowser\tfirefox.desktop\tFirefox\tavailable\t\tInstalled desktop entry' <<<"$snapshot"
grep -Fqx $'candidate\tterminal\tkitty.desktop\tkitty\tavailable\tkitty\tInstalled desktop entry' <<<"$snapshot"
grep -Fqx $'mime-candidate\ttext/plain\torg.example.Editor.desktop\tEditor\tavailable\tInstalled desktop entry' <<<"$snapshot"
for rejected_id in hidden.desktop not-an-app.desktop chromium.desktop duplicate.desktop \
	oversized.desktop control.desktop linked-escaped.desktop linked-leaf.desktop st.desktop; do
	if grep -Fq "$rejected_id" <<<"$snapshot"; then
		printf 'Rejected desktop entry was emitted as a candidate: %s\n' "$rejected_id" >&2
		exit 1
	fi
done
grep -Fqx $'candidate\tbrowser\tvendor-nested.desktop\tNested Browser\tavailable\t\tInstalled desktop entry' <<<"$snapshot"

cp -p "$work/home/.config/mimeapps.list" "$work/mimeapps.before-invalid-snapshot"
sed 's/^inode\/directory=.*/inode\/directory=oversized.desktop/' \
	"$work/mimeapps.before-invalid-snapshot" >"$work/home/.config/mimeapps.list"
snapshot=$(run_helper snapshot)
grep -Fqx $'role\tfile-manager\trestricted\toversized.desktop\t\txdg-mime\tConfigured desktop entry is not an application' <<<"$snapshot"
grep -Fqx $'mime\tinode/directory\tunavailable\toversized.desktop\t\tXDG MIME default is unavailable or invalid' <<<"$snapshot"
mv "$work/mimeapps.before-invalid-snapshot" "$work/home/.config/mimeapps.list"

symlink_root_snapshot=$(env "${env_common[@]}" \
	XDG_DATA_DIRS="$work/symlink-data:$work/empty" "$BASH_BIN" "$HELPER" snapshot)
if grep -Fq escaped.desktop <<<"$symlink_root_snapshot"; then
	printf 'Symlinked applications root was traversed\n' >&2
	exit 1
fi

run_helper browsers >"$work/browsers"
grep -Fqx $'firefox.desktop\tFirefox' "$work/browsers"
if grep -Fq org.example.Files.desktop "$work/browsers"; then
	printf 'Non-browser desktop file listed as browser\n' >&2
	exit 1
fi

mime_before=$(sha256sum "$work/home/.config/mimeapps.list")
: >"$work/log"
: >"$work/settings-log"
rm -f "$work/count"
result=$(run_helper set-role browser firefox.desktop)
[[ $result == $'defaults-result\t1\t0\tset-role\tbrowser\tfirefox.desktop\tok' ]]
[[ $(stat -c %a "$work/home/.config/mimeapps.list") == 640 ]]
[[ $(grep -c '^xdg-mime default firefox.desktop ' "$work/log") -eq 4 ]]
grep -Fqx 'xdg-mime default firefox.desktop x-scheme-handler/http' "$work/log"
grep -Fqx 'xdg-mime default firefox.desktop x-scheme-handler/https' "$work/log"
grep -Fqx 'xdg-mime default firefox.desktop text/html' "$work/log"
grep -Fqx 'xdg-mime default firefox.desktop application/xhtml+xml' "$work/log"
if grep -Fq 'xdg-settings set' "$work/settings-log"; then
	printf 'Browser mutation used broad xdg-settings set\n' >&2
	exit 1
fi
grep -Fqx 'application/x-unrelated=keep.desktop' "$work/home/.config/mimeapps.list"

defaults_state=$work/home/.local/state/dwm-titus/default-apps
browser_meta=$defaults_state/role-browser.meta
browser_before=$(recovery_backup_path role-browser)
browser_post=$(sha256sum "$work/home/.config/mimeapps.list")
browser_meta_before=$(sha256sum "$browser_meta")
browser_recovery_before=$(sha256sum "$browser_before")
: >"$work/log"
rm -f "$work/count"
expect_status 1 env DWM_TEST_REAL_MV="$REAL_MV" DWM_TEST_REAL_CHMOD="$REAL_CHMOD" \
	DWM_TEST_FAIL_JOURNAL_META="$browser_meta" \
	"${env_common[@]}" PATH="$work/fail-bin:$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$HELPER" set-role browser brave.desktop
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$browser_post" ]]
[[ $(sha256sum "$browser_meta") == "$browser_meta_before" ]]
[[ $(sha256sum "$browser_before") == "$browser_recovery_before" ]]
snapshot=$(run_helper snapshot)
grep -Fqx $'recovery\tbrowser\tavailable\tRestore previous selection' <<<"$snapshot"

journal_signal_marker=$work/journal-signal.marker
journal_files_before=$(find "$defaults_state" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
: >"$work/log"
rm -f "$work/count"
expect_status 143 env DWM_TEST_REAL_MV="$REAL_MV" DWM_TEST_REAL_CHMOD="$REAL_CHMOD" \
	DWM_TEST_SIGNAL_JOURNAL_META="$browser_meta" \
	DWM_TEST_SIGNAL_MARKER="$journal_signal_marker" \
	"${env_common[@]}" PATH="$work/fail-bin:$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$HELPER" set-role browser brave.desktop
[[ -f $journal_signal_marker ]]
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$browser_post" ]]
[[ $(sha256sum "$browser_meta") == "$browser_meta_before" ]]
[[ $(sha256sum "$browser_before") == "$browser_recovery_before" ]]
[[ $(find "$defaults_state" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort) == "$journal_files_before" ]]
[[ ! -e $defaults_state/.lock ]]
snapshot=$(run_helper snapshot)
grep -Fqx $'recovery\tbrowser\tavailable\tRestore previous selection' <<<"$snapshot"

expect_status 1 env DWM_TEST_REAL_MV="$REAL_MV" DWM_TEST_REAL_CHMOD="$REAL_CHMOD" \
	DWM_TEST_FAIL_RESET_CHMOD=1 \
	"${env_common[@]}" PATH="$work/fail-bin:$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$HELPER" reset-role browser
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$browser_post" ]]
[[ $(sha256sum "$browser_meta") == "$browser_meta_before" ]]
[[ $(sha256sum "$browser_before") == "$browser_recovery_before" ]]

reset_signal_marker=$work/reset-signal.marker
expect_status 143 env DWM_TEST_REAL_MV="$REAL_MV" DWM_TEST_REAL_CHMOD="$REAL_CHMOD" \
	DWM_TEST_SIGNAL_RESET_TARGET="$work/home/.config/mimeapps.list" \
	DWM_TEST_SIGNAL_MARKER="$reset_signal_marker" \
	"${env_common[@]}" PATH="$work/fail-bin:$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$HELPER" reset-role browser
[[ -f $reset_signal_marker ]]
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$browser_post" ]]
[[ $(sha256sum "$browser_meta") == "$browser_meta_before" ]]
[[ $(sha256sum "$browser_before") == "$browser_recovery_before" ]]
[[ ! -e $defaults_state/.lock ]]

result=$(run_helper reset-role browser)
[[ $result == $'defaults-result\t1\t0\treset-role\tbrowser\t\tok' ]]
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$mime_before" ]]
[[ $(stat -c %a "$work/home/.config/mimeapps.list") == 640 ]]

: >"$work/log"
rm -f "$work/count"
result=$(run_helper set-role file-manager org.example.Files.desktop)
[[ $result == $'defaults-result\t1\t0\tset-role\tfile-manager\torg.example.Files.desktop\tok' ]]
[[ $(wc -l <"$work/log") -eq 1 ]]
grep -Fqx 'xdg-mime default org.example.Files.desktop inode/directory' "$work/log"
run_helper reset-role file-manager >/dev/null

: >"$work/log"
rm -f "$work/count"
result=$(run_helper set-mime text/plain org.example.Editor.desktop)
[[ $result == $'defaults-result\t1\t0\tset-mime\ttext/plain\torg.example.Editor.desktop\tok' ]]
[[ $(wc -l <"$work/log") -eq 1 ]]
grep -Fqx 'xdg-mime default org.example.Editor.desktop text/plain' "$work/log"
result=$(run_helper reset-mime text/plain)
[[ $result == $'defaults-result\t1\t0\treset-mime\ttext/plain\t\tok' ]]
: >"$work/log"
rm -f "$work/count"
run_helper set-mime text/plain org.example.Editor.desktop >/dev/null
printf '# external change\n' >>"$work/home/.config/mimeapps.list"
drift_hash=$(sha256sum "$work/home/.config/mimeapps.list")
expect_status 1 run_helper reset-mime text/plain
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$drift_hash" ]]
cp "$(recovery_backup_path mime-text_plain)" "$work/home/.config/mimeapps.list"
chmod 640 "$work/home/.config/mimeapps.list"

before=$(sha256sum "$work/home/.config/mimeapps.list")
: >"$work/log"
rm -f "$work/count"
expect_status 1 env DWM_TEST_FAIL_AT=2 "${env_common[@]}" "$BASH_BIN" "$HELPER" \
	set-role browser firefox.desktop
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$before" ]]
[[ $(stat -c %a "$work/home/.config/mimeapps.list") == 640 ]]
if find "$work/home/.config" -maxdepth 1 -name '.mimeapps.list.dwm-defaults.*' \
	-print -quit | grep -q .; then
	printf 'Defaults mutation left a temporary MIME file\n' >&2
	exit 1
fi

: >"$work/log"
rm -f "$work/count"
expect_status 1 env DWM_TEST_NONCONVERGE_MIME=text/html "${env_common[@]}" \
	"$BASH_BIN" "$HELPER" set-role browser firefox.desktop
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$before" ]]

: >"$work/log"
expect_status 1 run_helper set-mime application/x-unsupported org.example.Editor.desktop
expect_status 1 run_helper set-mime text/plain firefox.desktop
expect_status 1 run_helper set-role browser '../../evil.desktop'
expect_status 1 run_helper set-role browser chromium.desktop
expect_status 1 run_helper set-role browser duplicate.desktop
expect_status 1 run_helper set-role browser oversized.desktop
expect_status 1 run_helper set-role browser control.desktop
expect_status 1 run_helper set-role browser linked-escaped.desktop
expect_status 1 run_helper set-role browser linked-leaf.desktop
[[ ! -s $work/log ]]

mv "$work/home/.config/mimeapps.list" "$work/mimeapps.target"
ln -s "$work/mimeapps.target" "$work/home/.config/mimeapps.list"
: >"$work/log"
expect_status 1 run_helper set-role browser firefox.desktop
[[ ! -s $work/log ]]
rm "$work/home/.config/mimeapps.list"
mv "$work/mimeapps.target" "$work/home/.config/mimeapps.list"

mime_parent_before=$(sha256sum "$work/home/.config/mimeapps.list")
ln -s "$work/home/.config" "$work/config-parent-link"
: >"$work/log"
expect_status 1 env "${env_common[@]}" XDG_CONFIG_HOME="$work/config-parent-link" \
	"$BASH_BIN" "$HELPER" set-role browser firefox.desktop
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$mime_parent_before" ]]
[[ ! -s $work/log ]]
rm "$work/config-parent-link"

mkdir -p "$work/state-parent-target"
ln -s "$work/state-parent-target" "$work/state-parent-link"
mime_parent_before=$(sha256sum "$work/home/.config/mimeapps.list")
: >"$work/log"
expect_status 1 env "${env_common[@]}" XDG_STATE_HOME="$work/state-parent-link" \
	"$BASH_BIN" "$HELPER" set-role browser firefox.desktop
[[ $(sha256sum "$work/home/.config/mimeapps.list") == "$mime_parent_before" ]]
[[ ! -s $work/log ]]
rm "$work/state-parent-link"

hotkeys_before=$(sha256sum "$work/home/.config/dwm-titus/hotkeys.toml")
hotkeys_without_terminal_before=$(sed '/^[[:space:]]*terminal[[:space:]]*=/d' \
	"$work/home/.config/dwm-titus/hotkeys.toml" | sha256sum)
result=$(run_helper set-role terminal kitty.desktop)
[[ $result == $'defaults-result\t1\t0\tset-role\tterminal\tkitty.desktop\tok' ]]
grep -Fqx 'terminal = "kitty"' "$work/home/.config/dwm-titus/hotkeys.toml"
[[ $(stat -c %a "$work/home/.config/dwm-titus/hotkeys.toml") == 640 ]]
[[ $(sed '/^[[:space:]]*terminal[[:space:]]*=/d' "$work/home/.config/dwm-titus/hotkeys.toml" | sha256sum) == "$hotkeys_without_terminal_before" ]]
result=$(run_helper reset-role terminal)
[[ $result == $'defaults-result\t1\t0\treset-role\tterminal\t\tok' ]]
[[ $(sha256sum "$work/home/.config/dwm-titus/hotkeys.toml") == "$hotkeys_before" ]]

sed -i 's/terminal = "alacritty"/terminal = "st"/' \
	"$work/home/.config/dwm-titus/hotkeys.toml"
snapshot=$(run_helper snapshot)
grep -Fqx $'role\tterminal\trestricted\t\t\thotkeys.toml\tCustom terminal command: st' <<<"$snapshot"
sed -i 's/terminal = "st"/terminal = "alacritty"/' \
	"$work/home/.config/dwm-titus/hotkeys.toml"

cp "$work/home/.config/dwm-titus/hotkeys.toml" "$work/hotkeys.target"
rm "$work/home/.config/dwm-titus/hotkeys.toml"
ln -s "$work/hotkeys.target" "$work/home/.config/dwm-titus/hotkeys.toml"
snapshot=$(run_helper snapshot)
grep -Fqx $'role\tterminal\trestricted\t\t\thotkeys.toml\tTerminal mutation is disabled because user hotkeys.toml is a symlink' <<<"$snapshot"
grep -Fqx $'candidate\tterminal\tkitty.desktop\tkitty\trestricted\tkitty\tTerminal hotkeys target is not safely writable' <<<"$snapshot"
expect_status 1 run_helper set-role terminal kitty.desktop
rm "$work/home/.config/dwm-titus/hotkeys.toml"
mv "$work/hotkeys.target" "$work/home/.config/dwm-titus/hotkeys.toml"

mv "$work/home/.config/dwm-titus" "$work/hotkeys-parent-target"
ln -s "$work/hotkeys-parent-target" "$work/home/.config/dwm-titus"
hotkeys_parent_before=$(sha256sum "$work/hotkeys-parent-target/hotkeys.toml")
snapshot=$(run_helper snapshot)
grep -Fqx $'role\tterminal\trestricted\t\t\thotkeys.toml\tTerminal mutation is disabled because the hotkeys path contains a symlink' <<<"$snapshot"
grep -Fqx $'candidate\tterminal\tkitty.desktop\tkitty\trestricted\tkitty\tTerminal hotkeys target is not safely writable' <<<"$snapshot"
expect_status 1 run_helper set-role terminal kitty.desktop
[[ $(sha256sum "$work/hotkeys-parent-target/hotkeys.toml") == "$hotkeys_parent_before" ]]
rm "$work/home/.config/dwm-titus"
mv "$work/hotkeys-parent-target" "$work/home/.config/dwm-titus"

mkdir -p "$work/home/.local/state/dwm-titus/default-apps/.lock"
expect_status 75 run_helper set-role terminal kitty.desktop
rmdir "$work/home/.local/state/dwm-titus/default-apps/.lock"

mkdir -p "$work/home/.local/state/dwm-titus/default-apps/.lock"
printf '999999 1\n' >"$work/home/.local/state/dwm-titus/default-apps/.lock/owner"
result=$(run_helper set-role terminal kitty.desktop)
[[ $result == $'defaults-result\t1\t0\tset-role\tterminal\tkitty.desktop\tok' ]]
run_helper reset-role terminal >/dev/null

mkdir -p "$work/home/.local/state/dwm-titus/default-apps/.lock"
shell_starttime=$(awk '{ print $22 }' "/proc/$$/stat")
printf '%s %s\n' "$$" "$shell_starttime" \
	>"$work/home/.local/state/dwm-titus/default-apps/.lock/owner"
expect_status 75 run_helper set-role terminal kitty.desktop
rm "$work/home/.local/state/dwm-titus/default-apps/.lock/owner"
rmdir "$work/home/.local/state/dwm-titus/default-apps/.lock"

run_helper set-browser firefox.desktop >"$work/legacy-browser"
grep -Fqx 'Default browser set to firefox.desktop' "$work/legacy-browser"
run_helper open 'https://example.test'
grep -Fqx 'https://example.test' "$work/opened"

if command -v inotifywait >/dev/null 2>&1; then
	run_helper watch >"$work/watch.out" 2>"$work/watch.err" &
	watch_pid=$!
	applications_child=
	for _ in {1..100}; do
		applications_child=$(watch_child_for_path "$watch_pid" \
			"$work/data/applications" 2>/dev/null || true)
		[[ -z $applications_child ]] || break
		sleep 0.02
	done
	[[ -n $applications_child ]] || {
		cat "$work/watch.err" >&2
		exit 1
	}
	watch_child_has_argument "$applications_child" -r
	printf '# watched\n' >>"$work/data/applications/vendor/nested.desktop"
	for _ in {1..100}; do
		grep -Fq nested.desktop "$work/watch.out" 2>/dev/null && break
		sleep 0.02
	done
	grep -Fq nested.desktop "$work/watch.out"
	kill "$watch_pid"
	wait "$watch_pid" 2>/dev/null || true
	watch_pid=

	watch_root=$work/watch-config
	absent_config=$watch_root/missing/config
	mkdir -p "$watch_root"
	env "${env_common[@]}" XDG_CONFIG_HOME="$absent_config" \
		"$BASH_BIN" "$HELPER" watch >"$work/watch-absent.out" \
		2>"$work/watch-absent.err" &
	watch_pid=$!
	first_child=
	for _ in {1..100}; do
		first_child=$(watch_child_for_path "$watch_pid" "$watch_root" 2>/dev/null || true)
		[[ -z $first_child ]] || break
		sleep 0.02
	done
	[[ -n $first_child ]]
	if watch_child_has_argument "$first_child" -r; then
		printf 'Ancestor defaults watch was recursive: %s\n' "$watch_root" >&2
		exit 1
	fi
	applications_child=$(watch_child_for_path "$watch_pid" "$work/data/applications")
	watch_child_has_argument "$applications_child" -r
	mkdir -p "$watch_root/unrelated/deep"
	printf 'unrelated\n' >"$watch_root/unrelated/deep/file"
	sleep 0.1
	[[ ! -s $work/watch-absent.out ]]
	mkdir "$watch_root/missing"
	second_child=
	for _ in {1..100}; do
		second_child=$(watch_child_for_path "$watch_pid" "$watch_root/missing" 2>/dev/null || true)
		[[ -n $second_child && $second_child != "$first_child" ]] && break
		sleep 0.02
	done
	[[ -n $second_child && $second_child != "$first_child" ]]
	if watch_child_has_argument "$second_child" -r; then
		printf 'Ancestor defaults watch was recursive: %s\n' "$watch_root/missing" >&2
		exit 1
	fi
	mkdir "$absent_config"
	third_child=
	for _ in {1..100}; do
		third_child=$(watch_child_for_path "$watch_pid" "$absent_config" 2>/dev/null || true)
		[[ -n $third_child && $third_child != "$second_child" ]] && break
		sleep 0.02
	done
	[[ -n $third_child && $third_child != "$second_child" ]]
	if watch_child_has_argument "$third_child" -r; then
		printf 'Ancestor defaults watch was recursive: %s\n' "$absent_config" >&2
		exit 1
	fi
	printf '[Default Applications]\n' >"$absent_config/mimeapps.list"
	for _ in {1..100}; do
		grep -Fq mimeapps.list "$work/watch-absent.out" 2>/dev/null && break
		sleep 0.02
	done
	grep -Fq mimeapps.list "$work/watch-absent.out"
	mkdir "$absent_config/dwm-titus"
	fourth_child=
	for _ in {1..100}; do
		fourth_child=$(watch_child_for_path "$watch_pid" "$absent_config" 2>/dev/null || true)
		[[ -n $fourth_child && $fourth_child != "$third_child" ]] && break
		sleep 0.02
	done
	[[ -n $fourth_child && $fourth_child != "$third_child" ]]
	watch_child_has_argument "$fourth_child" -r
	printf '[vars]\nterminal = "alacritty"\n' >"$absent_config/dwm-titus/hotkeys.toml"
	for _ in {1..100}; do
		grep -Fq hotkeys.toml "$work/watch-absent.out" 2>/dev/null && break
		sleep 0.02
	done
	grep -Fq hotkeys.toml "$work/watch-absent.out"
	fourth_identity=$(process_identity "$fourth_child")
	kill "$watch_pid"
	wait "$watch_pid" 2>/dev/null || true
	watch_pid=
	for _ in {1..100}; do
		process_identity_is_live "$fourth_identity" || break
		sleep 0.02
	done
	if process_identity_is_live "$fourth_identity"; then
		printf 'Defaults watch child survived helper exit: %s\n' "$fourth_identity" >&2
		exit 1
	fi

	owner_pid_file=$work/watch-owner.pid
	# shellcheck disable=SC2016 # Positional parameters are expanded by the child shell.
	env "${env_common[@]}" "$BASH_BIN" -c '
		"$1" "$2" watch >"$3" 2>"$4" &
		printf "%s\n" "$!" >"$5"
		wait "$!"
	' _ "$BASH_BIN" "$HELPER" "$work/watch-owner.out" "$work/watch-owner.err" \
		"$owner_pid_file" &
	watch_owner_pid=$!
	for _ in {1..100}; do
		[[ -s $owner_pid_file ]] && break
		sleep 0.02
	done
	[[ -s $owner_pid_file ]]
	watch_pid=$(<"$owner_pid_file")
	watch_identity=$(process_identity "$watch_pid")
	descendant_identities=()
	for _ in {1..100}; do
		descendant_identities=()
		while IFS= read -r descendant_pid; do
			[[ -n $descendant_pid ]] || continue
			descendant_identity=$(process_identity "$descendant_pid" 2>/dev/null || true)
			[[ -z $descendant_identity ]] || descendant_identities+=("$descendant_identity")
		done < <(pgrep -P "$watch_pid" 2>/dev/null || true)
		((${#descendant_identities[@]} >= 4)) && break
		sleep 0.02
	done
	((${#descendant_identities[@]} >= 4))
	kill -KILL "$watch_owner_pid"
	wait "$watch_owner_pid" 2>/dev/null || true
	watch_owner_pid=
	for _ in {1..100}; do
		live=0
		process_identity_is_live "$watch_identity" && live=1
		for descendant_identity in "${descendant_identities[@]}"; do
			process_identity_is_live "$descendant_identity" && live=1
		done
		((live == 0)) && break
		sleep 0.02
	done
	if process_identity_is_live "$watch_identity"; then
		printf 'Defaults watch survived owner death: %s\n' "$watch_identity" >&2
		exit 1
	fi
	for descendant_identity in "${descendant_identities[@]}"; do
		if process_identity_is_live "$descendant_identity"; then
			printf 'Defaults watch descendant survived owner death: %s\n' \
				"$descendant_identity" >&2
			exit 1
		fi
	done
	watch_pid=
fi

printf 'dwm-default-apps versioned backend: PASS\n'
