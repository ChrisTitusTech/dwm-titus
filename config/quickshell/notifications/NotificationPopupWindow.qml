import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root

    required property var notificationModel

    title: "dwm notifications"
    visible: notificationModel.notifications.length > 0
    implicitWidth: 380
    implicitHeight: notificationsColumn.implicitHeight + 24
    color: "#00000000"

    onVisibleChanged: {
        if (visible) {
            positionTimer.restart();
        }
    }

    onImplicitHeightChanged: {
        if (visible) {
            positionTimer.restart();
        }
    }

    Timer {
        id: positionTimer

        interval: 50
        repeat: false
        onTriggered: positionProcess.running = true
    }

    Process {
        id: positionProcess

        command: [
            "sh",
            "-c",
            "command -v xdotool >/dev/null 2>&1 || exit 0; wid=$(xdotool search --name '^dwm notifications$' 2>/dev/null | tail -n 1); [ -n \"$wid\" ] || exit 0; set -- $(xdotool getdisplaygeometry); x=$(( $1 - 380 - 12 )); [ \"$x\" -lt 0 ] && x=0; xdotool windowmove \"$wid\" \"$x\" 42"
        ]
        running: false
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
