import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "CommandMenuCatalog.js" as Catalog

Scope {
    id: root

    required property var launcherModel

    property bool visible: false
    property string query: ""
    property string activeMenu: "root"
    property var targetScreen: null
    property var rows: []
    property var currentEntryIds: []
    property int selectedIndex: 0
    readonly property string breadcrumb: Catalog.breadcrumb(root.activeMenu)
    readonly property string selectedLabel: root.rows.length > 0
        && root.selectedIndex >= 0
        && root.selectedIndex < root.rows.length
        ? root.rows[root.selectedIndex].label : ""

    signal ipcActionRequested(string target, string action, string argument, var screen)

    function applicationEntry(app) {
        return {
            "id": "application:" + app.desktopFile,
            "label": app.name,
            "detail": app.generic.length > 0 ? app.generic : app.comment,
            "kind": "application",
            "actionType": "application",
            "target": "launcher",
            "action": "launch",
            "argument": app.desktopFile,
            "keywords": [app.generic, app.comment, app.keywords, app.categories, app.startupWmClass, app.exec].join(" "),
            "enabled": true,
            "current": false,
            "app": app
        };
    }

    function applicationEntries() {
        const entries = [];

        for (const app of root.launcherModel.apps) {
            entries.push(root.applicationEntry(app));
        }

        return entries;
    }

    function placeholderEntry() {
        const loading = root.launcherModel.status === "Loading applications...";
        return {
            "id": loading ? "apps-loading" : "apps-empty",
            "label": loading ? "Loading applications..." : "No applications found",
            "detail": loading ? "Reading XDG desktop entries" : "No launchable desktop entries matched",
            "kind": "status",
            "enabled": false,
            "current": false
        };
    }

    function applyCurrentStates(entries) {
        for (let index = 0; index < entries.length; index++) {
            entries[index].current = root.currentEntryIds.indexOf(entries[index].id) >= 0;
        }

        return entries;
    }

    function refreshRows() {
        if (!root.visible) {
            root.rows = [];
            root.selectedIndex = 0;
            return;
        }

        const previousId = root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
            ? root.rows[root.selectedIndex].id : "";

        let entries;
        if (root.query.trim().length > 0) {
            entries = Catalog.searchableEntries().concat(root.applicationEntries());
            entries = Catalog.filterAndSort(entries, root.query);
        } else if (root.activeMenu === "apps") {
            entries = root.applicationEntries();
            if (entries.length === 0) entries = [root.placeholderEntry()];
        } else {
            entries = Catalog.entriesFor(root.activeMenu);
        }

        root.rows = root.applyCurrentStates(entries);
        root.selectedIndex = Catalog.restoredSelection(root.rows, previousId);
    }

    function openWindow() {
        const wasVisible = root.visible;

        root.visible = true;
        root.query = "";
        root.activeMenu = "root";
        root.selectedIndex = 0;
        if (!wasVisible) root.launcherModel.acquireApplications();
        root.refreshRows();
    }

    function open() {
        root.targetScreen = null;
        root.openWindow();
    }

    function openOnScreen(screen) {
        root.targetScreen = screen;
        root.openWindow();
    }

    function close() {
        const wasVisible = root.visible;

        root.visible = false;
        root.query = "";
        root.activeMenu = "root";
        root.rows = [];
        root.selectedIndex = 0;
        if (wasVisible) root.launcherModel.releaseApplications();
    }

    function toggle() {
        if (root.visible) root.close(); else root.open();
    }

    function toggleOnScreen(screen) {
        if (root.visible) root.close(); else root.openOnScreen(screen);
    }

    function setQuery(value) {
        root.query = value;
        root.selectedIndex = -1;
        root.refreshRows();
    }

    function selectRelative(delta) {
        if (root.rows.length === 0 || delta === 0) return;

        const direction = delta < 0 ? -1 : 1;
        const steps = Math.abs(delta);
        let index = root.selectedIndex;

        for (let step = 0; step < steps; step++) {
            index = Catalog.nextSelectable(root.rows, index, direction);
        }

        root.selectedIndex = index;
    }

    function selectAbsolute(index) {
        if (root.rows.length === 0) return;

        let candidate = Math.max(0, Math.min(index, root.rows.length - 1));
        if (!Catalog.isSelectable(root.rows[candidate])) {
            candidate = Catalog.nextSelectable(root.rows, candidate, 1);
        }
        root.selectedIndex = candidate;
    }

    function openSubmenu(menuId) {
        root.activeMenu = menuId;
        root.query = "";
        root.selectedIndex = -1;
        root.refreshRows();
    }

    function navigateBack() {
        if (root.query.length > 0) {
            root.setQuery("");
            return true;
        }
        if (root.activeMenu !== "root") {
            root.activeMenu = "root";
            root.selectedIndex = -1;
            root.refreshRows();
            return true;
        }
        return false;
    }

    function runHelper(entry) {
        if (actionProcess.running) return;

        if (entry.target === "screenshot") {
            actionProcess.command = Commands.screenshotHelperCommand(entry.action);
        } else if (entry.target === "lock") {
            actionProcess.command = Commands.lockHelperCommand();
        } else {
            return;
        }

        root.close();
        actionProcess.running = true;
    }

    function activate(entry) {
        if (!Catalog.isSelectable(entry)) return;

        if (entry.kind === "submenu") {
            root.openSubmenu(entry.target);
        } else if (entry.actionType === "application") {
            root.launcherModel.launchApp(entry.app);
            root.close();
        } else if (entry.actionType === "helper") {
            root.runHelper(entry);
        } else if (entry.actionType === "ipc") {
            const actionScreen = root.targetScreen;
            root.close();
            root.ipcActionRequested(entry.target, entry.action, entry.argument || "", actionScreen);
        }
    }

    function activateSelected() {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return;
        root.activate(root.rows[root.selectedIndex]);
    }

    Connections {
        target: root.launcherModel

        function onAppsChanged() {
            root.refreshRows();
        }

        function onStatusChanged() {
            if (root.activeMenu === "apps") root.refreshRows();
        }
    }

    onCurrentEntryIdsChanged: root.refreshRows()

    Process {
        id: actionProcess

        command: ["true"]
        running: false
    }
}
