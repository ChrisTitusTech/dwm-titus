#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
grep -Eq 'cmd="dwm-screenshot clip"' "$repo_dir/config/hotkeys.toml"

work=$(mktemp -d)
cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home/My Pictures" "$work/runtime"
chmod 700 "$work/runtime"

cat >"$work/bin/maim" <<'EOF'
#!/bin/sh
printf 'maim:%s\n' "$*" >>"${TEST_LOG:?}"
[ "${TEST_MAIM_FAIL:-0}" != 1 ] || exit 42
[ -z "${TEST_MAIM_DELAY:-}" ] || sleep "$TEST_MAIM_DELAY"
for output do :; done
case $output in
*.jpg) printf '%s' 'mock-jpeg-capture' >"$output" ;;
*.png) printf '%s' 'mock-png-capture' >"$output" ;;
*) exit 2 ;;
esac
EOF

cat >"$work/bin/xclip" <<'EOF'
#!/bin/sh
printf 'xclip:%s\n' "$*" >>"${TEST_LOG:?}"
cat >"${TEST_CLIPBOARD:?}"
EOF

cat >"$work/bin/xdg-user-dir" <<EOF
#!/bin/sh
printf '%s\n' '$work/home/My Pictures'
EOF

cat >"$work/bin/xrandr" <<'EOF'
#!/bin/sh
cat <<'MONITORS'
Monitors: 2
 0: +LEFT 1920/520x1080/290+0+0 LEFT
 1: +*RIGHT 2560/600x1440/340+1920+0 RIGHT
MONITORS
EOF

cat >"$work/bin/xdotool" <<'EOF'
#!/bin/sh
printf '%s\n' 'X=2400' 'Y=720' 'SCREEN=0' 'WINDOW=1'
EOF

cat >"$work/bin/notify-send" <<'EOF'
#!/bin/sh
printf 'notify:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

chmod +x "$work/bin/"*

log=$work/calls.log

run_capture() {
	env DISPLAY=:99 \
		HOME="$work/home" \
		PATH="$work/bin:/usr/bin:/bin" \
		TEST_CLIPBOARD="$work/clipboard.png" \
		TEST_LOG="$log" \
		TEST_MAIM_DELAY="${TEST_MAIM_DELAY:-}" \
		XDG_RUNTIME_DIR="$work/runtime" \
		"$repo_dir/scripts/dwm-screenshot" "$1"
}

run_capture clip
grep -Eq '^maim:--hidecursor --select .*/clipboard\.[^/]+\.png$' "$log"
grep -Fqx 'xclip:-selection clipboard -target image/png -loops 0 -silent -in' "$log"
test "$(cat "$work/clipboard.png")" = 'mock-png-capture'
if find "$work/runtime/dwm-titus" -type f -name 'clipboard.*.png' | grep -q .; then
	printf '%s\n' 'Clipboard temporary file was not removed' >&2
	exit 1
fi

: >"$log"
screen_path=$(run_capture screen)
test -s "$screen_path"
case $screen_path in *.jpg) ;; *) exit 1 ;; esac
grep -Fqx "maim:--hidecursor --geometry 2560x1440+1920+0 $screen_path" "$log"
grep -Fqx "notify:-a dwm-titus Screenshot saved $screen_path" "$log"

: >"$log"
full_path=$(run_capture full)
test -s "$full_path"
grep -Fqx "maim:--hidecursor $full_path" "$log"

: >"$log"
TEST_MAIM_DELAY=0.1 run_capture full >"$work/concurrent-a.out" &
first_pid=$!
TEST_MAIM_DELAY=0.1 run_capture full >"$work/concurrent-b.out" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
first_path=$(cat "$work/concurrent-a.out")
second_path=$(cat "$work/concurrent-b.out")
test "$first_path" != "$second_path"
test -s "$first_path"
test -s "$second_path"

: >"$log"
gui_path=$(run_capture gui)
test -s "$gui_path"
grep -Fqx "maim:--hidecursor --select $gui_path" "$log"

: >"$log"
if env DISPLAY=:99 \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_CLIPBOARD="$work/failed-clipboard.png" \
	TEST_LOG="$log" \
	TEST_MAIM_FAIL=1 \
	XDG_RUNTIME_DIR="$work/runtime" \
	"$repo_dir/scripts/dwm-screenshot" clip; then
	printf '%s\n' 'A cancelled maim selection must fail' >&2
	exit 1
else
	status=$?
fi
test "$status" -eq 42
if grep -q '^xclip:' "$log"; then
	printf '%s\n' 'A cancelled capture must not replace the clipboard' >&2
	exit 1
fi

env -u DISPLAY PATH="$work/bin:/usr/bin:/bin" \
	"$repo_dir/scripts/dwm-screenshot" setup

if env -u DISPLAY PATH="$work/bin:/usr/bin:/bin" \
	"$repo_dir/scripts/dwm-screenshot" full 2>"$work/no-display.err"; then
	printf '%s\n' 'A capture without DISPLAY must fail' >&2
	exit 1
fi
grep -Fqx 'dwm-screenshot: DISPLAY is not set' "$work/no-display.err"

missing_bin=$work/missing-bin
mkdir -p "$missing_bin"
for command in awk bash date mkdir; do
	ln -s "$(command -v "$command")" "$missing_bin/$command"
done
if DISPLAY=:99 HOME="$work/home" PATH="$missing_bin" \
	"$repo_dir/scripts/dwm-screenshot" full 2>"$work/no-maim.err"; then
	printf '%s\n' 'A capture without maim must fail' >&2
	exit 1
else
	status=$?
fi
test "$status" -eq 127
grep -Fqx 'dwm-screenshot: maim is not installed' "$work/no-maim.err"

printf '%s\n' 'maim JPEG files, active monitor, and PNG clipboard capture: PASS'
