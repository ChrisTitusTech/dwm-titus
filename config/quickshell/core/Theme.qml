pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool dark: true

    readonly property string transparent: "#00000000"
    property string bg: "#2E3440"
    property string barBackground: "#434C5E"
    property string surface: "#434C5E"
    property string surfaceHover: "#4C566A"
    property string surfaceActive: "#434C5E"
    property string border: "#3B4252"
    property string borderStrong: "#81A1C1"
    property string text: "#D8DEE9"
    property string textStrong: "#ECEFF4"
    property string textMuted: "#D8DEE9"
    property string placeholder: "#4C566A"
    property string accent: "#81A1C1"
    property string accentSecondary: "#81A1C1"
    property string accentText: "#2E3440"
    property string success: "#A3BE8C"
    property string warning: "#EBCB8B"
    property string danger: "#BF616A"
    property string dangerSurface: "#3B4252"
    readonly property string shadow: transparent

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string themesPath: configHome + "/dwm-titus/themes.toml"

    function sectionValue(text, section, key, fallback) {
        const lines = text.split("\n");
        let active = false;
        const sectionHeader = "[" + section + "]";
        const expression = new RegExp("^\\s*" + key + "\\s*=\\s*(?:\\\"([^\\\"]*)\\\"|([^#\\s]+))");

        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("[")) {
                active = trimmed === sectionHeader;
                continue;
            }
            if (!active) continue;
            const match = line.match(expression);
            if (match) return match[1] !== undefined ? match[1] : match[2];
        }
        return fallback;
    }

    function applyThemes(themeText) {
        const activeTheme = sectionValue(themeText, "active", "theme", "nord");
        const section = "theme." + activeTheme;
        const value = function(key, fallback) { return sectionValue(themeText, section, key, fallback); };

        root.dark = value("dark_mode", "true") !== "false";
        root.bg = value("term_bg", root.bg);
        root.barBackground = value("normbgcolor", root.bg);
        root.surface = value("normbgcolor", root.bg);
        root.surfaceHover = value("term_color8", value("selbgcolor", root.surface));
        root.surfaceActive = value("selbgcolor", root.surfaceHover);
        root.border = value("normbordercolor", root.surface);
        root.borderStrong = value("selbordercolor", root.border);
        root.text = value("normfgcolor", root.text);
        root.textStrong = value("selfgcolor", root.text);
        root.textMuted = value("term_fg", root.text);
        root.placeholder = value("term_color8", root.textMuted);
        root.accent = value("selbordercolor", root.accent);
        root.accentSecondary = value("term_color4", root.accent);
        root.accentText = root.bg;
        root.success = value("term_color2", root.success);
        root.warning = value("term_color3", root.warning);
        root.danger = value("term_color1", root.danger);
        root.dangerSurface = value("term_color0", root.surface);
    }

    FileView {
        id: themesFile
        path: root.themesPath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyThemes(text())
        onFileChanged: reload()
    }

    readonly property string fontFamily: "MesloLGS Nerd Font Mono"
    readonly property string iconFontFamily: fontFamily

    readonly property int panelHeight: 30
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: 4
    readonly property int popupMargin: 18
    readonly property int popupSpacing: 12
    readonly property int controlCenterX: 6
    readonly property int controlCenterWidth: 276
    readonly property int controlCenterGap: 8
    readonly property int rowSpacing: 10
    readonly property int listSpacing: 4
    readonly property int compactSpacing: 2
    readonly property int tightSpacing: 3
    readonly property int sectionSpacing: 14
    readonly property int radius: 6
    readonly property int smallRadius: 6
    readonly property int barRadius: 0
    readonly property int pillRadius: 6
    readonly property int pillHeight: 26
    readonly property int pillHorizontalPadding: 9
    readonly property int compactWidgetSize: 22
    readonly property int compactWidgetHorizontalPadding: 6
    readonly property real networkWidgetHorizontalPadding: 4.5
    readonly property int pillBorderWidth: 1
    readonly property int animationFast: 120
    readonly property int animationNormal: 180
    readonly property int buttonHeight: 30
    readonly property int chipHeight: 28
    readonly property int workspaceButtonSize: 22
    readonly property int compactButtonHeight: 40
    readonly property int confirmButtonHeight: 48
    readonly property int notificationAccentWidth: 4
    readonly property int notificationAccentRadius: 2
    readonly property int titleFontSize: 18
    readonly property int bodyFontSize: 14
    readonly property int panelFontSize: 13
    readonly property int smallFontSize: 12
    readonly property int tinyFontSize: 10
    readonly property int inputFontSize: 16
    readonly property int iconSize: 28
    readonly property int trayItemSize: 24
    readonly property int trayIconSize: 18
    readonly property int closeButtonSize: 30
}
