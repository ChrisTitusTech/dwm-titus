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

base_bin=$work/base-bin
fedora_bin=$work/fedora-bin
make_tools "$base_bin" dirname awk tr stat find grep
cp -a "$base_bin" "$fedora_bin"

for command_name in xrandr nmcli bluetoothctl pactl xset gsettings light-locker \
	xdg-settings xdg-mime pkexec sudo; do
	make_stub "$fedora_bin/$command_name"
done

mkdir -p "$work/fedora-config/dwm-titus" "$work/debian-config/dwm-titus"
cp "$repo/config/themes.toml" "$work/fedora-config/dwm-titus/themes.toml"
cp "$repo/config/themes.toml" "$work/debian-config/dwm-titus/themes.toml"

cat >"$work/fedora-os-release" <<'EOF'
ID=fedora
ID_LIKE="rhel"
PRETTY_NAME="Fedora Linux 44"
EOF

fedora_output=$(PATH="$fedora_bin" XDG_CONFIG_HOME="$work/fedora-config" \
	DWM_SETTINGS_OS_RELEASE="$work/fedora-os-release" "$provider" discover)
printf '%s\n' "$fedora_output" | grep -Fqx 'settings-protocol	1'
printf '%s\n' "$fedora_output" | grep -Fqx 'platform	fedora	rhel	Fedora Linux 44'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	displays	randr	Display discovery	available	read-only	xrandr	RandR display state is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	input	input-devices	Input devices	unsupported	user-session	xinput	Input device settings begin in Phase 2'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	network	networkmanager	NetworkManager	available	delegated	nmcli	NetworkManager state is available'
printf '%s\n' "$fedora_output" | grep -Fqx \
	'capability	audio	pipewire-audio	Audio	available	user-session	pactl	PipeWire Pulse-compatible session controls are available'
printf '%s\n' "$fedora_output" | grep -Eq \
	'^capability	system	authorization	Administrative authorization	(available|restricted)	privileged	polkit	'

cat >"$work/debian-os-release" <<'EOF'
ID=debian
PRETTY_NAME="Debian GNU/Linux 13"
EOF

debian_output=$(PATH="$base_bin" XDG_CONFIG_HOME="$work/debian-config" \
	DWM_SETTINGS_OS_RELEASE="$work/debian-os-release" "$provider" discover)
printf '%s\n' "$debian_output" | grep -Fqx 'platform	debian	debian	Debian GNU/Linux 13'
printf '%s\n' "$debian_output" | grep -Fqx \
	'capability	network	networkmanager	NetworkManager	unavailable	delegated	nmcli	Install and start NetworkManager to enable this section'
printf '%s\n' "$debian_output" | grep -Fqx \
	'capability	bluetooth	bluez	Bluetooth	unavailable	delegated	bluetoothctl	Install BlueZ tools and start Bluetooth to enable this section'
printf '%s\n' "$debian_output" | grep -Fqx \
	'capability	system	authorization	Administrative authorization	restricted	privileged	polkit	Read-only state remains available; install the trusted system helper for authorized actions'

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

grep -Fq 'target: "settings"' "$repo/config/quickshell/shell.qml"
grep -Fq 'providerProcess.running = false' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'Commands.settingsProviderCommand("discover")' "$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'title: "dwm settings"' "$repo/config/quickshell/settings/SettingsWindow.qml"
grep -Fq 'label: "Settings  >"' "$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.settingsModel.open()' "$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq '{ title="dwm settings",             isfloating=1, alwaysontop=1 }' \
	"$repo/config/window-rules.toml"

arch_qml=$(bash -c '. "$1"; dwm_packages arch qml-development' sh \
	"$repo/scripts/dwm-packages.sh")
rhel_qml=$(bash -c '. "$1"; dwm_packages rhel qml-development' sh \
	"$repo/scripts/dwm-packages.sh")
debian_qml=$(bash -c '. "$1"; dwm_packages debian qml-development' sh \
	"$repo/scripts/dwm-packages.sh")
[ "$arch_qml" = qt6-declarative ]
[ "$rhel_qml" = qt6-qtdeclarative-devel ]
[ "$debian_qml" = qt6-declarative-dev-tools ]

if grep -Eq '^[[:space:]]*(sudo|pkexec)([[:space:]]|$)' "$provider"; then
	printf 'Settings discovery must not execute an elevation tool.\n' >&2
	exit 1
fi

printf 'Settings capability provider and shell contract: PASS\n'
