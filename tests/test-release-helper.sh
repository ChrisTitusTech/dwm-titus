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

output=$(
	PATH="$work/bin:$PATH" "$helper" \
		--dry-run \
		--skip-checks \
		--no-bump \
		--iso "$work/dwm-titus.iso"
)

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

printf '%s\n' 'Release helper preflight and remote-write ordering: PASS'
