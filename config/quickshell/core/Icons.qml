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
        if (typeof source !== "string" && !(source instanceof String)) {
            return;
        }

        if (source.length === 0) {
            return;
        }

        if (sources.indexOf(source) < 0) {
            sources.push(source);
        }
    }

    function decodeIconPart(value) {
        try {
            return decodeURIComponent(value);
        } catch (error) {
            return value;
        }
    }

    function iconNameFallbacks(iconName) {
        const names = [iconName];

        if (iconName.indexOf("-symbolic") < 0) {
            names.push(iconName + "-symbolic");
        }

        if (iconName === "blueman" || iconName === "blueman-tray") {
            names.push("blueman-tray");
            names.push("blueman");
            names.push("blueman-active");
            names.push("bluetooth-active-symbolic");
            names.push("bluetooth-symbolic");
        } else if (iconName === "org.remmina.Remmina-status") {
            names.push("org.remmina.Remmina");
            names.push("org.remmina.Remmina-symbolic");
        }

        return names;
    }

    function addIconThemeFileSources(sources, themeRoot, iconName) {
        if (themeRoot.length === 0 || iconName.length === 0) {
            return;
        }

        const rootPath = themeRoot.replace(/\/+$/, "");
        const names = iconNameFallbacks(iconName);
        const sizes = ["24x24", "32x32", "22x22", "16x16", "48x48", "64x64", "96x96", "128x128", "192x192", "256x256", "512x512", "scalable"];
        const categories = ["status", "apps", "devices", "actions", "emblems"];
        const extensions = ["svg", "png"];

        for (let nameIndex = 0; nameIndex < names.length; nameIndex++) {
            const name = names[nameIndex];

            for (let sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
                const size = sizes[sizeIndex];

                for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex++) {
                    const category = categories[categoryIndex];

                    for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                        addIconSource(sources, "file://" + rootPath + "/" + size + "/" + category + "/" + name + "." + extensions[extensionIndex]);
                    }
                }
            }

            for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex++) {
                const category = categories[categoryIndex];

                for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                    addIconSource(sources, "file://" + rootPath + "/" + category + "/" + name + "." + extensions[extensionIndex]);
                }
            }

            addIconSource(sources, "file://" + rootPath + "/" + name);

            for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                addIconSource(sources, "file://" + rootPath + "/" + name + "." + extensions[extensionIndex]);
            }
        }
    }

    function addHicolorFallbacks(sources, iconName) {
        const home = Quickshell.env("HOME") || "";
        const xdgDataHome = Quickshell.env("XDG_DATA_HOME") || (home.length > 0 ? home + "/.local/share" : "");

        addIconThemeFileSources(sources, "/usr/share/icons/hicolor", iconName);
        addIconThemeFileSources(sources, "/usr/local/share/icons/hicolor", iconName);

        if (xdgDataHome.length > 0) {
            addIconThemeFileSources(sources, xdgDataHome + "/icons/hicolor", iconName);
        }

        if (home.length > 0) {
            addIconThemeFileSources(sources, home + "/.icons/hicolor", iconName);
        }
    }

    function addCheckedThemeSources(sources, iconName) {
        const names = iconNameFallbacks(iconName);

        for (let index = 0; index < names.length; index++) {
            addIconSource(sources, Quickshell.iconPath(names[index], true));
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
            const iconName = decodeIconPart(queryIndex >= 0 ? icon.substring(iconStart, queryIndex) : icon.substring(iconStart));

            if (iconName.indexOf("/") === 0) {
                addIconSource(sources, "file://" + iconName);
            }

            if (queryIndex >= 0) {
                let iconPath = icon.substring(queryIndex + "?path=".length);
                const iconPathEnd = iconPath.indexOf("&");

                if (iconPathEnd >= 0) {
                    iconPath = iconPath.substring(0, iconPathEnd);
                }

                iconPath = decodeIconPart(iconPath);
                if (iconName.indexOf("/") !== 0) {
                    addIconSource(sources, "file://" + iconPath + "/" + iconName);
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".png");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".svg");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".ico");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".tga");
                    addIconThemeFileSources(sources, iconPath, iconName);
                }
            }

            addThemeFallbacks(sources, iconName);
            addHicolorFallbacks(sources, iconName);
            addCheckedThemeSources(sources, iconName);
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

        addThemeFallbacks(sources, icon);
        addHicolorFallbacks(sources, icon);
        addCheckedThemeSources(sources, icon);
        addIconSource(sources, icon);
        return sources;
    }
}
