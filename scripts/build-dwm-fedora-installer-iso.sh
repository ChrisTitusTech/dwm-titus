#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/build-dwm-fedora-installer-iso.sh --input ISO --output ISO [--variant standard|nvidia]

Embed this checkout and a dwm-titus Kickstart into a Fedora installer ISO.
The resulting ISO exposes the checkout at /run/install/repo/dwm-titus.
EOF
}

err() {
	printf 'build-dwm-fedora-installer-iso: %s\n' "$*" >&2
}

input_iso=
output_iso=
variant=standard

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
	--variant)
		if (($# < 2)); then
			err "--variant requires a value."
			exit 1
		fi
		variant=$2
		shift 2
		;;
	--variant=*)
		variant=${1#*=}
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

case "$variant" in
standard | nvidia) ;;
*)
	err "unknown variant: $variant"
	usage >&2
	exit 1
	;;
esac

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
case "$variant" in
standard)
	ks_file="$repo_dir/dwm-fedora.ks"
	extra_linux_args=
	;;
nvidia)
	ks_file="$repo_dir/dwm-fedora-nvidia.ks"
	extra_linux_args="rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1"
	;;
esac

if [[ ! -f $ks_file ]]; then
	err "missing Kickstart file: $ks_file"
	exit 1
fi

work_dir="$(mktemp -d)"
payload_dir="$work_dir/dwm-titus"
grub_cfg="$work_dir/grub.cfg"
patched_grub_cfg="$work_dir/grub.cfg.patched"
output_dir="$(dirname "$output_iso")"
output_base="$(basename "$output_iso")"
tmp_output="$(mktemp "$output_dir/.$output_base.tmp.XXXXXX")"
rm -f "$tmp_output"
trap 'rm -rf "$work_dir"; rm -f "$tmp_output"' EXIT

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

xorriso -osirrox on -indev "$input_iso" -extract /EFI/BOOT/grub.cfg "$grub_cfg" >/dev/null 2>&1
awk -v extra_linux_args="$extra_linux_args" '
	function append_arg(arg) {
		if (arg != "" && index($0, arg) == 0) {
			$0 = $0 " " arg
		}
	}

	/^[[:space:]]*linux[[:space:]]/ {
		if (match($0, /inst\.stage2=[^[:space:]]+/)) {
			stage2 = substr($0, RSTART + length("inst.stage2="), RLENGTH - length("inst.stage2="))
			append_arg("inst.ks=" stage2 ":/dwm-fedora.ks")
		}
		if (extra_linux_args != "") {
			count = split(extra_linux_args, args, /[[:space:]]+/)
			for (i = 1; i <= count; i++) {
				append_arg(args[i])
			}
		}
	}
	{ print }
' "$grub_cfg" >"$patched_grub_cfg"

xorriso -indev "$input_iso" -outdev "$tmp_output" \
	-boot_image any replay \
	-map "$ks_file" /dwm-fedora.ks \
	-map "$patched_grub_cfg" /EFI/BOOT/grub.cfg \
	-map "$payload_dir" /dwm-titus

mv -f "$tmp_output" "$output_iso"
printf 'Created %s (%s)\n' "$output_iso" "$variant"
