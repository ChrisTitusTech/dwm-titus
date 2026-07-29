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

configure_body=$(sed -n '/^configurenotify(XEvent \*e)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$configure_body" | grep -q 'reconcilemonitortags();'
reconcile_line=$(printf '%s\n' "$configure_body" | grep -n 'reconcilemonitortags();' | cut -d: -f1)
scan_bars_line=$(printf '%s\n' "$configure_body" | grep -n 'scanaltbars();' | cut -d: -f1)
client_list_line=$(printf '%s\n' "$configure_body" |
	grep -n 'updateclientlist();' | cut -d: -f1 | sed -n '1p')
publish_line=$(printf '%s\n' "$configure_body" | grep -n 'updatecurrentdesktop();' | cut -d: -f1)
test "$reconcile_line" -lt "$scan_bars_line"
test "$scan_bars_line" -lt "$client_list_line"
test "$reconcile_line" -lt "$client_list_line"
test "$client_list_line" -lt "$publish_line"
test "$reconcile_line" -lt "$publish_line"
managed_client_line=$(printf '%s\n' "$configure_body" |
	grep -n '!wintoclient(ev->window)' | cut -d: -f1)
attributes_line=$(printf '%s\n' "$configure_body" |
	grep -n 'XGetWindowAttributes(dpy, ev->window, &wa)' | cut -d: -f1)
test "$managed_client_line" -lt "$attributes_line"
printf '%s\n' "$configure_body" | grep -q 'isaltbar(ev->window, &wa)'
printf '%s\n' "$configure_body" | grep -q 'm = recttomon(wa.x, wa.y, wa.width, wa.height);'
printf '%s\n' "$configure_body" | grep -q 'm = oldm;'
printf '%s\n' "$configure_body" | grep -q 'oldm->barwin = 0;'
printf '%s\n' "$configure_body" | grep -q 'oldm->bh = 0;'
printf '%s\n' "$configure_body" | grep -q 'arrange(oldm);'

reconcile_body=$(sed -n '/^reconcilemonitortags(void)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$reconcile_body" | grep -q 'updatemonitorcount();'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[s\] &= montags;'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[s\] = fallbacktag;'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags & getmontagmask(owner->num)'
printf '%s\n' "$reconcile_body" | grep -q 'c->mon = owner;'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags &= getmontagmask(owner->num);'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags &= montags;'
printf '%s\n' "$reconcile_body" | grep -q 'c->x = owner->mx + c->x - m->mx;'
printf '%s\n' "$reconcile_body" | grep -q 'wasselected = c == m->sel;'
printf '%s\n' "$reconcile_body" | grep -q 'wasfocused = wasselected && m == selmon;'
printf '%s\n' "$reconcile_body" | grep -q 'owner->sel = c;'
printf '%s\n' "$reconcile_body" | grep -q 'selmon = owner;'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[m->seltags\] == montags'
printf '%s\n' "$reconcile_body" | grep -q 'm->pertag->curtag == 0'
printf '%s\n' "$reconcile_body" | grep -q 'm->nmaster = m->pertag->nmasters\[m->pertag->curtag\];'
printf '%s\n' "$reconcile_body" | grep -q 'm->mfact = m->pertag->mfacts\[m->pertag->curtag\];'
printf '%s\n' "$reconcile_body" | grep -q 'm->lt\[m->sellt\] = m->pertag->ltidxs'
printf '%s\n' "$reconcile_body" | grep -q 'm->showbar = m->pertag->showbars\[m->pertag->curtag\];'

update_client_list_body=$(sed -n '/^updateclientlist(void)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$update_client_list_body" | grep -q 'PropModeReplace'
printf '%s\n' "$update_client_list_body" | grep -q 'memcmp(clients, clientlistcache'
scan_alt_bars_body=$(sed -n '/^scanaltbars(void)/,/^}$/p' "$repo_dir/dwm.c")
query_tree_line=$(printf '%s\n' "$scan_alt_bars_body" |
	grep -n 'XQueryTree' | cut -d: -f1)
clear_bars_line=$(printf '%s\n' "$scan_alt_bars_body" |
	grep -n 'm->barwin = 0;' | cut -d: -f1)
test "$query_tree_line" -lt "$clear_bars_line"
printf '%s\n' "$scan_alt_bars_body" | grep -q 'knownbars\[i\] = m->barwin;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'm->barwin = 0;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'wa.map_state != IsViewable'
printf '%s\n' "$scan_alt_bars_body" | grep -q '!isaltbar(wins\[i\], &wa)'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'knownbars\[j\] == wins\[i\]'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'INTERSECT(wa.x, wa.y, wa.width, wa.height, m) <= 0'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'm = oldm;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'updatealtbar(m, wins\[i\], &wa);'
grep -q 'ewmh_replace_root_cardinal(dwmtagupdateatom, data, 1)' "$repo_dir/dwm.c"
grep -q 'm->barwin, m->wx, m->by, m->ww, m->bh' "$repo_dir/dwm.c"
grep -q 'selmon->barwin, selmon->wx, selmon->by, selmon->ww, selmon->bh' "$repo_dir/dwm.c"
set_fullscreen_body=$(sed -n '/^setfullscreen(Client \*c, int fullscreen)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$set_fullscreen_body" | grep -q 'actualfullscreenchanged'
printf '%s\n' "$set_fullscreen_body" | grep -q 'wasactualfullscreen'
printf '%s\n' "$set_fullscreen_body" | grep -q 'updatefullscreenmonitors();'
visible_fullscreen_body=$(sed -n '/^isvisiblefullscreen(Client \*c)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$visible_fullscreen_body" | grep -q 'c->isfullscreen'
printf '%s\n' "$visible_fullscreen_body" | grep -q 'c->fakefullscreen != 1'
printf '%s\n' "$visible_fullscreen_body" | grep -q 'ISVISIBLE(c)'
monitor_has_fullscreen_body=$(sed -n '/^monitorhasfullscreen(Monitor \*m)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$monitor_has_fullscreen_body" | grep -q 'isvisiblefullscreen(c)'
fullscreen_monitors_body=$(sed -n '/^updatefullscreenmonitors(void)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'monitorhasfullscreen(m)'
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'getmonlogicalindex(m)'
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'dwmfullscreenmonitorsatom'
raise_always_body=$(sed -n '/^raisealwaysontop(Monitor \*m)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$raise_always_body" | grep -q 'monitorhasfullscreen(m)'
printf '%s\n' "$raise_always_body" | grep -q 'raisefullscreenclients(m->stack)'
raise_fullscreen_clients_body=$(sed -n '/^raisefullscreenclients(Client \*c)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$raise_fullscreen_clients_body" | grep -q 'raisefullscreenclients(c->snext);'
printf '%s\n' "$raise_fullscreen_clients_body" | grep -q 'isvisiblefullscreen(c)'
property_notify_body=$(sed -n '/^propertynotify(XEvent \*e)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$property_notify_body" | grep -q 'updateoverridewindow(ev->window);'
printf '%s\n' "$property_notify_body" | grep -q 'restack(m);'
tagmon_body=$(sed -n '/^tagmon(const Arg \*arg)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$tagmon_body" | grep -q 'c->isfullscreen = 1;'
printf '%s\n' "$tagmon_body" | grep -q 'updatefullscreenmonitors();'
reconcile_body=$(sed -n '/^reconcilemonitortags(void)/,/^}$/p' "$repo_dir/dwm.c")
printf '%s\n' "$reconcile_body" | grep -q 'dwmfullscreenmonitorsatom != None'
printf '%s\n' "$reconcile_body" | grep -q 'updatefullscreenmonitors();'
grep -q 'XInternAtom(dpy, "_DWM_FULLSCREEN_MONITORS", False)' "$repo_dir/dwm.c"
grep -q 'XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_COMBO", False)' "$repo_dir/dwm.c"

mkdir -p "$work/bin"
cat >"$work/bin/xprop" <<'SH'
#!/bin/sh
case $* in
*"_DWM_FULLSCREEN_MONITORS"*)
	if [ "${DWM_TEST_FULLSCREEN_MONITORS+x}" = x ]; then
		printf '_DWM_FULLSCREEN_MONITORS(CARDINAL) = %s\n' "$DWM_TEST_FULLSCREEN_MONITORS"
	else
		exit 1
	fi
	;;
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

DWM_TEST_FULLSCREEN_MONITORS='0, 1' \
	DWM_TEST_MONITOR_DESKTOPS='2560, 0, 2560, 1440, 0, 0, 0, 2560, 1440, 4' \
	PATH="$work/bin:$PATH" \
	"$repo_dir/scripts/dwm-quickshell-state" state >"$work/state.out"
grep -Fqx 'monitor_desktops=2560,0,2560,1440,0,0,0,2560,1440,4' "$work/state.out"
grep -Fqx 'fullscreen_monitors=0|1' "$work/state.out"

PATH="$work/bin:$PATH" \
	"$repo_dir/scripts/dwm-quickshell-state" state >"$work/fallback.out"
grep -Fqx 'monitor_desktops=4' "$work/fallback.out"

printf '%s\n' "Monitor tag-switch source guard: PASS"
