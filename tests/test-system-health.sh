#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER=$ROOT_DIR/scripts/dwm-system-health
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home/.config/dwm-titus" "$work/home/.config/quickshell"
printf 'ID=debian\nID_LIKE=debian\nPRETTY_NAME="Test Linux"\n' >"$work/os-release"
: >"$work/home/.config/dwm-titus/hotkeys.toml"
: >"$work/home/.config/dwm-titus/themes.toml"
: >"$work/home/.config/dwm-titus/window-rules.toml"
: >"$work/home/.config/quickshell/shell.qml"

cat >"$work/bin/dpkg" <<'SCRIPT'
#!/bin/sh
printf 'package is unpacked but not configured\n'
SCRIPT

cat >"$work/bin/xclip" <<'SCRIPT'
#!/bin/sh
cat >"${DWM_HEALTH_XCLIP_OUTPUT:?}"
SCRIPT

cat >"$work/bin/systemctl" <<'SCRIPT'
#!/bin/sh
case " $* " in
*" --user --failed "*) printf 'user-broken.service loaded failed failed Broken user service\n' ;;
*" --user restart -- user-broken.service "*) printf '%s\n' "$*" >>"$DWM_HEALTH_SYSTEMCTL_LOG" ;;
*) exit 1 ;;
esac
SCRIPT
chmod +x "$work/bin/dpkg" "$work/bin/systemctl" "$work/bin/xclip"

DWM_HEALTH_XCLIP_OUTPUT="$work/clipboard.txt" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" share-evidence copy journal-errors "Boot journal errors" "2 current-boot entries" \
	"first boot error | second boot error" >"$work/copy.out"
grep -Fq 'Copied Boot journal errors to the clipboard' "$work/copy.out"
grep -Fq 'Boot journal errors' "$work/clipboard.txt"
grep -Fq 'first boot error' "$work/clipboard.txt"
grep -Fq 'second boot error' "$work/clipboard.txt"

mkdir -p "$work/exports"
DWM_HEALTH_EXPORT_DIR="$work/exports" \
	"$HELPER" share-evidence export journal-errors "Boot journal errors" "2 current-boot entries" \
	"first boot error | second boot error" >"$work/export-boot.out"
DWM_HEALTH_EXPORT_DIR="$work/exports" \
	"$HELPER" share-evidence export kernel-errors "Kernel errors" "1 current-boot entry" \
	"kernel test error" >"$work/export-kernel.out"
boot_exports=("$work/exports"/boot*.txt)
kernel_exports=("$work/exports"/kernel-errors*.txt)
[[ -f ${boot_exports[0]} && -f ${kernel_exports[0]} ]]
grep -Fq 'second boot error' "${boot_exports[0]}"
grep -Fq 'kernel test error' "${kernel_exports[0]}"
[[ $(stat -c %a -- "${boot_exports[0]}") == 600 ]]

if "$HELPER" share-evidence export critical-kernel-events "Critical" "1 entry" "test" 2>"$work/share-invalid.err"; then
	printf 'unsupported evidence export unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'unsupported evidence record' "$work/share-invalid.err"

HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	DWM_HEALTH_OS_RELEASE="$work/os-release" \
	DWM_HEALTH_COMMAND_TIMEOUT=2 \
	DWM_HEALTH_SYSTEMCTL_LOG="$work/systemctl.log" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" scan-user >"$work/user.tsv"

awk -F '\t' 'NF != 10 { print "invalid field count at line " NR > "/dev/stderr"; exit 1 }' "$work/user.tsv"
grep -Fq $'meta\toverview\tinfo\tscan-user' "$work/user.tsv"
grep -Fq $'check\tresources\t' "$work/user.tsv"
grep -Fq $'check\tstorage\t' "$work/user.tsv"
grep -Fq $'check\tnetwork\t' "$work/user.tsv"
grep -Fq $'check\tdependencies\twarn\tpackage-database' "$work/user.tsv"
grep -Fq $'check\tservices\twarn\tuser-failed-user-broken-service\tuser-broken.service (user)' "$work/user.tsv"
grep -Fq $'manage-user-service|user-broken.service\tService actions\tuser' "$work/user.tsv"
grep -Fq $'meta\toverview\tok\tscan-user-complete' "$work/user.tsv"

