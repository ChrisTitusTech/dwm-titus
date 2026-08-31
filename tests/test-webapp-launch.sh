#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home/.local/share/applications"

cat >"$work/bin/xdg-settings" <<'EOF'
#!/bin/sh
printf '%s\n' helium.desktop
EOF

cat >"$work/bin/dwm-quickshell-launcher" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${DWM_TEST_NATIVE_LOG:?}"
EOF

cat >"$work/bin/test-browser" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${DWM_TEST_BROWSER_LOG:?}"
EOF

chmod +x \
	"$work/bin/xdg-settings" \
	"$work/bin/dwm-quickshell-launcher" \
	"$work/bin/test-browser"

cat >"$work/home/.local/share/applications/helium.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Test Browser
Exec=$work/bin/test-browser %U
EOF

run_webapp() {
	HOME="$work/home" \
		PATH="$work/bin:/usr/bin:/bin" \
		DWM_TEST_NATIVE_LOG="$work/native.log" \
		DWM_TEST_BROWSER_LOG="$work/browser.log" \
		"$repo_dir/scripts/webapp-launch" "$@"
}

run_webapp https://chatgpt.com
grep -Fqx 'launch-chatgpt' "$work/native.log"
test ! -e "$work/browser.log"

run_webapp https://chatgpt.com/
test "$(grep -Fxc 'launch-chatgpt' "$work/native.log")" -eq 2
test ! -e "$work/browser.log"

DWM_CHATGPT_WEB_FALLBACK=1 run_webapp https://chatgpt.com --new-window
grep -Fqx -- '--app=https://chatgpt.com --new-window' "$work/browser.log"
test "$(grep -Fxc 'launch-chatgpt' "$work/native.log")" -eq 2

# A partial installation without the native-first helper still opens the web app.
mv "$work/bin/dwm-quickshell-launcher" "$work/dwm-quickshell-launcher.disabled"
run_webapp https://chatgpt.com/
grep -Fqx -- '--app=https://chatgpt.com/' "$work/browser.log"
mv "$work/dwm-quickshell-launcher.disabled" "$work/bin/dwm-quickshell-launcher"

run_webapp https://example.com --incognito
grep -Fqx -- '--app=https://example.com --incognito' "$work/browser.log"

if run_webapp 2>"$work/missing.err"; then
	printf 'webapp-launch accepted a missing URL.\n' >&2
	exit 1
fi
grep -Fq 'usage: webapp-launch URL' "$work/missing.err"

grep -Fq 'DWM_CHATGPT_WEB_FALLBACK=1 webapp-launch https://chatgpt.com' \
	"$repo_dir/scripts/dwm-quickshell-launcher"

printf 'Legacy ChatGPT web-app compatibility: PASS\n'
