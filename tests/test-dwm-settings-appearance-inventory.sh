#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo/scripts/dwm-settings-appearance
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

process_running() {
	local pid=$1 stat fields
	[[ -r /proc/$pid/stat ]] || return 1
	IFS= read -r stat <"/proc/$pid/stat" || return 1
	fields=${stat##*) }
	[[ ${fields%% *} != Z ]]
}

home=$work/home
config_home=$home/.config
data_root=$work/data
bin_dir=$work/bin
wallpaper_dir=$home/Pictures/backgrounds
legacy_font_dir=$home/.fonts
proc_root=$work/proc
mkdir -p "$config_home/dwm-titus" "$config_home/dconf" "$config_home/fontconfig" \
	"$data_root/fonts/fixture" \
	"$data_root/icons/Capitaine-Cursors/cursors" \
	"$data_root/icons/Papirus" \
	"$data_root/linked-cursor/cursors" \
	"$data_root/themes/Nordic/gtk-3.0" "$data_root/themes/Nordic/gtk-4.0" \
	"$data_root/themes/Legacy/gtk-3.0" \
	"$wallpaper_dir/nested" "$legacy_font_dir/nested" "$bin_dir" "$proc_root/4242"
printf '[Icon Theme]\nName=Papirus\nDirectories=scalable/apps\n' \
	>"$data_root/icons/Papirus/index.theme"
printf '[Icon Theme]\nName=Capitaine Cursors\nInherits=hicolor\n' \
	>"$data_root/icons/Capitaine-Cursors/index.theme"
ln -s ../linked-cursor "$data_root/icons/LinkedCursor"
printf 'png\n' >"$wallpaper_dir/nord.png"
printf 'jpg\n' >"$wallpaper_dir/nested/forest.JPG"
printf 'ignored\n' >"$wallpaper_dir/readme.txt"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors\n' \
	>"$config_home/dwm-titus/theme-env.sh"

for command_name in awk bash find grep id mkfifo mktemp readlink rm rmdir sleep timeout tr; do
	ln -s "$(command -v "$command_name")" "$bin_dir/$command_name"
done
printf 'DISPLAY=:55\0' >"$proc_root/4242/environ"
export DISPLAY=:55 DWM_APPEARANCE_PROC_ROOT=$proc_root

cat >"$bin_dir/fc-list" <<'EOF'
#!/bin/sh
printf 'Noto Sans\tRegular\nJetBrains Mono\tRegular\nNoto Sans\tBold\n'
EOF
cat >"$bin_dir/fc-match" <<'EOF'
#!/bin/sh
printf 'Fallback Sans\n'
EOF
cat >"$bin_dir/gsettings" <<'EOF'
#!/bin/sh
case $3 in
font-name) printf "'%s'\n" "${DWM_TEST_FONT_NAME:-Noto Sans 11}" ;;
cursor-theme) printf "'%s'\n" "${DWM_TEST_CURSOR_THEME:-Capitaine-Cursors}" ;;
icon-theme) printf "'%s'\n" "${DWM_TEST_ICON_THEME:-Papirus}" ;;
gtk-theme) printf "'%s'\n" "${DWM_TEST_GTK_THEME:-Nordic}" ;;
*) exit 1 ;;
esac
EOF
cat >"$bin_dir/pgrep" <<'EOF'
#!/bin/sh
[ "${3:-}" = '-x' ] && [ "${4:-}" = picom ] || exit 1
if [ -n "${DWM_TEST_PICOM_STATE:-}" ]; then
	IFS= read -r state <"$DWM_TEST_PICOM_STATE"
	[ "$state" = running ] || exit 1
fi
printf '4242\n'
EOF
cat >"$bin_dir/picom" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$bin_dir/qt6ct" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$bin_dir/inotifywait" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$DWM_TEST_INOTIFY_ARGS"
printf 'Watches established.\n' >&2
if [ "${DWM_TEST_INOTIFY_BLOCK:-0}" = 1 ]; then
	printf '%s\n' "$$" >"$DWM_TEST_INOTIFY_PID_FILE"
	trap 'exit 143' HUP INT TERM
	while :; do sleep 10; done
