#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/build-dwm-fedora-installer-iso.sh --input ISO --output ISO

Embed this checkout and dwm-fedora.ks into a Fedora installer ISO.
The resulting ISO exposes the checkout at /run/install/repo/dwm-titus.
EOF
}

err() {
	printf 'build-dwm-fedora-installer-iso: %s\n' "$*" >&2
}

input_iso=
output_iso=

while (($# > 0)); do
	case "$1" in
	--input)
		if (($# < 2)); then
			err "--input requires a value."
			exit 1
		fi
		input_iso=$2
		shift 2
		;;
	--input=*)
		input_iso=${1#*=}
		shift
		;;
	--output)
		if (($# < 2)); then
			err "--output requires a value."
			exit 1
		fi
		output_iso=$2
		shift 2
		;;
	--output=*)
		output_iso=${1#*=}
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "unknown argument: $1"
		usage >&2
		exit 1
		;;
	esac
done

if [[ -z $input_iso || -z $output_iso ]]; then
	usage >&2
	exit 1
fi

if [[ ! -f $input_iso ]]; then
	err "input ISO not found: $input_iso"
	exit 1
fi

for command in xorriso rsync; do
	if ! command -v "$command" >/dev/null 2>&1; then
		err "missing required command: $command"
		exit 1
	fi
done

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ks_file="$repo_dir/dwm-fedora.ks"

if [[ ! -f $ks_file ]]; then
	err "missing Kickstart file: $ks_file"
	exit 1
fi

work_dir="$(mktemp -d)"
payload_dir="$work_dir/dwm-titus"
trap 'rm -rf "$work_dir"' EXIT

rsync -a --delete \
	--exclude='.git/' \
	--exclude='.cache/' \
	--exclude='release/' \
	--exclude='config.h' \
	--exclude='*.o' \
	--exclude='dwm' \
	--exclude='livemedia.log' \
	--exclude='program.log' \
	--exclude='*.iso' \
	"$repo_dir/" "$payload_dir/"

xorriso -indev "$input_iso" -outdev "$output_iso" \
	-boot_image any replay \
	-map "$ks_file" /dwm-fedora.ks \
	-map "$payload_dir" /dwm-titus

printf 'Created %s\n' "$output_iso"
