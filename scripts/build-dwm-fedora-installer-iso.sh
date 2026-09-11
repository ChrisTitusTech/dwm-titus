#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/build-dwm-fedora-installer-iso.sh --input ISO --output ISO [--variant standard|nvidia] [--version X.Y.Z] [--system-image ROOTFS.tar.xz]

Embed this checkout and a dwm-titus Kickstart into a Fedora installer ISO.
The resulting ISO exposes the checkout at /run/install/repo/dwm-titus.
--system-image selects offline installation from a factory-built root filesystem
and its required .tar.xz.json manifest. The manifest must match --variant.
EOF
}

err() {
	printf 'build-dwm-fedora-installer-iso: %s\n' "$*" >&2
}

input_iso=
output_iso=
variant=standard
version=
system_image=

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
	--system-image)
		(($# >= 2)) || {
			err "--system-image requires a value"
			exit 1
		}
		system_image=$2
		shift 2
		;;
	--version)
		if (($# < 2)) || [[ -z ${2:-} ]]; then
			err "--version requires a value."
			exit 1
		fi
		version=$2
		shift 2
		;;
	--version=*)
		version=${1#*=}
		if [[ -z $version ]]; then
			err "--version requires a value."
			exit 1
		fi
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

if [[ -n $version && ! $version =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	err "--version must be X.Y.Z or vX.Y.Z."
	exit 1
fi

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

for command in xorriso rsync implantisomd5 checkisomd5; do
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
tmp_output=
trap 'rm -rf "$work_dir"; [[ -z $tmp_output ]] || rm -f "$tmp_output"' EXIT
payload_dir="$work_dir/dwm-titus"
system_image_args=()
if [[ -n $system_image ]]; then
	image_sha=$(
		python3 - "$system_image" "$variant" <<'PYTHON'
import hashlib
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
if not path.name.endswith('.tar.xz'):
    sys.exit('System image must be a .tar.xz file')
metadata = json.loads(Path(str(path) + '.json').read_text())
if (metadata.get('protocol'), metadata.get('variant'), metadata.get('fedora'), metadata.get('architecture')) != (1, sys.argv[2], '44', 'x86_64'):
    sys.exit('System-image manifest does not match Fedora 44, x86_64 and selected variant')
with path.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
if digest != metadata.get('sha256') or path.stat().st_size != metadata.get('size'):
    sys.exit('System-image checksum or size mismatch')
print(digest)
PYTHON
	)
	ks_file="$work_dir/image.ks"
	boot_arguments=
	if [[ -n $extra_linux_args ]]; then
		boot_arguments="--append=\"$extra_linux_args\""
	fi
	sed -e "s/@IMAGE_SHA256@/$image_sha/" \
		-e "s/@BOOT_ARGUMENTS@/$boot_arguments/" "$repo_dir/dwm-fedora-image.ks" >"$ks_file"
	ksvalidator "$ks_file"
	system_image_args=(-map "$system_image" /images/dwm-rootfs.tar.xz)
fi
output_dir="$(dirname "$output_iso")"
output_base="$(basename "$output_iso")"
tmp_output="$(mktemp "$output_dir/.$output_base.tmp.XXXXXX")"
rm -f "$tmp_output"

# These basename patterns apply at every depth, independently of Git ignores.
rsync -a --delete \
	--exclude='.env' \
	--exclude='.env.*' \
	--exclude='.envrc' \
	--exclude='.git/' \
	--exclude='.cache/' \
	--exclude='node_modules/' \
	--exclude='__pycache__/' \
	--exclude='/docs/dist/' \
	--exclude='/docs/.astro/' \
	--exclude='/.ci-pykickstart/' \
	--exclude='/.serena/' \
	--exclude='/vicinae/' \
	--exclude='release/' \
	--exclude='config.h' \
	--exclude='*.o' \
	--exclude='dwm' \
	--exclude='livemedia.log' \
	--exclude='program.log' \
	--exclude='*.iso' \
	"$repo_dir/" "$payload_dir/"

# Fedora x86_64 has separate UEFI and BIOS menus. Patch each in place so
# both firmware paths select the requested Kickstart and variant arguments.
grub_xorriso_args=()
for grub_path in /EFI/BOOT/grub.cfg /boot/grub2/grub.cfg; do
	grub_cfg="$work_dir/${grub_path//\//_}"
	patched_grub_cfg="$grub_cfg.patched"
	xorriso -osirrox on -indev "$input_iso" -extract "$grub_path" "$grub_cfg" >/dev/null 2>&1
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

	grub_xorriso_args+=(-map "$patched_grub_cfg" "$grub_path")
done

branding_dir="$repo_dir/branding/anaconda"
product_img="$work_dir/product.img"
extra_xorriso_args=()

if [[ -d $branding_dir ]]; then
	staged_branding_dir="$work_dir/anaconda-branding"
	cp -a "$branding_dir" "$staged_branding_dir"

	if ! command -v gensquashfs >/dev/null 2>&1; then
		err "missing required command: gensquashfs (install squashfs-tools-ng)"
		exit 1
	fi
	if [[ -n "$version" ]]; then
		clean_ver="${version#v}"
		python3 "$repo_dir/scripts/generate-sidebar-logo.py" --version "$clean_ver" --output "$staged_branding_dir/usr/share/anaconda/pixmaps/sidebar-logo.png"
		cp -f "$staged_branding_dir/usr/share/anaconda/pixmaps/sidebar-logo.png" "$staged_branding_dir/usr/share/anaconda/pixmaps/server/sidebar-logo.png"
	fi
	rm -f "$product_img"
	gensquashfs --all-root --pack-dir "$staged_branding_dir" "$product_img" >/dev/null
	extra_xorriso_args+=(-map "$product_img" /images/product.img)
fi

xorriso -indev "$input_iso" -outdev "$tmp_output" \
	-boot_image any replay \
	-map "$ks_file" /dwm-fedora.ks \
	"${grub_xorriso_args[@]}" \
	-map "$payload_dir" /dwm-titus \
	"${extra_xorriso_args[@]}" \
	"${system_image_args[@]}"

# Rewriting the ISO drops the upstream media checksum. The default Fedora
# boot entry uses rd.live.check, so verify a fresh checksum before publishing
# the output path. This is a media-integrity check, not source authentication.
implantisomd5 --force --supported-iso "$tmp_output"
checkisomd5 "$tmp_output"

mv -f "$tmp_output" "$output_iso"
printf 'Created %s (%s)\n' "$output_iso" "$variant"
