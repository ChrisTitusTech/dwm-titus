#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export DWM_TEST_ISO_RELEASE=44

mkdir -p "$work/bin"
export DWM_TEST_REAL_RSYNC
DWM_TEST_REAL_RSYNC=$(command -v rsync)
export DWM_TEST_PAYLOAD_FIXTURE="$work/payload fixture"
mkdir -p "$DWM_TEST_PAYLOAD_FIXTURE/nested/deeper"
printf 'payload\n' >"$DWM_TEST_PAYLOAD_FIXTURE/payload-marker"
printf 'retained\n' >"$DWM_TEST_PAYLOAD_FIXTURE/nested/deeper/keep.txt"
for directory in "$DWM_TEST_PAYLOAD_FIXTURE" "$DWM_TEST_PAYLOAD_FIXTURE/nested/deeper"; do
	for name in .env .env.local .env.production .envrc; do
		printf 'DUMMY_TOKEN=test-only\n' >"$directory/$name"
	done
done

cat >"$work/bin/rsync" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DWM_TEST_RSYNC_LOG"
# Exercise the production filters with real rsync, using only dummy files.
args=("$@")
args[$#-2]="$DWM_TEST_PAYLOAD_FIXTURE/"
"$DWM_TEST_REAL_RSYNC" "${args[@]}"
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
cmp "$staging/etc/anaconda/conf.d/90-dwm-storage.conf" \
	"$DWM_TEST_BRANDING/etc/anaconda/conf.d/90-dwm-storage.conf"
printf 'mock product image\n' >"$4"
SH
chmod +x "$work/bin/gensquashfs"

cat >"$work/bin/xorriso" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

extract_to=
extract_path=
outdev=
efi_image=
efi_reference=
boot_replay=
ks_map=
grub_map=
bios_grub_map=
payload_map=
product_map=
rootfs_map=

while (($# > 0)); do
	case "$1" in
	-extract_boot_images)
		mkdir -p "$2"
		printf 'EFI fixture\n' >"$2/gpt_part2_efi.img"
		cp "$2/gpt_part2_efi.img" "$2/eltorito_img2_uefi.img"
		[[ ${DWM_TEST_BAD_ESP:-} != 1 ]] || printf 'different\n' >>"$2/gpt_part2_efi.img"
		exit 0
		;;
	-boot_image)
		[[ $2 == any ]]
		case $3 in
		replay) boot_replay=yes ;;
		efi_path=--interval:appended_partition_2:all::)
			[[ $boot_replay == yes && -n $efi_image ]]
			efi_reference=$3
			;;
		*) exit 1 ;;
		esac
		shift 3
		;;
	-append_partition)
		[[ $2 == 2 && $3 == 0xef ]]
		efi_image=$4
		shift 4
		;;
	-extract)
		if [[ ${2:-} == /EFI/BOOT/grub.cfg || ${2:-} == /boot/grub2/grub.cfg ]]; then
			extract_path=$2
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
		/boot/grub2/grub.cfg) bios_grub_map=${2:-} ;;
		/dwm-titus) payload_map=${2:-} ;;
		/images/product.img) product_map=${2:-} ;;
		/images/dwm-rootfs.tar) rootfs_map=${2:-} ;;
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
	cat >"$extract_to" <<OUT
set default="1"
menuentry 'Install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE} quiet
}
menuentry 'Test this media & install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE} rd.live.check quiet
}
OUT
	printf '# original menu: %s\n' "$extract_path" >>"$extract_to"
	exit 0
fi

