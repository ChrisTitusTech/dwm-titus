import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

ShellRoot {
    id: root
    property string scenario: Quickshell.env("DWM_CAPTURE_SCENARIO")
    property int assertions: 0

    function check(value, detail) {
        assertions++;
        if (!value) {
            console.error("Checked command FAILED: " + scenario + ": " + detail);
            throw new Error(detail);
        }
    }

    Component.onCompleted: Qt.callLater(function() {
        const command = Commands.terminatingCheckedCommand([
            Quickshell.env("DWM_CAPTURE_HELPER"), "fixture-helper"]);
        // Instrument only the fixture: allocation/child commands target the
        // exact wrapper process, not Quickshell or another host process.
        command[2] = "export DWM_CAPTURE_PARENT=$$\n" + command[2];
        process.command = command;
        process.running = true;
    })

    Process {
        id: process
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errorOutput }
        onExited: (code, status) => {
            const canceled = ["first-term", "second-term", "stop-child"].indexOf(root.scenario) >= 0;
            const expected = canceled ? 143 : root.scenario === "success" ? 0 : 1;
            root.check(status === 0 && code === expected, "Normal expected exit, got " + code + "/" + status);
            root.check(output.text === (root.scenario === "success" ? "fixture-output\n" : ""),
                "Only successful helper output is published");
            root.check(errorOutput.text === (["success", "helper-fail"].indexOf(root.scenario) >= 0 ? "fixture-error\n" : ""),
                "Expected bounded helper diagnostics");
            console.info("Checked command tests: PASS (" + root.scenario + ", " + root.assertions + " assertions)");
            Qt.quit();
        }
    }
    Timer {
        interval: 5000; running: true
        onTriggered: { console.error("Checked command FAILED: fixture timeout"); Qt.quit(); }
    }
}
