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

cat >"$work/bin/xorriso" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

extract_to=
outdev=
ks_map=
grub_map=
payload_map=

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
	: >"$DWM_TEST_XORRISO_LOG"
	: >"$DWM_TEST_RSYNC_LOG"

	PATH="$work/bin:$PATH" \
		"$repo/scripts/build-dwm-fedora-installer-iso.sh" \
		--input "$input_iso" \
		--output "$output" \
		--variant "$variant" >"$work/$variant.out"

	grep -Fqx "Created $output ($variant)" "$work/$variant.out"
	grep -Fqx 'mock iso' "$output"
	grep -F -- "--exclude=.git/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=release/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=*.iso" "$DWM_TEST_RSYNC_LOG" >/dev/null
}

export DWM_TEST_XORRISO_LOG="$work/xorriso.log"
export DWM_TEST_RSYNC_LOG="$work/rsync.log"

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

printf 'Fedora ISO builder: PASS\n'