if [[ -n $outdev ]]; then
	[[ -s $product_map && -s $efi_image && $efi_reference == efi_path=--interval:appended_partition_2:all:: ]]
	grep -Fq "inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE}:/dwm-fedora.ks" "$efi_image"
	cp "$efi_image" "$DWM_TEST_ESP_MENU"
	[[ -s $payload_map/payload-marker && -s $payload_map/nested/deeper/keep.txt ]]
	if [[ -n $(find "$payload_map" \( -name '.env' -o -name '.env.*' -o -name '.envrc' \) -print -quit) ]]; then
		printf 'dotenv file reached ISO payload\n' >&2
		exit 1
	fi
	{
		if [[ -n $rootfs_map ]]; then
			[[ -s $rootfs_map ]]
			cat "$ks_map" >"$DWM_TEST_IMAGE_KS"
		fi
		printf 'ks=%s\n' "$ks_map"
		printf 'grub=%s\n' "$grub_map"
		printf 'payload=%s\n' "$payload_map"
		printf 'grub-content-start\n'
		cat "$grub_map"
		printf 'grub-content-end\n'
		printf 'bios-grub-content-start\n'
		cat "$bios_grub_map"
		printf 'bios-grub-content-end\n'
	} >>"$DWM_TEST_XORRISO_LOG"
	printf 'mock iso\n' >"$outdev"
	exit 0
fi
SH
chmod +x "$work/bin/xorriso"

cat >"$work/bin/implantisomd5" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 && $1 == --force && $2 == --supported-iso ]]
[[ ${DWM_TEST_MEDIA_FAILURE:-} != implant ]] || exit 41
grep -Fqx 'mock iso' "$3"
printf 'media checksum\n' >>"$3"
SH
cat >"$work/bin/checkisomd5" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 ]]
[[ ${DWM_TEST_MEDIA_FAILURE:-} != check ]] || exit 42
grep -Fqx 'media checksum' "$1"
SH
chmod +x "$work/bin/implantisomd5" "$work/bin/checkisomd5"

# Keep the ESP menu independent from the ISO tree to catch tree-only patches.
cat >"$work/bin/mcopy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == -i ]]; then
	[[ $3 == ::/EFI/BOOT/grub.cfg ]]
	cat >"$4" <<MENU
set default="1"
# original ESP menu
menuentry 'Install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE} quiet
}
menuentry 'Test this media & install Fedora' {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE} rd.live.check quiet
}
MENU
else
	[[ $1 == -o && $2 == -i && $5 == ::/EFI/BOOT/grub.cfg ]]
	cp "$4" "$3"
fi
SH
chmod +x "$work/bin/mcopy"
export DWM_TEST_ESP_MENU="$work/esp-menu"

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
	grep -Fqx 'media checksum' "$output"
	# Verify each actual menu independently, including its original content.
	for firmware in uefi bios esp; do
		start=grub-content-start
		end=grub-content-end
		menu_path=/EFI/BOOT/grub.cfg
		if [[ $firmware == bios ]]; then
			start=bios-grub-content-start
			end=bios-grub-content-end
			menu_path=/boot/grub2/grub.cfg
		fi
		if [[ $firmware == esp ]]; then
			cp "$DWM_TEST_ESP_MENU" "$work/menu"
			grep -Fqx '# original ESP menu' "$work/menu"
		else
			awk -v start="$start" -v end="$end" '$0 == start { active=1; next } $0 == end { active=0 } active' \
				"$DWM_TEST_XORRISO_LOG" >"$work/menu"
			grep -Fqx "# original menu: $menu_path" "$work/menu"
		fi
		if [[ " $* " == *' --system-image '* ]]; then
			grep -Fqx 'set default="0"' "$work/menu"
			[[ $(grep -c 'ip=none.*systemd.mask=NetworkManager-wait-online.service.*rd.systemd.mask=nm-wait-online-initrd.service' "$work/menu") == 2 ]]
		else
			grep -Fqx 'set default="1"' "$work/menu"
		fi
		[[ $(grep -c "inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE}:/dwm-fedora.ks" "$work/menu") == 2 ]]
		[[ $(grep -c "inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-${DWM_TEST_ISO_RELEASE} " "$work/menu") == 2 ]]
		if [[ $variant == nvidia ]]; then
			[[ $(grep -c 'rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1' "$work/menu") == 2 ]]
		elif grep -Fq 'nvidia-drm.modeset=1' "$work/menu"; then
			printf 'standard %s menu contains NVIDIA arguments\n' "$firmware" >&2
			exit 1
		fi
	done
	grep -F -- "--exclude=.git/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=release/" "$DWM_TEST_RSYNC_LOG" >/dev/null
	grep -F -- "--exclude=*.iso" "$DWM_TEST_RSYNC_LOG" >/dev/null
}

