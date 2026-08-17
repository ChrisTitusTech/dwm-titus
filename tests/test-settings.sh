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

base_bin=$work/base-bin
fedora_bin=$work/fedora-bin
make_tools "$base_bin" dirname awk tr stat find grep timeout readlink
cp -a "$base_bin" "$fedora_bin"

for command_name in xrandr nmcli bluetoothctl pactl xset gsettings light-locker \
	xdg-settings xdg-mime xinput; do
	make_stub "$fedora_bin/$command_name"
done
make_failing_stub "$fedora_bin/pkexec"
make_failing_stub "$fedora_bin/sudo"

mkdir -p "$work/fedora-config/dwm-titus" "$work/unsupported-config/dwm-titus"
cp "$repo/config/themes.toml" "$work/fedora-config/dwm-titus/themes.toml"
cp "$repo/config/themes.toml" "$work/unsupported-config/dwm-titus/themes.toml"

printf 'ID=fedora\nID_LIKE="rhel"\nPRETTY_NAME="Fedora\tLinux 44"\n' \
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
printf '%s\n' "$fedora_output" | grep -Eq \
	'^capability	system	authorization	Administrative authorization	(available|restricted)	privileged	polkit	'

cat >"$work/unsupported-os-release" <<'EOF'
ID=example
ID_LIKE="fedora rhel"
PRETTY_NAME="Unsupported Linux"
EOF

unsupported_output=$(PATH="$base_bin" XDG_CONFIG_HOME="$work/unsupported-config" \
	DWM_SETTINGS_OS_RELEASE="$work/unsupported-os-release" "$provider" discover)
printf '%s\n' "$unsupported_output" | grep -Fqx 'platform	example	unknown	Unsupported Linux'
printf '%s\n' "$unsupported_output" | grep -Fqx \
	'capability	network	networkmanager	NetworkManager	unavailable	delegated	nmcli	Install NetworkManager to enable this section'
printf '%s\n' "$unsupported_output" | grep -Fqx \
	'capability	bluetooth	bluez	Bluetooth	unavailable	delegated	bluetoothctl	Install BlueZ tools to enable this section'
printf '%s\n' "$unsupported_output" | grep -Fqx \
	'capability	system	authorization	Administrative authorization	restricted	privileged	polkit	Read-only state remains available; install the trusted system helper for authorized actions'

runtime_down_bin=$work/runtime-down-bin
cp -a "$fedora_bin" "$runtime_down_bin"
for command_name in xrandr nmcli bluetoothctl pactl xset; do
	make_failing_stub "$runtime_down_bin/$command_name"
done
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
grep -Fq -- '--no-preview --yes' \
	"$repo/scripts/dwm-settings-display-root"
grep -Fq -- '--tearfree auto --force-full-composition-pipeline auto' \
	"$repo/scripts/dwm-settings-display-root"
grep -Fq 'fields.length >= 10 ? fields[9] : "unsupported"' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'NVIDIA full composition on persistent install' \
	"$repo/config/quickshell/settings/DisplaySettingsPane.qml"
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
if bash -c '. "$1"; dwm_packages unsupported runtime-required' sh \
	"$repo/scripts/dwm-packages.sh"; then
	printf 'Unsupported package family unexpectedly resolved.\n' >&2
	exit 1
fi

if grep -Eq '^[[:space:]]*(sudo|pkexec)([[:space:]]|$)' "$provider"; then
	printf 'Settings discovery must not execute an elevation tool.\n' >&2
	exit 1
fi

if "$repo/scripts/dwm-settings-display-root" rollback 2>"$work/root-helper.err"; then
	printf 'Privileged display helper ran without root authorization.\n' >&2
	exit 1
fi
grep -Fq 'must run through polkit as root' "$work/root-helper.err"

printf 'Settings capability provider and shell contract: PASS\n'
