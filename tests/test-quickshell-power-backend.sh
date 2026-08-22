#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)

cleanup() {
	set +e
	for pid_file in "$work/helper.pid" "$work/monitor.pid" \
		"$work/settings-monitor.pid" "$work/owner.pid" \
		"$work/hung-helper.pid" "$work/hung-monitor.pid" \
		"$work/hung-probe-wrapper.pid" "$work/hung-settings-get.pid" \
		"$work/hung-owner.pid"; do
		[ -r "$pid_file" ] || continue
		pid=$(cat "$pid_file")
		case $pid in
		'' | *[!0-9]*) continue ;;
		esac
		kill "$pid" 2>/dev/null || :
	done
	find "$work" -depth -delete
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/config/dwm-titus" "$work/home" "$work/state"
: >"$work/actions.log"

cat >"$work/bin/xset" <<'SH'
#!/bin/sh
state=${DWM_POWER_TEST_STATE:?}
printf 'xset %s\n' "$*" >>"${DWM_POWER_TEST_LOG:?}"
if [ "${DWM_POWER_TEST_XSET_FAIL:-}" = "$*" ]; then
	exit 1
fi
if [ "${DWM_POWER_TEST_XSET_Q_FAIL:-0}" = 1 ] && [ "${1:-}" = q ]; then
	exit 1
fi
if [ "${DWM_POWER_TEST_XSET_NO_DPMS:-0}" = 1 ]; then
	case ${1:-} in
	+dpms | -dpms | dpms) exit 1 ;;
	esac
fi
if [ "${DWM_POWER_TEST_XSET_NO_CONVERGE:-0}" = 1 ] && [ "${1:-}" != q ]; then
	exit 0
fi
read_state() {
	if [ -r "$state/$1" ]; then cat "$state/$1"; else printf '%s\n' "$2"; fi
}
case ${1:-} in
q)
	dpms=$(read_state dpms_enabled 0)
	[ "$dpms" = 1 ] && dpms_text=Enabled || dpms_text=Disabled
	timeout=$(read_state dpms_timeout 600)
	saver=$(read_state saver_timeout 0)
	if [ "${DWM_POWER_TEST_XSET_NO_DPMS:-0}" = 1 ]; then
		cat <<EOF
Screen Saver:
  timeout:  $saver    cycle:  600
DPMS (Display Power Management Signaling):
  Server does not have the DPMS Extension
EOF
		exit 0
	fi
	cat <<EOF
Screen Saver:
  timeout:  $saver    cycle:  600
DPMS (Display Power Management Signaling):
  Standby: $timeout    Suspend: $timeout    Off: $timeout
  DPMS is $dpms_text
EOF
	;;
+dpms) printf '1\n' >"$state/dpms_enabled" ;;
-dpms) printf '0\n' >"$state/dpms_enabled" ;;
dpms) printf '%s\n' "$4" >"$state/dpms_timeout" ;;
s)
	case ${2:-} in
	off) printf '0\n' >"$state/saver_timeout" ;;
	noblank) : ;;
	*) printf '%s\n' "$2" >"$state/saver_timeout" ;;
	esac
	;;
esac
SH
chmod +x "$work/bin/xset"

cat >"$work/bin/gsettings" <<'SH'
#!/bin/sh
state=${DWM_POWER_TEST_STATE:?}
printf 'gsettings %s\n' "$*" >>"${DWM_POWER_TEST_LOG:?}"
case ${1:-}:${2:-}:${3:-} in
monitor:apps.light-locker:)
	printf '%s\n' "$$" >"$state/settings-monitor.pid"
	if [ "${DWM_POWER_TEST_SETTINGS_MONITOR_IGNORE_TERM:-0}" = 1 ]; then
		trap '' TERM
	else
		trap 'exit 0' HUP INT TERM
	fi
	while [ ! -e "$state/settings-change.trigger" ]; do sleep 0.05; done
	rm -f "$state/settings-change.trigger"
	printf 'lock-after-screensaver: uint32 %s\n' "$(cat "$state/lock_after" 2>/dev/null || printf 0)"
	while :; do sleep 1; done
	;;
