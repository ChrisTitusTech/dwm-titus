#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${CONTAINER_ENGINE:-}"

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

DEBIAN_IMAGE="${DWM_CONTAINER_DEBIAN_IMAGE:-debian:stable-slim}"
ARCH_IMAGE="${DWM_CONTAINER_ARCH_IMAGE:-archlinux:latest}"
RHEL_IMAGE="${DWM_CONTAINER_RHEL_IMAGE:-fedora:latest}"

run_container() {
	local family=$1
	local image=$2
	local volume="${REPO_DIR}:/src:ro"
	local run_args=(run --rm)

	if [[ $ENGINE == "podman" ]]; then
		run_args+=(--security-opt label=disable)
	fi

	printf '==> Container smoke: %s (%s)\n' "$family" "$image"
	# Expansion in these single-quoted scripts must happen inside the container.
	# shellcheck disable=SC2016
	"$ENGINE" "${run_args[@]}" \
		-e "DWM_SMOKE_FAMILY=$family" \
		-v "$volume" \
		"$image" \
		/bin/sh -eu -c '
case "$DWM_SMOKE_FAMILY" in
debian)
	apt-get update
	apt-get install -y --no-install-recommends bash ca-certificates
	;;
arch)
	pacman -Syu --noconfirm
	pacman -S --needed --noconfirm bash ca-certificates
	;;
rhel)
	dnf install -y bash ca-certificates
	;;
*)
	printf "Unsupported smoke family: %s\n" "$DWM_SMOKE_FAMILY" >&2
	exit 1
	;;
esac

rm -rf /work
mkdir -p /work
cp -a /src/. /work/
cd /work

bash -euo pipefail -c '"'"'
source scripts/dwm-utils.sh
source scripts/dwm-packages.sh
mapfile -t packages < <(dwm_packages "$DISTRO_FAMILY" required | awk "NF" | sort -u)

case "$DISTRO_FAMILY" in
debian)
	apt-get install -y --no-install-recommends "${packages[@]}"
	;;
arch)
	pacman -S --needed --noconfirm "${packages[@]}"
	;;
rhel)
	dnf install -y "${packages[@]}"
	;;
*)
	printf "Unsupported detected family: %s\n" "$DISTRO_FAMILY" >&2
	exit 1
	;;
esac

./install.sh --dry-run --non-interactive --profile core
make clean
make
make check-install
make check-install-manifest
'"'"'
'
}

run_container debian "$DEBIAN_IMAGE"
run_container arch "$ARCH_IMAGE"
run_container rhel "$RHEL_IMAGE"

printf '==> Container smoke validation completed.\n'
