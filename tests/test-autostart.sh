#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

make_mock_command() {
	name=$1
	cat >"$work/bin/$name" <<'EOF'
#!/bin/sh
name=$(basename "$0")
count_file="${TEST_STATE:?}/$name.count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
: >"${TEST_STATE:?}/$name.running"
EOF
	chmod +x "$work/bin/$name"
}

mkdir -p "$work/bin"

cat >"$work/bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 1000
EOF

cat >"$work/bin/pgrep" <<'EOF'
#!/bin/sh
for arg do
	name=$arg
done
test -f "${TEST_STATE:?}/$name.running"
EOF

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$work/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$work/bin/xset" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$work/bin/dex-autostart" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod +x "$work/bin/"*

for name in feh picom dunst; do
	make_mock_command "$name"
done

run_duplicate_case() {
	mode=$1
	home="$work/$mode/home"
	state="$work/$mode/state"
	runtime="$work/$mode/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/polybar" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"

	cat >"$home/.config/polybar/launch.sh" <<'EOF'
#!/bin/sh
count_file="${TEST_STATE:?}/polybar-launch.count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
: >"${TEST_STATE:?}/polybar.running"
EOF
	chmod +x "$home/.config/polybar/launch.sh"

	# Prevent this isolated test from starting a host polkit agent.
	: >"$state/polkit-mate-authentication-agent-1.running"

	for _ in 1 2; do
		if [ "$mode" = startx ]; then
			XDG_RUNTIME_DIR="$runtime" /usr/bin/dbus-run-session -- env \
				HOME="$home" \
				TEST_STATE="$state" \
				PATH="$work/bin:/usr/bin:/bin" \
				XDG_CONFIG_HOME="$home/.config" \
				sh "$repo_dir/scripts/autostart.sh"
		else
			HOME=$home \
				TEST_STATE=$state \
				PATH="$work/bin:/usr/bin:/bin" \
				XDG_CONFIG_HOME="$home/.config" \
				sh "$repo_dir/scripts/autostart.sh"
		fi
		sleep 0.1
	done

	for name in feh picom dunst; do
		test "$(cat "$state/$name.count")" -eq 1
	done
	test "$(cat "$state/polybar-launch.count")" -eq 2
	test -f "$state/polybar.running"
}

run_missing_optional_case() {
	home="$work/missing/home"
	state="$work/missing/state"
	minimal_bin="$work/missing/bin"
	mkdir -p "$home" "$state" "$minimal_bin"

	for name in basename find grep id pgrep; do
		if [ -x "$work/bin/$name" ]; then
			ln -s "$work/bin/$name" "$minimal_bin/$name"
		else
			ln -s "$(command -v "$name")" "$minimal_bin/$name"
		fi
	done
	ln -s "$work/bin/dbus-update-activation-environment" \
		"$minimal_bin/dbus-update-activation-environment"
	: >"$state/polkit-mate-authentication-agent-1.running"

	HOME=$home \
		TEST_STATE=$state \
		PATH=$minimal_bin \
		XDG_CONFIG_HOME="$home/.config" \
		/bin/sh "$repo_dir/scripts/autostart.sh"
}

run_duplicate_case display-manager
run_duplicate_case startx
run_missing_optional_case

printf '%s\n' "Autostart duplicate and missing-optional command guards: PASS"
