import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var notificationModel

    title: "dwm notification history"
    visible: notificationModel.historyVisible
    implicitWidth: 560
    implicitHeight: 600
    color: Theme.transparent

    onVisibleChanged: {
        if (visible) Qt.callLater(historySurface.forceActiveFocus);
    }

    ShellSurface {
        id: historySurface

        anchors.fill: parent
        margin: Theme.largeSurfaceMargin
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.notificationModel.closeHistory();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            LargeSurfaceHeader {
                Layout.fillWidth: true
                eyebrow: "Recent desktop activity"
                title: "Notifications"
                subtitle: root.notificationModel.history.length + " saved / newest first"
                status: root.notificationModel.history.length > 0 ? "history" : "empty"
                statusColor: root.notificationModel.history.length > 0 ? Theme.accent : Theme.menuMutedText

                ShellButton {
                    label: "Clear"
                    enabled: root.notificationModel.history.length > 0
                    onActivated: root.notificationModel.clearHistory()
                }

                ShellButton {
                    label: "Close"
                    onActivated: root.notificationModel.closeHistory()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.notificationModel.history.length === 0
                text: "No notifications"
                color: Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                horizontalAlignment: Text.AlignHCenter
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: historyColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: historyColumn

                    width: parent.width
                    spacing: Theme.spacingLg

                    Repeater {
                        model: root.notificationModel.history

                        delegate: Rectangle {
                            id: historyEntry

                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(82, historyContent.implicitHeight + 26)
                            radius: Theme.largeSurfaceCardRadius
                            color: historyEntry.modelData.urgencyName === "critical" ? Theme.dangerSurface : Theme.surface
                            border.color: historyEntry.modelData.urgencyName === "critical" ? Theme.danger : Theme.popupBorder
                            border.width: Theme.controlBorderWidth

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Theme.notificationAccentWidth
                                color: historyEntry.modelData.urgencyName === "critical" ? Theme.danger : Theme.accent
                                radius: Theme.notificationAccentRadius
                            }

                            ColumnLayout {
                                id: historyContent

                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: Theme.tightSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.listSpacing * 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: historyEntry.modelData.appName || "Notification"
                                        color: historyEntry.modelData.urgencyName === "critical" ? Theme.danger : Theme.menuActionText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaptionSize
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: Qt.formatTime(new Date(historyEntry.modelData.timestamp || Date.now()), "hh:mm")
                                        color: Theme.menuMutedText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: historyEntry.modelData.summary || historyEntry.modelData.urgencyName || ""
                                    color: Theme.popupText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyFontSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: historyEntry.modelData.body || ""
                                    color: Theme.menuText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.smallFontSize
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