fi
printf 'CREATE\t%s/new.png\n' "$DWM_APPEARANCE_WALLPAPER_DIR"
EOF
chmod +x "$bin_dir/fc-list" "$bin_dir/fc-match" "$bin_dir/gsettings" \
	"$bin_dir/pgrep" "$bin_dir/picom" "$bin_dir/qt6ct" "$bin_dir/inotifywait"

inventory=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	"$helper" inventory)

grep -Fqx $'appearance-inventory-protocol\t1\t0' <<<"$inventory"
grep -Fqx $'provider\tappearance-inventory\tavailable\tread-only\tBounded appearance asset inventory' \
	<<<"$inventory"
grep -Fqx $'watch\tavailable\tinotifywait\tAsset changes are observable while Appearance is open' \
	<<<"$inventory"
grep -Fqx $'selection\twallpaper\tpartial\t\tfill\tNo managed wallpaper selection has been recorded yet' \
	<<<"$inventory"
grep -Fqx $'candidate\twallpaper\tavailable\t'"$wallpaper_dir/nord.png"$'\tnord.png\tImage in the configured wallpaper folder' \
	<<<"$inventory"
grep -Fqx $'candidate\twallpaper\tavailable\t'"$wallpaper_dir/nested/forest.JPG"$'\tforest.JPG\tImage in the configured wallpaper folder' \
	<<<"$inventory"
if grep -Fq 'readme.txt' <<<"$inventory"; then
	printf 'Non-image wallpaper candidate was emitted\n' >&2
	exit 1
fi
grep -Fqx $'selection\tfont\tavailable\tNoto Sans\tNoto Sans 11\tCurrent desktop font family is installed' \
	<<<"$inventory"
test "$(grep -Fc $'candidate\tfont\tavailable\tNoto Sans\tNoto Sans\tFontconfig family' \
	<<<"$inventory")" -eq 1
grep -Fqx $'candidate\tfont\tavailable\tJetBrains Mono\tJetBrains Mono\tFontconfig family' \
	<<<"$inventory"
grep -Fqx $'selection\tcursor\tavailable\tCapitaine-Cursors\t\tCurrent selection is installed: Xcursor theme' \
	<<<"$inventory"
grep -Fqx $'candidate\tcursor\tavailable\tCapitaine-Cursors\tCapitaine-Cursors\tXcursor theme' \
	<<<"$inventory"
grep -Fqx $'candidate\tcursor\tavailable\tLinkedCursor\tLinkedCursor\tXcursor theme' \
	<<<"$inventory"
grep -Fqx $'selection\ticon\tavailable\tPapirus\t\tCurrent selection is installed: XDG icon theme' \
	<<<"$inventory"
grep -Fqx $'candidate\ticon\tavailable\tPapirus\tPapirus\tXDG icon theme' <<<"$inventory"
if grep -Fq $'candidate\ticon\tavailable\tCapitaine-Cursors\t' <<<"$inventory"; then
	printf 'Cursor-only theme was emitted as an icon candidate\n' >&2
	exit 1
fi
grep -Fqx $'candidate\tgtk\tavailable\tNordic\tNordic\tGTK 3 and GTK 4 theme' <<<"$inventory"
grep -Fqx $'candidate\tgtk\tavailable\tAdwaita\tAdwaita\tBuilt-in GTK 3 and GTK 4 theme' \
	<<<"$inventory"
grep -Fqx $'candidate\tgtk\tavailable\tAdwaita-dark\tAdwaita-dark\tBuilt-in GTK 3 and GTK 4 theme' \
	<<<"$inventory"
grep -Fqx $'candidate\tgtk\tpartial\tLegacy\tLegacy\tTheme is missing GTK 3 or GTK 4 assets' \
	<<<"$inventory"
grep -Fqx $'selection\tqt\tavailable\tqt6ct\t\tCurrent Qt platform theme backend' <<<"$inventory"
grep -Fqx $'selection\tcompositor\tavailable\tpicom\trunning\tPicom is running' <<<"$inventory"

