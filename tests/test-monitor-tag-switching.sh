#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

update_current_body=$(sed -n '/^updatecurrentdesktop(void)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$update_current_body" | grep -q 'getmonlogicalindex(m)'
printf '%s\n' "$update_current_body" | grep -q 'netatom\[NetDwmMonitorDesktops\]'
grep -q 'XInternAtom(dpy, "_DWM_MONITOR_DESKTOPS", False)' "$repo_dir/dwm.c"

mkdir -p "$work/bin"
cat >"$work/bin/xprop" <<'SH'
#!/bin/sh
case $* in
*"_DWM_MONITOR_DESKTOPS"*)
	if [ "${DWM_TEST_MONITOR_DESKTOPS+x}" = x ]; then
		printf '_DWM_MONITOR_DESKTOPS(CARDINAL) = %s\n' "$DWM_TEST_MONITOR_DESKTOPS"
	else
		exit 1
	fi
	;;
*"_NET_CURRENT_DESKTOP"*) printf '_NET_CURRENT_DESKTOP(CARDINAL) = 4\n' ;;
*"_NET_NUMBER_OF_DESKTOPS"*) printf '_NET_NUMBER_OF_DESKTOPS(CARDINAL) = 9\n' ;;
*"_NET_DESKTOP_NAMES"*) printf '_NET_DESKTOP_NAMES(UTF8_STRING) = "1", "2", "3", "4", "5", "6", "7", "8", "9"\n' ;;
*"_NET_ACTIVE_WINDOW"*) printf '_NET_ACTIVE_WINDOW(WINDOW): window id # 0x0\n' ;;
*"_NET_CLIENT_LIST"*) printf '_NET_CLIENT_LIST(WINDOW): window id #\n' ;;
*"WM_NAME"*) printf 'WM_NAME(STRING) = "VOL 50%%"\n' ;;
*) exit 1 ;;
esac
SH
cat >"$work/bin/xdotool" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$work/bin/xprop" "$work/bin/xdotool"

DWM_TEST_MONITOR_DESKTOPS='2560, 0, 2560, 1440, 0, 0, 0, 2560, 1440, 4' PATH="$work/bin:$PATH" \
	"$repo_dir/scripts/dwm-quickshell-state" state >"$work/state.out"
grep -Fqx 'monitor_desktops=2560,0,2560,1440,0,0,0,2560,1440,4' "$work/state.out"

PATH="$work/bin:$PATH" \
	"$repo_dir/scripts/dwm-quickshell-state" state >"$work/fallback.out"
grep -Fqx 'monitor_desktops=4' "$work/fallback.out"

printf '%s\n' "Monitor tag-switch source guard: PASS"
