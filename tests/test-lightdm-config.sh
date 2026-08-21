#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fedora_stage="$work/fedora"

make -C "$repo/lightdm" --no-print-directory \
	DESTDIR="$fedora_stage" \
	LIGHTDM_SEAT_SECTION='Seat:*' \
	LIGHTDM_GREETER_SESSION=slick-greeter \
	LIGHTDM_SESSION_WRAPPER= \
	LIGHTDM_LOGIND_CHECK=true \
	install >/dev/null
cat >"$work/fedora.expected" <<'CONF'
[LightDM]
logind-check-graphical=true

[Seat:*]
greeter-session=slick-greeter
user-session=dwm
CONF
cmp -s "$work/fedora.expected" "$fedora_stage/etc/lightdm/lightdm.conf"

grep -Fqx 'xft-dpi=96' "$fedora_stage/etc/lightdm/slick-greeter.conf"
grep -Fqx 'activate-numlock=false' "$fedora_stage/etc/lightdm/slick-greeter.conf"
grep -Fqx 'show-hostname=false' "$fedora_stage/etc/lightdm/slick-greeter.conf"
grep -Fqx 'background=/usr/share/pixmaps/dwm-titus.png' "$fedora_stage/etc/lightdm/slick-greeter.conf"
cmp -s "$repo/lightdm/wallpaper.png" "$fedora_stage/usr/share/pixmaps/dwm-titus.png"

printf 'LightDM config rendering: PASS\n'
