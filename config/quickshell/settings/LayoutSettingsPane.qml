import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    property bool active: visible
    property var snapshot: ({ available: false, detail: "Loading layout controls" })
    property string message: ""
    readonly property bool editable: root.snapshot.available && !action.running
    spacing: Theme.spacingSm

    function parse(text) {
        try { root.snapshot = JSON.parse(text); }
        catch (error) { root.message = "Could not read layout state"; }
    }
    function setValue(setting, value) {
        if (!root.editable) return;
        root.message = "";
        action.command = Commands.helperCommand("dwm-layout-settings", "set",
            [setting, String(value), String(root.snapshot.monitor), String(root.snapshot.tags)], true);
        action.running = true;
    }

    SectionLabel { label: "Window layout" }
    UiText {
        Layout.fillWidth: true
        text: root.message || root.snapshot.detail
        color: root.message ? Theme.warning : Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Repeater {
            model: ["Tile", "Floating", "Monocle"]
            delegate: ShellButton {
                required property string modelData
                required property int index
                objectName: "windowLayout" + index
                label: modelData
                primary: root.snapshot.layout === index
                enabled: root.editable
                onActivated: root.setValue("layout", index)
            }
        }
    }
    UiText { text: "Master area: " + (root.snapshot.master || 55) + "%"; color: Theme.menuText }
    Controls.Slider {
        id: master
        objectName: "windowMasterArea"
        Accessible.name: "Master area percentage"
        Layout.fillWidth: true
        from: 5; to: 95; stepSize: 1
        value: root.snapshot.master || 55
        enabled: root.editable && root.snapshot.layout !== 1
        palette.highlight: Theme.accent
        onMoved: { if (!pressed) root.setValue("master", Math.round(value)); }
        onPressedChanged: { if (!pressed) root.setValue("master", Math.round(value)); }
    }
    RowLayout {
        UiText { text: "Master windows: " + (root.snapshot.count || 0); color: Theme.menuText }
        ShellButton { label: "-"; enabled: root.editable && root.snapshot.count > 0; onActivated: root.setValue("count", root.snapshot.count - 1) }
        ShellButton { label: "+"; enabled: root.editable && root.snapshot.count < 20; onActivated: root.setValue("count", root.snapshot.count + 1) }
    }
    UiText { text: "Tile gaps: " + (root.snapshot.gap || 0) + " px"; color: Theme.menuText }
    Controls.Slider {
        objectName: "windowTileGaps"
        Accessible.name: "Tile gap size"
        Layout.fillWidth: true
        from: 0; to: 64; stepSize: 1
        value: root.snapshot.gap || 0
        enabled: root.editable && root.snapshot.layout === 0
        palette.highlight: Theme.accent
        onMoved: { if (!pressed) root.setValue("gap", Math.round(value)); }
        onPressedChanged: { if (!pressed) root.setValue("gap", Math.round(value)); }
    }
    UiText {
        Layout.fillWidth: true
        text: "Font and text size below controls desktop scale. Corner rounding is provided by your optional Picom configuration."
        color: Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    Process {
        running: root.active
        command: Commands.helperCommand("dwm-layout-settings", "watch", [], true)
        stdout: SplitParser { onRead: data => root.parse(data) }
        onExited: { // qmllint disable signal-handler-parameters
            root.snapshot = ({ available: false, detail: "Layout controls disconnected; reopen Appearance to retry" });
        }
    }
    Process {
        id: action
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.message = text.trim(); } }
    }
}