printf 'DISPLAY=:99\0' >"$proc_root/4242/environ"
other_display=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	"$helper" inventory)
grep -Fqx $'selection\tcompositor\tpartial\tpicom\tstopped\tPicom is installed but not running on this display' \
	<<<"$other_display"
printf 'DISPLAY=:55\0' >"$proc_root/4242/environ"

export DISPLAY=:55.0
equivalent_display=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	"$helper" inventory)
grep -Fqx $'selection\tcompositor\tavailable\tpicom\trunning\tPicom is running' \
	<<<"$equivalent_display"
export DISPLAY=:55

stale_font=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_FONT_NAME='Missing Font 11' "$helper" inventory)
grep -Fqx $'selection\tfont\tunavailable\tMissing Font\tMissing Font 11\tConfigured desktop font family is not installed' \
	<<<"$stale_font"

styled_font=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_FONT_NAME='Noto Sans Bold 11' "$helper" inventory)
grep -Fqx $'selection\tfont\tavailable\tNoto Sans\tNoto Sans Bold 11\tCurrent desktop font family is installed' \
	<<<"$styled_font"

printf -v oversized_font '%*s' 4100 ''
oversized_font=${oversized_font// /x}
oversized=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_FONT_NAME="$oversized_font 11" "$helper" inventory)
grep -Fqx $'selection\tfont\tunavailable\t\t\tConfigured font selection exceeds the inventory field limit' \
	<<<"$oversized"
grep -Fqx $'selection\tcursor\tavailable\tCapitaine-Cursors\t\tCurrent selection is installed: Xcursor theme' \
	<<<"$oversized"

stale=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=unsupported \
	DWM_TEST_CURSOR_THEME=MissingCursor DWM_TEST_ICON_THEME=MissingIcons \
	DWM_TEST_GTK_THEME=MissingGtk "$helper" inventory)
for stale_capability in cursor icon gtk; do
	grep -Fq $'selection\t'"$stale_capability"$'\tunavailable\tMissing' <<<"$stale"
done
grep -Fqx $'selection\tqt\tpartial\tunsupported\t\tConfigured Qt platform theme backend is unsupported' \
	<<<"$stale"

legacy_gtk=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_GTK_THEME=Legacy "$helper" inventory)
grep -Fqx $'selection\tgtk\tpartial\tLegacy\t\tCurrent selection is installed: Theme is missing GTK 3 or GTK 4 assets' \
	<<<"$legacy_gtk"

builtin_gtk=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_GTK_THEME=Adwaita "$helper" inventory)
grep -Fqx $'selection\tgtk\tavailable\tAdwaita\t\tCurrent selection is installed: Built-in GTK 3 and GTK 4 theme' \
	<<<"$builtin_gtk"

no_qt_bin=$work/no-qt-bin
cp -a "$bin_dir" "$no_qt_bin"
rm -f "$no_qt_bin/qt6ct"
stale_qt=$(HOME=$home PATH=$no_qt_bin XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	"$helper" inventory)
grep -Fqx $'selection\tqt\tpartial\tqt6ct\t\tConfigured Qt platform theme backend is not installed' \
	<<<"$stale_qt"

limit_data=$work/limit-data
mkdir -p "$limit_data/icons"
for candidate_index in $(seq 0 259); do
	mkdir -p "$limit_data/icons/cursor-$candidate_index/cursors"
done
limited=$(HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$limit_data DWM_APPEARANCE_DATA_DIRS=$limit_data \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME=qt6ct \
	DWM_TEST_CURSOR_THEME=cursor-259 "$helper" inventory)
test "$(grep -c $'^candidate\tcursor\t' <<<"$limited")" -eq 256
grep -Fqx $'selection\tcursor\tavailable\tcursor-259\t\tCurrent selection is installed: Xcursor theme' \
	<<<"$limited"

watch_args=$work/watch.args
watch_find_complete=$work/watch-find.complete
watch_bin=$work/watch-bin
real_find=$(command -v find)
cp -a "$bin_dir" "$watch_bin"
rm -f "$watch_bin/find"
cat >"$watch_bin/find" <<'EOF'
#!/bin/sh
trap 'exit 143' HUP INT TERM
"$DWM_TEST_REAL_FIND" "$@"
if [ "${1:-}" = -L ] && [ "${2:-}" = "$DWM_APPEARANCE_WALLPAPER_DIR" ] &&
	[ "${3:-}" = -mindepth ]; then
	sleep 1
	printf 'complete\n' >"$DWM_TEST_FIND_COMPLETE"
