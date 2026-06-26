pragma Singleton

import Quickshell

Singleton {
    function launcherIcon(iconName) {
        if (iconName.length > 0) {
            return Quickshell.iconPath(iconName, true);
        }

        return Quickshell.iconPath("application-x-executable", true);
    }

    function trayIconSource(trayItem) {
        const icon = trayItem && trayItem.icon;

        if (typeof icon !== "string" && !(icon instanceof String)) {
            return "";
        }

        if (icon.length === 0) {
            return "";
        }

        if (icon.indexOf("?path=") >= 0) {
            const parts = icon.split("?path=");

            if (parts.length !== 2) {
                return icon;
            }

            let fileName = parts[0].substring(parts[0].lastIndexOf("/") + 1);

            if (fileName.indexOf("dropboxstatus") === 0) {
                fileName = "hicolor/16x16/status/" + fileName;
            }

            return "file://" + parts[1] + "/" + fileName;
        }

        if (icon.indexOf("/") === 0 && icon.indexOf("file://") !== 0) {
            return "file://" + icon;
        }

        return icon;
    }
}
