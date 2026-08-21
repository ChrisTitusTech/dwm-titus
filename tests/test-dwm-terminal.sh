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

cat >"$work/bin/herdr" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
chmod +x "$work/bin/herdr"

DWM_TERMINAL_TEST_OUT="$work/default-out" \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER"

grep -Fqx "$work/bin/alacritty" "$work/default-out"
if grep -Fqx -- "-e" "$work/default-out"; then
	echo "dwm-terminal launched Herdr without an explicit opt-in" >&2
	exit 1
fi

DWM_TERMINAL_TEST_OUT="$work/herdr-out" \
	DWM_HERDR=1 \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER"

grep -Fqx "$work/bin/alacritty" "$work/herdr-out"
grep -Fqx -- "-e" "$work/herdr-out"
grep -Fqx "$work/bin/herdr" "$work/herdr-out"

DWM_TERMINAL_TEST_OUT="$work/direct-out" \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER" -e sh -c "printf direct"

grep -Fqx "$work/bin/alacritty" "$work/direct-out"
grep -Fqx -- "-e" "$work/direct-out"
grep -Fqx "sh" "$work/direct-out"
if grep -Fqx "$work/bin/herdr" "$work/direct-out"; then
	echo "dwm-terminal wrapped an explicit command in Herdr" >&2
	exit 1
fi

DWM_TERMINAL_TEST_OUT="$work/disabled-out" \
	DWM_HERDR=0 \
	PATH="$work/bin" \
	"$BASH_BIN" "$HELPER"

if grep -Fqx -- "-e" "$work/disabled-out"; then
	echo "dwm-terminal launched Herdr while DWM_HERDR=0" >&2
	exit 1
fi

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

rm -f "$work/bin/alacritty" "$work/bin/custom-term" "$work/bin/herdr"

if PATH="$work/bin" "$BASH_BIN" "$HELPER" 2>"$work/err"; then
	echo "dwm-terminal succeeded without a terminal" >&2
	exit 1
fi

grep -Fq "no supported terminal emulator found" "$work/err"

grep -Eq '^[[:space:]]*terminal[[:space:]]*=[[:space:]]*"alacritty"' \
	"$ROOT_DIR/config/hotkeys.toml"
grep -Fq 'key="x",       desc="Terminal"' "$ROOT_DIR/config/hotkeys.toml"
