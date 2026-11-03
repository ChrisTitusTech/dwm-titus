#!/usr/bin/env bash
# Build the dwm-titus-ai-skills RPM from config/agents/skills.
# Usage: packaging/rpm/build.sh [output-dir]
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
spec=$repo/packaging/rpm/dwm-titus-ai-skills.spec
out=${1:-$repo/release}
name=$(rpmspec -q --qf '%{name}\n' "$spec" | head -n 1)
version=$(rpmspec -q --qf '%{version}\n' "$spec" | head -n 1)

work_root=${TMPDIR:-${DWM_TEST_TMP_ROOT:-$HOME/tmp}}
mkdir -p "$work_root"
work=$(mktemp -d "$work_root/dwm-ai-skills-rpm.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{SOURCES,SPECS,BUILD,RPMS,SRPMS} "$work/$name-$version"
cp -a "$repo/config/agents/skills" "$work/$name-$version/"
cp "$repo/config/agents/skills/dwm-titus/LICENSE" "$work/$name-$version/"
cp "$repo/packaging/rpm/README.md" "$work/$name-$version/"
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo" log -1 --format=%ct 2>/dev/null || printf 0)}
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
	-C "$work" -czf "$work/SOURCES/$name-$version.tar.gz" "$name-$version"
chmod 644 "$work/SOURCES/$name-$version.tar.gz"
install -m644 "$spec" "$work/SPECS/"

rpmbuild --define "_topdir $work" -ba "$work/SPECS/$(basename "$spec")"
mkdir -p -- "$out"
cp -- "$work/SOURCES/$name-$version.tar.gz" "$out/"
find "$work/RPMS" "$work/SRPMS" -name '*.rpm' -exec cp -- {} "$out/" \;
ls -1 -- "$out"/"$name"-*.rpm
