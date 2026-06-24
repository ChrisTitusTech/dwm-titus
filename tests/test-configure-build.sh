#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

output="$work/config.h"

DWM_REFRESH_RATE=144 \
	DWM_FONT_SIZE=15 \
	DWM_MODKEY=alt \
	DWM_MFACT=0.60 \
	DWM_NMASTER=2 \
	DWM_CURSORWARP=0 \
	DWM_SWALLOWFLOATING=1 \
	DWM_RESIZEHINTS=0 \
	"$repo_dir/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo_dir/config.def.h" \
	--output "$output" >/dev/null

grep -Eq 'refresh_rate[[:space:]]*=[[:space:]]*144;' "$output"
grep -Eq 'cursorwarp[[:space:]]*=[[:space:]]*0;' "$output"
grep -Eq 'swallowfloating[[:space:]]*=[[:space:]]*1;' "$output"
grep -Eq 'mfact[[:space:]]*=[[:space:]]*0.60;' "$output"
grep -Eq 'nmaster[[:space:]]*=[[:space:]]*2;' "$output"
grep -Eq 'resizehints[[:space:]]*=[[:space:]]*0;' "$output"
grep -Eq '^#define MODKEY[[:space:]]+Mod1Mask$' "$output"
grep -Fq 'MesloLGS Nerd Font Mono:size=15' "$output"

before=$(sha256sum "$output" | awk '{print $1}')
DWM_REFRESH_RATE=60 \
	"$repo_dir/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo_dir/config.def.h" \
	--output "$output" >/dev/null
after=$(sha256sum "$output" | awk '{print $1}')
test "$before" = "$after"

invalid="$work/invalid.h"
if DWM_REFRESH_RATE=invalid \
	"$repo_dir/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo_dir/config.def.h" \
	--output "$invalid" >/dev/null 2>&1; then
	printf '%s\n' "Invalid refresh rate unexpectedly succeeded." >&2
	exit 1
fi
test ! -e "$invalid"

printf '%s\n' "Build configuration generation and preservation: PASS"
