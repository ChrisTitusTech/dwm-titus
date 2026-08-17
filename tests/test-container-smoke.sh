#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${CONTAINER_ENGINE:-}"
IMAGE="${DWM_CONTAINER_FEDORA_IMAGE:-fedora:44}"

if [[ -z $ENGINE ]]; then
	if command -v podman >/dev/null 2>&1; then
		ENGINE=podman
	elif command -v docker >/dev/null 2>&1; then
		ENGINE=docker
	else
		printf 'No container engine found. Install podman or docker.\n' >&2
		exit 1
	fi
fi

case "$ENGINE" in
podman | docker) ;;
*)
	printf 'Unsupported CONTAINER_ENGINE: %s\n' "$ENGINE" >&2
	exit 1
	;;
esac

run_args=(run --rm --security-opt label=disable)
source_mount="${REPO_DIR}:/src:ro"

printf '==> Fedora container smoke: %s\n' "$IMAGE"
# Expansion in this single-quoted script must happen inside the container.
# shellcheck disable=SC2016
"$ENGINE" "${run_args[@]}" \
	-v "$source_mount" \
	"$IMAGE" \
	/bin/sh -eu -c '
dnf install -y bash ca-certificates
install -d -m 0700 /var/tmp/dwm-titus-smoke
install -d -m 0700 /var/tmp/dwm-titus-smoke/repo
tar -C /src \
	--exclude=.git \
	--exclude=release \
	--exclude='*.iso' \
	-cf - . | tar -C /var/tmp/dwm-titus-smoke/repo -xf -
cd /var/tmp/dwm-titus-smoke/repo

bash -euo pipefail -c '"'"'
source scripts/dwm-utils.sh
source scripts/dwm-packages.sh
[[ $DISTRO_ID == fedora ]]
[[ $DISTRO_FAMILY == fedora ]]
mapfile -t packages < <(dwm_packages fedora required | awk "NF" | sort -u)
mapfile -t desktop_packages < <(dwm_packages fedora desktop | awk "NF" | sort -u)
dnf install -y "${packages[@]}" "${desktop_packages[@]}"
scripts/dwm-quickshell-version-check

./install.sh --dry-run --non-interactive --profile core
make clean
make
make check-install
make check-install-manifest
DWM_SECURITY_CONTAINER=1 tests/test-settings-display-security.sh
'"'"'
'

printf '==> Fedora container smoke validation completed.\n'
