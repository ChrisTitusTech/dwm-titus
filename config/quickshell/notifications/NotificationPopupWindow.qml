import QtQuick
import QtQuick.Layouts
import Quickshell

FloatingWindow {
    id: root

    required property var notificationModel

    title: "dwm notifications"
    visible: notificationModel.notifications.length > 0
    implicitWidth: 380
    implicitHeight: notificationsColumn.implicitHeight + 24
    color: "#00000000"

    ColumnLayout {
        id: notificationsColumn

        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Repeater {
            model: root.notificationModel.notifications

            delegate: NotificationCard {
                required property var modelData

                item: modelData
                onDismiss: root.notificationModel.dismiss(modelData.key)
                onExpired: root.notificationModel.expire(modelData.key)
            }
        }
    }
}
