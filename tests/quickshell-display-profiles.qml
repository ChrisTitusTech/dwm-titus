import QtQuick
import Quickshell
import "settings" as Settings
import "power" as Power

Scope {
    id: root
    Settings.SettingsModel { id: model }
    Power.PowerModel { id: power }
    Settings.DisplaySettingsPane {
        id: pane
        width: 1000; height: 800
        settingsModel: model
        systemBatteryPresent: power.systemBatteryPresent
    }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }
    Timer { interval: 1; running: true; onTriggered: root.runTests() }
    function runTests() {
        try {
            model.parseDisplays("display-protocol\t1\n"
                + "output\teDP-1\t0\t0\t\t0\t0\tnormal\tunsupported\n"
                + "mode\teDP-1\t2560x1600\t90.00\t0\t1\n"
                + "output\tDVI-I-2-2\t1\t1\t2560x1440\t2560\t0\tnormal\tunsupported\n"
                + "mode\tDVI-I-2-2\t2560x1440\t60.00\t1\t1\n"
                + "output\tDVI-I-1-1\t1\t0\t2560x1440\t0\t0\tnormal\tunsupported\n"
                + "mode\tDVI-I-1-1\t2560x1440\t60.00\t1\t1\n");
            const docked = JSON.parse(JSON.stringify(model.displayOutputs));
            const mobile = [{ name: "eDP-1", enabled: true, primary: true, mode: "2560x1600",
                rate: "90.00", x: 0, y: 0, rotation: "normal" }];
            model.automaticDisplayState = { available: true, profiles: [
                { role: "undocked", name: "mobile", saved: true, outputs: mobile, error: "" },
                { role: "docked", name: "docked", saved: true, outputs: docked, error: "" }
            ], detected: ["docked"], current: [], default: "mobile", error: "" };
            const heading = findItem(pane, "automaticDisplayHeading");
            const profiles = findItem(pane, "automaticDisplayProfiles");
            require(heading && profiles, "Automatic display controls exist");
            require(!profiles.visible && !heading.visible, "Desktop hides laptop profiles");
            power.parseSnapshot("power-protocol\t1\t0\nprovider\tpower\tavailable\tuser-session\tTest\npower-system-battery\tyes\n");
            require(profiles.visible && heading.visible, "Physical laptop battery enables profiles");
            pane.saveAutomaticRole = "docked";
            power.parseSnapshot("power-protocol\t1\t0\nprovider\tpower\tavailable\tuser-session\tUPower absent\n");
            require(!profiles.visible && pane.saveAutomaticRole === "", "Service loss closes pending save despite native cache");
            power.parseSnapshot("power-protocol\t1\t0\nprovider\tpower\tavailable\tuser-session\tTest\npower-system-battery\tyes\n");
            require(profiles.visible, "Battery service recovery restores profiles");
            power.parseSnapshot("power-protocol\t1\t0\nprovider\tpower\tavailable\tuser-session\tTest\npower-system-battery\tno\n");
            require(!profiles.visible, "Physical battery removal hides profiles");
            const baseline = model.displayBaseline;
            model.editAutomaticDisplay("undocked");
            require(model.displayEditingRole === "undocked", "Selected editor role");
            require(model.displayOutputs.filter(item => item.enabled).length === 1, "Only builtin enabled in undocked draft");
            require(model.displayOutputs[0].primary && model.displayOutputs[0].mode === "2560x1600", "Restored builtin mode and primary");
            require(model.displayBaseline === baseline && model.displayHasPendingChanges, "Editing does not alter live baseline");
            require(model.previewToken === "" && !model.previewOperationLocked, "Editing cannot start a live preview");
            require(model.automaticDisplayArrangement("docked").tiles.length === 2, "Saved preview independent of draft");
            require(model.automaticDisplaySummary("undocked").indexOf("90.00 Hz") >= 0, "Saved rates visible");
            model.editAutomaticDisplay("docked");
            require(model.displayOutputs.filter(item => item.enabled).length === 2, "Restored dock draft");
            require(!model.displayHasPendingChanges, "Restored dock equals baseline");
            const modes = model.displayModes;
            model.displayModes = [];
            model.displayOutputs = model.displayOutputs.map(item => Object.assign({}, item, { pixelWidth: 800, pixelHeight: 600 }));
            model.editAutomaticDisplay("undocked");
            require(model.displayArrangement.width === 2560, "Saved geometry cannot reuse stale live dimensions");
            model.displayModes = modes;
            model.editAutomaticDisplay("docked");
            model.previewOperationLocked = true;
            model.editAutomaticDisplay("undocked");
            require(model.displayEditingRole === "docked", "Preview locks editing");
            model.previewOperationLocked = false;
            model.displayOutputs = model.displayOutputs.slice(0, 1);
            model.editAutomaticDisplay("docked");
            require(model.automaticDisplayMessage.indexOf("Connect") === 0, "Missing saved monitors block editing");
            console.log("Automatic display draft/model assertions: PASS");
            Qt.quit();
        } catch (error) {
            console.error(error);
            Qt.exit(1);
        }
    }
}
