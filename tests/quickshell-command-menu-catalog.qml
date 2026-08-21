import QtQml
import "../config/quickshell/launcher/CommandMenuCatalog.js" as Catalog

QtObject {
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }

    Component.onCompleted: {
        try {
            const rootEntries = Catalog.entriesFor("root");
            require(rootEntries.length === 10, "root taxonomy must contain ten entries");
            require(rootEntries[0].label === "Apps", "Apps must lead the root menu");
            require(rootEntries[0].provider === "applications", "Apps must declare its dynamic provider");
            require(Catalog.entriesFor(rootEntries[0].target).length === 0, "dynamic Apps submenu must resolve in the catalog");
            require(rootEntries[9].label === "System", "System must close the root menu");

            const screenshotEntries = Catalog.entriesFor("screenshots");
            require(screenshotEntries.length === 4, "all screenshot modes must be exposed");
            require(screenshotEntries[0].actionType === "helper", "screenshots must use typed helpers");

            const searchable = Catalog.searchableEntries().concat([{
                "id": "application:firefox.desktop",
                "label": "Firefox",
                "detail": "Web Browser",
                "keywords": "internet network",
                "kind": "application",
                "enabled": true
            }]);
            const matches = Catalog.filterAndSort(searchable, "fire");
            require(matches.length > 0 && matches[0].label === "Firefox", "application search must rank prefix matches first");

            const disabledRows = [
                { "label": "Loading", "kind": "status", "enabled": false },
                { "label": "Network", "kind": "action", "enabled": true }
            ];
            require(Catalog.firstSelectable(disabledRows) === 1, "disabled rows must not receive selection");
            require(Catalog.nextSelectable(disabledRows, 1, 1) === 1, "navigation must skip disabled rows");
            const refreshedRows = [
                { "id": "network", "kind": "action", "enabled": true },
                { "id": "audio", "kind": "action", "enabled": true }
            ];
            require(Catalog.restoredSelection(refreshedRows, "audio") === 1,
                "refresh must preserve a selectable entry by stable id");
            require(Catalog.restoredSelection(refreshedRows, "missing") === 0,
                "refresh must fall back when the prior entry disappeared");
            require(Catalog.breadcrumb("screenshots") === "Commands / Screenshots", "submenu breadcrumb must be stable");
        } catch (error) {
            console.error("Command menu catalog test failed: " + error);
            Qt.exit(1);
            return;
        }

        Qt.exit(0);
    }
}
