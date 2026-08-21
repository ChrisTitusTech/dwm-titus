import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PopupWindow {
    id: root

    required property var notificationModel
    required property var panelWindow

    readonly property int popupWidth: 400
    readonly property int edgeMargin: Theme.rowSpacing

    visible: panelWindow !== null && panelWindow.screen !== null
        && notificationModel.notifications.length > 0
    implicitWidth: popupWidth
    implicitHeight: notificationsColumn.implicitHeight
    anchor.window: panelWindow
    anchor.rect.x: panelWindow
        ? Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
        : edgeMargin
    anchor.rect.y: Theme.panelHeight
    color: Theme.transparent

    ColumnLayout {
        id: notificationsColumn

        anchors.fill: parent
        opacity: 1.0
        spacing: Theme.spacingLg

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
