#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
printf 'ID=fedora\n' >"$work/os-release"
export DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/os-release"
export PATH="$work/bin:$PATH" TIMESYNC_LOG="$work/log"
cat >"$work/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TIMESYNC_LOG"
case "$1" in
is-enabled)
	unit=${@: -1}
	if [[ $unit == "${ENABLED_PROVIDER:-}" ]]; then exit 0; fi
	if [[ $unit == systemd-timesyncd.service && $* != *--quiet* ]]; then
		printf '%s\n' "${TIMESYNC_STATE:-disabled}"
	fi
	exit 1 ;;
is-active)
	if [[ ${LIVE_MANAGER:-0} == 0 ]]; then exit 0; fi
	[[ ${@: -1} == "${ACTIVE_PROVIDER:-}" ]] ;;
show)
	if [[ ${LIVE_MANAGER:-0} == 1 ]]; then printf '259\n'; fi
	# Like real systemctl in a chroot, success alone does not prove a manager.
	;;
enable | start) [[ ${FAIL_MUTATION:-0} == 0 ]] ;;
*) exit 2 ;;
esac
MOCK
cat >"$work/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == systemctl && ( $2 == enable || $2 == start ) && $3 == systemd-timesyncd.service && $# == 3 ]]
shift
exec systemctl "$@"
MOCK
chmod +x "$work/bin/systemctl" "$work/bin/sudo"
run() {
	: >"$TIMESYNC_LOG"
	bash "$repo/scripts/configure-timesync.sh" >"$work/output" 2>&1
}
run
grep -Fxq 'enable systemd-timesyncd.service' "$TIMESYNC_LOG"
if grep -q '^start ' "$TIMESYNC_LOG"; then exit 1; fi
export LIVE_MANAGER=1
run
grep -Fxq 'start systemd-timesyncd.service' "$TIMESYNC_LOG"
run # repeated enable/start is safe and does not disable another provider
if grep -Eq '^(disable|stop|mask) ' "$TIMESYNC_LOG"; then exit 1; fi
for provider in chronyd.service chronyd-restricted.service ntpd.service ntpsec.service openntpd.service; do
	export ENABLED_PROVIDER=$provider
	run
	grep -Fxq "Preserving existing time synchronization provider: $provider" "$work/output"
	if grep -Eq '^(enable|start) ' "$TIMESYNC_LOG"; then exit 1; fi
	unset ENABLED_PROVIDER
	export ACTIVE_PROVIDER=$provider
	run
	grep -Fxq "Preserving existing time synchronization provider: $provider" "$work/output"
	if grep -Eq '^(enable|start) ' "$TIMESYNC_LOG"; then exit 1; fi
	unset ACTIVE_PROVIDER
done
for state in masked masked-runtime; do
	export TIMESYNC_STATE=$state
	run
	if grep -Eq '^(enable|start) ' "$TIMESYNC_LOG"; then exit 1; fi
done
unset TIMESYNC_STATE
export FAIL_MUTATION=1
if run; then
	echo 'Failed enablement must fail provisioning' >&2
	exit 1
fi
unset FAIL_MUTATION
printf 'ID=debian\n' >"$DWM_OS_RELEASE"
if run; then
	echo 'Non-Fedora provisioning must fail' >&2
	exit 1
fi
[[ ! -s $TIMESYNC_LOG ]]
"$repo/scripts/dwm-packages.sh" fedora runtime-required | grep -Fx systemd-udev >/dev/null
for ks in dwm-fedora.ks dwm-fedora-nvidia.ks; do
	grep -Fxq systemd-udev "$repo/$ks"
	grep -Fxq -- -chrony "$repo/$ks"
	grep -Fq 'services --enabled=NetworkManager,systemd-timesyncd' "$repo/$ks"
done
printf 'Automatic time synchronization provisioning checks passed.\n'
