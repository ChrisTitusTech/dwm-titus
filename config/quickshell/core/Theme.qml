pragma Singleton

import Quickshell

Singleton {
    readonly property bool dark: true

    readonly property string transparent: "#00000000"
    readonly property string bg: dark ? "#181616" : "#f2ecdc"
    readonly property string barBackground: dark ? "#e6181616" : "#eef2ecdc"
    readonly property string surface: dark ? "#252323" : "#e7dfcc"
    readonly property string surfaceHover: dark ? "#343131" : "#ddd3bd"
    readonly property string surfaceActive: dark ? "#3b2928" : "#ead6cf"
    readonly property string border: dark ? "#403c3b" : "#c7bda7"
    readonly property string borderStrong: dark ? "#5a5552" : "#aaa087"
    readonly property string text: dark ? "#c5c9c5" : "#545464"
    readonly property string textStrong: dark ? "#dcd7ba" : "#363646"
    readonly property string textMuted: dark ? "#a6a69c" : "#727169"
    readonly property string placeholder: dark ? "#727169" : "#8a8980"
    readonly property string accent: dark ? "#c4746e" : "#c84053"
    readonly property string accentSecondary: dark ? "#658594" : "#4d699b"
    readonly property string accentText: dark ? "#181616" : "#f2ecdc"
    readonly property string success: dark ? "#8a9a73" : "#6f894e"
    readonly property string warning: dark ? "#c8b36a" : "#b6923f"
    readonly property string danger: dark ? "#e46876" : "#c84053"
    readonly property string dangerSurface: dark ? "#452b2e" : "#f0d5da"
    readonly property string shadow: "#70000000"

    readonly property string fontFamily: "MesloLGS Nerd Font Mono"
    readonly property string iconFontFamily: fontFamily

    readonly property int panelHeight: 38
    readonly property int panelMargin: 4
    readonly property int panelEdgeMargin: 8
    readonly property int panelGap: 6
    readonly property int popupMargin: 18
    readonly property int popupSpacing: 12
    readonly property int rowSpacing: 10
    readonly property int listSpacing: 4
    readonly property int compactSpacing: 2
    readonly property int tightSpacing: 3
    readonly property int sectionSpacing: 14
    readonly property int radius: 8
    readonly property int smallRadius: 6
    readonly property int barRadius: 11
    readonly property int pillRadius: 8
    readonly property int pillHeight: 28
    readonly property int pillHorizontalPadding: 9
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
