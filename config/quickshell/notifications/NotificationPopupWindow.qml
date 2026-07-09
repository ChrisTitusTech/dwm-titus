import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PopupWindow {
    id: root

    required property var notificationModel
    required property var panelWindow

    readonly property int popupWidth: 380
    readonly property int edgeMargin: Theme.rowSpacing

    visible: notificationModel.notifications.length > 0
    implicitWidth: popupWidth
    implicitHeight: notificationsColumn.implicitHeight + 24
    anchor.window: panelWindow
    anchor.rect.x: Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
    anchor.rect.y: Theme.panelHeight
    color: Theme.transparent

    ColumnLayout {
        id: notificationsColumn

        anchors.fill: parent
        anchors.margins: 12
        spacing: Theme.listSpacing * 2

        Repeater {
            model: root.notificationModel.notifications

            delegate: NotificationCard {
                id: notificationCard

                required property var modelData

                item: notificationCard.modelData
                onDismiss: root.notificationModel.dismiss(notificationCard.modelData.key)
                onExpired: root.notificationModel.expire(notificationCard.modelData.key)
            }
        }
    }
}
