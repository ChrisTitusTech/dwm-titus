#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Simulate inherited desktop storage without touching the invoking user's files.
# The real installation fixture must bind both of its HOME variants elsewhere.
state=$work/inherited-state
cache=$work/inherited-cache
mkdir -p "$state/dwm-titus/desktop-update" "$cache/theme-cache"
printf '%s\n' '{"sentinel":"installed desktop receipt"}' >"$state/dwm-titus/desktop-update/installed.json"
printf '%s\n' '/* sentinel live build configuration */' >"$state/dwm-titus/desktop-update/build-config.h"
printf '%s\n' 'sentinel cache contents' >"$cache/theme-cache/marker"
cp -a "$state" "$work/expected-state"
cp -a "$cache" "$work/expected-cache"
find "$state" "$cache" -printf '%p %y %m %U %G\n' | LC_ALL=C sort >"$work/modes.before"

env XDG_STATE_HOME="$state" XDG_CACHE_HOME="$cache" \
	"$repo/tests/test-install-preservation.sh"

diff -r "$work/expected-state" "$state"
diff -r "$work/expected-cache" "$cache"
find "$state" "$cache" -printf '%p %y %m %U %G\n' | LC_ALL=C sort >"$work/modes.after"
cmp "$work/modes.before" "$work/modes.after"
printf 'Installer preserves inherited desktop state and cache: PASS\n'
