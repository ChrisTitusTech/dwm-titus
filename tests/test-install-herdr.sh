#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/install-herdr"
# shellcheck source=scripts/dwm-utils.sh
source "$ROOT_DIR/scripts/dwm-utils.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/agent-bin" "$work/home"
install -d -m 0700 "$work/home/.local/bin"

cat >"$work/remote-installer.sh" <<'SCRIPT'
#!/bin/sh
set -eu
install -d -m 0755 "$HERDR_INSTALL_DIR"
install -m 0755 "$HERDR_TEST_BINARY" "$HERDR_INSTALL_DIR/herdr"
SCRIPT

cat >"$work/herdr-binary" <<'SCRIPT'
#!/bin/sh
if [ "${1:-}" = "integration" ] && [ "${2:-}" = "install" ]; then
	if [ "${HERDR_TEST_FAIL_INTEGRATION:-}" = "${3:-}" ]; then
		exit 1
	fi
	printf '%s\n' "$3" >>"$HERDR_TEST_INTEGRATION_LOG"
	exit 0
fi
printf 'herdr 0.7.5\n'
SCRIPT
chmod +x "$work/herdr-binary"

for agent in codex claude; do
	cat >"$work/agent-bin/$agent" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
	chmod +x "$work/agent-bin/$agent"
done

cat >"$work/bin/curl" <<'SCRIPT'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
	case $1 in
	--output)
		output=$2
		shift 2
		;;
	*)
		shift
		;;
	esac
done
test -n "$output"
cp "$HERDR_TEST_INSTALLER" "$output"
SCRIPT
chmod +x "$work/bin/curl"

installer_sha256="$(sha256sum "$work/remote-installer.sh" | awk '{print $1}')"
asset_sha256="$(sha256sum "$work/herdr-binary" | awk '{print $1}')"

env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_INSTALLER_SHA256="$installer_sha256" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	HERDR_TEST_BINARY="$work/herdr-binary" \
	HERDR_TEST_INSTALLER="$work/remote-installer.sh" \
	HERDR_TEST_INTEGRATION_LOG="$work/integrations.log" \
	PATH="$work/agent-bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/install.out"

grep -Fq "Installed verified Herdr 0.7.5" "$work/install.out"
test -x "$work/home/.local/bin/herdr"
test "$("$work/home/.local/bin/herdr" --version)" = "herdr 0.7.5"
test "$(stat -c '%a' "$work/home/.local/bin")" = "700"
printf 'codex\nclaude\n' >"$work/expected-integrations"
cmp "$work/expected-integrations" "$work/integrations.log"

: >"$work/integrations.log"
env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	HERDR_TEST_INTEGRATION_LOG="$work/integrations.log" \
	PATH="$work/home/.local/bin:$work/agent-bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" --dry-run >"$work/dry-run.out"

grep -Fq "Herdr version: 0.7.5" "$work/dry-run.out"
if [ -s "$work/integrations.log" ]; then
	echo "install-herdr modified integrations during a dry run" >&2
	exit 1
fi

env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	HERDR_TEST_INTEGRATION_LOG="$work/integrations.log" \
	PATH="$work/home/.local/bin:$work/agent-bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/reinstall.out"

grep -Fq "Herdr is already installed and verified" "$work/reinstall.out"
cmp "$work/expected-integrations" "$work/integrations.log"

if env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	HERDR_TEST_FAIL_INTEGRATION=claude \
	HERDR_TEST_INTEGRATION_LOG="$work/integrations.log" \
	PATH="$work/home/.local/bin:$work/agent-bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/integration-failure.out" 2>"$work/integration-failure.err"; then
	echo "install-herdr ignored a detected agent integration failure" >&2
	exit 1
fi

grep -Fq "integration for Claude Code" "$work/integration-failure.err"
grep -Fq "one or more detected agent integrations failed" \
	"$work/integration-failure.err"

for legacy_terminal in alacritty kitty st warp-terminal xterm; do
	printf '[vars]\nterminal = "%s"\n' "$legacy_terminal" >"$work/hotkeys.toml"
	test "$(dwm_legacy_seeded_terminal_hotkey "$work/hotkeys.toml")" = \
		"$legacy_terminal"
done
printf '[vars]\nterminal = "dwm-terminal"\n' >"$work/hotkeys.toml"
if dwm_legacy_seeded_terminal_hotkey "$work/hotkeys.toml" >/dev/null; then
	echo "dwm-terminal was misidentified as a legacy seeded terminal" >&2
	exit 1