HOME="$work/home" \
	DWM_HEALTH_COMMAND_TIMEOUT=2 \
	DWM_HEALTH_SYSTEMCTL_LOG="$work/systemctl.log" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" repair-user 'manage-user-service|restart|user-broken.service' >"$work/user-service-repair.tsv"
grep -Fq -- '--user restart -- user-broken.service' "$work/systemctl.log"

if HOME="$work/home" DWM_HEALTH_COMMAND_TIMEOUT=2 PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" repair-user 'manage-user-service|restart|not-failed.service' 2>"$work/not-failed.err"; then
	printf 'non-failed user service repair unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'service is no longer failed' "$work/not-failed.err"

cat >"$work/bin/journalctl" <<'SCRIPT'
#!/bin/sh
case " $* " in
*" -k "*)
	printf 'I/O error on test device\n'
	;;
*)
	printf 'application failed to start\n'
	printf 'out of memory: killed process 42\n'
	;;
esac
SCRIPT

cat >"$work/bin/systemctl" <<'SCRIPT'
#!/bin/sh
case " $* " in
*" --failed "*) printf 'example.service loaded failed failed Example\n' ;;
*" cat NetworkManager.service "* | *" cat bluetooth.service "*) exit 0 ;;
*" is-active "*) printf 'inactive\n'; exit 3 ;;
*) exit 1 ;;
esac
SCRIPT

cat >"$work/bin/timedatectl" <<'SCRIPT'
#!/bin/sh
case "$*" in
*NTPSynchronized*) printf 'no\n' ;;
*) printf 'yes\n' ;;
esac
SCRIPT

cat >"$work/bin/smartctl" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT

cat >"$work/bin/sudo" <<'SCRIPT'
#!/bin/sh
[ "$*" = "-n -v" ]
SCRIPT
chmod +x "$work/bin/journalctl" "$work/bin/systemctl" "$work/bin/timedatectl" "$work/bin/smartctl" "$work/bin/sudo"

DWM_HEALTH_TEST_ROOT=1 \
	DWM_HEALTH_COMMAND_TIMEOUT=2 \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" scan-system >"$work/system.tsv"

grep -Fq $'check\tboot\twarn\tjournal-errors' "$work/system.tsv"
grep -Fq $'check\tboot\terror\tcritical-kernel-events' "$work/system.tsv"
grep -Fq $'check\tservices\terror\tsystem-failed-example-service\texample.service (system)' "$work/system.tsv"
grep -Fq $'manage-system-service|example.service\tService actions\tsystem' "$work/system.tsv"
grep -Fq $'check\tservices\twarn\ttime-sync' "$work/system.tsv"
grep -Fq $'check\tservices\twarn\tnetworkmanager-service' "$work/system.tsv"

DWM_HEALTH_TEST_ROOT=1 \
	DWM_HEALTH_COMMAND_TIMEOUT=2 \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" scan-privileged >"$work/privileged.tsv"
grep -Fq $'meta\toverview\tok\tscan-system-complete' "$work/privileged.tsv"

cat >"$work/bin/sudo" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT
cat >"$work/bin/pkexec" <<'SCRIPT'
#!/bin/sh
exit 126
SCRIPT
chmod +x "$work/bin/sudo" "$work/bin/pkexec"

if DWM_HEALTH_TEST_ROOT=1 PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" scan-privileged >"$work/no-helper.tsv"; then
	printf 'privileged scan without a trusted helper unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq $'meta\toverview\trestricted\tscan-system\tPrivileged scan\tNo trusted installed helper' "$work/no-helper.tsv"

if "$HELPER" repair-user 'restart-audio;touch /tmp/not-allowed' 2>"$work/user-repair.err"; then
	printf 'unknown user repair unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'unsupported user repair' "$work/user-repair.err"

if "$HELPER" repair-system 'example.service' 2>"$work/system-repair.err"; then
	printf 'arbitrary system repair unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'unsupported system repair' "$work/system-repair.err"

printf 'System health helper: PASS\n'
