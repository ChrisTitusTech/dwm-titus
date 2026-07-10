import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Rectangle {
    id: root

    required property var rowData
    required property var healthModel
    property bool expanded: false

    readonly property bool hasServiceActions: rowData.repairId.indexOf("manage-") === 0
    readonly property bool hasEvidenceActions: (rowData.id === "journal-errors" || rowData.id === "kernel-errors")
        && (rowData.status === "warn" || rowData.status === "error")
        && rowData.evidence.length > 0
    readonly property color statusColor: rowData.status === "error" ? Theme.danger
        : rowData.status === "warn" ? "#ebcb8b"
        : rowData.status === "restricted" ? "#b48ead"
        : rowData.status === "ok" ? "#a3be8c"
        : Theme.accent

    implicitHeight: cardColumn.implicitHeight + 24
    color: rowData.status === "error" ? Theme.dangerSurface : Theme.surface
    border.color: statusColor
    border.width: 1
    radius: Theme.radius

    ColumnLayout {
        id: cardColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: Theme.rowSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.rowSpacing

            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                color: root.statusColor
                radius: 4
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.tightSpacing

                Text {
                    Layout.fillWidth: true
                    text: root.rowData.title
                    color: Theme.textStrong
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.panelFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.rowData.summary
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    elide: root.expanded ? Text.ElideNone : Text.ElideRight
                    wrapMode: root.expanded ? Text.WordWrap : Text.NoWrap
                }
            }

            Text {
                text: root.rowData.status.toUpperCase()
                color: root.statusColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tinyFontSize
                font.bold: true
            }

            Repeater {
                model: root.hasServiceActions ? [
                    { "action": "start", "label": "Start" },
                    { "action": "stop", "label": "Stop" },
                    { "action": "restart", "label": "Restart" },
                    { "action": "disable", "label": "Disable" },
                    { "action": "enable", "label": "Enable" }
                ] : []

                ShellButton {
                    id: serviceButton

                    required property var modelData

                    label: serviceButton.modelData.label
                    enabled: !root.healthModel.busy
                    danger: root.rowData.privilege === "system"
                    onActivated: root.healthModel.requestServiceAction(
                        root.rowData,
                        serviceButton.modelData.action,
                        serviceButton.modelData.label
                    )
                }
            }

            Repeater {
                model: root.hasEvidenceActions ? [
                    { "action": "copy", "label": "Copy" },
                    { "action": "export", "label": "Export" }
                ] : []

                ShellButton {
                    id: evidenceButton

                    required property var modelData

                    label: evidenceButton.modelData.label
                    enabled: !root.healthModel.busy
                    onActivated: root.healthModel.shareEvidence(root.rowData, evidenceButton.modelData.action)
                }
            }

            ShellButton {
                visible: root.rowData.evidence.length > 0
                label: root.expanded ? "Less" : "Details"
                onActivated: root.expanded = !root.expanded
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.expanded && root.rowData.evidence.length > 0
            text: root.rowData.evidence
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            wrapMode: Text.WrapAnywhere
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.rowData.repairId.length > 0 && !root.hasServiceActions

            Item {
                Layout.fillWidth: true
            }

            ShellButton {
                label: root.rowData.repairLabel
                enabled: !root.healthModel.busy
                danger: root.rowData.privilege === "system"
                onActivated: root.healthModel.requestRepair(root.rowData)
            }
        }
    }
}
