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

    // Semantic shell roles. Keep these derived from the existing dwm palette
    // so hot-reloaded themes remain the single source of color state.
    readonly property string popupBackground: bg
    readonly property string popupBorder: borderStrong
    readonly property string popupText: text
    readonly property string menuBackground: bg
    readonly property string menuText: text
    readonly property string menuMutedText: textMuted
    readonly property string menuActionText: accent
    readonly property string menuHoverBackground: surfaceHover
    readonly property string menuHoverText: textStrong
    readonly property string menuSelectedBackground: surfaceActive
    readonly property string menuSelectedText: accentSecondary
    readonly property string controlNormalFill: surface
    readonly property string controlNormalBorder: border
    readonly property string controlNormalText: text
    readonly property string controlHoverFill: surfaceHover
    readonly property string controlHoverBorder: borderStrong
    readonly property string controlHoverText: text
    readonly property string controlFocusFill: surface
    readonly property string controlFocusBorder: accent
    readonly property string controlFocusText: text
    readonly property string controlSelectedFill: surfaceActive
    readonly property string controlSelectedBorder: accentSecondary
    readonly property string controlSelectedText: accentSecondary
    readonly property string controlDisabledFill: barBackground
    readonly property string controlDisabledBorder: border
    readonly property string controlDisabledText: textMuted

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

    // Shared spacing and type scales adapted from Omarchy's shell language.
    // Values intentionally map to the pre-existing dwm-titus geometry.
    readonly property int spacingXxs: 2
    readonly property int spacingXs: 3
    readonly property int spacingSm: 4
    readonly property int spacingMd: 6
    readonly property int spacingLg: 8
    readonly property int spacingXl: 10
    readonly property int spacingXxl: 12
    readonly property int spacingXxxl: 14
    readonly property int spacingHuge: 18

    readonly property int fontCaptionSize: 10
    readonly property int fontBodySmallSize: 12
    readonly property int fontBodySize: 13
    readonly property int fontSubtitleSize: 14
    readonly property int fontTitleSize: 18

    readonly property int controlHeight: 30
    readonly property int controlRowHeight: 32
    readonly property int controlPaddingX: 9
    readonly property int controlBorderWidth: 1
    readonly property int controlFocusBorderWidth: 2
    readonly property int controlRadius: 6
    readonly property int menuHeaderHeight: 26
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: controlRadius
    readonly property int panelHeroIconSize: 32
    readonly property real panelMetaLetterSpacing: 1.2
    readonly property int panelSliderHeight: 32
    readonly property int panelSliderTrackHeight: 6
    readonly property int panelSliderKnobSize: 16
    readonly property int panelToggleWidth: 40
    readonly property int panelToggleHeight: 22
    readonly property int panelToggleKnobSize: 14
    readonly property int panelToggleInset: 3

    readonly property int panelHeight: 30
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: spacingSm
    readonly property int popupMargin: popupPadding
    readonly property int popupSpacing: spacingXxl
    readonly property int controlCenterX: 6
    readonly property int controlCenterWidth: 276
    readonly property int rowSpacing: spacingXl
    readonly property int listSpacing: spacingSm
    readonly property int compactSpacing: spacingXxs
    readonly property int tightSpacing: spacingXs
    readonly property int sectionSpacing: spacingXxxl
    readonly property int radius: controlRadius
    readonly property int smallRadius: controlRadius
    readonly property int barRadius: 0
    readonly property int pillRadius: 6
    readonly property int pillHeight: 26
    readonly property int pillHorizontalPadding: 9
    readonly property int compactWidgetSize: 22
    readonly property int compactWidgetHorizontalPadding: 6
    readonly property real networkWidgetHorizontalPadding: 4.5
    readonly property int pillBorderWidth: controlBorderWidth
    readonly property int animationFast: 120
    readonly property int animationNormal: 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: 28
    readonly property int workspaceButtonSize: 22
    readonly property int compactButtonHeight: 40
    readonly property int confirmButtonHeight: 48
    readonly property int notificationAccentWidth: 4
    readonly property int notificationAccentRadius: 2
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: 16
    readonly property int iconSize: 28
    readonly property int trayItemSize: 24
    readonly property int trayIconSize: 18
    readonly property int closeButtonSize: 30
}
