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
    color: Theme.transparent

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.listSpacing * 2

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 58
                    Layout.preferredHeight: Theme.buttonHeight
                    radius: Theme.radius
                    color: clearMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Theme.text
                        font.family: Theme.fontFamily
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
                    Layout.preferredWidth: Theme.closeButtonSize
                    Layout.preferredHeight: Theme.closeButtonSize
                    radius: Theme.radius
                    color: closeMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.panelFontSize
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
                    spacing: Theme.listSpacing * 2

                    Repeater {
                        model: root.notificationModel.history

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(74, historyContent.implicitHeight + 22)
                            radius: Theme.radius
                            color: modelData.urgencyName === "critical" ? Theme.dangerSurface : Theme.surface
                            border.color: modelData.urgencyName === "critical" ? Theme.danger : Theme.border
                            border.width: 1

                            ColumnLayout {
                                id: historyContent

                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: Theme.tightSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.listSpacing * 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.appName || "Notification"
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: Qt.formatTime(new Date(modelData.timestamp || Date.now()), "hh:mm")
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.summary || modelData.urgencyName || ""
                                    color: Theme.textStrong
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyFontSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: modelData.body || ""
                                    color: Theme.text
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
