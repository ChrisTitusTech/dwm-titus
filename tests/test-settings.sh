#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
provider=$repo/scripts/dwm-settings-provider
launcher=$repo/scripts/dwm-settings
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

make_tools() {
	directory=$1
	shift
	mkdir -p "$directory"
	for tool in "$@"; do
		target=$(command -v "$tool")
		ln -s "$target" "$directory/$tool"
	done
}

make_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'exit 0' >"$path"
	chmod +x "$path"
}

make_failing_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'exit 1' >"$path"
	chmod +x "$path"
}

make_notification_bus_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'printf '\''{"type":"u","data":[4242]}\n'\''' >"$path"
	chmod +x "$path"
}

make_live_notification_bus_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		"printf '{\"type\":\"u\",\"data\":[%s]}\\n' \"\$PPID\"" >"$path"
	chmod +x "$path"
}

make_appearance_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "appearance-protocol\t1\t0\nprovider\tappearance\tavailable\tread-only\tfixture\nsource\tuser\t/fixture/themes.toml\nactive\tnone\tnone\tselected\ntheme\tnone\tselected\tvalid\ttrue\tautomatic\tfixture\n"' >"$path"
	chmod +x "$path"
}

make_personalization_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "personalization-protocol\t1\t0\nprovider\tpersonalization\tavailable\tuser-session\tFixture provider\nmutation\tavailable\tFixture mutations\nrepair\tavailable\tFixture repair\naction-readiness\tfont\tavailable\tavailable\tFixture readiness\naction-readiness\ttext-size\tavailable\tavailable\tFixture readiness\naction-readiness\tcursor\tavailable\tavailable\tFixture readiness\naction-readiness\ticon\tavailable\tavailable\tFixture readiness\naction-readiness\tgtk\tavailable\tavailable\tFixture readiness\naction-readiness\tqt\tavailable\tavailable\tFixture readiness\nselection\tfont\tavailable\tSans\tfollow-system\tFixture font\nselection\ttext-size\tavailable\t1.25\tfollow-system\tPersistent desktop text scale\nwatch-readiness\ttext-size\tavailable\tFixture watch\nselection\tcursor\tavailable\tCursor\tfollow-theme\tFixture cursor\nselection\ticon\tavailable\tIcons\tfollow-system\tFixture icon\nselection\tgtk\tavailable\tTheme\tfollow-theme\tFixture GTK\nselection\tqt\tavailable\tqt6ct\tfollow-theme\tFixture Qt\ndelegate\tgtk\tunavailable\t\tFixture GTK delegate\ndelegate\tqt\tunavailable\t\tFixture Qt delegate\nfuture-personalization-record\tappend-only-fixture\ncomplete\tstatus\n"' >"$path"
	chmod +x "$path"
}

make_incomplete_personalization_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\tfollow-system\tIncomplete desktop text scale\n"' >"$path"
	chmod +x "$path"
}

make_custom_personalization_stub() {
	path=$1
	payload=$2
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' "printf '%s\\n' '$payload'" >"$path"
	chmod +x "$path"
}

make_hanging_personalization_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' "trap '' TERM" 'while :; do :; done' >"$path"
	chmod +x "$path"
}

make_header_only_appearance_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'printf "appearance-protocol\t1\t0\n"' >"$path"
	chmod +x "$path"
}

make_empty_active_appearance_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "appearance-protocol\t1\t0\nprovider\tappearance\tavailable\tread-only\tfixture\nsource\tuser\t/fixture/themes.toml\nactive\t\t\tselected\ntheme\tnord\tselected\tvalid\ttrue\tautomatic\tfixture\n"' >"$path"
	chmod +x "$path"
}

make_malformed_appearance_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'printf "not-an-appearance-snapshot\n"' >"$path"
	chmod +x "$path"
}

make_preamble_appearance_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'printf "preamble\nappearance-protocol\t1\t0\n"' >"$path"
	chmod +x "$path"
}

make_accessibility_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "accessibility-settings-protocol\t1\t0\nstate\tdefaults\tFixture defaults\nsetting\tcontrast\tstandard\nsetting\tmotion\tfull\nmutation\tavailable\tFixture mutations\nfuture-accessibility-record\tappend-only-fixture\ncomplete\tstatus\n"' >"$path"
	chmod +x "$path"
}

make_custom_accessibility_stub() {
	path=$1
	payload=$2
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' "printf '%s\\n' '$payload'" >"$path"
	chmod +x "$path"
}

make_hanging_accessibility_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' "trap '' TERM" 'while :; do :; done' >"$path"
	chmod +x "$path"
}

