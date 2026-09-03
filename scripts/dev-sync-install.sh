#!/bin/sh

set -eu

program=${0##*/}

usage() {
	cat <<'EOF'
Usage: scripts/dev-sync-install.sh [--check]

Build and synchronize the current checkout with the live dwm-titus install.
The default mode:

  1. Builds dwm from a clean object state.
  2. Skips installation when every managed file already matches.
  3. Backs up the current managed installation before an update.
  4. Runs the complete system and user Makefile install.
  5. Verifies installed commands, generated files, managed data, and Quickshell.
  6. Restarts Quickshell when safe, or defers it to a required session restart.
  7. Reports whether dwm requires a session restart.

Options:
  --check   Verify install and runtime parity without building or changing files.
  -h, --help
            Show this help.

Path overrides use the same variables as the Makefile:
  PREFIX, MANPREFIX, XSESSIONSDIR, DATADIR, USER_HOME,
  XDG_CONFIG_HOME, XDG_DATA_HOME, and XDG_STATE_HOME.
EOF
}

die() {
	printf '%s: %s\n' "$program" "$*" >&2
	exit 1
}

note() {
	printf '==> %s\n' "$*"
}

validate_live_root() {
	live_root_name=$1
	live_root_value=$2

	case $live_root_value in
	/*) ;;
	*) die "$live_root_name must be an absolute path: $live_root_value" ;;
	esac
	if [ "$live_root_value" = / ]; then
		die "$live_root_name must not be the filesystem root"
	fi
}

repo_dir=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)

check_only=0
while [ "$#" -gt 0 ]; do
	case $1 in
	--check)
		check_only=1
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
	shift
done

if [ -n "${DESTDIR:-}" ]; then
	die "DESTDIR is not supported; this command targets a live installation"
fi

user_home=${USER_HOME:-${HOME:-}}
[ -n "$user_home" ] || die "USER_HOME and HOME are unavailable"
owner=$(id -un)
prefix=${PREFIX:-/usr/local}
manprefix=${MANPREFIX:-$prefix/share/man}
xsessions_dir=${XSESSIONSDIR:-/usr/share/xsessions}
data_root=${DATADIR:-/usr/share}
config_home=${XDG_CONFIG_HOME:-$user_home/.config}
xdg_data_home=${XDG_DATA_HOME:-$user_home/.local/share}
state_home=${XDG_STATE_HOME:-$user_home/.local/state}
data_dir=$xdg_data_home/dwm-titus
quickshell_dir=$config_home/quickshell
binary_target=$prefix/bin/dwm
man_target=$manprefix/man1/dwm.1
xsession_target=$xsessions_dir/dwm.desktop
display_root_helper_target=$prefix/libexec/dwm-titus/dwm-settings-display-root
make_command=${MAKE:-make}
os_release_file=/etc/os-release
if [ "${DWM_DEV_SYNC_TEST_MODE:-0}" = 1 ] &&
	[ -n "${DWM_DEV_SYNC_OS_RELEASE:-}" ]; then
	os_release_file=$DWM_DEV_SYNC_OS_RELEASE
fi

validate_live_root USER_HOME "$user_home"
validate_live_root PREFIX "$prefix"
validate_live_root MANPREFIX "$manprefix"
validate_live_root XSESSIONSDIR "$xsessions_dir"
validate_live_root DATADIR "$data_root"
validate_live_root XDG_CONFIG_HOME "$config_home"
validate_live_root XDG_DATA_HOME "$xdg_data_home"
validate_live_root XDG_STATE_HOME "$state_home"

for required_command in awk cmp diff id mktemp sed "$make_command"; do
	command -v "$required_command" >/dev/null 2>&1 ||
		die "required command not found: $required_command"
done
make_path=$(command -v "$make_command")

work=$(mktemp -d "${TMPDIR:-/tmp}/dwm-dev-sync.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
install_sources_file=$work/install-sources
expected_man=$work/dwm.1
expected_xsession=$work/dwm.desktop
expected_display_root_helper=$work/dwm-settings-display-root
tree_diff=$work/tree.diff

prepare_expected_files() {
	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-install-sources: ; @printf "%s\n" $(INSTALL_COMMANDS)' \
		dwm-dev-print-install-sources >"$install_sources_file"
	[ -s "$install_sources_file" ] ||
		die "Makefile did not report any installed commands"

	version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo_dir/config.mk")
	[ -n "$version" ] || die "could not read VERSION from config.mk"
	sed "s/VERSION/$version/g" "$repo_dir/dwm.1" >"$expected_man"
	sed "s|@PREFIX@|$prefix|g" "$repo_dir/dwm.desktop" >"$expected_xsession"
	sed "s|@PREFIX@|$prefix|g" "$repo_dir/scripts/dwm-settings-display-root" \
		>"$expected_display_root_helper"
}

source_update_dependencies_ready() {
	ready_packages_file=$work/source-update-ready-packages

	if [ "${DWM_DEV_SYNC_TEST_MODE:-0}" = 1 ] &&
		[ -n "${DWM_DEV_SYNC_SOURCE_UPDATE_READY:-}" ]; then
		case $DWM_DEV_SYNC_SOURCE_UPDATE_READY in
		1) return 0 ;;
		0) return 1 ;;
		*) die "invalid DWM_DEV_SYNC_SOURCE_UPDATE_READY value" ;;
		esac
	fi
	command -v xsettingsd >/dev/null 2>&1 &&
		command -v dump_xsettings >/dev/null 2>&1 &&
		command -v xkbset >/dev/null 2>&1 || return 1
	command -v rpm >/dev/null 2>&1 || return 1
	"$repo_dir/scripts/dwm-packages.sh" fedora source-update \
		>"$ready_packages_file" || return 1
	set --
	while IFS= read -r package; do
		[ -n "$package" ] && set -- "$@" "$package"
	done <"$ready_packages_file"
	[ "$#" -gt 0 ] && rpm -q "$@" >/dev/null 2>&1
}

source_update_dependencies_needed() {
	if [ "${DWM_DEV_SYNC_TEST_MODE:-0}" = 1 ] &&
		[ -n "${DWM_DEV_SYNC_DESKTOP_FEATURE:-}" ]; then
		case $DWM_DEV_SYNC_DESKTOP_FEATURE in
		1) return 0 ;;
		0) return 1 ;;
		*) die "invalid DWM_DEV_SYNC_DESKTOP_FEATURE value" ;;
		esac
	fi
	command -v quickshell >/dev/null 2>&1
}

require_fedora_for_package_changes() {
	distro_id=$(awk -F= '
		$1 == "ID" {
			value = $2
			gsub(/^[[:space:]"'\'' ]+|[[:space:]"'\'' ]+$/, "", value)
			print value
			exit
		}
	' "$os_release_file" 2>/dev/null) ||
		die "cannot read $os_release_file before installing source-update dependencies"
	[ "$distro_id" = fedora ] ||
		die "unsupported distribution for source-update dependencies: ${distro_id:-unknown}"
}

reconcile_source_update_dependencies() {
	packages_file=$work/source-update-packages
	if ! source_update_dependencies_needed; then
		return 0
	fi
	if source_update_dependencies_ready; then
		return 0
	fi
	if [ "$check_only" -eq 1 ]; then
		die "source-update dependencies are missing; run this command without --check to install them"
	fi
	command -v sudo >/dev/null 2>&1 ||
		die "sudo is required to install source-update dependencies"
	command -v dnf >/dev/null 2>&1 ||
		die "dnf is required to install source-update dependencies"
	require_fedora_for_package_changes
	"$repo_dir/scripts/dwm-packages.sh" fedora source-update >"$packages_file" ||
		die "could not resolve source-update dependencies"
	set --
	while IFS= read -r package; do
		[ -n "$package" ] && set -- "$@" "$package"
	done <"$packages_file"
	[ "$#" -gt 0 ] || die "source-update dependency profile is empty"
	note "Installing required source-update dependencies: $*"
	sudo dnf install -y "$@"
	source_update_dependencies_ready ||
		die "source-update dependencies are still unavailable after installation"
}

verification_failed=0

verify_file() {
	expected_file=$1
	actual_file=$2
	file_label=$3

	if [ ! -f "$expected_file" ]; then
		printf 'MISSING SOURCE: %s (%s)\n' "$file_label" "$expected_file" >&2
		verification_failed=1
	elif [ ! -f "$actual_file" ]; then
		printf 'MISSING INSTALL: %s (%s)\n' "$file_label" "$actual_file" >&2
		verification_failed=1
	elif ! cmp -s "$expected_file" "$actual_file"; then
		printf 'MISMATCH: %s (%s)\n' "$file_label" "$actual_file" >&2
		verification_failed=1
	fi
}

verify_executable() {
	expected_executable=$1
	actual_executable=$2
	executable_label=$3

	verify_file "$expected_executable" "$actual_executable" "$executable_label"
	if [ -e "$actual_executable" ] && [ ! -x "$actual_executable" ]; then
		printf 'NOT EXECUTABLE: %s (%s)\n' "$executable_label" "$actual_executable" >&2
		verification_failed=1
	fi
}

verify_tree() {
	expected_tree=$1
	actual_tree=$2
	tree_label=$3

	if [ ! -d "$expected_tree" ]; then
		printf 'MISSING SOURCE TREE: %s (%s)\n' "$tree_label" "$expected_tree" >&2
		verification_failed=1
	elif [ ! -d "$actual_tree" ]; then
		printf 'MISSING INSTALL TREE: %s (%s)\n' "$tree_label" "$actual_tree" >&2
		verification_failed=1
	elif diff -qr "$expected_tree" "$actual_tree" >"$tree_diff"; then
		:
	else
		printf 'MISMATCH TREE: %s (%s)\n' "$tree_label" "$actual_tree" >&2
		sed 's/^/  /' "$tree_diff" >&2
		verification_failed=1
	fi
}

verify_install() {
	verification_failed=0

	verify_executable "$repo_dir/dwm" "$binary_target" "dwm binary"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		install_name=${install_source##*/}
		verify_executable "$repo_dir/$install_source" "$prefix/bin/$install_name" \
			"installed command $install_name"
	done <"$install_sources_file"
	verify_executable "$expected_display_root_helper" \
		"$display_root_helper_target" "privileged display helper"
	verify_privileged_helper_trust=1
	if [ "${DWM_DEV_SYNC_SKIP_PRIVILEGED_TRUST:-0}" = 1 ]; then
		verify_privileged_helper_trust=0
	fi
	if [ "$verify_privileged_helper_trust" -eq 1 ] && [ -e "$display_root_helper_target" ]; then
		if [ "$(stat -c %u "$display_root_helper_target")" -ne 0 ] ||
			find "$display_root_helper_target" -maxdepth 0 -perm /022 -print -quit | grep -q .; then
			printf 'UNTRUSTED: privileged display helper ownership or mode (%s)\n' \
				"$display_root_helper_target" >&2
			verification_failed=1
		fi
	fi

	verify_file "$expected_man" "$man_target" "dwm man page"
	verify_file "$expected_xsession" "$xsession_target" "dwm X session"
	verify_tree "$repo_dir/config" "$data_dir/config" "managed data config"
	verify_tree "$repo_dir/scripts" "$data_dir/scripts" "managed data scripts"
	verify_tree "$repo_dir/config/quickshell" "$quickshell_dir" "managed Quickshell"

	for cursor_source in "$repo_dir"/assets/cursors/Capitaine-Cursors*; do
		[ -d "$cursor_source" ] || continue
		cursor_name=${cursor_source##*/}
		verify_tree "$cursor_source" "$data_root/icons/$cursor_name" \
			"cursor theme $cursor_name"
	done
	verify_file "$repo_dir/assets/cursors/COPYING" \
		"$data_root/licenses/dwm-titus/capitaine-cursors/COPYING" \
		"cursor license"

	if [ "$verification_failed" -eq 0 ]; then
		printf 'All managed files match the checkout.\n'
		return 0
	fi
	return 1
}

add_system_backup_path() {
	system_path=$1
	if [ -e "$system_path" ] || [ -L "$system_path" ]; then
		printf '%s\n' "${system_path#/}" >>"$system_manifest"
	fi
}

backup_live_install() {
	for backup_command in date git sha256sum tar; do
		command -v "$backup_command" >/dev/null 2>&1 ||
			die "required backup command not found: $backup_command"
	done

	backup_parent=$state_home/dwm-titus/live-update-backups
	backup_stamp=$(date -u +%Y%m%dT%H%M%SZ)
	mkdir -p "$backup_parent"
	backup_dir=$backup_parent/$backup_stamp-$$
	mkdir -m 700 "$backup_dir"

	if [ -e "$quickshell_dir" ]; then
		tar -C "$(dirname "$quickshell_dir")" -cpf \
			"$backup_dir/quickshell.tar" "$(basename "$quickshell_dir")"
	fi
	if [ -e "$data_dir" ]; then
		tar -C "$(dirname "$data_dir")" -cpf \
			"$backup_dir/dwm-titus-data.tar" "$(basename "$data_dir")"
	fi

	system_manifest=$work/system-files
	: >"$system_manifest"
	add_system_backup_path "$binary_target"
	add_system_backup_path "$man_target"
	add_system_backup_path "$xsession_target"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		add_system_backup_path "$prefix/bin/${install_source##*/}"
	done <"$install_sources_file"
	add_system_backup_path "$display_root_helper_target"
	for cursor_source in "$repo_dir"/assets/cursors/Capitaine-Cursors*; do
		[ -d "$cursor_source" ] || continue
		add_system_backup_path "$data_root/icons/${cursor_source##*/}"
	done
	add_system_backup_path "$data_root/licenses/dwm-titus/capitaine-cursors/COPYING"
	if [ -s "$system_manifest" ]; then
		tar -C / -cpf "$backup_dir/system-files.tar" -T "$system_manifest"
	fi

	{
		printf 'commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf unknown)"
		printf 'branch=%s\n' "$(git -C "$repo_dir" branch --show-current 2>/dev/null || printf unknown)"
		printf 'prefix=%s\n' "$prefix"
		printf 'data_root=%s\n' "$data_root"
		printf 'config_home=%s\n' "$config_home"
		printf 'xdg_data_home=%s\n' "$xdg_data_home"
	} >"$backup_dir/checkout.txt"

	: >"$backup_dir/SHA256SUMS"
	for backup_archive in "$backup_dir"/*.tar; do
		[ -f "$backup_archive" ] || continue
		sha256sum "$backup_archive" >>"$backup_dir/SHA256SUMS"
	done
	printf 'Backup created: %s\n' "$backup_dir"
}

runtime_verify() {
	allow_session_restart=$1
	runtime_failed=0

	if [ "${DWM_DEV_SYNC_SKIP_RUNTIME:-0}" = 1 ]; then
		printf 'Runtime validation skipped by DWM_DEV_SYNC_SKIP_RUNTIME=1.\n'
		return 0
	fi
	if [ -z "${DISPLAY:-}" ]; then
		printf 'Runtime validation deferred: DISPLAY is unavailable.\n'
		return 0
	fi

	dwm_pid=$(pgrep -xo dwm 2>/dev/null || true)
	dwm_restart_required=0
	if [ -n "$dwm_pid" ]; then
		running_executable=$(readlink "/proc/$dwm_pid/exe" 2>/dev/null || true)
		case $running_executable in
		*" (deleted)") dwm_restart_required=1 ;;
		esac
		if [ "$dwm_restart_required" -eq 0 ] &&
			! cmp -s "/proc/$dwm_pid/exe" "$binary_target"; then
			dwm_restart_required=1
		fi
	fi

	restart_quickshell_now=$allow_session_restart
	if [ "$allow_session_restart" -eq 1 ] && [ "$dwm_restart_required" -eq 1 ]; then
		restart_quickshell_now=0
		printf 'Quickshell activation deferred to the required session restart to preserve tray startup order.\n'
	fi

	if command -v quickshell >/dev/null 2>&1; then
		if [ "$restart_quickshell_now" -eq 1 ]; then
			control_helper=$prefix/bin/dwm-quickshell-controlcenter
			if [ ! -x "$control_helper" ]; then
				printf 'Runtime error: managed Quickshell control helper is unavailable.\n' >&2
				runtime_failed=1
			elif ! "$control_helper" action restart-quickshell; then
				printf 'Runtime error: Quickshell restart failed.\n' >&2
				runtime_failed=1
			fi
		fi

		tray_ready=0
		tray_count=
		tray_try=0
		while [ "$tray_try" -lt 50 ]; do
			if tray_count=$(quickshell ipc --path "$quickshell_dir/shell.qml" \
				call tray count 2>/dev/null); then
				tray_ready=1
				break
			fi
			tray_try=$((tray_try + 1))
			sleep 0.1
		done
		if [ "$tray_ready" -eq 1 ]; then
			quickshell_count=$(pgrep -xc quickshell 2>/dev/null || true)
			if [ "$quickshell_count" -ne 1 ]; then
				printf 'Runtime error: expected one Quickshell process, found %s.\n' \
					"$quickshell_count" >&2
				runtime_failed=1
			else
				printf 'Quickshell IPC ready; tray items: %s.\n' "$tray_count"
			fi
		else
			printf 'Runtime error: Quickshell tray IPC did not become ready.\n' >&2
			runtime_failed=1
		fi
	else
		printf 'Runtime validation deferred: Quickshell is not installed.\n'
	fi

	if [ -n "$dwm_pid" ]; then
		if [ "$dwm_restart_required" -eq 1 ]; then
			if [ "$allow_session_restart" -eq 1 ]; then
				printf '\nSESSION RESTART REQUIRED: log out and back in to activate %s.\n' \
					"$binary_target"
			else
				printf 'Runtime error: running dwm does not match the installed binary.\n' >&2
				runtime_failed=1
			fi
		else
			printf 'Running dwm matches the installed binary.\n'
		fi

		if command -v systemctl >/dev/null 2>&1; then
			for graphical_target in graphical-session.target xdg-desktop-autostart.target; do
				if ! systemctl --user is-active --quiet "$graphical_target" 2>/dev/null; then
					printf 'Runtime error: %s is not active.\n' "$graphical_target" >&2
					runtime_failed=1
				fi
			done
			failed_autostarts=$(systemctl --user --failed --no-legend --plain 2>/dev/null |
				awk '$1 ~ /@autostart[.]service$/ { print $1 }')
			if [ -n "$failed_autostarts" ]; then
				printf 'Runtime error: failed XDG autostart units:\n%s\n' \
					"$failed_autostarts" >&2
				runtime_failed=1
			fi
		fi
	else
		printf 'Runtime validation deferred: dwm is not running.\n'
	fi

	[ "$runtime_failed" -eq 0 ]
}

if [ "$check_only" -eq 0 ] && [ "$(id -u)" -eq 0 ]; then
	die "run this script as the desktop user, not root"
fi

prepare_expected_files
reconcile_source_update_dependencies

if [ "$check_only" -eq 1 ]; then
	note "Checking live install against $repo_dir"
	verify_install || exit 1
	runtime_verify 0 || exit 1
	exit 0
fi

note "Building current checkout"
"$make_path" -C "$repo_dir" clean
"$make_path" -C "$repo_dir" all

if verify_install; then
	note "Live installation is already current"
	runtime_verify 0 || exit 1
	exit 0
fi

note "Backing up current live installation"
backup_live_install

command -v sudo >/dev/null 2>&1 || die "sudo is required for the system install"
sudo -v

note "Installing complete system and user state"
sudo "$make_path" -C "$repo_dir" install \
	DESTDIR= \
	PREFIX="$prefix" \
	MANPREFIX="$manprefix" \
	XSESSIONSDIR="$xsessions_dir" \
	DATADIR="$data_root" \
	USER_HOME="$user_home" \
	OWNER="$owner" \
	XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$xdg_data_home"

note "Verifying installed state"
verify_install || die "live installation does not match the checkout"
runtime_verify 1 || die "runtime validation failed"
