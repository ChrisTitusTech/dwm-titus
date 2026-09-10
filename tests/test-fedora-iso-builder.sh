#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"

cat >"$work/bin/rsync" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DWM_TEST_RSYNC_LOG"
dest=${@: -1}
mkdir -p "$dest"
printf 'payload\n' >"$dest/payload-marker"
SH
chmod +x "$work/bin/rsync"

cat >"$work/bin/gensquashfs" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --all-root && $2 == --pack-dir ]]
staging=$3
[[ $staging != "$DWM_TEST_BRANDING" ]]
cmp "$staging/usr/share/anaconda/pixmaps/sidebar-logo.png" \
	"$staging/usr/share/anaconda/pixmaps/server/sidebar-logo.png"
cp "$staging/usr/share/anaconda/pixmaps/sidebar-logo.png" "$DWM_TEST_PACKED_LOGO"
[[ -s $staging/usr/share/anaconda/ui/spokes/installation_progress.glade ]]
printf 'mock product image\n' >"$4"
SH
chmod +x "$work/bin/gensquashfs"

cat >"$work/bin/xorriso" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

extract_to=
outdev=
ks_map=
grub_map=
payload_map=
product_map=

while (($# > 0)); do
	case "$1" in
	-extract)
		if [[ ${2:-} == /EFI/BOOT/grub.cfg ]]; then
			extract_to=${3:-}
		fi
		shift 3
		;;
	-outdev)
		outdev=${2:-}
		shift 2
		;;
	-map)
		case "${3:-}" in
		/dwm-fedora.ks) ks_map=${2:-} ;;
		/EFI/BOOT/grub.cfg) grub_map=${2:-} ;;
		/dwm-titus) payload_map=${2:-} ;;
		/images/product.img) product_map=${2:-} ;;
		esac
		shift 3
		;;
	*)
		shift
		;;
	esac
done

if [[ -n $extract_to ]]; then
	mkdir -p "$(dirname -- "$extract_to")"
	cat >"$extract_to" <<'OUT'
menuentry 'Install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 quiet
}
menuentry 'Test this media & install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 rd.live.check quiet
}
OUT
	exit 0
fi

if [[ -n $outdev ]]; then
	[[ -s $product_map ]]
	{
		printf 'ks=%s\n' "$ks_map"
		printf 'grub=%s\n' "$grub_map"
		printf 'payload=%s\n' "$payload_map"
		printf 'grub-content-start\n'
		cat "$grub_map"
		printf 'grub-content-end\n'
	} >>"$DWM_TEST_XORRISO_LOG"
	printf 'mock iso\n' >"$outdev"
	exit 0
fi
SH
chmod +x "$work/bin/xorriso"

input_iso="$work/Fedora-Server-netinst.iso"
standard_iso="$work/dwm-titus.iso"
nvidia_iso="$work/dwm-titus-nvidia.iso"
touch "$input_iso"

run_builder() {
	local variant=$1
	local output=$2
	shift 2
	: >"$DWM_TEST_XORRISO_LOG"
	: >"$DWM_TEST_RSYNC_LOG"

	PATH="$work/bin:$PATH" \
		"$repo/scripts/build-dwm-fedora-installer-iso.sh" \
		--input "$input_iso" \
		--output "$output" \
		--variant "$variant" "$@" >"$work/$variant.out"

	grep -Fqx "Created $output ($variant)" "$work/$variant.out"
	grep -Fqx 'mock iso' "$output"
	grep -F -- "--exclude=.git/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=release/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=*.iso" "$DWM_TEST_RSYNC_LOG" >/dev/null
}

export DWM_TEST_XORRISO_LOG="$work/xorriso.log"
export DWM_TEST_RSYNC_LOG="$work/rsync.log"
export DWM_TEST_BRANDING="$repo/branding/anaconda"
export DWM_TEST_PACKED_LOGO="$work/packed-logo.png"
cp "$DWM_TEST_BRANDING/usr/share/anaconda/pixmaps/sidebar-logo.png" "$work/original-logo.png"