fi
EOF
chmod +x "$watch_bin/find"
for wallpaper_index in $(seq 0 139); do
	mkdir -p "$wallpaper_dir/large-$wallpaper_index"
done
HOME=$home PATH=$watch_bin XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_INOTIFY_ARGS=$watch_args DWM_TEST_REAL_FIND=$real_find \
	DWM_TEST_FIND_COMPLETE=$watch_find_complete \
	"$helper" watch-inventory >"$work/watch.out"
if [[ -e $watch_find_complete ]]; then
	printf 'Inventory watcher consumed a descendant scan after reaching its watch cap\n' >&2
	exit 1
fi
grep -Fqx $'ready\tinventory' "$work/watch.out"
grep -Fqx $'changed\tCREATE\t'"$wallpaper_dir/new.png" "$work/watch.out"
grep -Fq -- '-m -P' "$watch_args"
grep -Fq -- "$wallpaper_dir" "$watch_args"
grep -Fq -- "$config_home/dconf" "$watch_args"
grep -Fq -- "$config_home/fontconfig" "$watch_args"
grep -Fq -- "$data_root/icons" "$watch_args"
grep -Fq -- "$data_root/themes" "$watch_args"
grep -Fq -- "$data_root/icons/Papirus" "$watch_args"
grep -Fq -- "$data_root/linked-cursor" "$watch_args"
grep -Fq -- "$data_root/themes/Nordic" "$watch_args"
grep -Fq -- "$data_root/fonts/fixture" "$watch_args"
grep -Fq -- "$legacy_font_dir" "$watch_args"
grep -Fq -- "$legacy_font_dir/nested" "$watch_args"
test "$(awk '{ for (field = 1; field <= NF; field++) if ($field ~ /^\//) count++ } END { print count + 0 }' \
	"$watch_args")" -le 128

missing_watch_args=$work/missing-watch.args
HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$work/missing-config \
	XDG_DATA_HOME=$work/missing-data DWM_APPEARANCE_DATA_DIRS=$work/missing-data \
	DWM_APPEARANCE_WALLPAPER_DIR=$home/NewPictures/backgrounds \
	DWM_TEST_INOTIFY_ARGS=$missing_watch_args "$helper" watch-inventory \
	>"$work/missing-watch.out"
grep -Fq -- "$home" "$missing_watch_args"
grep -Fq -- "$work" "$missing_watch_args"

blocking_args=$work/blocking-watch.args
blocking_helper_pid_file=$work/blocking-helper.pid
blocking_inotify_pid_file=$work/blocking-inotify.pid
HOME=$home PATH=$bin_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_INOTIFY_ARGS=$blocking_args DWM_TEST_INOTIFY_BLOCK=1 \
	DWM_TEST_INOTIFY_PID_FILE=$blocking_inotify_pid_file \
	bash -c '"$1" watch-inventory >"$2" 2>"$4" & helper_pid=$!; printf "%s\n" "$helper_pid" >"$3"; wait "$helper_pid"' \
	bash "$helper" "$work/blocking-watch.out" "$blocking_helper_pid_file" \
	"$work/blocking-watch.err" &
blocking_owner_pid=$!
for _ in $(seq 1 300); do
	[[ -s $blocking_helper_pid_file && -s $blocking_inotify_pid_file ]] && break
	sleep 0.02
done
blocking_helper_pid=$(<"$blocking_helper_pid_file")
blocking_inotify_pid=$(<"$blocking_inotify_pid_file")
blocking_helper_parent_pid=$(awk '/^PPid:/ { print $2 }' "/proc/$blocking_helper_pid/status")
[[ $blocking_helper_parent_pid == "$blocking_owner_pid" ]]
kill -KILL "$blocking_owner_pid"
wait "$blocking_owner_pid" 2>/dev/null || true
for _ in $(seq 1 300); do
	if ! process_running "$blocking_helper_pid" &&
		! process_running "$blocking_inotify_pid"; then
		break
	fi
	sleep 0.02