get:apps.light-locker:lock-after-screensaver)
	if [ "${DWM_POWER_TEST_GSETTINGS_GET_HANG:-0}" = 1 ]; then
		printf '%s\n' "$$" >"$state/settings-get.pid"
		printf '%s\n' "$PPID" >"$state/settings-get-parent.pid"
		if [ "${DWM_POWER_TEST_GSETTINGS_GET_IGNORE_TERM:-0}" = 1 ]; then
			trap '' TERM
		else
			trap 'exit 0' HUP INT TERM
		fi
		while :; do sleep 1; done
	fi
	printf 'uint32 %s\n' "$(cat "$state/lock_after" 2>/dev/null || printf 0)"
	;;
get:apps.light-locker:lock-on-suspend)
	cat "$state/lock_on_suspend" 2>/dev/null || printf 'false\n'
	;;
set:apps.light-locker:*)
	if [ "${DWM_POWER_TEST_GSETTINGS_FAIL:-}" = "${3:-}" ]; then
		exit 1
	fi
	case $3 in
	lock-after-screensaver) printf '%s\n' "$4" >"$state/lock_after" ;;
	lock-on-suspend) printf '%s\n' "$4" >"$state/lock_on_suspend" ;;
	esac
	;;
*) exit 1 ;;
esac
SH
chmod +x "$work/bin/gsettings"

cat >"$work/bin/light-locker" <<'SH'
#!/bin/sh
[ "${DWM_POWER_TEST_LOCKER_NO_CONVERGE:-0}" != 1 ] || exit 0
: >"${DWM_POWER_TEST_STATE:?}/light-locker.running"
SH
chmod +x "$work/bin/light-locker"

cat >"$work/bin/pgrep" <<'SH'
#!/bin/sh
case $* in
*light-locker*) test -e "${DWM_POWER_TEST_STATE:?}/light-locker.running" ;;
*) exit 1 ;;
esac
SH
chmod +x "$work/bin/pgrep"

cat >"$work/bin/pkill" <<'SH'
#!/bin/sh
case $* in
*light-locker*)
	if [ "${DWM_POWER_TEST_LOCKER_EXIT_DELAY:-0}" = 1 ]; then
		(sleep 0.2; rm -f "${DWM_POWER_TEST_STATE:?}/light-locker.running") &
	else
		rm -f "${DWM_POWER_TEST_STATE:?}/light-locker.running"
	fi
	;;
esac
SH
chmod +x "$work/bin/pkill"

cat >"$work/bin/notify-send" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$work/bin/notify-send"

cat >"$work/bin/mv" <<'SH'
#!/bin/sh
if [ "${DWM_POWER_TEST_MV_FAIL:-0}" = 1 ]; then
	for argument in "$@"; do
		destination=$argument
	done
	case ${destination:-} in
	*/power.conf) exit 1 ;;
	esac
fi
exec /usr/bin/mv "$@"
SH
chmod +x "$work/bin/mv"

cat >"$work/bin/busctl" <<'SH'
#!/bin/sh
state=${DWM_POWER_TEST_STATE:?}
printf 'busctl %s\n' "$*" >>"${DWM_POWER_TEST_LOG:?}"
command_name=
while [ "$#" -gt 0 ]; do
	case $1 in
	get-property | set-property | call | monitor)
		command_name=$1
		shift
		break
		;;
	esac
	shift
done

case $command_name in
monitor)
	printf '%s\n' "$$" >"$state/monitor.pid"
	trap 'exit 0' HUP INT TERM
	printf 'signal\n'
	while :; do sleep 1; done
	;;
set-property)
	[ "${DWM_POWER_TEST_PROFILE_SET_FAIL:-0}" != 1 ] || exit 1
	for argument in "$@"; do profile=$argument; done
	if [ "${DWM_POWER_TEST_PROFILE_NO_CONVERGE:-0}" != 1 ]; then
		printf '%s\n' "$profile" >"$state/active_profile"
	fi
	exit 0
	;;
call)
	[ "${DWM_POWER_TEST_LOGIND_FAIL:-0}" != 1 ] || exit 1
	printf '{"type":"s","data":["%s"]}\n' "${DWM_POWER_TEST_CAN_SUSPEND:-yes}"
	;;
