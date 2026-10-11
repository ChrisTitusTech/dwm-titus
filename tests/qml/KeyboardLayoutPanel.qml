import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.panel
import qs.state

// Runs the real DwmState and PanelSettingsModel against a private X display.
// tests/test-keyboard-layout-panel-xvfb.sh drives it over IPC.
ShellRoot {
    id: root

    property int assertions: 0
    property string parserResult: "pending"

    DwmState { id: dwmState }

    PanelSettingsModel { id: panelSettings }

    PanelSettingsModel { id: parserModel }

    DwmState { id: labelState }

    function check(value, message) {
        root.assertions++;
        if (!value) throw new Error(message);
    }

    function widgets(entries) {
        return entries.map(function(entry) { return "widget\t" + entry; }).join("\n");
    }

    function parse(lines) {
        parserModel.statusParsed = false;
        parserModel.parseStatus(lines.join("\n") + "\n");
        return parserModel.statusParsed;
    }

    function runParserChecks() {
        const state = "state\tavailable\tPersistent panel visibility is active for every monitor";
        const legacy = ["workspaces\tenabled", "volume\tdisabled", "bluetooth\tenabled",
            "network\tenabled", "power\tenabled"];
        try {
            // Current helper: six widgets, 1.1 with the seconds option.
            root.check(root.parse(["panel-settings-protocol\t1\t1", state,
                root.widgets(legacy.concat(["keyboard-layout\tdisabled"])),
                "option\tclock-seconds\tenabled", "complete\tstatus"]), "six widgets parse");
            root.check(parserModel.widgetEnabled("keyboard-layout") === false, "keyboard-layout disabled kept");
            root.check(parserModel.widgetEnabled("volume") === false, "volume disabled kept");
            root.check(parserModel.optionEnabled("clock-seconds") === true, "clock-seconds kept with six widgets");
            // Older helper (clock-seconds branch): five widgets, 1.1.
            root.check(root.parse(["panel-settings-protocol\t1\t1", state, root.widgets(legacy),
                "option\tclock-seconds\tenabled", "complete\tstatus"]), "five widgets 1.1 parse");
            root.check(parserModel.widgetEnabled("keyboard-layout") === true, "missing keyboard-layout defaults on");
            root.check(parserModel.optionEnabled("clock-seconds") === true, "clock-seconds kept with five widgets");
            // Older helper from before options: five widgets, 1.0.
            root.check(root.parse(["panel-settings-protocol\t1\t0", state, root.widgets(legacy),
                "complete\tstatus"]), "five widgets 1.0 parse");
            root.check(parserModel.widgetEnabled("keyboard-layout") === true, "1.0 keyboard-layout defaults on");
            root.check(parserModel.optionEnabled("clock-seconds") === false, "1.0 has no seconds option");
            // Corrupt: a legacy widget replaced by keyboard-layout.
            root.check(!root.parse(["panel-settings-protocol\t1\t0", state,
                root.widgets(legacy.slice(0, 4).concat(["keyboard-layout\tenabled"])), "complete\tstatus"]),
                "missing legacy widget rejected");
            // Corrupt: duplicate widget.
            root.check(!root.parse(["panel-settings-protocol\t1\t0", state,
                root.widgets(legacy.concat(["volume\tenabled"])), "complete\tstatus"]), "duplicate widget rejected");
            // Corrupt: 1.1 without its option line.
            root.check(!root.parse(["panel-settings-protocol\t1\t1", state,
                root.widgets(legacy.concat(["keyboard-layout\tenabled"])), "complete\tstatus"]),
                "1.1 without option rejected");
            // Corrupt: unknown widget.
            root.check(!root.parse(["panel-settings-protocol\t1\t0", state,
                root.widgets(legacy.concat(["keyboard\tenabled"])), "complete\tstatus"]), "unknown widget rejected");
            // Labels: codes first, then group names, then numbers.
            labelState.parseState("keyboard_group=1\nkeyboard_groups=3\nkeyboard_names=English (US)|German|\nkeyboard_layouts=us||\n");
            root.check(labelState.keyboardLabel(0) === "US", "code label");
            root.check(labelState.keyboardLabel(1) === "GE", "name fallback label");
            root.check(labelState.keyboardLabel(2) === "3", "number fallback label");
            root.check(labelState.keyboardName(2) === "Layout 3", "name fallback");
            // A partial keyboard block leaves the rest of the state alone.
            labelState.parseState("current=4\ntitle=Kept\n");
            labelState.parseState("keyboard_group=2\nkeyboard_groups=3\n");
            root.check(labelState.currentWorkspace === 4 && labelState.activeWindowTitle === "Kept",
                "keyboard block keeps workspace state");
            root.check(labelState.keyboardGroup === 2 && labelState.keyboardNames[1] === "German",
                "keyboard block keeps names");
            root.parserResult = "PASS";
            console.log("Keyboard layout QML checks: PASS (" + root.assertions + " assertions)");
        } catch (error) {
            root.parserResult = "FAIL " + error.message;
            console.log("Keyboard layout QML checks FAILED: " + error.message);
        }
    }

    Timer {
        // The parser model loads its own status first; run the fixtures after.
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (parserModel.initialLoading) return;
            running = false;
            root.runParserChecks();
        }
    }

    IpcHandler {
        target: "kbdtest"

        function parser(): string {
            return root.parserResult;
        }

        function state(): string {
            return JSON.stringify({
                "group": dwmState.keyboardGroup,
                "count": dwmState.keyboardGroupCount,
                "label": dwmState.keyboardLabel(dwmState.keyboardGroup),
                "layouts": dwmState.keyboardLayouts.join(","),
                "summary": dwmState.keyboardSummary()
            });
        }

        function label(): string {
            return dwmState.keyboardGroupCount + ":" + dwmState.keyboardLabel(dwmState.keyboardGroup);
        }

        function cycle(step: int): void {
            dwmState.cycleKeyboardLayout(step);
        }

        function select(index: int): void {
            dwmState.setKeyboardLayout(index);
        }

        function widget(): string {
            return panelSettings.widgetEnabled("keyboard-layout") ? "on" : "off";
        }
    }
}
