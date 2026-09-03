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
test_bin="$work/bin"
source_update_probe="$work/source-update-probe"

mkdir -p "$test_repo" "$test_bin" "$prefix/bin" "$prefix/libexec/dwm-titus" \
	"$manprefix/man1" "$xsessions_dir" \
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
sed "s|@PREFIX@|$prefix|g" "$test_repo/scripts/dwm-settings-display-root" |
	install -Dm755 /dev/stdin "$prefix/libexec/dwm-titus/dwm-settings-display-root"
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
printf '#!/bin/sh\nexit 0\n' >"$test_bin/xsettingsd"
printf '#!/bin/sh\nexit 0\n' >"$test_bin/dump_xsettings"
chmod +x "$test_bin/xsettingsd" "$test_bin/dump_xsettings"

sed -n '/^source_update_dependencies_ready() {$/,/^}$/p' \
	"$test_repo/scripts/dev-sync-install.sh" >"$source_update_probe"
for required_command in xsettingsd dump_xsettings xkbset; do
	grep -Fq "command -v $required_command" "$source_update_probe" || {
		printf 'Source-update readiness omits required command: %s\n' \
			"$required_command" >&2
		exit 1
	}
done
run_check() {
	PATH="$test_bin:$PATH" \
		DWM_DEV_SYNC_SKIP_RUNTIME=1 \
		DWM_DEV_SYNC_SKIP_PRIVILEGED_TRUST=1 \
		USER_HOME="$test_home" \
		PREFIX="$prefix" \
		MANPREFIX="$manprefix" \
		XSESSIONSDIR="$xsessions_dir" \
		DATADIR="$data_root" \
		XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$xdg_data_home" \
		XDG_STATE_HOME="$state_home" \
		DWM_DEV_SYNC_TEST_MODE="${DWM_DEV_SYNC_TEST_MODE:-1}" \
		DWM_DEV_SYNC_DESKTOP_FEATURE="${DWM_DEV_SYNC_DESKTOP_FEATURE:-1}" \
		DWM_DEV_SYNC_SOURCE_UPDATE_READY="${DWM_DEV_SYNC_SOURCE_UPDATE_READY:-1}" \
		"$test_repo/scripts/dev-sync-install.sh" --check
}

run_check >"$output"
grep -Fqx 'All managed files match the checkout.' "$output"
grep -Fqx 'Runtime validation skipped by DWM_DEV_SYNC_SKIP_RUNTIME=1.' "$output"

mv "$test_bin/xsettingsd" "$test_bin/xsettingsd.missing"
if DWM_DEV_SYNC_SOURCE_UPDATE_READY=0 run_check >"$output" 2>&1; then
	printf '%s\n' 'Missing source-update dependency unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'source-update dependencies are missing' "$output"
DWM_DEV_SYNC_DESKTOP_FEATURE=0 DWM_DEV_SYNC_SOURCE_UPDATE_READY=0 run_check >"$output"
grep -Fqx 'All managed files match the checkout.' "$output"
if grep -Fq 'source-update dependencies' "$output"; then
	printf '%s\n' 'Core-profile check reached desktop dependency reconciliation.' >&2
	exit 1
fi
mv "$test_bin/xsettingsd.missing" "$test_bin/xsettingsd"

cat >"$test_bin/id" <<'EOF'
#!/bin/sh
case ${1:-} in
-u) printf '0\n' ;;
-un) printf 'root\n' ;;
*) exit 2 ;;
esac
EOF
chmod +x "$test_bin/id"
mv "$test_bin/xsettingsd" "$test_bin/xsettingsd.missing"
if PATH="$test_bin:$PATH" \
	DWM_DEV_SYNC_SKIP_RUNTIME=1 \
	USER_HOME="$test_home" \
	PREFIX="$prefix" \
	MANPREFIX="$manprefix" \
	XSESSIONSDIR="$xsessions_dir" \
	DATADIR="$data_root" \
	XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$xdg_data_home" \
	XDG_STATE_HOME="$state_home" \
	"$test_repo/scripts/dev-sync-install.sh" >"$output" 2>&1; then
	printf '%s\n' 'Root source update unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'run this script as the desktop user, not root' "$output"
if grep -Fq 'source-update dependencies' "$output"; then
	printf '%s\n' 'Root source update reached dependency reconciliation.' >&2
	exit 1
fi
rm "$test_bin/id"
mv "$test_bin/xsettingsd.missing" "$test_bin/xsettingsd"

printf 'ID=other\nPRETTY_NAME="Other Linux"\n' >"$work/os-release"
cat >"$test_bin/id" <<'EOF'
#!/bin/sh
case ${1:-} in
-u) printf '1000\n' ;;
-un) printf 'testuser\n' ;;
*) exit 2 ;;
esac
EOF
cat >"$test_bin/sudo" <<EOF
#!/bin/sh
printf 'sudo invoked\n' >"$work/package-transaction"
exit 1
EOF
cat >"$test_bin/dnf" <<EOF
#!/bin/sh
printf 'dnf invoked\n' >"$work/package-transaction"
exit 1
EOF
chmod +x "$test_bin/id" "$test_bin/sudo" "$test_bin/dnf"
mv "$test_bin/xsettingsd" "$test_bin/xsettingsd.missing"
if PATH="$test_bin:$PATH" \
	DWM_DEV_SYNC_TEST_MODE=1 \
	DWM_DEV_SYNC_DESKTOP_FEATURE=1 \
	DWM_DEV_SYNC_SOURCE_UPDATE_READY=0 \
	DWM_DEV_SYNC_OS_RELEASE="$work/os-release" \
	DWM_DEV_SYNC_SKIP_RUNTIME=1 \
	USER_HOME="$test_home" \
	PREFIX="$prefix" \
	MANPREFIX="$manprefix" \
	XSESSIONSDIR="$xsessions_dir" \
	DATADIR="$data_root" \
	XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$xdg_data_home" \
	XDG_STATE_HOME="$state_home" \
	"$test_repo/scripts/dev-sync-install.sh" >"$output" 2>&1; then
	printf '%s\n' 'Non-Fedora source update unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'unsupported distribution for source-update dependencies: other' "$output"
if [ -e "$work/package-transaction" ]; then
	printf '%s\n' 'Non-Fedora source update reached a package transaction.' >&2
	exit 1
fi
rm "$test_bin/id" "$test_bin/sudo" "$test_bin/dnf"
mv "$test_bin/xsettingsd.missing" "$test_bin/xsettingsd"

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
