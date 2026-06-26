import QtQuick
import QtQuick.Layouts
import Quickshell

PanelWindow {
    id: root

    required property var notificationModel

    visible: notificationModel.notifications.length > 0
    implicitWidth: 380
    implicitHeight: notificationsColumn.implicitHeight + 24
    color: "#00000000"
    exclusiveZone: 0
    aboveWindows: true

    anchors {
        top: true
        right: true
    }

    margins {
        top: 42
        right: 12
    }

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