get-property)
	service=$1
	path=$2
	interface=$3
	property=$4
	case $service in
	org.freedesktop.UPower)
		[ "${DWM_POWER_TEST_UPOWER_FAIL:-0}" != 1 ] || exit 1
		case $property in
		OnBattery) printf '{"type":"b","data":%s}\n' "${DWM_POWER_TEST_ON_BATTERY:-false}" ;;
		LidIsPresent) printf '{"type":"b","data":%s}\n' "${DWM_POWER_TEST_LID_PRESENT:-false}" ;;
		LidIsClosed) printf '{"type":"b","data":%s}\n' "${DWM_POWER_TEST_LID_CLOSED:-false}" ;;
		IsPresent) printf '{"type":"b","data":%s}\n' "${DWM_POWER_TEST_BATTERY_PRESENT:-false}" ;;
		State) printf '{"type":"u","data":%s}\n' "${DWM_POWER_TEST_BATTERY_STATE:-0}" ;;
		Percentage)
			if [ "${DWM_POWER_TEST_BATTERY_PERCENT:-0}" = malformed ]; then
				printf '%s\n' '{"type":"d","data":"malformed"}'
			else
				printf '{"type":"d","data":%s}\n' "${DWM_POWER_TEST_BATTERY_PERCENT:-0}"
			fi
			;;
		TimeToEmpty) printf '{"type":"x","data":%s}\n' "${DWM_POWER_TEST_TIME_EMPTY:-0}" ;;
		TimeToFull) printf '{"type":"x","data":%s}\n' "${DWM_POWER_TEST_TIME_FULL:-0}" ;;
		EnergyRate) printf '{"type":"d","data":%s}\n' "${DWM_POWER_TEST_ENERGY_RATE:-0}" ;;
		*) exit 1 ;;
		esac
		;;
	org.freedesktop.UPower.PowerProfiles)
		[ "${DWM_POWER_TEST_PROFILE_FAIL:-0}" != 1 ] || exit 1
		case $property in
		ActiveProfile)
			profile=$(cat "$state/active_profile" 2>/dev/null || printf balanced)
			printf '{"type":"s","data":"%s"}\n' "$profile"
			;;
		Profiles)
			printf '%s\n' '{"type":"aa{sv}","data":[{"Profile":{"type":"s","data":"power-saver"}},{"Profile":{"type":"s","data":"balanced"}},{"Profile":{"type":"s","data":"performance"}}]}'
			;;
		*) exit 1 ;;
		esac
		;;
	org.freedesktop.login1)
		[ "${DWM_POWER_TEST_LOGIND_FAIL:-0}" != 1 ] || exit 1
		case $property in
		HandleLidSwitch) value=suspend ;;
		HandleLidSwitchExternalPower) value= ;;
		HandleLidSwitchDocked) value=ignore ;;
		*) exit 1 ;;
		esac
		printf '{"type":"s","data":"%s"}\n' "$value"
		;;
	*) exit 1 ;;
	esac
	;;
*) exit 2 ;;
esac
SH
chmod +x "$work/bin/busctl"

cat >"$work/bin/dbus-monitor" <<'SH'
#!/bin/sh
state=${DWM_POWER_TEST_STATE:?}
printf 'dbus-monitor %s\n' "$*" >>"${DWM_POWER_TEST_LOG:?}"
printf '%s\n' "$$" >"$state/monitor.pid"
trap 'exit 0' HUP INT TERM
printf 'signal\n'
while :; do sleep 1; done
SH
chmod +x "$work/bin/dbus-monitor"

write_initial_config() {
	cat >"$work/config/dwm-titus/power.conf" <<'EOF'
# user power preferences
custom_key=keep
dpms_enabled=0
dpms_timeout=600
lock_enabled=0
lock_managed=1
lock_timeout=600
lock_after=5
EOF
	chmod 600 "$work/config/dwm-titus/power.conf"
	printf '0\n' >"$work/state/dpms_enabled"
	printf '600\n' >"$work/state/dpms_timeout"
	printf '0\n' >"$work/state/saver_timeout"
	printf '0\n' >"$work/state/lock_after"
	printf 'false\n' >"$work/state/lock_on_suspend"
	rm -f "$work/state/light-locker.running"
}

run_helper() {
	HOME="$work/home" \
		XDG_CONFIG_HOME="$work/config" \
		DWM_POWER_TEST_STATE="$work/state" \
		DWM_POWER_TEST_LOG="$work/actions.log" \
		PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/dwm-quickshell-controlcenter" "$@"
}

