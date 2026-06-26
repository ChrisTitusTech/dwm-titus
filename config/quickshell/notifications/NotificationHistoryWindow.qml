import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var notificationModel

    title: "dwm notification history"
    visible: notificationModel.historyVisible
    implicitWidth: 520
    implicitHeight: 560
    color: "#00000000"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Theme.text
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 58
                    Layout.preferredHeight: 30
                    radius: Theme.radius
                    color: clearMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Theme.text
                        font.pixelSize: Theme.smallFontSize
                        font.bold: true
                    }

                    MouseArea {
                        id: clearMouse

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notificationModel.clearHistory()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: Theme.radius
                    color: closeMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: Theme.text
                        font.pixelSize: 13
                        font.bold: true
                    }

                    MouseArea {
                        id: closeMouse

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notificationModel.closeHistory()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.notificationModel.history.length === 0
                text: "No notifications"
                color: Theme.textMuted
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
                    spacing: 8

                    Repeater {
                        model: root.notificationModel.history

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(74, historyContent.implicitHeight + 22)
                            radius: Theme.radius
                            color: modelData.urgencyName === "critical" ? "#4a2f35" : Theme.surface
                            border.color: modelData.urgencyName === "critical" ? "#bf616a" : Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: historyContent

                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.appName || "Notification"
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.smallFontSize
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: Qt.formatTime(new Date(modelData.timestamp || Date.now()), "hh:mm")
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.smallFontSize
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.summary || modelData.urgencyName || ""
                                    color: Theme.textStrong
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: modelData.body || ""
                                    color: Theme.text
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
