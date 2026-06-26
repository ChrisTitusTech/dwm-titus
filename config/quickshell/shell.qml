import QtQuick
import Quickshell
import Quickshell.Io
import qs.launcher
import qs.panel
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

    LauncherWindow {
        launcherModel: launcherModel
    }

    DwmPanel {
        state: dwmState
        clock: clock
    }
}