export DWM_TEST_IMAGE_KS="$work/image.ks"
export DWM_TEST_XORRISO_LOG="$work/xorriso.log"
export DWM_TEST_RSYNC_LOG="$work/rsync.log"
export DWM_TEST_BRANDING="$repo/branding/anaconda"
export DWM_TEST_PACKED_LOGO="$work/packed-logo.png"
cp "$DWM_TEST_BRANDING/usr/share/anaconda/pixmaps/sidebar-logo.png" "$work/original-logo.png"

# Missing comparison support must be reported before EFI topology validation.
mkdir "$work/no-cmp"
for required in xorriso rsync implantisomd5 checkisomd5 mcopy; do
	ln -s "$work/bin/$required" "$work/no-cmp/$required"
done
bash_bin=$(command -v bash)
if PATH="$work/no-cmp" "$bash_bin" "$repo/scripts/build-dwm-fedora-installer-iso.sh" \
	--input "$input_iso" --output "$work/missing-cmp.iso" >"$work/missing-cmp.out" 2>"$work/missing-cmp.err"; then
	echo 'builder accepted missing cmp' >&2
	exit 1
fi
grep -Fqx 'build-dwm-fedora-installer-iso: missing required command: cmp' "$work/missing-cmp.err"

run_builder standard "$standard_iso"
[[ $(grep -c '^set default="1"$' "$DWM_TEST_XORRISO_LOG") == 2 ]]
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

# Reject an unsupported EFI topology before replacing a published image.
printf 'previous image\n' >"$standard_iso"
if DWM_TEST_BAD_ESP=1 PATH="$work/bin:$PATH" \
	"$repo/scripts/build-dwm-fedora-installer-iso.sh" --input "$input_iso" \
	--output "$standard_iso" >"$work/bad-esp.out" 2>"$work/bad-esp.err"; then
	echo 'accepted mismatched EFI images' >&2
	exit 1
fi
grep -Fq 'expected Fedora x86_64 media' "$work/bad-esp.err"
[[ $(cat "$standard_iso") == 'previous image' ]]

# A failed checksum implant or verification must preserve an existing image,
# return the failing command's status, and remove the temporary output.
for failure in implant check; do
	printf 'previous image\n' >"$standard_iso"
	status=0
	DWM_TEST_MEDIA_FAILURE=$failure PATH="$work/bin:$PATH" \
		"$repo/scripts/build-dwm-fedora-installer-iso.sh" \
		--input "$input_iso" --output "$standard_iso" \
		>"$work/failed.out" 2>"$work/failed.err" || status=$?
	expected_status=41
	[[ $failure != check ]] || expected_status=42
	[[ $status == "$expected_status" ]]
	[[ $(cat "$standard_iso") == 'previous image' ]]
	if compgen -G "$work/.dwm-titus.iso.tmp.*" >/dev/null; then
		printf 'failed media check left a temporary output\n' >&2
		exit 1
	fi
done

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

# Minimal ISO9660 PVD fixture: platform checks read bytes, not the input name.
set_iso_release() {
	export DWM_TEST_ISO_RELEASE=$1
	python3 - "$input_iso" "$1" <<'PYPVD'
from pathlib import Path
import sys
pvd = bytearray(2048)
pvd[:7] = b'\x01CD001\x01'
pvd[40:72] = f'Fedora-S-dvd-x86_64-{sys.argv[2]}'.encode().ljust(32)
with Path(sys.argv[1]).open('wb') as stream:
    stream.seek(16 * 2048)
    stream.write(pvd)
PYPVD
}
set_iso_release 44

