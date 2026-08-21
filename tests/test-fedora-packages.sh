#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

for command_name in dnf sort comm awk; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Missing required Fedora package-check command: %s\n' \
			"$command_name" >&2
		exit 1
	fi
done

# shellcheck source=scripts/dwm-utils.sh
source "$repo/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

if [[ $DISTRO_ID != fedora || $DISTRO_FAMILY != fedora ]]; then
	printf 'Fedora package validation requires Fedora; detected %s.\n' \
		"$DISTRO_NAME" >&2
	exit 1
fi

mapfile -t packages < <(
	{
		dwm_packages fedora required
		dwm_packages fedora desktop
	} | awk 'NF' | sort -u
)
if ((${#packages[@]} == 0)); then
	printf 'Fedora package map returned no required or desktop packages.\n' >&2
	exit 1
fi

printf '%s\n' "${packages[@]}" >"$work/expected"
dnf -q repoquery --available --latest-limit 1 \
	--queryformat $'%{name}\n' "${packages[@]}" |
	sort -u >"$work/available"
comm -23 "$work/expected" "$work/available" >"$work/missing"
if [[ -s $work/missing ]]; then
	printf 'Unavailable Fedora package-map entries:\n' >&2
	sed 's/^/  /' "$work/missing" >&2
	exit 1
fi

"$repo/install.sh" --dry-run --non-interactive --profile core >/dev/null

printf 'Fedora required and desktop package map: PASS (%s packages)\n' \
	"${#packages[@]}"