done
if process_running "$blocking_helper_pid" || process_running "$blocking_inotify_pid"; then
	printf 'Inventory watcher survived its owner process (helper %s, inotify %s)\n' \
		"$blocking_helper_pid" "$blocking_inotify_pid" >&2
	ps -o pid=,ppid=,state=,args= -p "$blocking_helper_pid","$blocking_inotify_pid" >&2 || true
	exit 1
fi
if grep -Fq '/proc/' "$work/blocking-watch.err"; then
	printf 'Inventory watcher leaked a process-exit race to stderr\n' >&2
	exit 1
fi

failing_inventory_bin=$work/failing-inventory-bin
real_find=$(command -v find)
cp -a "$bin_dir" "$failing_inventory_bin"
rm -f "$failing_inventory_bin/find" "$failing_inventory_bin/fc-list"
cat >"$failing_inventory_bin/find" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -L ] && [ "${2:-}" = "$DWM_APPEARANCE_WALLPAPER_DIR" ]; then
	exit 7
fi
exec "$DWM_TEST_REAL_FIND" "$@"
EOF
cat >"$failing_inventory_bin/fc-list" <<'EOF'
#!/bin/sh
exit 9
EOF
chmod +x "$failing_inventory_bin/find" "$failing_inventory_bin/fc-list"
failed_inventory=$(HOME=$home PATH=$failing_inventory_bin XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir DWM_TEST_REAL_FIND=$real_find \
	QT_QPA_PLATFORMTHEME=qt6ct "$helper" inventory)
grep -Fqx $'selection\twallpaper\tpartial\t\tfill\tWallpaper candidate discovery did not complete' \
	<<<"$failed_inventory"
grep -Fqx $'selection\tfont\tunavailable\tNoto Sans\tNoto Sans 11\tFontconfig candidate discovery did not complete' \
	<<<"$failed_inventory"

bounded_inventory_bin=$work/bounded-inventory-bin
cp -a "$bin_dir" "$bounded_inventory_bin"
rm -f "$bounded_inventory_bin/find"
cat >"$bounded_inventory_bin/find" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -L ] && [ "${2:-}" = "$DWM_APPEARANCE_WALLPAPER_DIR" ]; then
	sleep 10
	exit 0
fi
exec "$DWM_TEST_REAL_FIND" "$@"
EOF
chmod +x "$bounded_inventory_bin/find"
SECONDS=0
bounded_inventory=$(HOME=$home PATH=$bounded_inventory_bin XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir DWM_TEST_REAL_FIND=$real_find \
	QT_QPA_PLATFORMTHEME=qt6ct "$helper" inventory)
((SECONDS < 8))
grep -Fqx $'selection\twallpaper\tpartial\t\tfill\tWallpaper candidate discovery did not complete' \
	<<<"$bounded_inventory"

compositor_owner_helper_pid_file=$work/compositor-owner-helper.pid
HOME=$home PATH=$bin_dir TMPDIR=$work XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root \
	bash -c '"$1" watch-compositor >"$2" & helper_pid=$!; printf "%s\n" "$helper_pid" >"$3"; wait "$helper_pid"' \
	bash "$helper" "$work/compositor-owner.out" "$compositor_owner_helper_pid_file" &
compositor_owner_pid=$!
for _ in $(seq 1 300); do
	[[ -s $compositor_owner_helper_pid_file && -s $work/compositor-owner.out ]] && break
	sleep 0.02
done
compositor_owner_helper_pid=$(<"$compositor_owner_helper_pid_file")
compositor_owner_helper_parent_pid=$(awk '/^PPid:/ { print $2 }' \
	"/proc/$compositor_owner_helper_pid/status")
[[ $compositor_owner_helper_parent_pid == "$compositor_owner_pid" ]]
kill -KILL "$compositor_owner_pid"
wait "$compositor_owner_pid" 2>/dev/null || true
for _ in $(seq 1 300); do
	process_running "$compositor_owner_helper_pid" || break
	sleep 0.02