# Offline payloads must match the variant and verified bytes before ISO creation.
image="$work/root filesystem.tar.xz"
mkdir "$work/rootfs"
printf 'root filesystem fixture\n' >"$work/rootfs/marker"
tar -cJf "$image" -C "$work/rootfs" .
python3 - "$image" <<'PYTHON'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = dict(protocol=1, variant='standard', fedora='44', architecture='x86_64',
         size=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())
pathlib.Path(str(p) + '.json').write_text(json.dumps(m))
PYTHON
run_builder standard "$standard_iso" --system-image "$image"
grep -Fq 'liveimg --url="file:///run/install/repo/images/dwm-rootfs.tar" --checksum=' "$DWM_TEST_IMAGE_KS"
[[ $(grep -c '^set default="0"$' "$DWM_TEST_XORRISO_LOG") == 2 ]]
[[ $(grep -c 'rd.live.check' "$DWM_TEST_XORRISO_LOG") == 2 ]]
[[ $(grep -c 'ip=none' "$DWM_TEST_XORRISO_LOG") == 4 ]]
[[ $(grep -c 'systemd.mask=NetworkManager-wait-online.service' "$DWM_TEST_XORRISO_LOG") == 4 ]]
[[ $(grep -c 'rd.systemd.mask=nm-wait-online-initrd.service' "$DWM_TEST_XORRISO_LOG") == 4 ]]
if grep -Eq 'ip=none|systemd.mask=' "$DWM_TEST_IMAGE_KS"; then
	echo 'Installer-only networking option leaked into target configuration' >&2
	exit 1
fi
if grep -Eq '^(url |repo |%packages)' "$DWM_TEST_IMAGE_KS"; then
	echo 'Offline installer requests online package selection' >&2
	exit 1
fi
python3 - "$image.json" <<'PYTHON'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); m = json.loads(p.read_text())
m['variant'] = 'nvidia'; p.write_text(json.dumps(m))
PYTHON
run_builder nvidia "$nvidia_iso" --system-image "$image"
grep -Fq 'bootloader --location=mbr --append="rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1"' "$DWM_TEST_IMAGE_KS"
python3 - "$image.json" <<'PYTHON'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); m = json.loads(p.read_text())
m['variant'] = 'standard'; p.write_text(json.dumps(m))
PYTHON
mkdir "$work/invalid-temp"
for failure in variant platform checksum manifest; do
	selected=standard
	case $failure in
	variant) selected=nvidia ;;
	platform) set_iso_release 45 ;;
	checksum) printf 'tampered\n' >>"$image" ;;
	manifest) rm "$image.json" ;;
	esac
	printf 'previous image\n' >"$standard_iso"
	if TMPDIR="$work/invalid-temp" PATH="$work/bin:$PATH" \
		"$repo/scripts/build-dwm-fedora-installer-iso.sh" --input "$input_iso" \
		--output "$standard_iso" --variant "$selected" --system-image "$image" \
		>"$work/failed.out" 2>"$work/failed.err"; then
		echo "Accepted invalid system image: $failure" >&2
		exit 1
	fi
	[[ $(cat "$standard_iso") == 'previous image' ]]
	[[ -z $(find "$work/invalid-temp" -mindepth 1 -print -quit) ]]
	set_iso_release 44
done

# Fedora 45 is the new primary; reject cross-release payloads above, while
# retaining Fedora 44 and legacy xz/protocol-1 pairing compatibility.
set_iso_release 45
tar -cJf "$image" -C "$work/rootfs" .
python3 - "$image" <<'PY45'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = dict(protocol=1, variant='standard', fedora='45', architecture='x86_64',
         size=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())
