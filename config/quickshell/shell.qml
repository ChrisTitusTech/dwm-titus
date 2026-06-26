import QtQuick
import Quickshell
import Quickshell.Io
import qs.launcher
import qs.notifications
import qs.panel
import qs.power
import qs.state

ShellRoot {
    id: root

    DwmState {
        id: dwmState
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    LauncherModel {
        id: launcherModel
    }

    PowerMenuModel {
        id: powerMenuModel
    }

    NotificationModel {
        id: notificationModel
    }

    IpcHandler {
        target: "launcher"

        function close(): void {
            launcherModel.close();
        }

        function open(): void {
            launcherModel.open();
        }

        function toggle(): void {
            launcherModel.toggle();
        }
    }

    IpcHandler {
        target: "power"

        function close(): void {
            powerMenuModel.close();
        }

        function open(): void {
            powerMenuModel.open();
        }

        function toggle(): void {
            powerMenuModel.toggle();
        }
    }

    IpcHandler {
        target: "notifications"

        function clear(): void {
            notificationModel.clear();
        }

        function count(): int {
            return notificationModel.notifications.length;
        }

        function clearHistory(): void {
            notificationModel.clearHistory();
        }

        function closeHistory(): void {
            notificationModel.closeHistory();
        }

        function historyCount(): int {
            return notificationModel.history.length;
        }

        function historyLatestSummary(): string {
            return notificationModel.historyLatestSummary();
        }

        function openHistory(): void {
            notificationModel.openHistory();
        }

        function toggleHistory(): void {
            notificationModel.toggleHistory();
        }
    }

    LauncherWindow {
        launcherModel: launcherModel
    }

    PowerMenuWindow {
        powerMenuModel: powerMenuModel
    }

    NotificationPopupWindow {
        notificationModel: notificationModel
    }

    NotificationHistoryWindow {
        notificationModel: notificationModel
    }

    DwmPanel {
        state: dwmState
        clock: clock
    }
}
