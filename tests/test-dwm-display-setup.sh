#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-display-setup"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home" "$work/etc/X11/xorg.conf.d"

cat >"$work/query" <<'EOF'
Screen 0: minimum 320 x 200, current 4480 x 1440, maximum 16384 x 16384
HDMI-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 527mm x 296mm
   1920x1080     60.00*+ 120.00
   1280x720      60.00
DP-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
   1920x1080     60.00
DP-2 connected (normal left inverted right x axis y axis)
EOF

cat >"$work/verbose" <<'EOF'
HDMI-1 connected primary 1920x1080+0+0 (0x46) normal (normal left inverted right x axis y axis) 527mm x 296mm
  1920x1080 (0x47) 148.500MHz +HSync +VSync *current +preferred
        h: width  1920 start 2008 end 2052 total 2200 skew    0 clock  67.50KHz
        v: height 1080 start 1084 end 1089 total 1125           clock  60.00Hz
  1920x1080 (0x48) 297.000MHz +HSync +VSync
        h: width  1920 start 2008 end 2052 total 2200 skew    0 clock 135.00KHz
        v: height 1080 start 1084 end 1089 total 1125           clock 120.00Hz
  1280x720 (0x49) 74.250MHz +HSync +VSync
        h: width  1280 start 1390 end 1430 total 1650 skew    0 clock  45.00KHz
        v: height 720 start 725 end 730 total 750           clock  60.00Hz
DP-1 connected 2560x1440+1920+0 (0x50) normal (normal left inverted right x axis y axis) 600mm x 340mm
  2560x1440 (0x51) 241.500MHz +HSync -VSync *current +preferred
        h: width  2560 start 2608 end 2640 total 2720 skew    0 clock  88.79KHz
        v: height 1440 start 1443 end 1448 total 1481           clock  59.95Hz
  1920x1080 (0x52) 148.500MHz +HSync +VSync
        h: width  1920 start 2008 end 2052 total 2200 skew    0 clock  67.50KHz
        v: height 1080 start 1084 end 1089 total 1125           clock  60.00Hz
DP-2 connected (normal left inverted right x axis y axis)
EOF

cat >"$work/properties-supported" <<'EOF'
HDMI-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis)
	TearFree: auto
		supported: off, on, auto
DP-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis)
	TearFree: auto
		supported: off, on, auto
DP-2 connected (normal left inverted right x axis y axis)
EOF

cat >"$work/properties-unsupported" <<'EOF'
HDMI-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis)
DP-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis)
DP-2 connected (normal left inverted right x axis y axis)
EOF

cat >"$work/bin/xrandr" <<'EOF'
#!/bin/sh
case ${1:-} in
--query | --current)
	cat "$TEST_QUERY"
	;;
--verbose)
	cat "$TEST_VERBOSE"
	;;
--prop)
	cat "$TEST_PROPERTIES"
	;;
*)
	printf '%s\n' "$*" >>"$TEST_XRANDR_LOG"
	if [ "${1:-}" = "--dryrun" ]; then
		printf '%s\n' 'dry run accepted'
	fi
	;;
esac
EOF
chmod +x "$work/bin/xrandr"

cat >"$work/profile-60.conf" <<'EOF'
HDMI-1 --primary --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal
DP-1 --mode 2560x1440 --rate 60 --pos 1920x0 --rotate left
DP-2 --off
EOF

cat >"$work/profile-120.conf" <<'EOF'
HDMI-1 --primary --mode 1920x1080 --rate 120 --pos 0x0 --rotate normal
DP-1 --off
DP-2 --off
EOF

env_common=(
	DISPLAY=:77
	DWM_DISPLAY_NO_SUDO=1
	DWM_KERNEL_DRIVER=amdgpu
	DWM_XORG_DRIVER=amdgpu
	DWM_XORG_MAIN_CONFIG="$work/etc/X11/xorg.conf"
	HOME="$work/home"
	PATH="$work/bin:/usr/bin:/bin"
	TEST_PROPERTIES="$work/properties-supported"
	TEST_QUERY="$work/query"
	TEST_VERBOSE="$work/verbose"
	TEST_XRANDR_LOG="$work/xrandr.log"
)

