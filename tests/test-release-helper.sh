#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
helper=$repo_dir/scripts/dwm-titus-release
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/gh"
: >"$work/dwm-titus.iso"
version=$(awk -F= '$1 ~ /^VERSION[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$repo_dir/config.mk")

output=$(
	PATH="$work/bin:$PATH" "$helper" \
		--dry-run \
		--skip-checks \
		--no-bump \
		--iso "$work/dwm-titus.iso"
)

printf '%s\n' "$output" | grep -Fq "release/dwm-titus-$version.iso"
printf '%s\n' "$output" | grep -Fq '+ cp --reflink=auto --'
printf '%s\n' "$output" | grep -Fq '+ make release'
printf '%s\n' "$output" | grep -Fq '+ gh api -X POST repos/:owner/:repo/git/refs'
build_line=$(printf '%s\n' "$output" | grep -nF '+ make release' | cut -d: -f1)
tag_line=$(printf '%s\n' "$output" |
	grep -nF '+ gh api -X POST repos/:owner/:repo/git/refs' | cut -d: -f1)
if [ "$build_line" -ge "$tag_line" ]; then
	printf '%s\n' 'release validation must run before remote tag creation' >&2
	exit 1
fi

if PATH="$work/bin:$PATH" "$helper" \
	--dry-run --skip-checks --no-bump --iso "$work/dwm-titus.iso" \
	--version 99.0.0 >"$work/mismatch.out" 2>"$work/mismatch.err"; then
	printf '%s\n' 'release helper accepted a version not committed in config.mk' >&2
	exit 1
fi
grep -Fq 'does not match committed config.mk VERSION' "$work/mismatch.err"

# Exercise real local staging and checksum generation with mocked remote tools.
fixture=$work/repository
mkdir -p "$fixture/scripts"
cp "$helper" "$fixture/scripts/dwm-titus-release"
printf 'VERSION = %s\n' "$version" >"$fixture/config.mk"
printf 'release/\n' >"$fixture/.gitignore"
git -C "$fixture" init -q
git -C "$fixture" add .
git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgSign=false commit -qm fixture
mkdir "$work/remote"
export RELEASE_TEST_REMOTE="$work/remote"
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${RELEASE_TEST_LOG:?}"
case "$*" in
*git/ref/tags/*) exit 1 ;;
'release view '*)
	[ -e "$RELEASE_TEST_REMOTE/exists" ] || exit 1
	if [ "$#" -gt 3 ]; then
		for asset in "$RELEASE_TEST_REMOTE/"*.iso; do
			[ ! -f "$asset" ] || printf '%s\n' "${asset##*/}"
		done
	fi
	;;
'release download '*)
	[ "${RELEASE_TEST_DOWNLOAD_FAIL:-0}" != 1 ] || exit 1
	cp "$RELEASE_TEST_REMOTE/$5" "$7/$5"
	;;
'release create '* | 'release upload '*)
	shift 3
	for asset do
		case $asset in --*) break ;; esac
		cp "$asset" "$RELEASE_TEST_REMOTE/${asset##*/}"
	done
	: >"$RELEASE_TEST_REMOTE/exists"
	;;
esac
EOF
cat >"$work/bin/make" <<'EOF'
#!/bin/sh
set -eu
mkdir -p release
printf 'archive\n' >"release/dwm-titus-${RELEASE_TEST_VERSION:?}.tar.gz"
EOF
chmod +x "$work/bin/make"
printf 'installer image\n' >"$work/source image.iso"
for variant in standard nvidia standard; do
	run_fixture=$fixture
	if [ "$variant" = nvidia ]; then
		git clone -q "$fixture" "$work/second-checkout"
		run_fixture=$work/second-checkout
		# An obsolete remote manifest must not supply the retained ISO hash.
		printf '%064d  dwm-titus-%s.iso\n' 0 "$version" \
			>"$work/remote/dwm-titus-$version-SHA256SUMS"
	fi
	# Each invocation has no prior local ISO or checksum. Retained remote bytes
	# deliberately differ from this invocation, exposing stale-hash shortcuts.
	rm -rf "$run_fixture/release"
	printf '%s installer image\n' "$variant" >"$work/source image.iso"
	suffix=
	[ "$variant" = standard ] || suffix=-nvidia
	PATH="$work/bin:$PATH" RELEASE_TEST_LOG="$work/gh.log" RELEASE_TEST_VERSION="$version" \
		"$run_fixture/scripts/dwm-titus-release" --skip-checks --no-bump \
		--iso "$work/source image.iso" --iso-variant "$variant" >"$work/release.out"
	asset=dwm-titus-$version$suffix.iso
	cmp "$work/source image.iso" "$run_fixture/release/$asset"
	grep -Fq "release/$asset" "$work/gh.log"
	(cd "$work/remote" && sha256sum -c "dwm-titus-$version-SHA256SUMS")
	if [ "$variant" = nvidia ]; then
		grep -Fq "dwm-titus-$version.iso" "$run_fixture/release/dwm-titus-$version-SHA256SUMS"
	fi
	if grep -Fq "$work" "$run_fixture/release/dwm-titus-$version-SHA256SUMS"; then
		printf '%s\n' 'release checksum contains a machine-local path' >&2
		exit 1
	fi
done
# Failure to read a retained remote image must not publish a partial manifest.
cp "$work/remote/dwm-titus-$version-SHA256SUMS" "$work/manifest-before-failure"
if PATH="$work/bin:$PATH" RELEASE_TEST_LOG="$work/gh.log" RELEASE_TEST_VERSION="$version" \
	RELEASE_TEST_DOWNLOAD_FAIL=1 "$fixture/scripts/dwm-titus-release" \
	--skip-checks --no-bump --iso "$work/source image.iso" >"$work/download-failure.out" 2>&1; then
	echo 'release proceeded without reading the retained remote image' >&2
	exit 1
fi
cmp "$work/manifest-before-failure" "$work/remote/dwm-titus-$version-SHA256SUMS"
if find "$fixture/release" -maxdepth 1 -name '.remote-assets.*' | grep -q .; then
	echo 'temporary remote assets leaked' >&2
	exit 1
fi
if PATH="$work/bin:$PATH" "$helper" --dry-run --iso-variant unknown \
	>"$work/variant.out" 2>"$work/variant.err"; then
	printf '%s\n' 'release helper accepted an invalid ISO variant' >&2
	exit 1
fi
grep -Fq -- '--iso-variant must be standard or nvidia' "$work/variant.err"

printf '%s\n' 'Release helper preflight, versioned assets and remote-write ordering: PASS'
