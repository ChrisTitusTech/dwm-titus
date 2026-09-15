import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PopupWindow {
    id: root

    required property var notificationModel
    required property var panelWindow

    readonly property int popupWidth: Math.min(Theme.scaledSize(400),
        panelWindow ? Math.max(1, panelWindow.width - edgeMargin * 2) : Theme.scaledSize(400))
    readonly property int edgeMargin: Theme.rowSpacing

    visible: panelWindow !== null && panelWindow.screen !== null
        && notificationModel.notifications.length > 0
    implicitWidth: popupWidth
    implicitHeight: Math.min(notificationsColumn.implicitHeight,
        panelWindow && panelWindow.screen
            ? Math.max(1, panelWindow.screen.height - Theme.panelHeight - edgeMargin) : 1)
    anchor.window: panelWindow
    anchor.rect.x: panelWindow
        ? Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
        : edgeMargin
    anchor.rect.y: Theme.panelHeight
    color: Theme.transparent

    Flickable {
        id: viewport
        objectName: "notificationViewport"
        anchors.fill: parent
        contentWidth: width
        contentHeight: notificationsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        onVisibleChanged: if (visible) contentY = 0

        ColumnLayout {
            id: notificationsColumn

            width: viewport.width
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
}