env "${env_common[@]}" "$BASH_BIN" "$HELPER" detect >"$work/detect"
grep -Fq 'HDMI-1  default=1920x1080@60.00' "$work/detect"
grep -Fq 'TearFree=supported' "$work/detect"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" generate \
	"$work/profile-60.conf" >"$work/generated-60.conf"
grep -Fq 'Option "Monitor-HDMI-1" "dwm-titus-HDMI-1"' "$work/generated-60.conf"
grep -Fq 'MatchDriver "amdgpu"' "$work/generated-60.conf"
grep -Fq 'Driver "amdgpu"' "$work/generated-60.conf"
grep -Fq 'Option "TearFree" "true"' "$work/generated-60.conf"
grep -Fq 'Modeline "1920x1080_60" 148.500 1920 2008 2052 2200 1080 1084 1089 1125 +HSync +VSync' "$work/generated-60.conf"
grep -Fq 'Option "Position" "1920 0"' "$work/generated-60.conf"
grep -Fq 'Option "Rotate" "left"' "$work/generated-60.conf"
grep -Fq 'Option "Enable" "false"' "$work/generated-60.conf"

env "${env_common[@]}" TEST_PROPERTIES="$work/properties-unsupported" \
	"$BASH_BIN" "$HELPER" generate "$work/profile-60.conf" >"$work/generated-ddx-tearfree.conf"
grep -Fq 'Option "TearFree" "true"' "$work/generated-ddx-tearfree.conf"

env "${env_common[@]}" TEST_PROPERTIES="$work/properties-unsupported" \
	DWM_KERNEL_DRIVER=xe DWM_XORG_DRIVER=modesetting \
	"$BASH_BIN" "$HELPER" generate "$work/profile-60.conf" >"$work/generated-no-tearfree.conf"
grep -Fq 'Driver "modesetting"' "$work/generated-no-tearfree.conf"
if grep -Fq 'Option "TearFree" "true"' "$work/generated-no-tearfree.conf"; then
	printf '%s\n' 'TearFree was enabled for an unsupported driver' >&2
	exit 1
fi
if env "${env_common[@]}" TEST_PROPERTIES="$work/properties-unsupported" \
	DWM_KERNEL_DRIVER=xe DWM_XORG_DRIVER=modesetting \
	"$BASH_BIN" "$HELPER" generate "$work/profile-60.conf" --tearfree on \
	2>"$work/tearfree-error"; then
	printf '%s\n' 'forced unsupported TearFree was accepted' >&2
	exit 1
fi
grep -Fq 'no compatible interface' "$work/tearfree-error"

rm -f "$work/xrandr.log"
env "${env_common[@]}" "$BASH_BIN" "$HELPER" preview \
	"$work/profile-60.conf" --yes >/dev/null
grep -Fq -- '--dryrun --output HDMI-1 --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal --primary --set TearFree on' "$work/xrandr.log"
grep -Fq -- '--output HDMI-1 --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal --primary --set TearFree on' "$work/xrandr.log"

managed="$work/etc/X11/xorg.conf.d/90-dwm-titus-display.conf"
env "${env_common[@]}" DWM_DISPLAY_TIMESTAMP=20260101-000001 \
	"$BASH_BIN" "$HELPER" install "$work/profile-60.conf" \
	--config "$managed" --no-preview --yes >/dev/null
test -f "$managed"
test -f "$managed.backup.20260101-000001.absent"
grep -Fq 'PreferredMode" "1920x1080_60"' "$managed"

env "${env_common[@]}" DWM_DISPLAY_TIMESTAMP=20260101-000002 \
	"$BASH_BIN" "$HELPER" install "$work/profile-120.conf" \
	--config "$managed" --no-preview --yes >/dev/null
test -f "$managed.backup.20260101-000002"
grep -Fq 'PreferredMode" "1920x1080_120"' "$managed"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" rollback \
	--config "$managed" --yes >/dev/null
grep -Fq 'PreferredMode" "1920x1080_60"' "$managed"

if env "${env_common[@]}" "$BASH_BIN" "$HELPER" generate \
	<(printf '%s\n' 'HDMI-9 --auto') 2>"$work/output-error"; then
	printf '%s\n' 'disconnected output was accepted' >&2
	exit 1
fi
grep -Fq 'output is not connected' "$work/output-error"

printf '%s\n' 'Display detection, Xorg generation, TearFree, preview, install, and rollback: PASS'
