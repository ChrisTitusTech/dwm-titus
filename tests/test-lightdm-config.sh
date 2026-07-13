#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

arch_stage="$work/arch"
rhel_stage="$work/rhel"

make -C "$repo/lightdm" --no-print-directory DESTDIR="$arch_stage" install >/dev/null
cat >"$work/arch.expected" <<'CONF'
[SeatDefaults]
greeter-session=lightdm-slick-greeter
user-session=dwm
session-wrapper=/etc/lightdm/Xsession
CONF
cmp -s "$work/arch.expected" "$arch_stage/etc/lightdm/lightdm.conf"

make -C "$repo/lightdm" --no-print-directory \
	DESTDIR="$rhel_stage" \
	LIGHTDM_SEAT_SECTION='Seat:*' \
	LIGHTDM_GREETER_SESSION=slick-greeter \
	LIGHTDM_SESSION_WRAPPER= \
	LIGHTDM_LOGIND_CHECK=true \
	install >/dev/null
cat >"$work/rhel.expected" <<'CONF'
[LightDM]
logind-check-graphical=true

[Seat:*]
greeter-session=slick-greeter
user-session=dwm
CONF
cmp -s "$work/rhel.expected" "$rhel_stage/etc/lightdm/lightdm.conf"

grep -Fqx 'xft-dpi=96.0' "$rhel_stage/etc/lightdm/slick-greeter.conf"
grep -Fqx 'activate-numlock=false' "$rhel_stage/etc/lightdm/slick-greeter.conf"

printf 'LightDM config rendering: PASS\n'
