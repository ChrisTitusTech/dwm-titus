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
    readonly property bool editable: root.active && root.snapshot.available && !action.running
    spacing: Theme.spacingSm

    function parse(text) {
        try { root.snapshot = JSON.parse(text); }
        catch (error) { root.message = "Could not read layout state"; }
    }
    function currentView() {
        return { monitor: root.snapshot.monitor, tags: root.snapshot.tags, owner: root.snapshot.owner };
    }
    function sliderValue(setting, fallback) {
        return typeof root.snapshot[setting] === "number" ? root.snapshot[setting] : fallback;
    }
    function setValue(setting, value, view) {
        if (!root.editable) return;
        const target = view || root.currentView();
        if (target.monitor !== root.snapshot.monitor || target.tags !== root.snapshot.tags || target.owner !== root.snapshot.owner) {
            root.message = "The edited monitor or tag changed; try again";
            return;
        }
        root.message = "";
        if (root.snapshot[setting] === value) return;
        action.command = Commands.helperCommand("dwm-layout-settings", "set",
            [setting, String(value), String(target.monitor), String(target.tags), String(target.owner)], true);
        action.running = true;
    }

    component ViewSlider: Controls.Slider {
        id: slider
        required property string setting
        required property int fallbackValue
        property var editView: null
        property int editValue: 0
        value: root.sliderValue(slider.setting, slider.fallbackValue)
        onMoved: {
            slider.editValue = Math.round(value);
            if (!pressed) root.setValue(slider.setting, slider.editValue, root.currentView());
        }
        onPressedChanged: {
            if (pressed) {
                slider.editView = root.currentView();
                slider.editValue = Math.round(value);
            } else if (slider.editView !== null) {
                const view = slider.editView;
                slider.editView = null;
                root.setValue(slider.setting, slider.editValue, view);
                slider.value = Qt.binding(function() {
                    return root.sliderValue(slider.setting, slider.fallbackValue);
                });
            }
        }
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
                visible: ((root.snapshot.choices || 0) & (1 << index)) !== 0
                primary: root.snapshot.layout === index
                enabled: root.editable
                onActivated: root.setValue("layout", index)
            }
        }
    }
    UiText { text: "Master area: " + (root.snapshot.master || 55) + "%"; color: Theme.menuText }
    ViewSlider {
        setting: "master"
        fallbackValue: 55
        id: master
        objectName: "windowMasterArea"
        Accessible.name: "Master area percentage"
        Layout.fillWidth: true
        from: 5; to: 95; stepSize: 1
        enabled: root.editable && root.snapshot.layout !== 1
        palette.highlight: Theme.accent
    }
    RowLayout {
        UiText { text: "Master windows: " + (root.snapshot.count || 0); color: Theme.menuText }
        ShellButton { objectName: "windowMasterMinus"; label: "-"; enabled: root.editable && root.snapshot.count > 0; onActivated: root.setValue("count", Math.min(20, root.snapshot.count - 1)) }
        ShellButton { label: "+"; enabled: root.editable && root.snapshot.count < 20; onActivated: root.setValue("count", root.snapshot.count + 1) }
    }
    UiText { text: "Tile gaps: " + (root.snapshot.gap || 0) + " px"; color: Theme.menuText }
    ViewSlider {
        setting: "gap"
        fallbackValue: 0
        objectName: "windowTileGaps"
        Accessible.name: "Tile gap size"
        Layout.fillWidth: true
        from: 0; to: 64; stepSize: 1
        enabled: root.editable && root.snapshot.layout === 0
        palette.highlight: Theme.accent
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
        // The watch stream owns current state; an older mutation acknowledgement
        // must not replace a newer monitor/tag snapshot.
        stdout: StdioCollector {}
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.message = text.trim(); } }
    }
}
