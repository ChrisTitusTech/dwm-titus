#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/xdpyinfo" <<'EOF'
#!/bin/sh
printf '  dimensions:    %s pixels (0x0 millimeters)\n' "${TEST_DIMENSIONS:?}"
EOF
chmod +x "$work/xdpyinfo"

extract_px() {
	key=$1
	sed -n "s/.*$key: \([0-9][0-9]*\)px.*/\1/p"
}

check_theme_for_display() {
	dimensions=$1
	max_width=$2
	max_height=$3

	theme=$(TEST_DIMENSIONS=$dimensions \
		PATH="$work:$PATH" \
		"$repo_dir/config/rofi/powermenu.sh" --print-theme)

	width=$(printf '%s\n' "$theme" | extract_px width)
	height=$(printf '%s\n' "$theme" | extract_px height)

	[ "$width" -le "$max_width" ]
	[ "$height" -le "$max_height" ]
	printf '%s\n' "$theme" | grep -q 'location: center'
	printf '%s\n' "$theme" | grep -q 'anchor: center'
	printf '%s\n' "$theme" | grep -q 'fixed-height: false'
	printf '%s\n' "$theme" | grep -q 'scrollbar: true'
	printf '%s\n' "$theme" | grep -q 'inputbar { enabled: false; }'
}

check_theme_for_display 1366x768 1318 720
check_theme_for_display 800x600 752 552

ROFI_RETV=0 "$repo_dir/config/rofi/powermenu.sh" --no-symbols |
	grep -aq 'no-custom'

printf '%s\n' "Power menu low-resolution layout: PASS"
