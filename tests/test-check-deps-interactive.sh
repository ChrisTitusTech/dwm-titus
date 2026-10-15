#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CHECK_DEPS="$REPO_DIR/scripts/check-deps.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-deps.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/bin" "$work/home"

# Mock all required commands
for cmd in cc make pkg-config Xorg startx xrandr xset xsetroot xkbset dwm-status \
	quickshell picom feh xsettingsd bwrap xclip xdotool dex amixer jq \
	bluetoothctl blueman-applet alacritty xdg-open dwm-desktop-update; do
	cat >"$work/bin/$cmd" <<'SH'
#!/bin/sh
exit 0
SH
	chmod +x "$work/bin/$cmd"
done

# Mock pkg-config --exists
cat >"$work/bin/pkg-config" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$work/bin/pkg-config"

# Mock fc-list
cat >"$work/bin/fc-list" <<'SH'
#!/bin/sh
printf '%s\n' 'MesloLGS Nerd Font' 'Noto Color Emoji'
SH
chmod +x "$work/bin/fc-list"

# Mock dwm.desktop and .xinitrc
mkdir -p "$work/xsessions"
touch "$work/xsessions/dwm.desktop"
touch "$work/home/.xinitrc"

# Symlink essential system utilities into work bin
for tool in bash sh dirname pwd printf echo grep awk cat sed cut tr rm paste; do
	cmd_path=$(command -v "$tool" || true)
	[ -n "$cmd_path" ] && ln -sf "$cmd_path" "$work/bin/$tool"
done

# Mock rpm
cat >"$work/bin/rpm" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$work/bin/rpm"

# 1. Non-interactive mode when all dependencies satisfied
output=$(env HOME="$work/home" PATH="$work/bin" \
	bash "$CHECK_DEPS" </dev/null)
if ! grep -Fq "All dependencies satisfied" <<<"$output"; then
	echo "FAIL: expected non-interactive success message" >&2
	exit 1
fi
if grep -Fq "press any key to quit" <<<"$output"; then
	echo "FAIL: non-interactive mode should not prompt to press any key" >&2
	exit 1
fi

# 2. Interactive mode when all dependencies satisfied
output=$(printf '\n' | env HOME="$work/home" PATH="$work/bin" \
	bash "$CHECK_DEPS" --interactive)
if ! grep -Fq "Dependencies OK, press any key to quit." <<<"$output"; then
	echo "FAIL: expected interactive green OK prompt" >&2
	exit 1
fi

# 3. Interactive mode when dependency missing and user says 'n'
rm -f "$work/bin/startx"
set +e
output=$(printf 'n\n\n' | env HOME="$work/home" PATH="$work/bin" \
	bash "$CHECK_DEPS" --interactive)
exit_code=$?
set -e
if [ "$exit_code" -ne 1 ]; then
	echo "FAIL: expected exit code 1 when declining dependency installation, got $exit_code" >&2
	exit 1
fi
if ! grep -Fq "Missing dependencies found, install now? [y/n]" <<<"$output"; then
	echo "FAIL: expected missing dependencies prompt" >&2
	exit 1
fi
if ! grep -Fq "Nothing to do, press any key to quit." <<<"$output"; then
	echo "FAIL: expected abort message" >&2
	exit 1
fi

# 4. Interactive mode when dependency missing and user says 'y'
cat >"$work/bin/dwm-desktop-update" <<'SH'
#!/bin/sh
printf 'INSTALLER_CALLED:%s\n' "$*" >"$DWM_TEST_INSTALLER_LOG"
exit 0
SH
chmod +x "$work/bin/dwm-desktop-update"
export DWM_TEST_INSTALLER_LOG="$work/installer.log"

output=$(printf 'y\n' | env HOME="$work/home" PATH="$work/bin" \
	DWM_TEST_INSTALLER_LOG="$DWM_TEST_INSTALLER_LOG" \
	bash "$CHECK_DEPS" --interactive || true)
if [ ! -f "$DWM_TEST_INSTALLER_LOG" ]; then
	echo "FAIL: installer was not invoked when answering y" >&2
	exit 1
fi
if ! grep -Fq "INSTALLER_CALLED:install-dependencies" "$DWM_TEST_INSTALLER_LOG"; then
	echo "FAIL: installer called with wrong arguments" >&2
	exit 1
fi

# 5. Interactive mode when dependency missing and updater unavailable (no install.sh fallback)
rm -f "$work/bin/dwm-desktop-update"
isolated_dir="$work/isolated"
mkdir -p "$isolated_dir"
cp "$CHECK_DEPS" "$REPO_DIR/scripts/dwm-utils.sh" "$REPO_DIR/scripts/dwm-packages.sh" "$isolated_dir/"
output=$(printf 'y\n\n' | env HOME="$work/home" PATH="$work/bin" \
	bash "$isolated_dir/check-deps.sh" --interactive || true)
if ! grep -Fq "Automated dependency installer not found." <<<"$output"; then
	echo "FAIL: expected installer not found message" >&2
	exit 1
fi

# 6. Interactive mode when only Meslo Nerd Font is missing (non-package dependency)
cat >"$work/bin/startx" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$work/bin/startx"

cat >"$work/bin/dwm-desktop-update" <<'SH'
#!/bin/sh
printf 'INSTALLER_CALLED:%s\n' "$*" >"$DWM_TEST_INSTALLER_LOG"
exit 0
SH
chmod +x "$work/bin/dwm-desktop-update"
rm -f "$DWM_TEST_INSTALLER_LOG"

cat >"$work/bin/fc-list" <<'SH'
#!/bin/sh
printf '%s\n' 'Noto Color Emoji'
SH
chmod +x "$work/bin/fc-list"

output=$(printf '\n' | env HOME="$work/home" PATH="$work/bin" \
	DWM_TEST_INSTALLER_LOG="$DWM_TEST_INSTALLER_LOG" \
	bash "$CHECK_DEPS" --interactive || true)

if [ -f "$DWM_TEST_INSTALLER_LOG" ]; then
	echo "FAIL: package-only updater was invoked when only Meslo was missing" >&2
	exit 1
fi
if grep -Fq "Missing dependencies found, install now?" <<<"$output"; then
	echo "FAIL: should not offer package repair when only Meslo is missing" >&2
	exit 1
fi
if ! grep -Fq "Meslo" <<<"$output"; then
	echo "FAIL: expected Meslo font guidance" >&2
	exit 1
fi

# 7. Interactive mode when both package and Meslo font are missing (mixed failure)
rm -f "$work/bin/startx"
rm -f "$DWM_TEST_INSTALLER_LOG"

set +e
output=$(printf 'y\n\n' | env HOME="$work/home" PATH="$work/bin" \
	DWM_TEST_INSTALLER_LOG="$DWM_TEST_INSTALLER_LOG" \
	bash "$CHECK_DEPS" --interactive)
exit_code=$?
set -e

if [ "$exit_code" -ne 1 ]; then
	echo "FAIL: expected exit code 1 on mixed failure after package install, got $exit_code" >&2
	exit 1
fi
if [ ! -f "$DWM_TEST_INSTALLER_LOG" ]; then
	echo "FAIL: installer was not invoked on mixed failure" >&2
	exit 1
fi
if ! grep -Fq "Meslo" <<<"$output"; then
	echo "FAIL: expected Meslo guidance on mixed failure" >&2
	exit 1
fi

echo "test-check-deps-interactive: PASS"
