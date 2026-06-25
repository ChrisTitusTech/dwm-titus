#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

case "$ARCH" in
aarch64 | armv7h | armv7l) ;;
*)
	printf 'install-arm.sh is for ARM systems only (detected: %s).\n' "$ARCH" >&2
	printf 'For x86_64 and other architectures, use ./install.sh directly.\n' >&2
	exit 1
	;;
esac

printf '%s\n' "install-arm.sh is a compatibility wrapper; using ./install.sh."
exec "$REPO_DIR/install.sh" "$@"
