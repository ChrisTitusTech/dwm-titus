#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

view_body=$(sed -n '/^view(const Arg \*arg)/,/^}$/p' "$repo_dir/dwm.c")

printf '%s\n' "$view_body" | grep -q 'selmon = targetmon;'
printf '%s\n' "$view_body" | grep -q 'focus(NULL);'
printf '%s\n' "$view_body" | grep -q 'XWarpPointer(dpy, None, root'
printf '%s\n' "$view_body" | grep -q 'updatecurrentdesktop();'

same_tag_block=$(printf '%s\n' "$view_body" |
	sed -n '/already the active tagset/,/return;/p')
printf '%s\n' "$same_tag_block" | grep -q 'arrange(selmon);'
printf '%s\n' "$same_tag_block" | grep -q 'focus(NULL);'
printf '%s\n' "$same_tag_block" | grep -q 'XWarpPointer(dpy, None, root'
printf '%s\n' "$same_tag_block" | grep -q 'updatecurrentdesktop();'

printf '%s\n' "Monitor tag-switch source guard: PASS"
