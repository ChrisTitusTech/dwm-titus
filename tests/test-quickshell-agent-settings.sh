#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell_qml=$repo/config/quickshell/shell.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
agent_model=$repo/config/quickshell/settings/AgentSettingsModel.qml
agent_pane=$repo/config/quickshell/settings/AgentSettingsPane.qml
commands=$repo/config/quickshell/core/Commands.qml
agent=$repo/scripts/dwm-agent

# Wiring: one model, a registered section and a deferred pane.
test "$(grep -c 'AgentSettingsModel {' "$shell_qml")" -eq 1
grep -Fq 'settingsVisible: settingsModel.visible && settingsModel.selectedSectionId === "agent"' "$shell_qml"
grep -Fq 'agentModel: agentModel' "$shell_qml"
grep -Fq '{ "id": "agent", "label": "AI assistant",' "$settings_model"
grep -Fq 'required property var agentModel' "$settings_window"
grep -Fq 'AgentSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "agent"' "$settings_window"
grep -Fq 'dataLoading: root.agentModel.initialLoading' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId !== "agent"' "$settings_window"

# Helpers go through the managed command resolver.
grep -Fq 'helperCommand("dwm-agent", action, args, true)' "$commands"
grep -Fq 'helperCommand("dwm-terminal", "-e", agentCommand(action, args), true)' "$commands"
grep -Fq 'Commands.checkedCommand(Commands.agentCommand("list", []))' "$agent_model"
grep -Fq 'Commands.checkedCommand(Commands.agentCommand("status", []))' "$agent_model"
grep -Fq 'Commands.checkedCommand(Commands.agentCommand(action, args))' "$agent_model"
grep -Fq 'root.runAction("set", [name, enabled ? "on" : "off"])' "$agent_model"
grep -Fq 'root.runAction("default", [name])' "$agent_model"
grep -Fq 'Quickshell.execDetached(Commands.agentTerminalCommand(action, [name]))' "$agent_model"
grep -Fq 'if (fields[0] !== "agent" || fields.length < 7) continue;' "$agent_model"
grep -Fq 'root.refresh();' "$agent_model"
if grep -Eq 'Timer|repeat:' "$agent_model"; then
	printf 'The AI assistant model must not poll.\n' >&2
	exit 1
fi

# One card per listed agent with state badges and per-agent actions.
grep -Fq 'SectionLabel { label: "Agents" }' "$agent_pane"
grep -Fq 'model: root.agentModel.agents' "$agent_pane"
grep -Fq '"Installed" : "Not installed"' "$agent_pane"
grep -Fq '"Signed in"' "$agent_pane"
grep -Fq '"Not signed in"' "$agent_pane"
grep -Fq 'label: "Default"' "$agent_pane"
grep -Fq 'label: "Install..."' "$agent_pane"
grep -Fq 'visible: !agentCard.modelData.installed' "$agent_pane"
grep -Fq 'root.agentModel.openTerminal("setup", agentCard.modelData.name)' "$agent_pane"
grep -Fq 'label: "Sign in..."' "$agent_pane"
grep -Fq 'visible: agentCard.modelData.installed && !agentCard.signedIn' "$agent_pane"
grep -Fq 'root.agentModel.openTerminal("login", agentCard.modelData.name)' "$agent_pane"
grep -Fq 'label: "Make default"' "$agent_pane"
grep -Fq 'visible: agentCard.modelData.installed && !agentCard.modelData.isDefault' "$agent_pane"
grep -Fq 'root.agentModel.makeDefault(agentCard.modelData.name)' "$agent_pane"
grep -Fq 'Press Refresh when they finish' "$agent_pane"
if grep -Fq 'label: "Set up..."' "$agent_pane"; then
	printf 'The generic Set up button was replaced by per-agent Install.\n' >&2
	exit 1
fi
grep -Fq 'title: "Crash notifications"' "$agent_pane"
grep -Fq 'title: "Hang detection"' "$agent_pane"
grep -Fq 'dwm checks every few seconds that windows still answer and tells you when one stops for 10 seconds. ' "$agent_pane"
grep -Fq 'Games, virtual machines and apps that are busy on purpose can show up as not responding when they are fine.' "$agent_pane"
grep -Fq 'setToggle("crash-notifications"' "$agent_pane"
grep -Fq 'setToggle("hang-detection"' "$agent_pane"
grep -Fq 'PanelToggleSwitch {' "$agent_pane"

# Backend: `dwm-agent set` creates and removes the toggle files.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
run_agent() {
	env HOME="$work/home" XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" \
		PATH=/usr/bin:/bin "$agent" "$@"
}
expect_status() {
	run_agent status | grep -Fqx "$(printf '%s\t%s' "$1" "$2")" || {
		printf 'Expected %s %s in dwm-agent status\n' "$1" "$2" >&2
		exit 1
	}
}

expect_status crash-notifications on
expect_status hang-detection off
run_agent set hang-detection on
test -e "$work/config/dwm-titus/hang-detection"
expect_status hang-detection on
run_agent set crash-notifications off
test -e "$work/config/dwm-titus/crash-notifications-off"
expect_status crash-notifications off
run_agent set hang-detection off
test ! -e "$work/config/dwm-titus/hang-detection"
expect_status hang-detection off
run_agent set crash-notifications on
test ! -e "$work/config/dwm-titus/crash-notifications-off"
expect_status crash-notifications on
if run_agent set hang-detection maybe 2>/dev/null; then
	printf 'dwm-agent set accepted an invalid value\n' >&2
	exit 1
fi
if run_agent set unknown on 2>/dev/null; then
	printf 'dwm-agent set accepted an unknown setting\n' >&2
	exit 1
fi
run_agent --help | grep -Fq 'dwm-agent set <crash-notifications|hang-detection> <on|off>'

# `dwm-agent list` is the row contract the pane parses: seven fields per agent.
# The fake bin directory holds a stand-in agent; real host agents may also be
# found on /usr/bin, so only the fake agent's exact row is pinned.
mkdir -p "$work/bin"
list_env() {
	env HOME="$work/home" XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" \
		MISE_DATA_DIR="$work/mise" PATH="$work/bin:/usr/bin:/bin" "$agent" "$@"
}
list_output=$(list_env list)
test "$(printf '%s\n' "$list_output" | wc -l)" -eq 6
printf '%s\n' "$list_output" | awk -F '\t' 'NF != 7 || $1 != "agent" { exit 1 }'
for name in codex opencode gemini claude cursor-agent hermes; do
	printf '%s\n' "$list_output" | awk -F '\t' -v name="$name" '$2 == name { found = 1 } END { exit !found }'
done
printf '%s\n' "$list_output" | awk -F '\t' '$7 != "no" { exit 1 }'

printf '#!/bin/sh\necho opencode 1.2.3\n' >"$work/bin/opencode"
chmod +x "$work/bin/opencode"
list_env list | grep -Fqx "$(printf 'agent\topencode\tOpenCode\tyes\t1.2.3\tno\tno')"
list_env default opencode
list_env list | grep -Fqx "$(printf 'agent\topencode\tOpenCode\tyes\t1.2.3\tno\tyes')"
list_env list | awk -F '\t' '$2 != "opencode" && $7 != "no" { exit 1 }'

# Install and sign-in terminals must not open behind the Settings window.
grep -Fq 'root.terminalOpened();' "$repo/config/quickshell/settings/AgentSettingsModel.qml"
grep -Fq 'onTerminalOpened: settingsModel.close()' "$repo/config/quickshell/shell.qml"

printf 'Quickshell AI assistant settings contract: PASS\n'