make_input_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "input-protocol\t1\ndevice\taccessx\tsession\taccessibility\tKeyboard accessibility\nsetting\taccessx\taccessx-shortcuts\tAccessibility shortcuts\tboolean\t0\t0\t0\t1\nsetting\taccessx\tsticky-keys\tSticky keys\tboolean\t0\t0\t0\t1\nsetting\taccessx\tslow-keys\tSlow keys\tboolean\t0\t0\t0\t1\nsetting\taccessx\tbounce-keys\tBounce keys\tboolean\t0\t0\t0\t1\nsetting\taccessx\tmouse-keys\tMouse keys\tboolean\t0\t0\t0\t1\nfuture-input-record\tappend-only-fixture\n"' >"$path"
	chmod +x "$path"
}

make_incomplete_accessibility_input_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "input-protocol\t1\ndevice\taccessx\tsession\taccessibility\tKeyboard accessibility\nsetting\taccessx\tsticky-keys\tSticky keys\tboolean\t0\t0\t0\t1\n"' >"$path"
	chmod +x "$path"
}

make_malformed_input_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' 'printf "input-protocol\t2\n"' >"$path"
	chmod +x "$path"
}

make_malformed_known_input_stub() {
	path=$1
	mkdir -p "${path%/*}"
	printf '%s\n' '#!/bin/sh' \
		'printf "input-protocol\t1\ndevice\tmissing-required-fields\n"' >"$path"
	chmod +x "$path"
}

base_bin=$work/base-bin
fedora_bin=$work/fedora-bin
make_tools "$base_bin" dirname awk tr stat find grep timeout readlink getconf
cp -a "$base_bin" "$fedora_bin"

for command_name in xrandr nmcli bluetoothctl pactl xset gsettings light-locker \
	xdg-settings xdg-mime xinput xkbset; do
	make_stub "$fedora_bin/$command_name"
done
make_notification_bus_stub "$fedora_bin/busctl"
make_stub "$fedora_bin/dwm-xdg-autostart"
make_appearance_stub "$fedora_bin/dwm-settings-appearance"
make_personalization_stub "$fedora_bin/dwm-settings-personalization"
make_accessibility_stub "$fedora_bin/dwm-accessibility-settings"
make_input_stub "$fedora_bin/dwm-settings-input"
make_stub "$fedora_bin/dwm-settings-theme"
make_stub "$fedora_bin/inotifywait"
make_failing_stub "$fedora_bin/pkexec"
make_failing_stub "$fedora_bin/sudo"

mkdir -p "$work/fedora-config/dwm-titus"
cp "$repo/config/themes.toml" "$work/fedora-config/dwm-titus/themes.toml"

printf 'ID=fedora\nPRETTY_NAME="Fedora\tLinux 44"\n' \
	>"$work/fedora-os-release"

