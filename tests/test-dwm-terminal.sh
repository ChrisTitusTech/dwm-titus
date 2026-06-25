#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-terminal"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"

cat >"$work/bin/alacritty" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$0" >"$DWM_TERMINAL_TEST_OUT"
printf '%s\n' "$@" >>"$DWM_TERMINAL_TEST_OUT"
SCRIPT
chmod +x "$work/bin/alacritty"

DWM_TERMINAL_TEST_OUT="$work/out" \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER" --class dwm-test

grep -Fqx "$work/bin/alacritty" "$work/out"
grep -Fqx -- "--class" "$work/out"
grep -Fqx "dwm-test" "$work/out"

cat >"$work/bin/custom-term" <<'SCRIPT'
#!/bin/sh
printf 'custom\n' >"$DWM_TERMINAL_TEST_OUT"
SCRIPT
chmod +x "$work/bin/custom-term"

DWM_TERMINAL_TEST_OUT="$work/custom-out" \
	DWM_TERMINAL=custom-term \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER"

grep -Fqx "custom" "$work/custom-out"

rm -f "$work/bin/alacritty" "$work/bin/custom-term"

if PATH="$work/bin" "$BASH_BIN" "$HELPER" 2>"$work/err"; then
	echo "dwm-terminal succeeded without a terminal" >&2
	exit 1
fi

grep -Fq "no supported terminal emulator found" "$work/err"