expect_status() {
	expected=$1
	shift
	set +e
	"$@" >"$work/status.out" 2>"$work/status.err"
	status=$?
	set -e
	[ "$status" -eq "$expected" ]
}

process_running() {
	pid=$1
	[ -r "/proc/$pid/stat" ] || return 1
	state=$(sed 's/^.*) //' "/proc/$pid/stat" | awk '{ print $1 }')
	[ "$state" != Z ]
}

write_initial_config
export DWM_POWER_TEST_BATTERY_PRESENT=true
export DWM_POWER_TEST_BATTERY_STATE=2
export DWM_POWER_TEST_BATTERY_PERCENT=72.6
export DWM_POWER_TEST_TIME_EMPTY=4200
export DWM_POWER_TEST_ENERGY_RATE=12.5
export DWM_POWER_TEST_LID_PRESENT=true
export DWM_POWER_TEST_LID_CLOSED=true
export DWM_POWER_TEST_ON_BATTERY=true
export DWM_POWER_TEST_CAN_SUSPEND=challenge
snapshot=$(run_helper power-snapshot)
[ "$(printf '%s\n' "$snapshot" | sed -n '1p')" = "power-protocol	1	0" ]
printf '%s\n' "$snapshot" | grep -Fqx 'power-external	off	System is running on battery power'
printf '%s\n' "$snapshot" | grep -Fqx 'power-battery	available	discharging	73	4200	0	12.5	Composite UPower display battery'
printf '%s\n' "$snapshot" | grep -Fqx 'power-lid	available	closed	delegated	Lid policy is owned by systemd-logind'
printf '%s\n' "$snapshot" | grep -Fqx 'power-profile	balanced	active'
printf '%s\n' "$snapshot" | grep -Fqx 'power-suspend	available	delegated	Suspend requires authorization'
printf '%s\n' "$snapshot" | grep -Fqx 'power-lid-policy	available	suspend	default	ignore	read-only	Persistent lid policy is owned by systemd-logind'

export DWM_POWER_TEST_ENERGY_RATE=1E-7
exponent_rate_snapshot=$(run_helper power-snapshot)
printf '%s\n' "$exponent_rate_snapshot" |
	grep -Fqx 'power-battery	available	discharging	73	4200	0	1E-7	Composite UPower display battery'
export DWM_POWER_TEST_ENERGY_RATE=12.5

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_XSET_NO_DPMS=1
no_dpms_snapshot=$(run_helper power-snapshot)
printf '%s\n' "$no_dpms_snapshot" |
	grep -Fqx 'power-dpms	unavailable	no	600	user-session	X11 display power management'
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
if grep -Fq 'power-dpms' "$work/status.out"; then
	printf 'Unavailable DPMS action reported success\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_XSET_NO_DPMS

export DWM_POWER_TEST_CAN_SUSPEND=no
printf '%s\n' "$(run_helper power-snapshot)" |
	grep -Fqx 'power-suspend	restricted	delegated	Suspend is blocked by authorization policy'
export DWM_POWER_TEST_CAN_SUSPEND=na
printf '%s\n' "$(run_helper power-snapshot)" |
	grep -Fqx 'power-suspend	unavailable	read-only	Suspend is not supported by this system'
export DWM_POWER_TEST_CAN_SUSPEND=yes
printf '%s\n' "$(run_helper power-snapshot)" |
	grep -Fqx 'power-suspend	available	delegated	Suspend is available without an authorization challenge'

export DWM_POWER_TEST_BATTERY_PERCENT=malformed
malformed_battery=$(run_helper power-snapshot)
printf '%s\n' "$malformed_battery" | grep -Fqx 'power-battery	restricted	unknown	0	0	0	0	UPower battery state is incomplete'
export DWM_POWER_TEST_BATTERY_PERCENT=72.6

export DWM_POWER_TEST_ENERGY_RATE=1E+999
overflow_battery=$(run_helper power-snapshot)
printf '%s\n' "$overflow_battery" | grep -Fqx 'power-battery	restricted	unknown	0	0	0	0	UPower battery state is incomplete'
export DWM_POWER_TEST_ENERGY_RATE=12.5

