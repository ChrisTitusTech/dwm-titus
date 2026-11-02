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
git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${RELEASE_TEST_LOG:?}"
case "$*" in
*git/ref/tags/* | 'release view '*) exit 1 ;;
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
for variant in standard nvidia; do
	suffix=
	[ "$variant" = standard ] || suffix=-nvidia
	PATH="$work/bin:$PATH" RELEASE_TEST_LOG="$work/gh.log" RELEASE_TEST_VERSION="$version" \
		"$fixture/scripts/dwm-titus-release" --skip-checks --no-bump \
		--iso "$work/source image.iso" --iso-variant "$variant" >"$work/release.out"
	asset=dwm-titus-$version$suffix.iso
	cmp "$work/source image.iso" "$fixture/release/$asset"
	grep -Fq "release/$asset" "$work/gh.log"
	(cd "$fixture/release" && sha256sum -c "dwm-titus-$version-SHA256SUMS")
	if grep -Fq "$work" "$fixture/release/dwm-titus-$version-SHA256SUMS"; then
		printf '%s\n' 'release checksum contains a machine-local path' >&2
		exit 1
	fi
done
if PATH="$work/bin:$PATH" "$helper" --dry-run --iso-variant unknown \
	>"$work/variant.out" 2>"$work/variant.err"; then
	printf '%s\n' 'release helper accepted an invalid ISO variant' >&2
	exit 1
fi
grep -Fq -- '--iso-variant must be standard or nvidia' "$work/variant.err"

printf '%s\n' 'Release helper preflight, versioned assets and remote-write ordering: PASS'