pathlib.Path(str(p) + '.json').write_text(json.dumps(m))
PY45
run_builder standard "$standard_iso" --system-image "$image"
set_iso_release 44

# Zstd uses the same Anaconda-compatible neutral archive path. Verify both
# firmware defaults, then reject a correctly hashed but damaged stream.
image="$work/root filesystem.tar.zst"
tar --zstd -cf "$image" -C "$work/rootfs" .
write_manifest() {
	python3 - "$image" <<'PYTHON'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = dict(protocol=2, variant='standard', fedora='44', architecture='x86_64',
         compression='zstd', size=p.stat().st_size,
         sha256=hashlib.sha256(p.read_bytes()).hexdigest())
pathlib.Path(str(p) + '.json').write_text(json.dumps(m))
PYTHON
}
write_manifest
run_builder standard "$standard_iso" --system-image "$image"
[[ $(grep -c '^set default="0"$' "$DWM_TEST_XORRISO_LOG") == 2 ]]
grep -Fq 'file:///run/install/repo/images/dwm-rootfs.tar"' "$DWM_TEST_IMAGE_KS"
for failure in compression damaged; do
	if [[ $failure == compression ]]; then
		sed -i 's/"zstd"/"xz"/' "$image.json"
	else
		truncate -s 12 "$image"
		write_manifest
	fi
	printf 'previous image\n' >"$standard_iso"
	if TMPDIR="$work/invalid-temp" PATH="$work/bin:$PATH" \
		"$repo/scripts/build-dwm-fedora-installer-iso.sh" --input "$input_iso" \
		--output "$standard_iso" --system-image "$image" \
		>"$work/failed.out" 2>"$work/failed.err"; then
		echo "Accepted invalid zstd image: $failure" >&2
		exit 1
	fi
	[[ $(cat "$standard_iso") == 'previous image' ]]
	[[ -z $(find "$work/invalid-temp" -mindepth 1 -print -quit) ]]
done

# Execute the actual bootstrap against new and legacy filesystem fixtures.
python3 - "$repo" "$work" <<'PYTEST'
import os
from pathlib import Path
import subprocess
import sys
repo, work = map(Path, sys.argv[1:])
profile = (repo / 'dwm-fedora-image.ks').read_text()
body = profile.split('\nset -euo pipefail\n', 1)[1].split('\n%end', 1)[0]
for modern in (False, True):
    root = work / ('modern-root' if modern else 'legacy-root')
    scripts = root / 'usr/share/dwm-titus-image/scripts'
    (scripts / 'image').mkdir(parents=True)
    (root / 'etc').mkdir()
    (root / 'etc/dwm-titus-image').touch()
    for helper in ('seed-apps.sh', 'seed-terminal.sh'):
        (scripts / 'image' / helper).write_text('legacy helper\n')
    shared = scripts / 'seed-default-apps.sh'
    if modern:
        shared.write_text('old shared helper\n')
    test_body = body.replace('/mnt/sysimage', str(root)).replace('/run/install/repo/dwm-titus', str(repo))
    test_body = test_body.replace('-o 0 -g 0', f'-o {os.getuid()} -g {os.getgid()}')
    subprocess.run(['bash', '-ec', 'set -euo pipefail\n' + test_body], check=True)
    assert (scripts / 'image/finish-install.sh').read_bytes() == (repo / 'scripts/image/finish-install.sh').read_bytes()
    assert (scripts / 'configure-timesync.sh').read_bytes() == (repo / 'scripts/configure-timesync.sh').read_bytes()
    if modern:
        assert shared.read_bytes() == (repo / 'scripts/seed-default-apps.sh').read_bytes()
        assert (scripts / 'image/seed-apps.sh').read_bytes() == (repo / 'scripts/image/seed-apps.sh').read_bytes()
    else:
        assert not shared.exists()
        assert (scripts / 'image/seed-apps.sh').read_text() == 'legacy helper\n'
PYTEST

printf 'Fedora ISO builder: PASS\n'