export DWM_POWER_TEST_UPOWER_FAIL=1
export DWM_POWER_TEST_PROFILE_FAIL=1
export DWM_POWER_TEST_LOGIND_FAIL=1
degraded=$(run_helper power-snapshot)
printf '%s\n' "$degraded" | grep -Fq 'power-dpms	available'
printf '%s\n' "$degraded" | grep -Fqx 'power-battery	unavailable	unknown	0	0	0	0	UPower is unavailable'
printf '%s\n' "$degraded" | grep -Fqx 'power-profile-support	unavailable	read-only	Power Profiles service is unavailable'
printf '%s\n' "$degraded" | grep -Fqx 'power-suspend	unavailable	read-only	logind suspend capability is unavailable'
printf '%s\n' "$degraded" | grep -Fqx 'power-lid-policy	unavailable	unknown	unknown	unknown	read-only	logind lid policy is unavailable'
unset DWM_POWER_TEST_UPOWER_FAIL DWM_POWER_TEST_PROFILE_FAIL DWM_POWER_TEST_LOGIND_FAIL

: >"$work/actions.log"
profile_result=$(run_helper power-profile-set performance)
[ "$profile_result" = 'power-profile	performance' ]
[ "$(cat "$work/state/active_profile")" = performance ]
grep -Fq -- '--allow-interactive-authorization=yes set-property' "$work/actions.log"
expect_status 2 run_helper power-profile-set turbo
export DWM_POWER_TEST_PROFILE_NO_CONVERGE=1
expect_status 1 run_helper power-profile-set balanced
if grep -Fq 'power-profile	balanced' "$work/status.out"; then
	printf 'Profile action reported success without convergence\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_PROFILE_NO_CONVERGE
export DWM_POWER_TEST_PROFILE_SET_FAIL=1
expect_status 1 run_helper power-profile-set power-saver
if grep -Fq 'power-profile	power-saver' "$work/status.out"; then
	printf 'Denied profile action reported success\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_PROFILE_SET_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
