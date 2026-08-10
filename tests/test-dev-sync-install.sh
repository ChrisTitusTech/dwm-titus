#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

test_repo="$work/repo"
test_home="$work/user home"
prefix="$work/prefix with space"
manprefix="$prefix/share/man"
xsessions_dir="$work/xsessions"
data_root="$work/system data"
config_home="$test_home/.config"
xdg_data_home="$test_home/.local/share"
state_home="$test_home/.local/state"
data_dir="$xdg_data_home/dwm-titus"
output="$work/output"
install_sources="$work/install-sources"

mkdir -p "$test_repo" "$prefix/bin" "$manprefix/man1" "$xsessions_dir" \
	"$data_root/icons" "$data_root/licenses/dwm-titus/capitaine-cursors" \
	"$config_home/systemd/user" "$data_dir"
cp -a \
	"$repo_dir/Makefile" \
	"$repo_dir/config.mk" \
	"$repo_dir/dwm.1" \
	"$repo_dir/dwm.desktop" \
	"$repo_dir/config" \
	"$repo_dir/scripts" \
	"$repo_dir/assets" \
	"$test_repo/"
printf '%s\n' 'test dwm binary' >"$test_repo/dwm"
chmod 755 "$test_repo/dwm"

# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-install-sources: ; @printf "%s\n" $(INSTALL_COMMANDS)' \
	test-print-install-sources >"$install_sources"

install -Dm755 "$test_repo/dwm" "$prefix/bin/dwm"
while IFS= read -r install_source; do
	[ -n "$install_source" ] || continue
	install -Dm755 "$test_repo/$install_source" \
		"$prefix/bin/${install_source##*/}"
done <"$install_sources"

version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$test_repo/config.mk")
sed "s/VERSION/$version/g" "$test_repo/dwm.1" >"$manprefix/man1/dwm.1"
sed "s|@PREFIX@|$prefix|g" "$test_repo/dwm.desktop" >"$xsessions_dir/dwm.desktop"
cp -a "$test_repo/config" "$data_dir/config"
cp -a "$test_repo/scripts" "$data_dir/scripts"
cp -a "$test_repo/config/quickshell" "$config_home/quickshell"
printf '%s\n' '# preserved custom user unit' \
	>"$config_home/systemd/user/wm-graphical-session.service"
for cursor_source in "$test_repo"/assets/cursors/Capitaine-Cursors*; do
	cp -a "$cursor_source" "$data_root/icons/"
done
install -Dm644 "$test_repo/assets/cursors/COPYING" \
	"$data_root/licenses/dwm-titus/capitaine-cursors/COPYING"

run_check() {
	DWM_DEV_SYNC_SKIP_RUNTIME=1 \
		USER_HOME="$test_home" \
		PREFIX="$prefix" \
		MANPREFIX="$manprefix" \
		XSESSIONSDIR="$xsessions_dir" \
		DATADIR="$data_root" \
		XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$xdg_data_home" \
		XDG_STATE_HOME="$state_home" \
		"$test_repo/scripts/dev-sync-install.sh" --check
}

run_check >"$output"
grep -Fqx 'All managed files match the checkout.' "$output"
grep -Fqx 'Runtime validation skipped by DWM_DEV_SYNC_SKIP_RUNTIME=1.' "$output"

printf '%s\n' '// stale live marker' >>"$config_home/quickshell/shell.qml"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Managed Quickshell mismatch unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISMATCH TREE: managed Quickshell' "$output"
cp "$test_repo/config/quickshell/shell.qml" "$config_home/quickshell/shell.qml"

rm -f "$prefix/bin/dwm-status"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Missing installed command unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISSING INSTALL: installed command dwm-status' "$output"

"$test_repo/scripts/dev-sync-install.sh" --help >"$output"
grep -Fq 'Usage: scripts/dev-sync-install.sh [--check]' "$output"
if "$test_repo/scripts/dev-sync-install.sh" --unknown >"$output" 2>&1; then
	printf '%s\n' 'Unknown option unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'unknown option: --unknown' "$output"

printf '%s\n' 'Developer live-install synchronization: PASS'
