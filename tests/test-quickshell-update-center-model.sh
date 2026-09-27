#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
protocol=$repo/config/quickshell/updatecenter/UpdateCenterProtocol.js
model=$repo/config/quickshell/updatecenter/UpdateCenterModel.qml
commands=$repo/config/quickshell/core/Commands.qml

test -f "$protocol"
test -f "$model"
grep -Fq 'import Quickshell.Networking' "$model"
grep -Fq 'property var connectivitySource: Networking' "$model"
grep -Fq 'NetworkConnectivity.Full' "$model"
grep -Fq 'if (!root.connectivityReady) return;' "$model"
grep -Fq 'interval: 30000' "$model"
grep -Fq 'root.pendingForceRefresh = true;' "$model"
grep -Fq 'Commands.updateCenterCommand("terminal-closed", [operationId])' "$model"
grep -Fq 'operationProcess.needsAuthoritativeRefresh = true;' "$model"
grep -Fq 'property bool pendingSettingsReload: false' "$model"
grep -Fq 'exitStatus === 0 && exitCode === 0' "$model"
grep -Fq 'function updateCenterCommand(action, args)' "$commands"
grep -Fq 'function updateCenterSettingsCommand(action, args)' "$commands"
[ "$(grep -Fc 'Process {' "$model")" -eq 4 ]
if grep -Eq '(^|[^A-Za-z])(XMLHttpRequest|LocalStorage|FileDialog|StandardPaths)([^A-Za-z]|$)' "$model"; then
	printf '%s\n' 'Update Center QML must not read or write files directly.' >&2
	exit 1
fi

command -v quickshell >/dev/null 2>&1 || {
	printf '%s\n' 'SKIP: Quickshell is unavailable; executable model assertions were not run.'
	exit 77
}

tmp=$(mktemp -d "${DWM_TEST_WORKSPACE:-${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}}/update-center-qml.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/config/core" "$tmp/config/updatecenter" "$tmp/data/dwm-titus/scripts" "$tmp/state"
cp "$repo/tests/quickshell-update-center-model.qml" "$tmp/config/shell.qml"
cp "$repo/config/quickshell/core/Commands.qml" "$tmp/config/core/Commands.qml"
cp "$repo/config/quickshell/updatecenter/UpdateCenterModel.qml" "$tmp/config/updatecenter/UpdateCenterModel.qml"
cp "$repo/config/quickshell/updatecenter/UpdateCenterProtocol.js" "$tmp/config/updatecenter/UpdateCenterProtocol.js"

fixture=$tmp/data/dwm-titus/scripts/dwm-update-center
cat >"$fixture" <<'EOF'
#!/bin/sh
set -eu
root=${DWM_UPDATE_CENTER_FIXTURE:?}
header='update-center-action-protocol	1	0'
emit_operation() {
	printf '%b\noperation\t%s\t%s\t%s\t%s\t%s\ncomplete\taction\n' "$header" "$1" "$2" "$3" "$4" "$5"
}
case ${1-} in
snapshot)
	if [ "${2-}" = --force ]; then
		count=$(($(cat "$root/scan-count" 2>/dev/null || printf 0) + 1))
		printf '%s\n' "$count" >"$root/scan-count"
		[ "$count" -ne 1 ] || sleep 0.15
		if [ "$count" -eq 5 ]; then
			printf 'update-center-protocol\t1\t0\nprovider\tfedora\tFedora\tavailable\t1\t1\tfresh\t10\tyes\t\tinvalid-nonzero\nitem\tfedora\tupdate\tPackage\t1\t2\tpkg\tsystem\thttps://example.test/release\ncomplete\tsnapshot\n'
			printf '%s\n' 'fixture scan failure' >&2
			exit 1
		fi
		detail=force-$count
	else
		detail=cache
	fi
	printf 'update-center-protocol\t1\t0\nprovider\tfedora\tFedora\tavailable\t1\t1\tfresh\t10\tyes\t\t%s\nitem\tfedora\tupdate\tPackage\t1\t2\tpkg\tsystem\thttps://example.test/release\ncomplete\tsnapshot\n' "$detail"
	;;