done
if process_running "$compositor_owner_helper_pid"; then
	printf 'Compositor watcher survived its owner process (helper %s)\n' \
		"$compositor_owner_helper_pid" >&2
	exit 1
fi

picom_state=$work/picom.state
printf 'running\n' >"$picom_state"
coproc COMPOSITOR_WATCH {
	exec env HOME="$home" PATH="$bin_dir" TMPDIR="$work" XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$data_root" DWM_TEST_PICOM_STATE="$picom_state" \
		"$helper" watch-compositor
}
# shellcheck disable=SC2153 # Named coprocesses expose NAME_PID dynamically.
compositor_watch_pid=$COMPOSITOR_WATCH_PID
read -r -t 3 compositor_running <&"${COMPOSITOR_WATCH[0]}"
[[ $compositor_running == $'compositor\trunning' ]]
printf 'stopped\n' >"$picom_state"
read -r -t 3 compositor_stopped <&"${COMPOSITOR_WATCH[0]}"
[[ $compositor_stopped == $'compositor\tstopped' ]]
kill "$compositor_watch_pid"
wait "$compositor_watch_pid" 2>/dev/null || true
if find "$work" -maxdepth 1 -type d -name 'dwm-appearance-compositor.*' -print -quit | grep -q .; then
	printf 'Compositor watcher left its wait directory behind\n' >&2
	exit 1
fi

blocking_scan_bin=$work/blocking-scan-bin
blocking_scan_pid_file=$work/blocking-scan-child.pid
cp -a "$bin_dir" "$blocking_scan_bin"
cat >"$blocking_scan_bin/fc-list" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >"$DWM_TEST_FC_LIST_PID_FILE"
trap '' HUP INT TERM
while :; do sleep 10; done
EOF
chmod +x "$blocking_scan_bin/fc-list"
HOME=$home PATH=$blocking_scan_bin XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_FC_LIST_PID_FILE=$blocking_scan_pid_file \
	"$helper" inventory >"$work/blocking-scan.out" &
blocking_scan_helper_pid=$!
for _ in $(seq 1 300); do
	[[ -s $blocking_scan_pid_file ]] && break
	sleep 0.02
done
blocking_scan_child_pid=$(<"$blocking_scan_pid_file")
kill -TERM "$blocking_scan_helper_pid"
wait "$blocking_scan_helper_pid" 2>/dev/null || true
for _ in $(seq 1 300); do
	process_running "$blocking_scan_child_pid" || break
	sleep 0.02
done
if process_running "$blocking_scan_child_pid"; then
	printf 'Inventory scan child survived pane-close termination (child %s)\n' \
		"$blocking_scan_child_pid" >&2
	kill -KILL "$blocking_scan_child_pid" 2>/dev/null || true
	exit 1
fi

minimal_bin=$work/minimal-bin
mkdir -p "$minimal_bin"
ln -s "$(command -v bash)" "$minimal_bin/bash"
ln -s "$(command -v find)" "$minimal_bin/find"
ln -s "$(command -v awk)" "$minimal_bin/awk"
minimal=$(HOME=$home PATH=$minimal_bin XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir QT_QPA_PLATFORMTHEME='' \
	"$helper" inventory)
grep -Fqx $'watch\tunavailable\tinotifywait\tInstall inotify-tools for live asset updates' \
	<<<"$minimal"
grep -Fqx $'selection\tfont\tunavailable\t\t\tFontconfig inventory tools are unavailable' \
	<<<"$minimal"
grep -Fqx $'selection\tcompositor\tunavailable\t\tmissing\tPicom is optional and not installed' \
	<<<"$minimal"

if HOME=$home PATH=$minimal_bin XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root "$helper" watch-inventory \
	2>"$work/missing-watch.err"; then
	printf 'Inventory watch unexpectedly succeeded without inotifywait\n' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-appearance: inotifywait is required for inventory watching' \
	"$work/missing-watch.err"

if "$helper" inventory extra 2>"$work/usage.err"; then
	printf 'Inventory accepted extra arguments\n' >&2
	exit 1
fi
grep -Fq 'usage:' "$work/usage.err"

printf 'Appearance inventory contract: PASS\n'