fi

mkdir -p "$work/early"
cat >"$work/early/herdr" <<'SCRIPT'
#!/bin/sh
printf 'herdr 0.6.0\n'
SCRIPT
chmod +x "$work/early/herdr"

if env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	PATH="$work/early:$work/home/.local/bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/unverified.out" 2>"$work/unverified.err"; then
	echo "install-herdr accepted an unverified executable from PATH" >&2
	exit 1
fi

grep -Fq "selected Herdr executable is not the verified 0.7.5 release" \
	"$work/unverified.err"

if env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_INSTALLER_SHA256="$installer_sha256" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	HERDR_TEST_BINARY="$work/herdr-binary" \
	HERDR_TEST_INSTALLER="$work/remote-installer.sh" \
	PATH="$work/early:$work/home/.local/bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" --force >"$work/shadowed.out" 2>"$work/shadowed.err"; then
	echo "install-herdr reported success while PATH selected another executable" >&2
	exit 1
fi

grep -Fq "terminal wrapper would select an unverified executable" \
	"$work/shadowed.err"
test "$(stat -c '%a' "$work/home/.local/bin")" = "700"

mkdir -p "$work/custom" "$work/custom-home"
install -m 0755 "$work/herdr-binary" "$work/custom/herdr"

if env \
	HOME="$work/custom-home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/custom" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/custom-unselected.out" 2>"$work/custom-unselected.err"; then
	echo "install-herdr accepted a custom install the wrapper could not select" >&2
	exit 1
fi

grep -Fq "terminal wrapper would select an unverified executable: none" \
	"$work/custom-unselected.err"

env \
	HOME="$work/custom-home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/custom" \
	HERDR_ASSET_SHA256="$asset_sha256" \
	DWM_HERDR_COMMAND="$work/custom/herdr" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/custom-selected.out"

grep -Fq "Herdr is already installed and verified: $work/custom/herdr" \
	"$work/custom-selected.out"

if env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	HERDR_INSTALLER_SHA256="$installer_sha256" \
	HERDR_ASSET_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
	HERDR_TEST_BINARY="$work/herdr-binary" \
	HERDR_TEST_INSTALLER="$work/remote-installer.sh" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" --force >"$work/tampered.out" 2>"$work/tampered.err"; then
	echo "install-herdr accepted a binary with the wrong checksum" >&2
	exit 1
fi

grep -Fq "binary checksum verification failed" "$work/tampered.err"
test "$("$work/home/.local/bin/herdr" --version)" = "herdr 0.7.5"
test "$(stat -c '%a' "$work/home/.local/bin")" = "700"

mkdir -p "$work/plan-bin"
cat >"$work/plan-bin/uname" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$DWM_TEST_UNAME"
SCRIPT
chmod +x "$work/plan-bin/uname"

env \
	HOME="$work/home" \
	DWM_TEST_UNAME=armv7l \
	PATH="$work/plan-bin:$PATH" \
	"$ROOT_DIR/install.sh" --dry-run --non-interactive --profile recommended \
	>"$work/arm-plan.out"

grep -Fq "Herdr workspace: skipped (unsupported architecture: armv7l)" \
	"$work/arm-plan.out"

env \
	HOME="$work/home" \
	DWM_TEST_UNAME=x86_64 \
	PATH="$work/plan-bin:$PATH" \
	"$ROOT_DIR/install.sh" --dry-run --non-interactive --profile recommended \
	>"$work/recommended-plan.out"
grep -Fq "Herdr workspace: verified user install" "$work/recommended-plan.out"

env \
	HOME="$work/home" \
	DWM_TEST_UNAME=x86_64 \
	PATH="$work/plan-bin:$PATH" \
	"$ROOT_DIR/install.sh" --dry-run --non-interactive --profile core \
	--install-herdr >"$work/forced-plan.out"
grep -Fq "Herdr workspace: verified user install" "$work/forced-plan.out"

env \
	HOME="$work/home" \
	DWM_TEST_UNAME=x86_64 \
	PATH="$work/plan-bin:$PATH" \
	"$ROOT_DIR/install.sh" --dry-run --non-interactive --profile recommended \
	--skip-herdr >"$work/skipped-plan.out"
grep -Fq "Herdr workspace: skipped" "$work/skipped-plan.out"

printf 'install-herdr tests: PASS\n'
