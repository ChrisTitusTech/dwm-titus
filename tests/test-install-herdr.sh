#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/install-herdr"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home"

cat >"$work/remote-installer.sh" <<'SCRIPT'
#!/bin/sh
set -eu
install -d -m 0755 "$HERDR_INSTALL_DIR"
install -m 0755 "$HERDR_TEST_BINARY" "$HERDR_INSTALL_DIR/herdr"
SCRIPT

cat >"$work/herdr-binary" <<'SCRIPT'
#!/bin/sh
printf 'herdr 0.7.5\n'
SCRIPT
chmod +x "$work/herdr-binary"

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
	PATH="$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/install.out"

grep -Fq "Installed verified Herdr 0.7.5" "$work/install.out"
test -x "$work/home/.local/bin/herdr"
test "$("$work/home/.local/bin/herdr" --version)" = "herdr 0.7.5"

env \
	HOME="$work/home" \
	HERDR_ALLOW_ROOT=1 \
	HERDR_INSTALL_DIR="$work/home/.local/bin" \
	PATH="$work/home/.local/bin:$work/bin:/usr/bin:/bin" \
	"$HELPER" >"$work/reinstall.out"

grep -Fq "Herdr is already installed" "$work/reinstall.out"

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

printf 'install-herdr tests: PASS\n'
