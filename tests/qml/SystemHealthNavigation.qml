import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property var activePanelScreen: "panel-a"
    property int assertions: 0
    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Health navigation FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function navigate(expected) {
        settingsModel.visible = true;
        model.settingsVisible = true;
        root.check(model.openHealth(), "Available navigation is accepted");
        root.check(health.screen === expected, "Health follows the Settings screen: " + expected);
        root.check(!settingsModel.visible, "Navigation closes Settings");
    }
    function run() {
        model.actions = [{ id: "health-open", availability: "available" }];
        root.navigate("window-a");
        settingsWindow.screen = "window-moved";
        root.navigate("window-moved");
        settingsWindow.screen = null;
        root.navigate("requested-b");
        settingsModel.targetScreen = null;
        root.navigate("panel-a");
        root.activePanelScreen = "panel-b";
        root.navigate("panel-b");
        console.info("Health navigation tests: PASS (" + root.assertions + " assertions)");
        Qt.quit();
    }
    QtObject { id: settingsWindow; property var screen: "window-a" }
    QtObject {
        id: settingsModel
        property var targetScreen: "requested-b"
        property bool visible: false
        function close() { visible = false; }
    }
    QtObject {
        id: health
        property var screen: null
        function openOnScreen(value) { screen = value; }
    }
    SystemManagementModel {
        id: model
        healthModel: health
        targetScreen: null // Inject the production shell binding before loading.
        onHealthOpened: settingsModel.close()
        snapshotOwned: true
    }
    Component.onCompleted: Qt.callLater(root.run)
}
