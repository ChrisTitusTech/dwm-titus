import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var healthModel

    title: "dwm system health"
    visible: healthModel.visible
    fullscreen: true
    color: Theme.transparent

    function stateColor(status) {
        if (status === "error") return Theme.danger;
        if (status === "warn") return Theme.warning;
        if (status === "restricted") return Theme.accentSecondary;
        if (status === "ok") return Theme.success;
        return Theme.accent;
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(content.forceActiveFocus);
        }
    }

    ShellSurface {
        anchors.fill: parent
        radius: 0
        margin: Theme.largeSurfaceMargin

        Item {
            id: content

            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (root.healthModel.confirming) {
                        root.healthModel.cancelRepair();
                    } else {
                        root.healthModel.close();
                    }
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.sectionSpacing

                LargeSurfaceHeader {
                    Layout.fillWidth: true
                    eyebrow: "Fedora workstation diagnostics"
                    title: "System Health"
                    subtitle: root.healthModel.coverageMessage
                    status: root.healthModel.overallLabel()
                    statusColor: root.healthModel.countStatus("error") > 0 ? Theme.danger
                        : root.healthModel.countStatus("warn") > 0 ? Theme.warning
                        : root.healthModel.busy || root.healthModel.countStatus("restricted") > 0
                            ? Theme.accentSecondary : Theme.success

                    ShellButton {
                        label: root.healthModel.showIssuesOnly ? "Show All" : "Issues Only"
                        onActivated: root.healthModel.showIssuesOnly = !root.healthModel.showIssuesOnly
                    }

                    ShellButton {
                        label: root.healthModel.busy ? "Scanning..." : "Refresh"
                        enabled: !root.healthModel.busy
                        onActivated: root.healthModel.refresh()
                    }

                    ShellButton {
                        label: "Close"
                        onActivated: root.healthModel.close()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    Repeater {
                        model: [
                            { "label": "Errors", "status": "error" },
                            { "label": "Warnings", "status": "warn" },
                            { "label": "Restricted", "status": "restricted" },
                            { "label": "Passing", "status": "ok" }
                        ]

                        Rectangle {
                            id: statusTile

                            required property var modelData
                            readonly property color accentColor: root.stateColor(modelData.status)

                            Layout.preferredWidth: 145
                            Layout.preferredHeight: 48
                            color: Theme.controlNormalFill
                            border.color: Theme.controlNormalBorder
                            border.width: Theme.controlBorderWidth
                            radius: Theme.largeSurfaceCardRadius

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 4
                                color: statusTile.accentColor
                                radius: 2
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12

                                UiText {
                                    Layout.fillWidth: true
                                    text: statusTile.modelData.label.toUpperCase()
                                    color: Theme.menuMutedText
                                    font.pixelSize: Theme.fontCaptionSize
                                    font.bold: true
                                    font.letterSpacing: 0.7
                                }

                                UiText {
                                    text: root.healthModel.countStatus(statusTile.modelData.status)
                                    color: statusTile.accentColor
                                    font.pixelSize: Theme.fontTitleSize
                                    font.bold: true
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    UiText {
                        visible: root.healthModel.repairMessage.length > 0
                        text: root.healthModel.repairMessage
                        color: root.healthModel.repairError.length > 0 ? Theme.danger : Theme.menuMutedText
                        font.pixelSize: Theme.fontBodySmallSize
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.sectionSpacing

                    Rectangle {
                        Layout.preferredWidth: Theme.largeSurfaceNavWidth
                        Layout.fillHeight: true
                        color: Theme.menuBackground
                        border.color: Theme.popupBorder
                        border.width: Theme.controlBorderWidth
                        radius: Theme.largeSurfaceCardRadius

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingXl
                            spacing: Theme.spacingLg

                            SectionLabel { label: "Check categories" }

                            Repeater {
                                model: root.healthModel.categories

                                Rectangle {
                                    id: categoryButton

                                    required property int index
                                    required property var modelData
                                    readonly property bool selected: root.healthModel.selectedCategory === modelData.id

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    color: selected ? Theme.menuSelectedBackground
                                        : categoryMouse.containsMouse ? Theme.menuHoverBackground : Theme.transparent
                                    border.color: selected ? Theme.controlSelectedBorder : Theme.transparent
                                    border.width: Theme.controlBorderWidth
                                    radius: Theme.controlRadius

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        height: parent.height - 14
                                        visible: categoryButton.selected
                                        color: Theme.accentSecondary
                                        radius: 2
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: Theme.spacingLg

                                        UiText {
                                            text: String(categoryButton.index + 1).padStart(2, "0")
                                            color: categoryButton.selected ? Theme.menuActionText : Theme.menuMutedText
                                            font.pixelSize: Theme.fontCaptionSize
                                            font.bold: true
                                        }

                                        UiText {
                                            Layout.fillWidth: true
                                            text: categoryButton.modelData.label
                                            color: categoryButton.selected ? Theme.menuSelectedText : Theme.menuText
                                            font.bold: categoryButton.selected
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            visible: root.healthModel.categoryIssueCount(categoryButton.modelData.id) > 0
                                            implicitWidth: categoryCount.implicitWidth + 12
                                            implicitHeight: 22
                                            color: Theme.dangerSurface
                                            border.color: Theme.danger
                                            border.width: 1
                                            radius: 6

                                            UiText {
                                                id: categoryCount
                                                anchors.centerIn: parent
                                                text: root.healthModel.categoryIssueCount(categoryButton.modelData.id)
                                                color: Theme.danger
                                                font.pixelSize: Theme.fontCaptionSize
                                                font.bold: true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: categoryMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.healthModel.selectedCategory = categoryButton.modelData.id
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: healthScope.implicitHeight + 20
                                color: Theme.controlNormalFill
                                border.color: Theme.controlNormalBorder
                                border.width: 1
                                radius: Theme.controlRadius

                                UiText {
                                    id: healthScope
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    text: "CURRENT BOOT ONLY\nNO EXTERNAL NETWORK PROBES"
                                    color: Theme.menuMutedText
                                    font.pixelSize: Theme.fontCaptionSize
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    ListView {
                        id: healthList

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Theme.spacingLg
                        model: root.healthModel.visibleRows

                        delegate: HealthCheckCard {
                            id: healthCard

                            required property var modelData
                            width: healthList.width
                            rowData: healthCard.modelData
                            healthModel: root.healthModel
                        }

                        UiText {
                            anchors.centerIn: parent
                            visible: healthList.count === 0
                            text: root.healthModel.busy ? "Collecting system health..." : "No checks match this view"
                            color: Theme.menuMutedText
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.healthModel.confirming
                color: Theme.bg
                opacity: 0.96
                z: 10

                ShellSurface {
                    anchors.centerIn: parent
                    width: Math.min(620, parent.width - 80)
                    height: 290
                    border.color: Theme.danger
                    margin: Theme.largeSurfaceMargin

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.sectionSpacing

                        LargeSurfaceHeader {
                            Layout.fillWidth: true
                            eyebrow: "Explicit confirmation required"
                            title: "Confirm Repair"
                            subtitle: root.healthModel.pendingRepair ? root.healthModel.pendingRepair.repairLabel : ""
                            status: root.healthModel.pendingRepair && root.healthModel.pendingRepair.privilege === "system"
                                ? "administrator" : "user session"
                            statusColor: Theme.danger
                        }

                        UiText {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: root.healthModel.pendingRepair
                                ? root.healthModel.repairImpact(root.healthModel.pendingRepair.repairId) : ""
                            color: Theme.menuText
                            font.pixelSize: Theme.fontBodySize
                            wrapMode: Text.WordWrap
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: root.healthModel.pendingRepair && root.healthModel.pendingRepair.privilege === "system"
                                ? "Administrator authorization is required."
                                : "This action affects only the current user session."
                            color: root.healthModel.pendingRepair && root.healthModel.pendingRepair.privilege === "system"
                                ? Theme.warning : Theme.menuMutedText
                            font.pixelSize: Theme.fontBodySmallSize
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }

                            ShellButton {
                                label: "Cancel"
                                onActivated: root.healthModel.cancelRepair()
                            }

                            ShellButton {
                                label: "Run Repair"
                                danger: true
                                onActivated: root.healthModel.confirmRepair()
                            }
                        }
                    }
                }
            }
        }
    }
}