fedora_output=$(PATH="$fedora_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$fedora_output" | grep -Fqx 'settings-protocol	1'
printf '%s\n' "$fedora_output" | grep -Fqx 'platform	fedora	fedora	Fedora Linux 44'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	displays	randr	Display discovery	available	read-only	xrandr	RandR display state is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	displays	display-changes	Display changes	available	user-session	dwm-settings-display	Validated layout previews, rollback, and user profiles are available'
if ! printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	displays	display-persistence	Persistent display profiles	available	privileged	dwm-settings-display-root	Managed Xorg install and rollback are available through polkit' &&
	! printf '%s\n' "$fedora_output" | grep -Fqx \
		'capability	displays	display-persistence	Persistent display profiles	restricted	privileged	dwm-settings-display-root	Live previews remain available; install the trusted root helper for persistence'; then
	printf '%s\n' 'unexpected display-persistence capability state' >&2
	exit 1
fi
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	input	input-devices	Input devices	available	user-session	dwm-settings-input	Stable device discovery, preview, reset, and persistence are available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	network	networkmanager	NetworkManager	available	delegated	nmcli	NetworkManager state is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	audio	pipewire-audio	Audio	available	user-session	pactl	PipeWire Pulse-compatible session controls are available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	defaults	xdg-autostart	Startup applications	available	user-session	xdg-autostart	Per-user XDG autostart overrides and live updates are available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	themes	Themes	available	user-session	dwm-settings-theme	Theme inventory, bounded preview, apply, reset, and recovery are available'
available_theme_record='capability	appearance	themes	Themes	available	user-session	dwm-settings-theme	Theme inventory, bounded preview, apply, reset, and recovery are available'

printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	accessibility-text-scale	Text scaling	available	user-session	dwm-settings-personalization	Persistent desktop text scale'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	accessibility-contrast	High contrast	available	user-session	dwm-accessibility-settings	Persistent managed-shell high-contrast policy is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	accessibility-reduced-motion	Reduced motion	available	user-session	dwm-accessibility-settings	Persistent managed-shell reduced-motion policy is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	accessibility-notifications	Notification policy	partial	read-only	dbus	A notification owner is active, but it is not the managed policy provider'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	available	user-session	dwm-settings-input	Persistent XKB accessibility controls are available'
[ "$(printf '%s\n' "$fedora_output" |
	grep -c '^capability	appearance	accessibility-')" -eq 5 ]

slow_input_bin=$work/slow-input-bin
cp -a "$fedora_bin" "$slow_input_bin"
make_input_stub "$slow_input_bin/dwm-settings-input"
sed -i '2i /usr/bin/sleep 3' "$slow_input_bin/dwm-settings-input"
slow_input_output=$(PATH="$slow_input_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$slow_input_output" | grep -Fqx \
	'capability	input	input-devices	Input devices	available	user-session	dwm-settings-input	Stable device discovery, preview, reset, and persistence are available'
printf '%s\n' "$slow_input_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	available	user-session	dwm-settings-input	Persistent XKB accessibility controls are available'

for invalid_accessibility_case in malformed duplicate-setting missing-complete; do
	invalid_accessibility_bin=$work/invalid-accessibility-$invalid_accessibility_case-bin
	cp -a "$fedora_bin" "$invalid_accessibility_bin"
	case $invalid_accessibility_case in
	malformed)
		invalid_accessibility_payload='not-an-accessibility-status'
		;;
	duplicate-setting)
		invalid_accessibility_payload=$(printf \
			'accessibility-settings-protocol\t1\t0\nstate\tdefaults\tFixture defaults\nsetting\tcontrast\tstandard\nsetting\tcontrast\thigh\nsetting\tmotion\tfull\nmutation\tavailable\tFixture mutations\ncomplete\tstatus')
		;;
	missing-complete)
		invalid_accessibility_payload=$(printf \
			'accessibility-settings-protocol\t1\t0\nstate\tdefaults\tFixture defaults\nsetting\tcontrast\tstandard\nsetting\tmotion\tfull\nmutation\tavailable\tFixture mutations')
		;;
	esac
	make_custom_accessibility_stub \
		"$invalid_accessibility_bin/dwm-accessibility-settings" \
		"$invalid_accessibility_payload"
	invalid_accessibility_output=$(PATH="$invalid_accessibility_bin" \
		XDG_CONFIG_HOME="$work/fedora-config" \
		DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
	printf '%s\n' "$invalid_accessibility_output" | grep -Fqx \
		'capability	appearance	accessibility-contrast	High contrast	unavailable	user-session	dwm-accessibility-settings	The accessibility settings provider returned an unsupported response'
	printf '%s\n' "$invalid_accessibility_output" | grep -Fqx \
		'capability	appearance	accessibility-reduced-motion	Reduced motion	unavailable	user-session	dwm-accessibility-settings	The accessibility settings provider returned an unsupported response'
done

unsafe_accessibility_bin=$work/unsafe-accessibility-bin
cp -a "$fedora_bin" "$unsafe_accessibility_bin"
unsafe_accessibility_payload=$(printf \
	'accessibility-settings-protocol\t1\t0\nstate\tunavailable\tUnsafe fixture state\nsetting\tcontrast\tstandard\nsetting\tmotion\tfull\nmutation\tunavailable\tFixture mutations disabled\ncomplete\tstatus')
make_custom_accessibility_stub \
	"$unsafe_accessibility_bin/dwm-accessibility-settings" \
	"$unsafe_accessibility_payload"
unsafe_accessibility_output=$(PATH="$unsafe_accessibility_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$unsafe_accessibility_output" | grep -Fqx \
	'capability	appearance	accessibility-contrast	High contrast	unavailable	user-session	dwm-accessibility-settings	Persistent accessibility state cannot be safely updated'
printf '%s\n' "$unsafe_accessibility_output" | grep -Fqx \
	'capability	appearance	accessibility-reduced-motion	Reduced motion	unavailable	user-session	dwm-accessibility-settings	Persistent accessibility state cannot be safely updated'

hanging_accessibility_bin=$work/hanging-accessibility-bin
cp -a "$fedora_bin" "$hanging_accessibility_bin"
make_hanging_accessibility_stub \
	"$hanging_accessibility_bin/dwm-accessibility-settings"
hanging_accessibility_output=$(PATH="$hanging_accessibility_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" \
	timeout --signal=KILL 10 "$provider" discover)
printf '%s\n' "$hanging_accessibility_output" | grep -Fqx \
	'capability	appearance	accessibility-contrast	High contrast	unavailable	user-session	dwm-accessibility-settings	The accessibility settings provider returned an unsupported response'

incomplete_personalization_bin=$work/incomplete-personalization-bin
cp -a "$fedora_bin" "$incomplete_personalization_bin"
make_incomplete_personalization_stub \
	"$incomplete_personalization_bin/dwm-settings-personalization"
incomplete_personalization_output=$(PATH="$incomplete_personalization_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$incomplete_personalization_output" | grep -Fqx \
	'capability	appearance	accessibility-text-scale	Text scaling	unavailable	user-session	dwm-settings-personalization	The personalization provider returned an unsupported response'

for malformed_text_scale_case in incomplete-status-shape empty-value empty-preference unsupported-preference malformed-scale duplicate-header malformed-duplicate malformed-known-record oversized-known-field; do
	malformed_text_scale_bin=$work/malformed-text-scale-$malformed_text_scale_case-bin
	cp -a "$fedora_bin" "$malformed_text_scale_bin"
	case $malformed_text_scale_case in
	incomplete-status-shape)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\tfollow-system\tIncomplete status shape\ncomplete\tstatus')
		;;
	empty-value)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t\tfollow-system\tMissing live value\ncomplete\tstatus')
		;;
	empty-preference)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\t\tMissing persisted mode\ncomplete\tstatus')
		;;
	unsupported-preference)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\tgarbage-mode\tUnsupported persisted mode\ncomplete\tstatus')
		;;
	malformed-scale)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\t1x25\tMalformed persisted scale\ncomplete\tstatus')
		;;
	duplicate-header)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\npersonalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\tfollow-system\tDuplicate protocol header\ncomplete\tstatus')
		;;
	malformed-duplicate)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nselection\ttext-size\tavailable\t1.25\tfollow-system\tValid record\nselection\ttext-size\tbogus\t1.25\tfollow-system\tMalformed duplicate\ncomplete\tstatus')
		;;
	malformed-known-record)
		malformed_text_scale_payload=$(printf \
			'personalization-protocol\t1\t0\nprovider\tbroken\nselection\ttext-size\tavailable\t1.25\tfollow-system\tValid record\ncomplete\tstatus')
		;;
	oversized-known-field)
		oversized_option=$(awk 'BEGIN { for (i = 0; i < 4096; i++) printf "x" }')
		malformed_text_scale_payload=$("$fedora_bin/dwm-settings-personalization" status |
			awk -F '\t' -v option="$oversized_option" '
				BEGIN { OFS = "\t" }
				$1 == "selection" && $2 == "font" { $5 = option }
				{ print }
			')
		;;
	esac
	make_custom_personalization_stub \
		"$malformed_text_scale_bin/dwm-settings-personalization" \
		"$malformed_text_scale_payload"
	malformed_text_scale_output=$(PATH="$malformed_text_scale_bin" \
		XDG_CONFIG_HOME="$work/fedora-config" \
		DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
	printf '%s\n' "$malformed_text_scale_output" | grep -Fqx \
		'capability	appearance	accessibility-text-scale	Text scaling	unavailable	user-session	dwm-settings-personalization	The personalization provider returned an unsupported response'
done

unavailable_text_scale_bin=$work/unavailable-text-scale-bin
cp -a "$fedora_bin" "$unavailable_text_scale_bin"
unavailable_text_scale_payload=$("$fedora_bin/dwm-settings-personalization" status |
	awk -F '\t' '
		$1 == "selection" && $2 == "text-size" {
			print "selection\ttext-size\tunavailable\t\tfollow-system\tGSettings key is unavailable"
			next
		}
		{ print }
	')
make_custom_personalization_stub \
	"$unavailable_text_scale_bin/dwm-settings-personalization" \
	"$unavailable_text_scale_payload"
unavailable_text_scale_output=$(PATH="$unavailable_text_scale_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$unavailable_text_scale_output" | grep -Fqx \
	'capability	appearance	accessibility-text-scale	Text scaling	unavailable	user-session	dwm-settings-personalization	GSettings key is unavailable'

hanging_personalization_bin=$work/hanging-personalization-bin
cp -a "$fedora_bin" "$hanging_personalization_bin"
make_hanging_personalization_stub \
	"$hanging_personalization_bin/dwm-settings-personalization"
hanging_personalization_output=$(PATH="$hanging_personalization_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" \
	timeout --signal=KILL 10 "$provider" discover)
printf '%s\n' "$hanging_personalization_output" | grep -Fqx \
	'capability	appearance	accessibility-text-scale	Text scaling	unavailable	user-session	dwm-settings-personalization	The personalization provider is not responding'

missing_personalization_bin=$work/missing-personalization-bin
cp -a "$fedora_bin" "$missing_personalization_bin"
rm -f "$missing_personalization_bin/dwm-settings-personalization" \
	"$missing_personalization_bin/dwm-accessibility-settings"
missing_personalization_provider_dir=$work/missing-personalization-provider
mkdir "$missing_personalization_provider_dir"
cp "$provider" "$missing_personalization_provider_dir/dwm-settings-provider"
missing_personalization_output=$(PATH="$missing_personalization_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" \
	"$missing_personalization_provider_dir/dwm-settings-provider" discover)
printf '%s\n' "$missing_personalization_output" | grep -Fqx \
	'capability	appearance	accessibility-text-scale	Text scaling	unavailable	user-session	dwm-settings-personalization	Install the managed personalization provider'
printf '%s\n' "$missing_personalization_output" | grep -Fqx \
	'capability	appearance	accessibility-contrast	High contrast	unavailable	user-session	dwm-accessibility-settings	Install the managed accessibility settings provider'
printf '%s\n' "$missing_personalization_output" | grep -Fqx \
	'capability	appearance	accessibility-reduced-motion	Reduced motion	unavailable	user-session	dwm-accessibility-settings	Install the managed accessibility settings provider'

missing_accessibility_input_bin=$work/missing-accessibility-input-bin
cp -a "$fedora_bin" "$missing_accessibility_input_bin"
rm -f "$missing_accessibility_input_bin/xinput"
missing_accessibility_input_output=$(PATH="$missing_accessibility_input_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$missing_accessibility_input_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	read-only	x11	Install xinput and the managed input Settings provider'

missing_xkbset_bin=$work/missing-xkbset-bin
cp -a "$fedora_bin" "$missing_xkbset_bin"
rm -f "$missing_xkbset_bin/xkbset"
missing_xkbset_output=$(PATH="$missing_xkbset_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$missing_xkbset_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	user-session	x11	Install xkbset to manage XKB accessibility controls'

unready_xkbset_bin=$work/unready-xkbset-bin
cp -a "$fedora_bin" "$unready_xkbset_bin"
make_failing_stub "$unready_xkbset_bin/xkbset"
unready_xkbset_output=$(PATH="$unready_xkbset_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$unready_xkbset_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	user-session	x11	xkbset is installed, but no complete responsive XKB state is available'

incomplete_xkb_input_bin=$work/incomplete-xkb-input-bin
cp -a "$fedora_bin" "$incomplete_xkb_input_bin"
make_incomplete_accessibility_input_stub "$incomplete_xkb_input_bin/dwm-settings-input"
incomplete_xkb_input_output=$(PATH="$incomplete_xkb_input_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$incomplete_xkb_input_output" | grep -Fqx \
	'capability	input	input-devices	Input devices	available	user-session	dwm-settings-input	Stable device discovery, preview, reset, and persistence are available'
printf '%s\n' "$incomplete_xkb_input_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	user-session	x11	xkbset is installed, but no complete responsive XKB state is available'

unready_accessibility_input_bin=$work/unready-accessibility-input-bin
cp -a "$fedora_bin" "$unready_accessibility_input_bin"
make_failing_stub "$unready_accessibility_input_bin/dwm-settings-input"
unready_accessibility_input_output=$(PATH="$unready_accessibility_input_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$unready_accessibility_input_output" | grep -Fqx \
	'capability	input	input-devices	Input devices	unavailable	user-session	dwm-settings-input	Input tools are installed, but no responsive XInput session is available'
printf '%s\n' "$unready_accessibility_input_output" | grep -Fqx \
	'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	read-only	x11	Input tools are installed, but no responsive XInput session is available'

for invalid_input_case in empty malformed-version malformed-known; do
	invalid_input_bin=$work/invalid-input-$invalid_input_case-bin
	cp -a "$fedora_bin" "$invalid_input_bin"
	case $invalid_input_case in
	empty) make_stub "$invalid_input_bin/dwm-settings-input" ;;
	malformed-version) make_malformed_input_stub "$invalid_input_bin/dwm-settings-input" ;;
	malformed-known) make_malformed_known_input_stub "$invalid_input_bin/dwm-settings-input" ;;
	esac
	invalid_input_output=$(PATH="$invalid_input_bin" \
		XDG_CONFIG_HOME="$work/fedora-config" \
		DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
	printf '%s\n' "$invalid_input_output" | grep -Fqx \
		'capability	input	input-devices	Input devices	unavailable	user-session	dwm-settings-input	Input tools are installed, but no responsive XInput session is available'
	printf '%s\n' "$invalid_input_output" | grep -Fqx \
		'capability	appearance	accessibility-input	Keyboard and pointer access	unavailable	read-only	x11	Input tools are installed, but no responsive XInput session is available'
done

missing_notification_owner_bin=$work/missing-notification-owner-bin
cp -a "$fedora_bin" "$missing_notification_owner_bin"
make_failing_stub "$missing_notification_owner_bin/busctl"
missing_notification_owner_output=$(PATH="$missing_notification_owner_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$missing_notification_owner_output" | grep -Fqx \
	'capability	appearance	accessibility-notifications	Notification policy	unavailable	read-only	dbus	No notification D-Bus owner is observable in this session'

mismatched_notification_owner_bin=$work/mismatched-notification-owner-bin
cp -a "$fedora_bin" "$mismatched_notification_owner_bin"
make_live_notification_bus_stub "$mismatched_notification_owner_bin/busctl"
mismatched_notification_owner_output=$(PATH="$mismatched_notification_owner_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$mismatched_notification_owner_output" | grep -Fqx \
	'capability	appearance	accessibility-notifications	Notification policy	partial	read-only	dbus	A notification owner is active, but it is not the managed policy provider'
grep -Fq "notification_process_started_recently \"\$PPID\"" "$provider"
grep -Fq "[ \"\$process_age_seconds\" -ge 0 ] && [ \"\$process_age_seconds\" -le 15 ]" "$provider"

unsafe_theme_bin=$work/unsafe-theme-bin
cp -a "$fedora_bin" "$unsafe_theme_bin"
make_failing_stub "$unsafe_theme_bin/dwm-settings-theme"
unsafe_theme_output=$(PATH="$unsafe_theme_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$unsafe_theme_output" | grep -Fqx \
	'capability	appearance	themes	Themes	partial	read-only	dwm-settings-appearance	Theme inventory is available; the theme source is not safely mutable'
if printf '%s\n' "$unsafe_theme_output" | grep -Fqx "$available_theme_record"; then
	printf 'unsafe theme source was also advertised as mutable\n' >&2
	exit 1
fi

repo_source_home=$work/repo-source-home
repo_source_config=$work/repo-source-config
mkdir -p "$repo_source_home" "$repo_source_config/dwm-titus"
cp "$repo/config/themes.toml" "$repo_source_config/dwm-titus/themes.toml"
repo_source_output=$(PATH="$repo/scripts:/usr/bin" HOME="$repo_source_home" \
	XDG_CONFIG_HOME="$repo_source_config" XDG_DATA_HOME="$work/missing-repo-source-data" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$repo_source_output" | grep -Fqx \
	"$available_theme_record"

read_only_appearance_bin=$work/read-only-appearance-bin
cp -a "$fedora_bin" "$read_only_appearance_bin"
rm -f "$read_only_appearance_bin/dwm-settings-theme"
read_only_provider_dir=$work/read-only-provider
mkdir "$read_only_provider_dir"
cp "$provider" "$read_only_provider_dir/dwm-settings-provider"
read_only_appearance_output=$(PATH="$read_only_appearance_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" \
	"$read_only_provider_dir/dwm-settings-provider" discover)
printf '%s\n' "$read_only_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	partial	read-only	dwm-settings-appearance	Theme inventory is available; install the managed mutation helper for changes'
if printf '%s\n' "$read_only_appearance_output" | grep -Fqx "$available_theme_record"; then
	printf 'read-only appearance provider was also advertised as mutable\n' >&2
	exit 1
fi
printf '%s\n' "$fedora_output" | grep -Eq \
	'^capability	system	authorization	Administrative authorization	(available|restricted)	privileged	polkit	'

runtime_down_bin=$work/runtime-down-bin
cp -a "$fedora_bin" "$runtime_down_bin"
for command_name in xrandr nmcli bluetoothctl pactl xset; do
	make_failing_stub "$runtime_down_bin/$command_name"
done
make_failing_stub "$runtime_down_bin/dwm-settings-appearance"
runtime_down_output=$(PATH="$runtime_down_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$runtime_down_output" | grep -Fqx \
	'capability	displays	randr	Display discovery	unavailable	read-only	xrandr	RandR tools are installed, but no responsive X11 display is available'
printf '%s\n' "$runtime_down_output" | grep -Fqx \
	'capability	network	networkmanager	NetworkManager	unavailable	delegated	nmcli	NetworkManager is installed, but its service is not responding'
printf '%s\n' "$runtime_down_output" | grep -Fqx \
	'capability	bluetooth	bluez	Bluetooth	unavailable	delegated	bluetoothctl	BlueZ tools are installed, but no daemon or adapter is responding'
printf '%s\n' "$runtime_down_output" | grep -Fqx \
	'capability	audio	pipewire-audio	Audio	unavailable	user-session	pipewire	Audio tools are installed, but no PipeWire or Pulse session is responding'
printf '%s\n' "$runtime_down_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Restore a valid themes.toml configuration or inspect the appearance snapshot errors'

malformed_appearance_bin=$work/malformed-appearance-bin
cp -a "$fedora_bin" "$malformed_appearance_bin"
make_malformed_appearance_stub "$malformed_appearance_bin/dwm-settings-appearance"
malformed_appearance_output=$(PATH="$malformed_appearance_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$malformed_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Restore a valid themes.toml configuration or inspect the appearance snapshot errors'

preamble_appearance_bin=$work/preamble-appearance-bin
cp -a "$fedora_bin" "$preamble_appearance_bin"
make_preamble_appearance_stub "$preamble_appearance_bin/dwm-settings-appearance"
preamble_appearance_output=$(PATH="$preamble_appearance_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$preamble_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Restore a valid themes.toml configuration or inspect the appearance snapshot errors'

header_only_appearance_bin=$work/header-only-appearance-bin
cp -a "$fedora_bin" "$header_only_appearance_bin"
make_header_only_appearance_stub "$header_only_appearance_bin/dwm-settings-appearance"
header_only_appearance_output=$(PATH="$header_only_appearance_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$header_only_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Restore a valid themes.toml configuration or inspect the appearance snapshot errors'

empty_active_appearance_bin=$work/empty-active-appearance-bin
cp -a "$fedora_bin" "$empty_active_appearance_bin"
make_empty_active_appearance_stub "$empty_active_appearance_bin/dwm-settings-appearance"
empty_active_appearance_output=$(PATH="$empty_active_appearance_bin" \
	XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$empty_active_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Restore a valid themes.toml configuration or inspect the appearance snapshot errors'

missing_appearance_bin=$work/missing-appearance-bin
cp -a "$fedora_bin" "$missing_appearance_bin"
rm -f "$missing_appearance_bin/dwm-settings-appearance"
isolated_provider_dir=$work/isolated-provider
mkdir "$isolated_provider_dir"
cp "$provider" "$isolated_provider_dir/dwm-settings-provider"
missing_appearance_output=$(PATH="$missing_appearance_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" \
	"$isolated_provider_dir/dwm-settings-provider" discover)
printf '%s\n' "$missing_appearance_output" | grep -Fqx \
	'capability	appearance	themes	Themes	unavailable	read-only	dwm-settings-appearance	Install the managed appearance provider'

if "$provider" unknown 2>"$work/provider.err"; then
	exit 1
fi
grep -Fq 'usage:' "$work/provider.err"

mkdir -p "$work/home/.config/quickshell" "$work/home/.local/share/dwm-titus/config/quickshell" "$work/launcher-bin"
: >"$work/home/.config/quickshell/shell.qml"
cat >"$work/launcher-bin/quickshell" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$DWM_SETTINGS_LAUNCH_LOG"
EOF
chmod +x "$work/launcher-bin/quickshell"

PATH="$work/launcher-bin:$PATH" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
	DWM_SETTINGS_LAUNCH_LOG="$work/launch.log" "$launcher" status
grep -Fqx 'ipc' "$work/launch.log"
grep -Fqx -- '--path' "$work/launch.log"
grep -Fqx "$work/home/.config/quickshell/shell.qml" "$work/launch.log"
grep -Fqx 'settings' "$work/launch.log"
grep -Fqx 'status' "$work/launch.log"

if PATH="$work/launcher-bin:$PATH" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
	DWM_SETTINGS_LAUNCH_LOG="$work/launch.log" "$launcher" invalid 2>"$work/launcher.err"; then
	exit 1
fi
grep -Fq 'usage:' "$work/launcher.err"

rm -f "$work/home/.config/quickshell/shell.qml"
if PATH="$work/launcher-bin:$PATH" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
	DWM_SETTINGS_LAUNCH_LOG="$work/launch.log" "$launcher" status 2>"$work/missing-config.err"; then
	exit 1
fi
grep -Fq 'managed Quickshell configuration not found' "$work/missing-config.err"

grep -Fq 'target: "settings"' "$repo/config/quickshell/shell.qml"
grep -Fq 'providerProcess.running = false' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsProviderCommand("discover")' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsDisplayCommand("discover")' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsInputCommand("discover")' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsDisplayCommand("watch", root.watchOwnerArguments())' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsInputCommand("watch", root.watchOwnerArguments())' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'path: "/proc/" + Quickshell.processId.toString() + "/stat"' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.runInput("preview-status", [])' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.runDisplay("preview-status", [])' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'if (!root.visible) root.closeRollbackPending = true;' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'if (!root.previewToken && (displayPreviewStarting || inputPreviewStarting)) {' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.previewKind = "input"; root.previewToken = fields[1]; root.previewOperationLocked = true;' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.previewKind = "display"; root.previewToken = fields[1]; root.previewOperationLocked = true;' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'property var displayUnsupportedProfiles: []' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'readonly property bool displayPersistenceAvailable:' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.settingsModel.displayPersistenceAvailable' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'root.settingsModel.displayUnsupportedProfiles' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'if (!visible) root.confirmation = "";' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'label: "Apply changes"' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'enabled: root.settingsModel.displayState === "ready"' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq '&& root.settingsModel.displayHasPendingChanges' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'readonly property bool displayHasPendingChanges:' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'property bool displayRefreshPending: false' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.displayRefreshPending = true;' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'if (!running && root.displayRefreshPending && root.visible) {' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq '? "Display changes are ready to apply" : outputs.length + " connected outputs";' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'label: root.settingsModel.previewRollbackFailed ? "Keep current" : "Keep changes"' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'onActivated: root.settingsModel.keepPreview()' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'onTextEdited: if (acceptableInput)' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
test "$(grep -Fc 'onTextEdited: if (acceptableInput)' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml")" -eq 2
grep -Fq 'function keepPreview() {' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.runDisplay("keep", [root.previewToken]);' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
if grep -Fq 'keepPreview(root.profileName' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"; then
	printf 'Keeping a display preview must not implicitly save a typed layout name.\n' >&2
	exit 1
fi
grep -Fq 'label: "Use at next login"' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'label: "Restore login backup"' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'the previous dwm-titus next-login layout will be backed up' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
if grep -Fq 'root.profileName = modelData;' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"; then
	printf 'Trying a saved layout must not populate the save target.\n' >&2
	exit 1
fi
if grep -Fq 'label: "Install persistent"' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"; then
	printf 'Displays still exposes implementation-oriented persistence wording.\n' >&2
	exit 1
fi
grep -Fq -- '--no-preview --yes' \
	"$repo/scripts/dwm-settings-display-root"
grep -Fq -- '--tearfree auto --force-full-composition-pipeline auto' \
	"$repo/scripts/dwm-settings-display-root"
grep -Fq 'fields.length >= 10 ? fields[9] : "unsupported"' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'NVIDIA anti-tearing available at next login' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'import QtQuick.Controls as Controls' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'component DisplayComboBox: Controls.ComboBox' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'Accessible.name: accessibleLabel' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'palette.window: Theme.popupBackground' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'highlighted: comboBox.highlightedIndex === index' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'accessibleLabel: "Resolution for " + outputCard.modelData.name' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'root.settingsModel.displayResolutionChoices(outputCard.index)' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'root.settingsModel.setDisplayResolution(outputCard.index, model[index])' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'root.settingsModel.displayRefreshRateChoices(outputCard.index)' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'root.settingsModel.setDisplayRefreshRate(outputCard.index, model[index])' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
grep -Fq 'function displayResolutionChoices(index)' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'const scanVariant = /^([ip])/i.exec(match[3]);' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq '(scanVariant ? scanVariant[1].toLowerCase() : "")' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'function displayRefreshRateChoices(index)' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
if grep -Fq 'cycleDisplayMode' "$repo/config/quickshell/settings/DisplaySettingsPane.qml"; then
	printf 'Display resolution must not be presented as a mode-cycling button.\n' >&2
	exit 1
fi
grep -Fq 'migrate or remove it before installing a managed display profile' \
	"$repo/scripts/dwm-settings-display-root"
grep -Fq 'watch-apply' "$repo/scripts/autostart.sh"
grep -Fq 'displayWatchProcess.running = false' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'inputWatchProcess.running = false' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'stdout: SplitParser { onRead: inputSettleTimer.restart() }' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'root.searchQuery = ""' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'activeFocusOnTab: root.enabled' "$repo/config/quickshell/core/ShellButton.qml"
grep -Fq 'event.key === Qt.Key_Return' "$repo/config/quickshell/core/ShellButton.qml"
grep -Fq 'property bool primary: false' "$repo/config/quickshell/core/ShellButton.qml"
grep -Fq ': root.danger ? (root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill)' \
	"$repo/config/quickshell/core/ShellButton.qml"
grep -Fq 'title: "dwm settings"' "$repo/config/quickshell/settings/SettingsWindow.qml"
grep -Fq 'label: "Settings"' "$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.settingsModel.openOnScreen(targetScreen)' "$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq '{ title="dwm settings",             isfloating=1, alwaysontop=1 }' \
	"$repo/config/window-rules.toml"

fedora_qml=$(bash -c '. "$1"; dwm_packages fedora qml-development' sh \
	"$repo/scripts/dwm-packages.sh")
[ "$fedora_qml" = qt6-qtdeclarative-devel ]
bash -c '. "$1"; dwm_packages fedora runtime-required' sh \
	"$repo/scripts/dwm-packages.sh" | grep -Fx util-linux >/dev/null

if grep -Eq '^[[:space:]]*(sudo|pkexec)([[:space:]]|$)' "$provider"; then
	printf 'Settings discovery must not execute an elevation tool.\n' >&2
	exit 1
fi
grep -Fq "trusted_installed_file \"\$candidate\"" "$provider"
grep -Fq 'provider_available sudo && run_bounded_probe sudo -n -v' "$provider"

if "$repo/scripts/dwm-settings-display-root" rollback 2>"$work/root-helper.err"; then
	printf 'Privileged display helper ran without root authorization.\n' >&2
	exit 1
fi
grep -Fq 'must run through polkit as root' "$work/root-helper.err"

printf 'Settings capability provider and shell contract: PASS\n'
