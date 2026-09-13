import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    property real activeOpacity: 100
    property real inactiveOpacity: 100
    property bool changed: false
    Layout.fillWidth: true
    spacing: 10

    function synchronize() {
        if (foreground.pressed || background.pressed || root.changed) return;
        root.activeOpacity = root.model.snapshot.active;
        root.inactiveOpacity = root.model.snapshot.inactive;
    }

    function applyOpacity() {
        keyboardDelay.stop();
        if (!root.changed || !root.model.editable) return;
        root.changed = false;
        root.model.setOpacity(root.activeOpacity, root.inactiveOpacity);
    }

    Component.onCompleted: root.synchronize()
    Connections {
        target: root.model
        function onSnapshotChanged() { root.synchronize(); }
        function onBusyChanged() {
            if (!root.model.busy) {
                if (root.changed) keyboardDelay.restart();
                else root.synchronize();
            }
        }
    }

    SectionLabel { label: "Compositor" }
    UiText {
        Layout.fillWidth: true
        text: root.model.snapshot.detail
        color: Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    UiText {
        Layout.fillWidth: true
        text: root.model.snapshot.path
        color: Theme.menuMutedText
        wrapMode: Text.WrapAnywhere
    }
    UiText {
        text: "Foreground (active): " + Math.round(root.activeOpacity) + "%"
        color: Theme.menuText
    }
    Controls.Slider {
        id: foreground
        objectName: "picomActiveOpacity"
        Accessible.name: "Foreground window opacity"
        palette.highlight: Theme.accent
        palette.button: Theme.controlNormalFill
        Layout.fillWidth: true
        from: 0; to: 100; stepSize: 1
        value: root.activeOpacity
        enabled: root.model.editable
        onMoved: {
            root.activeOpacity = value;
            root.changed = true;
            if (!pressed) keyboardDelay.restart();
        }
        onPressedChanged: { if (!pressed) root.applyOpacity(); }
    }
    UiText {
        text: "Background (inactive): " + Math.round(root.inactiveOpacity) + "%"
        color: Theme.menuText
    }
    Controls.Slider {
        id: background
        objectName: "picomInactiveOpacity"
        Accessible.name: "Background window opacity"
        palette.highlight: Theme.accent
        palette.button: Theme.controlNormalFill
        Layout.fillWidth: true
        from: 0; to: 100; stepSize: 1
        value: root.inactiveOpacity
        enabled: root.model.editable
        onMoved: {
            root.inactiveOpacity = value;
            root.changed = true;
            if (!pressed) keyboardDelay.restart();
        }
        onPressedChanged: { if (!pressed) root.applyOpacity(); }
    }
    UiText {
        text: "Backend" + (root.model.snapshot.effective ? " (current: " + root.model.snapshot.effective + ")" : "")
        color: Theme.menuText
    }
    Controls.ComboBox {
        objectName: "picomBackend"
        Accessible.name: "Picom backend"
        implicitHeight: Theme.controlHeight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.inputFontSize
        palette.button: Theme.controlNormalFill
        palette.buttonText: Theme.controlNormalText
        palette.base: Theme.popupBackground
        palette.window: Theme.popupBackground
        palette.text: Theme.popupText
        palette.highlight: Theme.controlSelectedFill
        palette.highlightedText: Theme.controlSelectedText
        Layout.fillWidth: true
        model: ["Automatic", "XRender", "GLX", "EGL (experimental)"]
        currentIndex: ["auto", "xrender", "glx", "egl"].indexOf(root.model.snapshot.policy)
        enabled: root.model.editable && !root.model.snapshot.override
        onActivated: index => root.model.mutate("set-backend", [["auto", "xrender", "glx", "egl"][index]])
    }
    ShellButton {
        visible: root.model.snapshot.copyable
        enabled: !root.model.busy
        label: "Create user configuration"
        onActivated: root.model.mutate("copy-config", [])
    }
    UiText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.model.failure || root.model.message
        color: root.model.failure ? Theme.danger : Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    Timer {
        id: keyboardDelay
        interval: 250
        onTriggered: root.applyOpacity()
    }
}
