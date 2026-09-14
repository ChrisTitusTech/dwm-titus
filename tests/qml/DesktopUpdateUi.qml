import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings

ShellRoot {
    id: root
    property int stage: 0
    property int ticks: 0
    property bool sawProgress: false
    property bool progressOpened: false
    property int expireAt: 0
    property int authorizationRequests: 0

    function check(condition, detail) {
        if (!condition) {
            console.error("Desktop UI FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function find(name, item) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = find(name, child);
            if (found) return found;
        }
        return null;
    }

    FileView {
        path: root.stage > 0 ? Quickshell.env("XDG_STATE_HOME") + "/dwm-titus/desktop-update/progress-opened" : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.progressOpened = text().trim() === "opened"
        onFileChanged: reload()
    }
    DesktopUpdateModel {
        id: model
        settingsVisible: true
        onAuthorizationRequested: {
            root.authorizationRequests++;
            window.visible = false;
            model.settingsVisible = false;
        }
    }
    DesktopUpdateModel {
        id: background
        backgroundMonitor: true
        Component.onCompleted: {
            refreshStatus(false);
            refreshStatus(true);
            root.check(discoverAfterStatus, "Opening Settings preserves discovery during startup status read");
        }
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 920
        implicitHeight: 620
        color: "#1b1e28"
        DesktopUpdateControls { id: controls; width: parent.width - 40; x: 20; y: 20; model: model }
    }
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            root.ticks++;
            root.check(root.ticks < 200, "Update UI timeout: stage=" + root.stage + " state=" + model.status.state
                + " busy=" + model.busy + " error=" + model.commandError);
            if (root.stage === 0 && model.canUpdate) {
                root.check(!model.busy, "Update discovery is idle");
                model.systemBusy = true;
                root.check(!model.canUpdate, "Package operation blocks desktop update");
                model.systemBusy = false;
                root.find("prepareDesktopUpdate", controls).requestActivation();
                root.check(model.confirming, "Update button opens confirmation");
                model.confirming = false;
                root.check(!model.active, "Dismissed confirmation makes no change");
                model.prepare();
                root.find("confirmDesktopUpdate", controls).requestActivation();
                root.check(model.updateOwned, "Desktop owns the workflow during dispatch before service progress");
                root.stage = 1;
            } else if (root.stage === 1 && model.active) {
                root.check(!model.canUpdate, "Duplicate update is disabled");
                root.check(root.find("desktopUpdateProgress", controls).visible, "Progress bar is visible");
                root.check(root.find("desktopUpdateProgress", controls).indeterminate, "Build has unknown progress");
                root.check(root.authorizationRequests === 1, "Authorization hides Settings before waiting");
                root.check(!window.visible, "Settings is hidden to reveal the authentication dialog");
                window.visible = true;
                model.settingsVisible = true;
                root.stage = 7;
            } else if (root.stage === 7 && !model.commandPending) {
                root.check(root.authorizationRequests === 1 && window.visible, "Reading the same status does not hide reopened Settings");
                root.check(root.find("revealDesktopUpdateAuthorization", controls).visible, "Prompt reveal is available during authorization");
                model.statusCheckedAt = 0;
                model.refreshStatus(false);
                root.stage = 8;
            } else if (root.stage === 8 && !model.commandPending) {
                root.check(model.statusCheckedAt > 0, "Check status completed while the worker is active");
                root.check(model.active && !model.canUpdate, "Status refresh preserves the active update");
                root.check(root.authorizationRequests === 1, "Status refresh does not repeat authorization");
                root.stage = 2;
            } else if (root.stage === 2 && model.status.state === "verifying") {
                root.check(root.find("desktopUpdateProgress", controls).value === 50, "Measured progress is displayed");
                root.check(background.active, "Background model follows updates with Settings closed");
                root.sawProgress = true;
                model.settingsVisible = false;
                window.visible = false;
                root.stage = 3;
            } else if (root.stage === 3 && model.status.state === "restart-required") {
                root.check(root.sawProgress, "Progress stream was observed while visible");
                root.check(root.progressOpened, "Confirmed update opened the independent progress window");
                model.commandError = "old connection error";
                window.visible = true;
                model.settingsVisible = true;
                root.stage = 4;
            } else if (root.stage === 4 && !model.busy) {
                root.check(model.commandError === "", "No command or parser errors");
                model.check(true);
                root.expireAt = root.ticks + 4;
                root.stage = 5;
            } else if (root.stage === 5 && root.ticks >= root.expireAt) {
                model.expireCommand();
                root.check(model.busy, "Terminating command still blocks another launch");
                root.stage = 6;
            } else if (root.stage === 6 && !model.busy) {
                root.check(model.commandError.indexOf("timed out") >= 0, "Process exit preserves timeout guidance");
                console.info("Desktop update UI: PASS");
                Qt.quit();
            }
        }
    }
}