run_builder standard "$standard_iso"
grep -Fqx "ks=$repo/dwm-fedora.ks" "$DWM_TEST_XORRISO_LOG"
grep -Fqx '	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 quiet inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-44:/dwm-fedora.ks' "$DWM_TEST_XORRISO_LOG"
grep -Fqx '	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 rd.live.check quiet inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-44:/dwm-fedora.ks' "$DWM_TEST_XORRISO_LOG"
if grep -Fq 'nvidia-drm.modeset=1' "$DWM_TEST_XORRISO_LOG"; then
	printf 'standard ISO builder added NVIDIA boot arguments\n' >&2
	exit 1
fi

run_builder nvidia "$nvidia_iso"
grep -Fqx "ks=$repo/dwm-fedora-nvidia.ks" "$DWM_TEST_XORRISO_LOG"
grep -Fqx '	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 quiet inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-44:/dwm-fedora.ks rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1' "$DWM_TEST_XORRISO_LOG"
grep -Fqx '	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 rd.live.check quiet inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-44:/dwm-fedora.ks rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1' "$DWM_TEST_XORRISO_LOG"

if PATH="$work/bin:$PATH" "$repo/scripts/build-dwm-fedora-installer-iso.sh" --input "$input_iso" --output "$work/bad.iso" --variant bad >"$work/bad.out" 2>"$work/bad.err"; then
	printf 'builder accepted an unknown variant\n' >&2
	exit 1
fi
grep -Fq 'unknown variant: bad' "$work/bad.err"

for version in '' v ../bad 0.7; do
	expected_error='--version must be X.Y.Z or vX.Y.Z.'
	[[ -n $version ]] || expected_error='--version requires a value.'
	for form in separate equals; do
		args=(--version "$version")
		[[ $form != equals ]] || args=("--version=$version")
		if PATH="$work/bin:$PATH" "$repo/scripts/build-dwm-fedora-installer-iso.sh" \
			--input "$input_iso" --output "$work/bad.iso" --variant standard \
			"${args[@]}" >"$work/bad.out" 2>"$work/bad.err"; then
			printf 'builder accepted invalid version: %s\n' "$version" >&2
			exit 1
		fi
		grep -Fxq -- "build-dwm-fedora-installer-iso: $expected_error" "$work/bad.err"
	done
done

# Exercise the real Pillow/Fontconfig generator, then ensure another build
# without --version uses the original badge, not the previous build's output.
run_builder standard "$standard_iso" --version v0.7.1
if cmp -s "$DWM_TEST_PACKED_LOGO" "$work/original-logo.png"; then
	printf 'versioned build did not generate a new logo\n' >&2
	exit 1
fi
cmp "$DWM_TEST_BRANDING/usr/share/anaconda/pixmaps/sidebar-logo.png" "$work/original-logo.png"
cmp "$DWM_TEST_BRANDING/usr/share/anaconda/pixmaps/server/sidebar-logo.png" "$work/original-logo.png"
run_builder standard "$standard_iso"
cmp "$DWM_TEST_PACKED_LOGO" "$work/original-logo.png"

# Invalid destination/mode combinations must not silently write elsewhere.
if (cd "$work" && python3 "$repo/scripts/generate-sidebar-logo.py" --series --output ignored.png) >"$work/bad.out" 2>"$work/bad.err"; then
	printf 'series generation accepted a single-file destination\n' >&2
	exit 1
fi
grep -Fq -- '--output requires --version' "$work/bad.err"
if (cd "$work" && python3 "$repo/scripts/generate-sidebar-logo.py" --version 0.7.1 --out-dir ignored) >"$work/bad.out" 2>"$work/bad.err"; then
	printf 'single-version generation accepted a series destination\n' >&2
	exit 1
fi
grep -Fq -- '--out-dir requires --series' "$work/bad.err"
[[ ! -e $work/ignored.png && ! -e $work/ignored && ! -e $work/branding && ! -e $work/sidebar-logo-v0.7.1.png ]]

printf 'Fedora ISO builder: PASS\n'
