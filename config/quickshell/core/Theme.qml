pragma Singleton

import Quickshell

Singleton {
    readonly property bool dark: true

    readonly property string transparent: "#00000000"
    readonly property string bg: dark ? "#2e3440" : "#eceff4"
    readonly property string surface: dark ? "#3b4252" : "#e5e9f0"
    readonly property string surfaceHover: dark ? "#434c5e" : "#d8dee9"
    readonly property string border: dark ? "#4c566a" : "#b8c0cc"
    readonly property string text: dark ? "#d8dee9" : "#2e3440"
    readonly property string textStrong: dark ? "#eceff4" : "#1f2630"
    readonly property string textMuted: dark ? "#aeb7c4" : "#5d6778"
    readonly property string placeholder: dark ? "#8f9aa8" : "#687386"
    readonly property string accent: dark ? "#81a1c1" : "#5e81ac"
    readonly property string accentText: dark ? "#2e3440" : "#eceff4"
    readonly property string danger: "#bf616a"
    readonly property string dangerSurface: dark ? "#4a2f35" : "#f0d5da"

    readonly property string fontFamily: "Maple Mono NF"

    readonly property int panelHeight: 30
    readonly property int popupMargin: 18
    readonly property int popupSpacing: 12
    readonly property int rowSpacing: 10
    readonly property int listSpacing: 4
    readonly property int compactSpacing: 2
    readonly property int tightSpacing: 3
    readonly property int sectionSpacing: 14
    readonly property int radius: 4
    readonly property int smallRadius: 3
    readonly property int pillHeight: 24
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
