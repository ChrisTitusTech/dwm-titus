import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var controlCenterModel
    property bool receivedFocus: false

    visible: controlCenterModel.utilityVisible
    implicitWidth: 680
    implicitHeight: 500
    color: Theme.transparent
    title: "dwm utility"

    onActiveChanged: {
        if (active) root.receivedFocus = true;
        else if (visible && root.receivedFocus) root.controlCenterModel.closeUtility();
    }

    onVisibleChanged: if (!visible) receivedFocus = false

    function titleForPage() {
        if (controlCenterModel.utilityPage === "health") return "System Health";
        if (controlCenterModel.utilityPage === "keybinds") return "Keybinds";
        return "System Info";
    }

    function rowsForPage() {
        if (controlCenterModel.utilityPage === "health") return controlCenterModel.healthRows;
        if (controlCenterModel.utilityPage === "keybinds") return controlCenterModel.keybindRows;
        return controlCenterModel.infoRows;
    }

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.controlCenterModel.closeUtility();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true
                UiText {
                    Layout.fillWidth: true
                    text: root.titleForPage()
                    color: Theme.textStrong
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                }
                ShellButton {
                    label: "Close"
                    onActivated: root.controlCenterModel.closeUtility()
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.controlCenterModel.message.length > 0
                text: root.controlCenterModel.message
                color: Theme.textMuted
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.rowsForPage()

                delegate: ControlCenterRow {
                    required property var modelData
                    width: ListView.view.width
                    title: root.controlCenterModel.utilityPage === "keybinds" ? modelData.keys : (modelData.label || "")
                    detail: root.controlCenterModel.utilityPage === "keybinds" ? modelData.description : (modelData.detail || modelData.value || "")
                    status: modelData.status || ""
                }
            }
        }
    }
}
