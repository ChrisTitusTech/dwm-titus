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
            "command -v xdotool >/dev/null 2>&1 || exit 0; " +
            "wid=$(xdotool search --name '^dwm notifications$' 2>/dev/null | tail -n 1); [ -n \"$wid\" ] || exit 0; " +
            "eval \"$(xdotool getwindowgeometry --shell \"$wid\")\"; popup_width=${WIDTH:-380}; " +
            "active=$(xdotool getactivewindow 2>/dev/null || true); active_x=; active_y=; " +
            "if [ -n \"$active\" ]; then eval \"$(xdotool getwindowgeometry --shell \"$active\" | sed 's/^/active_/')\"; active_x=$(( active_X + active_WIDTH / 2 )); active_y=$(( active_Y + active_HEIGHT / 2 )); fi; " +
            "geom=; primary=; first=; " +
            "if command -v xrandr >/dev/null 2>&1; then while read -r line; do geom_candidate=$(printf '%s\\n' \"$line\" | sed -n 's/.* \\([0-9][0-9]*x[0-9][0-9]*[+][0-9][0-9]*[+][0-9][0-9]*\\).*/\\1/p'); [ -n \"$geom_candidate\" ] || continue; [ -z \"$first\" ] && first=$geom_candidate; printf '%s\\n' \"$line\" | grep -q ' primary ' && primary=$geom_candidate; monw=${geom_candidate%%x*}; rest=${geom_candidate#*x}; monh=${rest%%+*}; rest=${rest#*+}; monx=${rest%%+*}; mony=${rest#*+}; if [ -n \"$active_x\" ] && [ \"$active_x\" -ge \"$monx\" ] && [ \"$active_x\" -lt $(( monx + monw )) ] && [ \"$active_y\" -ge \"$mony\" ] && [ \"$active_y\" -lt $(( mony + monh )) ]; then geom=$geom_candidate; break; fi; done <<EOF\n$(xrandr --query | sed -n '/^[^ ]\\+ connected/p')\nEOF\nfi; " +
            "[ -n \"$geom\" ] || geom=$primary; [ -n \"$geom\" ] || geom=$first; " +
            "if [ -n \"$geom\" ]; then monw=${geom%%x*}; rest=${geom#*x}; monh=${rest%%+*}; rest=${rest#*+}; monx=${rest%%+*}; mony=${rest#*+}; else set -- $(xdotool getdisplaygeometry); monw=$1; monh=$2; monx=0; mony=0; fi; " +
            "x=$(( monx + monw - popup_width - 12 )); y=$(( mony + 42 )); [ \"$x\" -lt \"$monx\" ] && x=$monx; xdotool windowmove \"$wid\" \"$x\" \"$y\""
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
