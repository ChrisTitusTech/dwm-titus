pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool dark: true
    property bool highContrast: false
    property bool reducedMotion: false

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
    property string paletteTextMuted: "#D8DEE9"
    readonly property string textMuted: highContrast ? text : paletteTextMuted
    property string placeholder: "#4C566A"
    property string accent: "#81A1C1"
    property string accentSecondary: "#81A1C1"
    property string accentText: "#2E3440"
    readonly property string accentHoverText: readableText(accentText, accentSecondary)
    property string success: "#A3BE8C"
    property string warning: "#EBCB8B"
    property string danger: "#BF616A"
    property string dangerSurface: "#3B4252"
    readonly property string shadow: transparent

    // Semantic shell roles. Keep these derived from the existing dwm palette
    // so hot-reloaded themes remain the single source of color state.
    readonly property string popupBackground: bg
    readonly property string popupBorder: highContrast ? textStrong : borderStrong
    readonly property string popupText: text
    readonly property string menuBackground: bg
    readonly property string menuText: dark ? text : readableTextOnSurfaces(text, [menuBackground, menuHoverBackground])
    readonly property string menuMutedText: dark ? textMuted : readableTextOnSurfaces(textMuted, [menuBackground, menuHoverBackground])
    readonly property string menuActionText: readableText(accent, menuBackground)
    readonly property string menuHoverBackground: surfaceHover
    readonly property string menuHoverText: readableText(textStrong, menuHoverBackground)
    readonly property string menuSelectedBackground: surfaceActive
    readonly property string menuSelectedText: readableText(accentSecondary, menuSelectedBackground)
    readonly property string controlNormalFill: surface
    readonly property string controlNormalBorder: highContrast ? textStrong : border
    readonly property string controlNormalText: dark ? readableText(text, controlNormalFill) : readableTextOnSurfaces(text, [controlNormalFill, controlHoverFill])
    readonly property string controlHoverFill: surfaceHover
    readonly property string controlHoverBorder: highContrast ? textStrong : borderStrong
    readonly property string controlHoverText: readableText(text, controlHoverFill)
    readonly property string controlFocusFill: surface
    readonly property string controlFocusBorder: highContrast ? textStrong : accent
    readonly property string controlFocusText: readableText(text, controlFocusFill)
    readonly property string controlSelectedFill: surfaceActive
    readonly property string controlSelectedBorder: highContrast ? textStrong : accentSecondary
    readonly property string controlSelectedText: readableText(accentSecondary, controlSelectedFill)
    readonly property string controlDisabledFill: barBackground
    readonly property string controlDisabledBorder: highContrast ? textStrong : border
    readonly property string controlDisabledText: textMuted

    function luminance(color) {
        const channels = [1, 3, 5].map(function(offset) {
            const value = parseInt(color.slice(offset, offset + 2), 16) / 255;
            return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }

    function readableText(foreground, background) {
        const fg = luminance(foreground);
        const bg = luminance(background);
        if ((Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= 4.5)
            return foreground;
        return bg > 0.179 ? "#000000" : "#ffffff";
    }

    function readableTextOnSurfaces(foreground, backgrounds) {
        // Some controls intentionally keep one text role while their fill
        // changes on hover. Check that role against both actual surfaces.
        function minimumContrast(color) {
            const fg = luminance(color);
            return Math.min.apply(null, backgrounds.map(function(background) {
                const bg = luminance(background);
                return (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
            }));
        }
        if (minimumContrast(foreground) >= 4.5)
            return foreground;
        return minimumContrast("#000000") > minimumContrast("#ffffff") ? "#000000" : "#ffffff";
    }

    function lightHover(background, foreground) {
        // ANSI bright-black is a terminal foreground, not a light UI surface.
        return "#" + [1, 3, 5].map(function(offset) {
            const bg = parseInt(background.slice(offset, offset + 2), 16);
            const fg = parseInt(foreground.slice(offset, offset + 2), 16);
            return Math.round(bg * 0.92 + fg * 0.08).toString(16).padStart(2, "0");
        }).join("");
    }

    // AppearanceModel is the single owner of theme inventory and validation.
    // Existing shell surfaces continue to consume these semantic properties.
    function applyAppearanceColors(colors, darkMode) {
        root.dark = darkMode;
        root.bg = colors.background;
        root.barBackground = colors["bar-background"];
        root.surface = colors.surface;
        root.surfaceHover = darkMode ? colors["surface-hover"]
            : lightHover(colors.background, colors["text-strong"]);
        root.surfaceActive = colors["surface-active"];
        root.border = colors.border;
        root.borderStrong = colors["border-strong"];
        root.text = colors.text;
        root.textStrong = colors["text-strong"];
        root.paletteTextMuted = colors["text-muted"];
        root.placeholder = colors.placeholder;
        root.accent = colors.accent;
        root.accentSecondary = colors["accent-secondary"];
        root.accentText = readableText(colors["accent-text"], colors.accent);
        root.success = colors.success;
        root.warning = colors.warning;
        root.danger = colors.danger;
        root.dangerSurface = colors["danger-surface"];
    }

    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real requestedFontScale: 1.0
    property bool desktopTypography: false
    // Qt already scales X11 windows using Xft/DPI. Apply only the remainder
    // here, so a 200% desktop never becomes a 400% shell.
    readonly property real nativeScale: Quickshell.screens.length > 0
        ? Math.max(0.1, Quickshell.screens[0].devicePixelRatio) : 1.0
    readonly property real fontScale: requestedFontScale
        / (desktopTypography ? nativeScale : 1.0)
    readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"

    function applyFontPreferences(family, scale) {
        root.fontFamily = family.length > 0 ? family : "MesloLGS Nerd Font Mono";
        root.requestedFontScale = Math.max(0.75, Math.min(2.0, scale));
    }

    function applyAccessibility(highContrastEnabled, reducedMotionEnabled) {
        root.highContrast = highContrastEnabled;
        root.reducedMotion = reducedMotionEnabled;
    }

    function scaledSize(value) {
        return Math.round(value * root.fontScale);
    }

    function scaledFontSize(value, minimum) {
        // Minimums are desktop pixels too; apply them before DPI compensation.
        const desktopSize = Math.max(minimum, Math.round(value * root.requestedFontScale));
        return Math.max(1, Math.round(desktopSize / (root.desktopTypography ? root.nativeScale : 1.0)));
    }

    // Shared spacing and type scales adapted from Omarchy's shell language.
    // Values intentionally map to the pre-existing dwm-titus geometry.
    readonly property int spacingXxs: scaledSize(2)
    readonly property int spacingXs: scaledSize(3)
    readonly property int spacingSm: scaledSize(4)
    readonly property int spacingMd: scaledSize(6)
    readonly property int spacingLg: scaledSize(8)
    readonly property int spacingXl: scaledSize(10)
    readonly property int spacingXxl: scaledSize(12)
    readonly property int spacingXxxl: scaledSize(14)
    readonly property int spacingHuge: scaledSize(18)

    readonly property int fontCaptionSize: scaledFontSize(10, 8)
    readonly property int fontBodySmallSize: scaledFontSize(12, 10)
    readonly property int fontBodySize: scaledFontSize(13, 10)
    readonly property int fontSubtitleSize: scaledFontSize(14, 11)
    readonly property int fontTitleSize: scaledFontSize(18, 14)
    readonly property int largeSurfaceTitleSize: scaledFontSize(24, 18)
    readonly property int panelIconFontSize: scaledFontSize(14, 8)

    readonly property int controlHeight: scaledSize(30)
    readonly property int controlRowHeight: scaledSize(32)
    readonly property int controlPaddingX: scaledSize(9)
    readonly property int controlBorderWidth: highContrast ? 2 : 1
    readonly property int controlFocusBorderWidth: controlBorderWidth
    readonly property int controlRadius: scaledSize(6)
    readonly property int menuHeaderHeight: scaledSize(26)
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: 0
    readonly property int panelHeroIconSize: scaledSize(32)
    readonly property real panelMetaLetterSpacing: 1.2 * fontScale
    readonly property int panelSliderHeight: scaledSize(32)
    readonly property int panelSliderTrackHeight: scaledSize(6)
    readonly property int panelSliderKnobSize: scaledSize(16)
    readonly property int panelToggleWidth: scaledSize(40)
    readonly property int panelToggleHeight: scaledSize(22)
    readonly property int panelToggleKnobSize: scaledSize(14)
    readonly property int panelToggleInset: scaledSize(3)

    readonly property int panelHeight: scaledSize(30)
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: spacingSm
    readonly property int popupMargin: popupPadding
    readonly property int popupSpacing: spacingXxl
    readonly property int controlCenterX: scaledSize(6)
    readonly property int controlCenterWidth: scaledSize(276)
    readonly property int rowSpacing: spacingXl
    readonly property int listSpacing: spacingSm
    readonly property int compactSpacing: spacingXxs
    readonly property int tightSpacing: spacingXs
    readonly property int sectionSpacing: spacingXxxl
    readonly property int radius: controlRadius
    readonly property int smallRadius: controlRadius
    readonly property int barRadius: 0
    readonly property int pillRadius: scaledSize(6)
    readonly property int pillHeight: scaledSize(26)
    readonly property int pillHorizontalPadding: scaledSize(9)
    readonly property int compactWidgetSize: scaledSize(22)
    readonly property int compactWidgetHorizontalPadding: scaledSize(6)
    readonly property real networkWidgetHorizontalPadding: 4.5 * fontScale
    readonly property int pillBorderWidth: controlBorderWidth
    readonly property int animationFast: reducedMotion ? 0 : 120
    readonly property int animationNormal: reducedMotion ? 0 : 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: scaledSize(28)
    readonly property int workspaceButtonSize: scaledSize(22)
    readonly property int compactButtonHeight: scaledSize(40)
    readonly property int confirmButtonHeight: scaledSize(48)
    readonly property int notificationAccentWidth: scaledSize(4)
    readonly property int notificationAccentRadius: 0
    readonly property int largeSurfaceMargin: scaledSize(22)
    readonly property int largeSurfaceNavWidth: scaledSize(248)
    readonly property int largeSurfaceSearchHeight: scaledSize(44)
    readonly property int largeSurfaceCardRadius: scaledSize(8)
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: scaledFontSize(16, 12)
    readonly property int iconSize: scaledSize(28)
    readonly property int trayItemSize: scaledSize(24)
    readonly property int trayIconSize: scaledSize(18)
    readonly property int closeButtonSize: scaledSize(30)
}
