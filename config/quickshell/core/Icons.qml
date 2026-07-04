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
        const sources = trayIconSources(trayItem);
        return sources.length > 0 ? sources[0] : "";
    }

    function addIconSource(sources, source) {
        if (source.length === 0) {
            return;
        }

        if (sources.indexOf(source) < 0) {
            sources.push(source);
        }
    }

    function addThemeFallbacks(sources, iconName) {
        if (iconName === "dialog-password") {
            addIconSource(sources, "file:///usr/share/icons/Adwaita/symbolic/status/dialog-password-symbolic.svg");
            addIconSource(sources, "file:///usr/share/icons/AdwaitaLegacy/24x24/legacy/dialog-password.png");
            addIconSource(sources, "image://icon/dialog-password-symbolic");
        } else if (iconName === "flameshot-tray") {
            addIconSource(sources, "file:///usr/share/icons/hicolor/48x48/apps/flameshot.png");
            addIconSource(sources, "file:///usr/share/icons/hicolor/scalable/apps/flameshot.svg");
            addIconSource(sources, "image://icon/flameshot-tray-symbolic");
            addIconSource(sources, "image://icon/flameshot");
            addIconSource(sources, "image://icon/org.flameshot.Flameshot");
        } else if (iconName === "steam_tray_mono") {
            addIconSource(sources, "file:///usr/share/pixmaps/steam_tray_mono.png");
        }
    }

    function trayIconSources(trayItem) {
        const icon = trayItem && trayItem.icon;
        const sources = [];

        if (typeof icon !== "string" && !(icon instanceof String)) {
            return sources;
        }

        if (icon.length === 0) {
            return sources;
        }

        if (icon.indexOf("image://icon/") === 0) {
            const queryIndex = icon.indexOf("?path=");
            const iconStart = "image://icon/".length;
            const iconName = queryIndex >= 0 ? icon.substring(iconStart, queryIndex) : icon.substring(iconStart);

            if (queryIndex >= 0) {
                const iconPath = icon.substring(queryIndex + "?path=".length);
                addIconSource(sources, "file://" + iconPath + "/" + iconName + ".png");
                addIconSource(sources, "file://" + iconPath + "/" + iconName + ".svg");
                addIconSource(sources, "file://" + iconPath + "/" + iconName + ".ico");
                addIconSource(sources, "file://" + iconPath + "/" + iconName + ".tga");
            }

            addThemeFallbacks(sources, iconName);
            addIconSource(sources, icon);
            return sources;
        }

        if (icon.indexOf("image://") === 0 || icon.indexOf("file://") === 0 || icon.indexOf("qrc:") === 0) {
            addIconSource(sources, icon);
            return sources;
        }

        if (icon.indexOf("/") === 0 && icon.indexOf("file://") !== 0) {
            addIconSource(sources, "file://" + icon);
            return sources;
        }

        if (icon === "dialog-password") {
            addIconSource(sources, Quickshell.iconPath("dialog-password-symbolic", true));
        }

        addIconSource(sources, Quickshell.iconPath(icon, true));
        addIconSource(sources, icon);
        addThemeFallbacks(sources, icon);
        return sources;
    }
}