for invalid in '' 59 86401 abc 999999999999999999999999; do
	expect_status 2 run_helper power-dpms-timeout "$invalid"
	[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
	expect_status 2 run_helper power-lock-timeout "$invalid"
	[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
done

run_helper power-dpms-timeout 900 >/dev/null
grep -Fqx '# user power preferences' "$work/config/dwm-titus/power.conf"
grep -Fqx 'custom_key=keep' "$work/config/dwm-titus/power.conf"
grep -Fqx 'dpms_enabled=1' "$work/config/dwm-titus/power.conf"
grep -Fqx 'dpms_timeout=900' "$work/config/dwm-titus/power.conf"
[ "$(stat -c %a "$work/config/dwm-titus/power.conf")" = 600 ]
if find "$work/config/dwm-titus" -maxdepth 1 -name '.power.conf.*' -print -quit | grep -q .; then
	printf 'Power configuration temporary file was not cleaned up\n' >&2
	exit 1
fi

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_XSET_FAIL=+dpms
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
unset DWM_POWER_TEST_XSET_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_XSET_NO_CONVERGE=1
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
unset DWM_POWER_TEST_XSET_NO_CONVERGE

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_MV_FAIL=1
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
[ "$(cat "$work/state/dpms_enabled")" = 0 ]
if grep -Fq 'power-dpms' "$work/status.out"; then
	printf 'Persistence failure reported display power success\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_MV_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_MV_FAIL=1
export DWM_POWER_TEST_XSET_FAIL=-dpms
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
grep -Fq 'rollback also failed and live state may differ' "$work/status.err"
if grep -Fq 'power-dpms' "$work/status.out"; then
	printf 'Rollback failure reported display power success\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_MV_FAIL DWM_POWER_TEST_XSET_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
: >"$work/actions.log"
export DWM_POWER_TEST_XSET_Q_FAIL=1
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
if grep -Eq '^xset (\+dpms|-dpms|dpms )' "$work/actions.log"; then
	printf 'Unavailable DPMS provider was mutated before rejection\n' >&2
	exit 1
fi

: >"$work/actions.log"
expect_status 1 run_helper power-lock on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
[ "$(cat "$work/state/lock_after")" = 0 ]
[ ! -e "$work/state/light-locker.running" ]
if grep -Eq '^gsettings set |^light-locker ' "$work/actions.log"; then
	printf 'Unavailable lock provider was mutated before rejection\n' >&2
	exit 1
fi
unset DWM_POWER_TEST_XSET_Q_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_GSETTINGS_FAIL=lock-on-suspend
expect_status 1 run_helper power-lock on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
[ "$(cat "$work/state/lock_after")" = 0 ]
unset DWM_POWER_TEST_GSETTINGS_FAIL

write_initial_config
before=$(sha256sum "$work/config/dwm-titus/power.conf")
export DWM_POWER_TEST_LOCKER_NO_CONVERGE=1
expect_status 1 run_helper power-lock on
[ "$(sha256sum "$work/config/dwm-titus/power.conf")" = "$before" ]
unset DWM_POWER_TEST_LOCKER_NO_CONVERGE

write_initial_config
sed -i 's/^lock_enabled=0$/lock_enabled=1/' "$work/config/dwm-titus/power.conf"
printf '600\n' >"$work/state/saver_timeout"
printf '5\n' >"$work/state/lock_after"
printf 'true\n' >"$work/state/lock_on_suspend"
: >"$work/state/light-locker.running"
export DWM_POWER_TEST_LOCKER_EXIT_DELAY=1
[ "$(run_helper power-lock off)" = "$(printf 'power-lock\t0')" ]
unset DWM_POWER_TEST_LOCKER_EXIT_DELAY

write_initial_config
mv "$work/config/dwm-titus/power.conf" "$work/power-target.conf"
ln -s "$work/power-target.conf" "$work/config/dwm-titus/power.conf"
before=$(sha256sum "$work/power-target.conf")
: >"$work/actions.log"
expect_status 1 run_helper power-dpms on
[ "$(sha256sum "$work/power-target.conf")" = "$before" ]
if grep -Eq '^xset (\+dpms|-dpms|dpms )' "$work/actions.log"; then
	printf 'Symlinked configuration changed live DPMS before rejection\n' >&2
	exit 1
fi
rm "$work/config/dwm-titus/power.conf"
mv "$work/power-target.conf" "$work/config/dwm-titus/power.conf"

(
	HOME="$work/home" \
		XDG_CONFIG_HOME="$work/config" \
		DWM_POWER_TEST_STATE="$work/state" \
		DWM_POWER_TEST_LOG="$work/actions.log" \
		DWM_POWER_TEST_SETTINGS_MONITOR_IGNORE_TERM=1 \
		PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/dwm-quickshell-controlcenter" power-watch >"$work/watch.out" 2>&1 &
	printf '%s\n' "$!" >"$work/helper.pid"
	wait
) &
owner_pid=$!
printf '%s\n' "$owner_pid" >"$work/owner.pid"
i=0
while [ "$i" -lt 100 ] &&
	{ [ ! -r "$work/state/monitor.pid" ] || [ ! -r "$work/state/settings-monitor.pid" ]; }; do
	sleep 0.05
	i=$((i + 1))
done
[ -r "$work/state/monitor.pid" ]
[ -r "$work/state/settings-monitor.pid" ]
if grep -Fq 'lock-after-screensaver:' "$work/watch.out"; then
	printf 'GSettings watcher emitted a change before the external trigger\n' >&2
	exit 1
fi
: >"$work/state/settings-change.trigger"
i=0
while [ "$i" -lt 100 ] && ! grep -Fq 'lock-after-screensaver:' "$work/watch.out"; do
	sleep 0.05
	i=$((i + 1))
done
grep -Fq 'lock-after-screensaver:' "$work/watch.out"
cp "$work/state/monitor.pid" "$work/monitor.pid"
cp "$work/state/settings-monitor.pid" "$work/settings-monitor.pid"
helper_pid=$(cat "$work/helper.pid")
monitor_pid=$(cat "$work/monitor.pid")
settings_monitor_pid=$(cat "$work/settings-monitor.pid")
kill -STOP "$owner_pid"
sleep 0.5
if ! process_running "$helper_pid" || ! process_running "$monitor_pid" ||
	! process_running "$settings_monitor_pid"; then
	printf 'Parent-bound power watcher stopped during a live-parent state transition\n' >&2
	exit 1
fi
kill -CONT "$owner_pid"
kill -KILL "$owner_pid"
wait "$owner_pid" 2>/dev/null || :
i=0
while [ "$i" -lt 100 ] &&
	{ process_running "$helper_pid" || process_running "$monitor_pid" ||
		process_running "$settings_monitor_pid"; }; do
	sleep 0.05
	i=$((i + 1))
done
if process_running "$helper_pid" || process_running "$monitor_pid" ||
	process_running "$settings_monitor_pid"; then
	printf 'Parent-bound power watcher survived owner exit\n' >&2
	exit 1
fi
grep -Fq "member='NameOwnerChanged',arg0='org.freedesktop.UPower'" "$work/actions.log"
grep -Fq "member='NameOwnerChanged',arg0='org.freedesktop.UPower.PowerProfiles'" "$work/actions.log"
grep -Fq "member='NameOwnerChanged',arg0='org.freedesktop.login1'" "$work/actions.log"
grep -Fq 'gsettings monitor apps.light-locker' "$work/actions.log"

rm -f "$work/state/monitor.pid" "$work/state/settings-get.pid" \
	"$work/state/settings-get-parent.pid"
(
	HOME="$work/home" \
		XDG_CONFIG_HOME="$work/config" \
		DWM_POWER_TEST_STATE="$work/state" \
		DWM_POWER_TEST_LOG="$work/actions.log" \
		DWM_POWER_TEST_GSETTINGS_GET_HANG=1 \
		DWM_POWER_TEST_GSETTINGS_GET_IGNORE_TERM=1 \
		PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/dwm-quickshell-controlcenter" power-watch >/dev/null 2>&1 &
	printf '%s\n' "$!" >"$work/hung-helper.pid"
	wait
) &
hung_owner_pid=$!
printf '%s\n' "$hung_owner_pid" >"$work/hung-owner.pid"
i=0
while [ "$i" -lt 100 ] &&
	{ [ ! -r "$work/state/monitor.pid" ] || [ ! -r "$work/state/settings-get.pid" ] ||
		[ ! -r "$work/state/settings-get-parent.pid" ]; }; do
	sleep 0.05
	i=$((i + 1))
done
[ -r "$work/state/monitor.pid" ]
[ -r "$work/state/settings-get.pid" ]
[ -r "$work/state/settings-get-parent.pid" ]
cp "$work/state/monitor.pid" "$work/hung-monitor.pid"
cp "$work/state/settings-get.pid" "$work/hung-settings-get.pid"
cp "$work/state/settings-get-parent.pid" "$work/hung-probe-wrapper.pid"
hung_helper_pid=$(cat "$work/hung-helper.pid")
hung_monitor_pid=$(cat "$work/hung-monitor.pid")
hung_settings_get_pid=$(cat "$work/hung-settings-get.pid")
hung_probe_wrapper_pid=$(cat "$work/hung-probe-wrapper.pid")
kill -KILL "$hung_owner_pid"
wait "$hung_owner_pid" 2>/dev/null || :
i=0
while [ "$i" -lt 100 ] &&
	{ process_running "$hung_helper_pid" || process_running "$hung_monitor_pid" ||
		process_running "$hung_probe_wrapper_pid" || process_running "$hung_settings_get_pid"; }; do
	sleep 0.05
	i=$((i + 1))
done
if process_running "$hung_helper_pid" || process_running "$hung_monitor_pid" ||
	process_running "$hung_probe_wrapper_pid" || process_running "$hung_settings_get_pid"; then
	printf 'Power watcher startup probe survived owner exit\n' >&2
	exit 1
fi

source_packages=$(bash -c '. "$1"; dwm_packages fedora desktop' _ "$repo/scripts/dwm-packages.sh")
printf '%s\n' "$source_packages" | grep -Fqx upower
printf '%s\n' "$source_packages" | grep -Fqx power-profiles-daemon
printf '%s\n' "$source_packages" | grep -Fqx dbus-tools
for kickstart in "$repo/dwm-fedora.ks" "$repo/dwm-fedora-nvidia.ks"; do
	grep -Fqx upower "$kickstart"
	grep -Fqx power-profiles-daemon "$kickstart"
	grep -Fqx dbus-tools "$kickstart"
done

printf 'Quickshell power backend: PASS\n'
