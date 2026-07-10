import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool userRunning: false
    property bool systemRunning: false
    property bool repairRunning: false
    property bool shareRunning: false
    property bool repairSucceeded: false
    property bool confirming: false
    property bool showIssuesOnly: false
    property string selectedCategory: "overview"
    property string coverageMessage: "Waiting for privileged scan"
    property string repairMessage: ""
    property string repairError: ""
    property var rows: []
    property var pendingRepair: null
    property var targetScreen: null

    readonly property bool busy: root.userRunning || root.systemRunning || root.repairRunning || root.shareRunning
    readonly property var categories: [
        { "id": "overview", "label": "Overview" },
        { "id": "boot", "label": "Boot & Kernel" },
        { "id": "services", "label": "Services" },
        { "id": "resources", "label": "Resources" },
        { "id": "storage", "label": "Storage" },
        { "id": "network", "label": "Network" },
        { "id": "desktop", "label": "Desktop" },
        { "id": "dependencies", "label": "Dependencies" }
    ]
    readonly property var visibleRows: root.rows.filter(function(row) {
        const issue = row.status === "error" || row.status === "warn" || row.status === "restricted";
        if (root.showIssuesOnly && !issue) {
            return false;
        }
        if (root.selectedCategory === "overview") {
            return row.category === "overview" || issue;
        }
        return row.category === root.selectedCategory;
    })

    function openOnScreen(screen) {
        if (screen) {
            root.targetScreen = screen;
        }
        root.visible = true;
        root.refresh();
    }

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        userScanProcess.running = false;
        systemScanProcess.running = false;
        repairProcess.running = false;
        evidenceProcess.running = false;
        root.visible = false;
        root.confirming = false;
        root.pendingRepair = null;
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh() {
        if (root.repairRunning || root.shareRunning) {
            return;
        }
        userScanProcess.running = false;
        systemScanProcess.running = false;
        root.rows = [];
        root.coverageMessage = "Authorizing complete system scan...";
        root.repairMessage = "";
        root.repairError = "";
        root.repairSucceeded = false;
        root.userRunning = true;
        root.systemRunning = true;
        userScanProcess.running = true;
        systemScanProcess.running = true;
    }

    function ingestLine(data) {
        const line = data.trim();
        if (line.length === 0) {
            return;
        }
        const fields = line.split("\t");
        if (fields.length < 10) {
            return;
        }
        const record = {
            "kind": fields[0],
            "category": fields[1],
            "status": fields[2],
            "id": fields[3],
            "title": fields[4],
            "summary": fields[5],
            "evidence": fields[6],
            "repairId": fields[7],
            "repairLabel": fields[8],
            "privilege": fields[9]
        };

        if (record.kind === "meta") {
            if (record.id === "scan-system") {
                root.coverageMessage = record.status === "restricted" ? record.summary : "Privileged scan running...";
                if (record.status === "restricted") {
                    root.markRestricted(record.summary, record.evidence);
                }
            } else if (record.id === "scan-system-complete") {
                root.coverageMessage = "Privileged current-boot scan complete";
            }
            return;
        }
        if (record.kind !== "check") {
            return;
        }

        root.upsertRecord(record);
    }

    function upsertRecord(record) {
        const updated = root.rows.slice();
        let replaced = false;
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].id === record.id) {
                updated[i] = record;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            updated.push(record);
        }
        root.rows = updated;
    }

    function markRestricted(summary, evidence) {
        root.upsertRecord({
            "kind": "check",
            "category": "overview",
            "status": "restricted",
            "id": "privileged-coverage",
            "title": "Privileged diagnostics",
            "summary": summary,
            "evidence": evidence || "Current-boot journal, kernel, system service, and drive checks are incomplete",
            "repairId": "",
            "repairLabel": "",
            "privilege": "system"
        });
    }

    function countStatus(status) {
        let count = 0;
        for (let i = 0; i < root.rows.length; i++) {
            if (root.rows[i].status === status) {
                count++;
            }
        }
        return count;
    }

    function categoryIssueCount(category) {
        let count = 0;
        for (let i = 0; i < root.rows.length; i++) {
            const row = root.rows[i];
            if ((category === "overview" || row.category === category)
                    && (row.status === "error" || row.status === "warn" || row.status === "restricted")) {
                count++;
            }
        }
        return count;
    }

    function overallLabel() {
        if (root.countStatus("error") > 0) {
            return "Critical";
        }
        if (root.countStatus("warn") > 0) {
            return "Needs Attention";
        }
        if (root.countStatus("restricted") > 0 || root.systemRunning) {
            return "Scan Incomplete";
        }
        return root.rows.length > 0 ? "Healthy" : "Scanning";
    }

    function requestRepair(row) {
        if (!row || row.repairId.length === 0 || root.busy) {
            return;
        }
        root.pendingRepair = row;
        root.confirming = true;
        root.repairError = "";
    }

    function requestServiceAction(row, action, label) {
        if (!row || root.busy) {
            return;
        }
        const parts = row.repairId.split("|");
        if (parts.length !== 2 || parts[0].indexOf("manage-") !== 0) {
            return;
        }
        root.pendingRepair = {
            "kind": row.kind,
            "category": row.category,
            "status": row.status,
            "id": row.id,
            "title": row.title,
            "summary": row.summary,
            "evidence": row.evidence,
            "repairId": parts[0] + "|" + action + "|" + parts[1],
            "repairLabel": label + " " + parts[1],
            "privilege": row.privilege
        };
        root.confirming = true;
        root.repairError = "";
    }

    function shareEvidence(row, mode) {
        if (!row || root.busy || (row.id !== "journal-errors" && row.id !== "kernel-errors")) {
            return;
        }
        root.shareRunning = true;
        root.repairMessage = mode === "copy" ? "Copying diagnostics..." : "Exporting diagnostics...";
        root.repairError = "";
        evidenceProcess.command = Commands.systemHealthHelperCommand(
            "share-evidence",
            [mode, row.id, row.title, row.summary, row.evidence]
        );
        evidenceProcess.running = true;
    }

    function cancelRepair() {
        root.confirming = false;
        root.pendingRepair = null;
    }

    function repairImpact(id) {
        if (id.indexOf("manage-") === 0) {
            const parts = id.split("|");
            const action = parts.length > 1 ? parts[1] : "change";
            const unit = parts.length > 2 ? parts[2] : "this service";
            if (action === "enable") {
                return unit + " will be enabled for future starts. It will not be started now.";
            }
            if (action === "disable") {
                return unit + " will be disabled for future starts. It will not be stopped now.";
            }
            if (action === "stop") {
                return unit + " will be stopped for the current session.";
            }
            if (action === "restart") {
                return unit + " will be stopped and started again.";
            }
            return unit + " will be started now.";
        }
        if (id === "restart-networkmanager") {
            return "Network connectivity will drop briefly while NetworkManager restarts.";
        }
        if (id === "restart-bluetooth") {
            return "Connected Bluetooth devices will disconnect briefly.";
        }
        if (id === "repair-time-sync") {
            return "The detected time synchronization provider will be enabled and restarted.";
        }
        if (id === "restart-quickshell") {
            return "Quickshell will restart and this dashboard will close.";
        }
        if (id === "install-dependencies") {
            return "The interactive dependency installer or detailed dependency check will open in a terminal.";
        }
        return "The affected desktop component will be restarted.";
    }

    function confirmRepair() {
        if (!root.pendingRepair || root.repairRunning) {
            return;
        }
        const row = root.pendingRepair;
        root.confirming = false;
        root.pendingRepair = null;
        root.repairRunning = true;
        root.repairSucceeded = false;
        root.repairMessage = "Running " + row.repairLabel + "...";
        root.repairError = "";
        repairProcess.command = Commands.systemHealthHelperCommand(
            row.privilege === "system" ? "repair-privileged" : "repair-user",
            [row.repairId]
        );
        repairProcess.running = true;
    }

    Process {
        id: userScanProcess

        command: Commands.systemHealthHelperCommand("scan-user")
        running: false
        onRunningChanged: {
            if (!running && root.userRunning) {
                root.userRunning = false;
            }
        }

        stdout: SplitParser {
            onRead: function(data) {
                root.ingestLine(data);
            }
        }
    }

    Process {
        id: systemScanProcess

        command: Commands.systemHealthHelperCommand("scan-privileged")
        running: false
        onRunningChanged: {
            if (!running && root.systemRunning) {
                root.systemRunning = false;
            }
            if (!running && root.coverageMessage.indexOf("complete") < 0) {
                root.coverageMessage = "Privileged scan was cancelled or unavailable";
                root.markRestricted(root.coverageMessage, "Use Refresh to retry authorization");
            }
        }

        stdout: SplitParser {
            onRead: function(data) {
                root.ingestLine(data);
            }
        }
    }

    Process {
        id: evidenceProcess

        command: ["sh", "-c", "exit 0"]
        running: false
        onRunningChanged: {
            if (!running && root.shareRunning) {
                root.shareRunning = false;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const message = this.text.trim();
                if (message.length > 0) {
                    root.repairMessage = message;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = this.text.trim();
                root.repairError = message;
                if (message.length > 0) {
                    root.repairMessage = message;
                }
            }
        }
    }

    Process {
        id: repairProcess

        command: ["sh", "-c", "exit 0"]
        running: false
        onRunningChanged: {
            if (!running && root.repairRunning) {
                root.repairRunning = false;
                if (root.repairSucceeded) {
                    root.repairMessage = "Repair completed; rescanning...";
                    Qt.callLater(root.refresh);
                } else {
                    root.repairMessage = root.repairError.length > 0 ? root.repairError : "Repair failed";
                }
            }
        }

        stdout: SplitParser {
            onRead: function(data) {
                if (data.indexOf("repair\t") === 0) {
                    root.repairSucceeded = true;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: root.repairError = this.text.trim()
        }
    }
}