active)
	if [ ! -s "$root/operation" ]; then
		printf '%b\nactive\tnone\ncomplete\taction\n' "$header"
	else
		IFS="$(printf '\t')" read -r operation provider action phase outcome <"$root/operation"
		emit_operation "$operation" "$provider" "$action" "$phase" "$outcome"
	fi
	;;
terminal-closed)
	IFS="$(printf '\t')" read -r operation provider action phase outcome <"$root/operation"
	[ "$2" = "$operation" ] || exit 1
	case $phase in
	completed | failed)
		emit_operation "$operation" "$provider" "$action" closed "$outcome"
		: >"$root/operation"
		;;
	*) emit_operation "$operation" "$provider" "$action" "$phase" "$outcome" ;;
	esac
	;;
launch)
	case $2 in
	fedora)
		op=op-00000000000000000000000000000001
		printf '%s\t%s\t%s\t%s\t%s\n' "$op" fedora update completed succeeded >"$root/operation"
		emit_operation "$op" fedora update launched pending
		;;
	dwm-titus)
		op=op-00000000000000000000000000000002
		printf '%s\t%s\t%s\t%s\t%s\n' "$op" dwm-titus update failed failed >"$root/operation"
		emit_operation "$op" dwm-titus update launched pending
		;;
	flatpak)
		op=op-00000000000000000000000000000003
		printf '%s\t%s\t%s\t%s\t%s\n' "$op" flatpak update interrupted unknown >"$root/operation"
		emit_operation "$op" flatpak update launched pending
		printf '%s\n' 'ambiguous fixture launch' >&2
		exit 1
		;;
	*) exit 1 ;;
	esac
	;;
recover)
	[ "$2" = flatpak ] || exit 1
	op=op-00000000000000000000000000000004
	printf '%s\t%s\t%s\t%s\t%s\n' "$op" flatpak recover completed succeeded >"$root/operation"
	emit_operation "$op" flatpak recover launched pending
	;;
*) exit 2 ;;
esac
EOF
chmod 755 "$fixture"

settings=$tmp/data/dwm-titus/scripts/dwm-update-center-settings
cat >"$settings" <<'EOF'
#!/bin/sh
set -eu
root=${DWM_UPDATE_CENTER_FIXTURE:?}
case ${1-} in
status)
	count=$(($(cat "$root/status-count" 2>/dev/null || printf 0) + 1))
	printf '%s\n' "$count" >"$root/status-count"
	if [ -s "$root/settings" ]; then read -r seconds show baseline <"$root/settings"; else seconds=600 show=disabled baseline=absent; fi
	[ "$count" -gt 2 ] || sleep 1
	printf 'update-center-settings-protocol\t1\t0\nstate\tavailable\tReady\npreference\trefreshSeconds\t%s\npreference\talwaysShow\t%s\nbaseline\t%s\ncomplete\tstatus\n' "$seconds" "$show" "$baseline"
	;;
set)
	count=$(($(cat "$root/settings-count" 2>/dev/null || printf 0) + 1))
	printf '%s\n' "$count" >"$root/settings-count"
	if [ "$count" -gt 2 ]; then printf '%s\n' 'preferences changed; refresh status before saving' >&2; exit 1; fi
	current=absent
	[ ! -s "$root/settings" ] || { read -r _ _ current <"$root/settings"; }
	[ "$4" = "$current" ] || { printf '%s\n' 'preferences changed; refresh status before saving' >&2; exit 1; }
	if [ "$count" -eq 1 ]; then baseline=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; else baseline=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc; fi
	printf '%s %s %s\n' "$2" "$3" "$baseline" >"$root/settings"
	printf 'update-center-settings-action-protocol\t1\t0\nresult\tsuccess\tPreferences saved\nbaseline\t%s\ncomplete\tset\n' "$baseline"
	;;
*) exit 2 ;;
esac
EOF
chmod 755 "$settings"

export DWM_UPDATE_CENTER_FIXTURE="$tmp/state"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_STATE_HOME="$tmp/runtime-state"
export XDG_CONFIG_HOME="$tmp/xdg-config"
export QT_QPA_PLATFORM=offscreen
timeout 20 quickshell --no-duplicate --path "$tmp/config/shell.qml" --no-color

printf '%s\n' 'Quickshell Update Center model contract: PASS'
