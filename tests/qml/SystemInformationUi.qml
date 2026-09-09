import QtQuick
import Quickshell
import qs.core
import qs.settings

ShellRoot {
    id: root
    property int assertions: 0
    property int stage: 0
    property bool done: false
    readonly property bool manual: Quickshell.env("DWM_INFORMATION_UI_MANUAL") === "1"
    function check(condition, message) {
        assertions++;
        if (!condition) {
            done = true;
            console.error("Information UI FAILED: " + message);
            Qt.callLater(Qt.quit);
            throw new Error(message);
        }
    }
    function find(name, parent) {
        if (parent.objectName === name) return parent;
        for (const child of parent.children || []) {
            const result = find(name, child);
            if (result !== null) return result;
        }
        return null;
    }
    function item(name) {
        const result = find(name, window.contentItem);
        check(result !== null, "Component exists: " + name);
        return result;
    }
    function advance() {
        if (done) return;
        if (stage === 0 && content.height > 500) {
            stage = 1;
            check(item("systemFilesystems").count === 256, "Maximum mount inventory renders");
            check(item("systemFilesystems").height <= 240, "Mount inventory has bounded viewport");
            check(item("systemFilesystems").contentItem.children.length < 256, "Mount inventory remains virtualized");
            check(item("information-value-memory-total-bytes").text.indexOf("18446744073709551615 bytes") >= 0,
                "Exact uint64 string retained in rendered detail");
            check(item("information-value-secure-boot").text === "Unknown", "Unknown status never claims disabled");
            check(item("information-value-selinux").text === "enforcing", "Peer security state remains readable");
            model.filesystemsRetained = true;
            item("openSystemHealth").forceActiveFocus();
        } else if (stage === 1 && item("openSystemHealth").activeFocus) {
            stage = 2;
            check(item("filesystemFreshness").text.indexOf("may be stale") >= 0, "Retained mount data has explicit stale guidance");
            const button = item("openSystemHealth");
            const position = button.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + button.height <= pane.height + 1, "Keyboard focus is revealed at current viewport size");
            button.requestActivation();
            check(model.openCount === 1, "Health navigation has one fixed callback");
            model.actions = [];
        } else if (stage === 2) {
            check(!item("openSystemHealth").enabled, "Missing health capability disables navigation");
            item("openSystemHealth").requestActivation();
            check(model.openCount === 1, "Disabled control cannot navigate");
            check(item("systemFilesystems").count === 256, "Missing health capability preserves readable storage");
            if (manual) {
                model.actions = [{id: "health-open", availability: "available", detail: "Open a read-only scan; repairs need separate confirmation."}];
                model.filesystems = model.filesystems.slice(0, 3);
                stage = 3;
                const section = Quickshell.env("DWM_INFORMATION_UI_SECTION");
                Qt.callLater(function() {
                    pane.contentY = section === "storage" ? item("filesystemFreshness").mapToItem(content, 0, 0).y
                        : section === "security" ? item("information-value-selinux").mapToItem(content, 0, 0).y - 90
                        : section === "recovery" ? pane.contentHeight - pane.height : 0;
                    console.info("Information UI manual fixture ready");
                });
                return;
            }
            done = true;
            console.info("Information UI tests: PASS (" + assertions + " assertions)");
            Qt.quit();
        }
    }
    QtObject {
        id: model
        property int openCount: 0
        property var actions: [{id: "health-open", availability: "available", detail: "Open a read-only scan; repairs need separate confirmation."}]
        property bool filesystemsRetained: false
        property var filesystems: Array.from({length: 256}, (_, index) => ({id: String(index), status: "available",
            source: "/dev/fixture-" + index, target: "/mnt/fixture-" + index, fstype: "ext4",
            sizeBytes: "18446744073709551615", usedBytes: "1073741824", availableBytes: "2147483648", detail: "Fixture filesystem bytes at this read"}))
        function nativeStateView(identifier) {
            if (identifier === "secure-boot") return {status: "partial", value: "unknown", detail: "Firmware evidence unavailable"};
            const values = {"os-name": "Fedora Linux 44 (Fixture)", "os-version": "44", "kernel-release": "6.18.fixture",
                architecture: "x86_64", "hardware-vendor": "Fixture vendor", "hardware-model": "Fixture workstation",
                "cpu-model": "Fixture CPU", "logical-cpus": "16", "uptime-seconds": "94231", "selinux": "enforcing",
                "firewalld": "enabled", "root-encryption": "encrypted", "screen-lock": "enabled"};
            return {status: "available", value: values[identifier] || "18446744073709551615", detail: "Read-only fixture observation"};
        }
        function nativeProviderView(owner) { return {status: "available", detail: "Bounded read-only " + owner + " observations"}; }
        function openHealth() { openCount++; }
    }
    Window {
        id: window
        visible: true
        title: "Phase 6 information fixture"
        width: Number(Quickshell.env("DWM_INFORMATION_UI_WIDTH") || "780")
        height: Number(Quickshell.env("DWM_INFORMATION_UI_HEIGHT") || "580")
        color: Theme.menuBackground
        Flickable {
            id: pane
            anchors.fill: parent
            anchors.margins: 16
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            SystemInformationControls {
                id: content
                width: pane.width
                model: model
                onRevealRequested: target => {
                    const position = target.mapToItem(content, 0, 0);
                    pane.contentY = Math.max(0, Math.min(position.y + target.height - pane.height, pane.contentHeight - pane.height));
                }
            }
        }
    }
    Timer { interval: 30; repeat: true; running: !root.done; onTriggered: root.advance() }
    Timer { interval: 10000; running: !root.manual; onTriggered: { console.error("Information UI FAILED: timeout stage " + root.stage); Qt.quit(); } }
}
