import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property string clockText: ""
    property string networkText: ""
    property string powerText: ""
    property string systemText: ""
    property string volumeText: ""
    property string activeWindowTitle: "Desktop"
    property int currentWorkspace: 0
    property int selectedLauncherIndex: 0
    property bool launcherVisible: false
    property string launcherQuery: ""
    property string launcherStatus: "Loading applications..."
    property var launcherApps: []
    property var filteredLauncherApps: []
    property var workspaceNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    function launcherHelperCommand(action, args) {
        const argv = args || [];
        const script = "if command -v dwm-quickshell-launcher >/dev/null 2>&1; then exec dwm-quickshell-launcher \"$@\"; fi; data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus; exec \"$data_dir/scripts/dwm-quickshell-launcher\" \"$@\"";

        return ["sh", "-c", script, "dwm-quickshell-launcher", action].concat(argv);
    }

    function appMatchesQuery(app, query) {
        const needle = query.trim().toLowerCase();

        if (needle.length === 0) {
            return true;
        }

        return app.name.toLowerCase().indexOf(needle) >= 0 ||
            app.generic.toLowerCase().indexOf(needle) >= 0 ||
            app.comment.toLowerCase().indexOf(needle) >= 0 ||
            app.keywords.toLowerCase().indexOf(needle) >= 0 ||
            app.categories.toLowerCase().indexOf(needle) >= 0 ||
            app.exec.toLowerCase().indexOf(needle) >= 0;
    }

    function closeLauncher() {
        root.launcherVisible = false;
        root.launcherQuery = "";
        root.filteredLauncherApps = [];
        root.selectedLauncherIndex = 0;
    }

    function refreshFilteredLauncherApps() {
        if (!root.launcherVisible) {
            root.filteredLauncherApps = [];
            root.selectedLauncherIndex = 0;
            return;
        }

        const apps = root.launcherApps.filter(app => root.appMatchesQuery(app, root.launcherQuery));

        if (root.selectedLauncherIndex >= apps.length) {
            root.selectedLauncherIndex = Math.max(0, apps.length - 1);
        }

        root.filteredLauncherApps = apps;
    }

    function launchApp(app) {
        if (!app || app.desktopFile.length === 0) {
            return;
        }

        launcherLaunchProcess.command = root.launcherHelperCommand("launch", [app.desktopFile]);
        launcherLaunchProcess.running = true;
        root.closeLauncher();
    }

    function launchSelectedApp() {
        const apps = root.filteredLauncherApps;

        if (apps.length === 0) {
            return;
        }

        root.launchApp(apps[root.selectedLauncherIndex]);
    }

    function openLauncher() {
        root.launcherVisible = true;
        root.launcherQuery = "";
        root.selectedLauncherIndex = 0;
        root.launcherStatus = "Loading applications...";
        root.refreshFilteredLauncherApps();
        if (!launcherIndexProcess.running) {
            launcherIndexProcess.running = true;
        }
        Qt.callLater(function() {
            launcherSearch.forceActiveFocus();
            launcherSearch.cursorPosition = launcherSearch.text.length;
        });
    }

    function parseLauncherApps(text) {
        const apps = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 6) {
                continue;
            }

            apps.push({
                "name": fields[0],
                "generic": fields[1],
                "comment": fields[2],
                "exec": fields[3],
                "icon": fields[4],
                "desktopFile": fields[5],
                "keywords": fields.length >= 7 ? fields[6] : "",
                "categories": fields.length >= 8 ? fields[7] : ""
            });
        }

        root.launcherApps = apps;
        root.launcherStatus = apps.length === 1 ? "1 application" : apps.length + " applications";
        root.selectedLauncherIndex = 0;
        root.refreshFilteredLauncherApps();
    }

    function selectLauncherRelative(delta) {
        const apps = root.filteredLauncherApps;

        if (apps.length === 0) {
            root.selectedLauncherIndex = 0;
            return;
        }

        root.selectedLauncherIndex = (root.selectedLauncherIndex + delta + apps.length) % apps.length;
        launcherResults.positionViewAtIndex(root.selectedLauncherIndex, ListView.Contain);
    }

    function toggleLauncher() {
        if (root.launcherVisible) {
            root.closeLauncher();
        } else {
            root.openLauncher();
        }
    }

    function updateWorkspaceState(text) {
        const lines = text.trim().split("\n");

        for (const line of lines) {
            const separator = line.indexOf("=");

            if (separator < 0) {
                continue;
            }

            const key = line.slice(0, separator);
            const value = line.slice(separator + 1);

            if (key === "current") {
                const parsed = parseInt(value, 10);

                root.currentWorkspace = isNaN(parsed) ? 0 : parsed;
            } else if (key === "names") {
                root.workspaceNames = value.length > 0 ? value.split("|") : [];
            } else if (key === "title") {
                root.activeWindowTitle = value.length > 0 ? value : "Desktop";
            }
        }
    }

    function switchWorkspace(index) {
        switchWorkspaceProcess.command = ["dwm-quickshell-state", "switch", index.toString()];
        switchWorkspaceProcess.running = true;
    }

    IpcHandler {
        target: "launcher"

        function close(): void {
            root.closeLauncher();
        }

        function open(): void {
            root.openLauncher();
        }

        function toggle(): void {
            root.toggleLauncher();
        }
    }

    Process {
        id: dateProcess

        command: ["date", "+%a %b %d  %H:%M"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.clockText = this.text.trim()
        }
    }

    Process {
        id: systemProcess

        command: ["sh", "-c", "load=$(cut -d ' ' -f1 /proc/loadavg); mem=$(awk '/MemTotal/ { total = $2 } /MemAvailable/ { available = $2 } END { printf \"%d\", (total - available) * 100 / total }' /proc/meminfo); printf 'CPU %s  RAM %s%%' \"$load\" \"$mem\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.systemText = this.text.trim()
        }
    }

    Process {
        id: networkProcess

        command: ["sh", "-c", "iface=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $5 }'); if [ -n \"$iface\" ]; then state=$(cat \"/sys/class/net/$iface/operstate\" 2>/dev/null || printf unknown); printf 'NET %s %s' \"$iface\" \"$state\"; else printf 'NET offline'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.networkText = this.text.trim()
        }
    }

    Process {
        id: volumeProcess

        command: ["sh", "-c", "if command -v pactl >/dev/null 2>&1; then mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{ print $2 }'); volume=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk 'match($0, /[0-9]+%/) { print substr($0, RSTART, RLENGTH); exit }'); if [ \"$mute\" = yes ]; then printf 'VOL muted'; else printf 'VOL %s' \"${volume:-n/a}\"; fi; else printf 'VOL n/a'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.volumeText = this.text.trim()
        }
    }

    Process {
        id: powerProcess

        command: ["sh", "-c", "battery=; for path in /sys/class/power_supply/BAT*; do [ -e \"$path\" ] || continue; battery=$path; break; done; if [ -n \"$battery\" ]; then capacity=$(cat \"$battery/capacity\" 2>/dev/null || printf n/a); status=$(cat \"$battery/status\" 2>/dev/null || printf unknown); printf 'BAT %s%% %s' \"$capacity\" \"$status\"; else printf 'AC'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.powerText = this.text.trim()
        }
    }

    Process {
        id: workspaceProcess

        command: ["dwm-quickshell-state", "watch"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: function(data) {
                root.updateWorkspaceState(data);
            }
        }
    }

    Process {
        id: launcherIndexProcess

        command: root.launcherHelperCommand("list")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseLauncherApps(this.text)
        }
    }

    Process {
        id: launcherLaunchProcess

        command: ["sh", "-c", "exit 0"]
        running: false
    }

    Process {
        id: switchWorkspaceProcess

        command: ["dwm-quickshell-state", "switch", root.currentWorkspace.toString()]
        running: false
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            if (!dateProcess.running) {
                dateProcess.running = true;
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: {
            if (!systemProcess.running) {
                systemProcess.running = true;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!networkProcess.running) {
                networkProcess.running = true;
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: {
            if (!volumeProcess.running) {
                volumeProcess.running = true;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!powerProcess.running) {
                powerProcess.running = true;
            }
        }
    }

    FloatingWindow {
        id: launcherWindow

        title: "dwm launcher"
        visible: root.launcherVisible
        implicitWidth: 620
        implicitHeight: 430
        color: "#00000000"

        Rectangle {
            anchors.fill: parent
            color: "#2e3440"
            border.color: "#4c566a"
            border.width: 1
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: "Applications"
                    color: "#d8dee9"
                    font.pixelSize: 18
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: "#3b4252"
                    radius: 4

                    TextInput {
                        id: launcherSearch

                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#eceff4"
                        selectionColor: "#81a1c1"
                        selectedTextColor: "#2e3440"
                        text: root.launcherQuery
                        font.pixelSize: 16
                        clip: true

                        onTextChanged: {
                            root.launcherQuery = text;
                            root.selectedLauncherIndex = 0;
                            root.refreshFilteredLauncherApps();
                        }

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Down) {
                                root.selectLauncherRelative(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                root.selectLauncherRelative(-1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.launchSelectedApp();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.closeLauncher();
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: launcherSearch.text.length === 0
                        text: "Search applications"
                        color: "#8f9aa8"
                        font.pixelSize: 16
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.launcherStatus
                    color: "#aeb7c4"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                ListView {
                    id: launcherResults

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.filteredLauncherApps

                    delegate: Rectangle {
                        required property int index
                        required property var modelData

                        width: launcherResults.width
                        height: 54
                        radius: 4
                        color: index === root.selectedLauncherIndex ? "#3b4252" : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchApp(parent.modelData)
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                text: modelData.name
                                color: "#d8dee9"
                                font.pixelSize: 14
                                font.bold: index === root.selectedLauncherIndex
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.generic.length > 0 ? modelData.generic : modelData.comment
                                color: "#aeb7c4"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        implicitHeight: 30
        color: "#2e3440"
        exclusiveZone: 30
        aboveWindows: true

        anchors {
            top: true
            left: true
            right: true
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
                text: "dwm"
                color: "#d8dee9"
                font.pixelSize: 13
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            Repeater {
                model: root.workspaceNames

                delegate: Rectangle {
                    required property int index
                    required property string modelData

                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 3
                    color: index === root.currentWorkspace ? "#3b4252" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.index === root.currentWorkspace ? "#81a1c1" : "#d8dee9"
                        font.pixelSize: 13
                        font.bold: parent.index === root.currentWorkspace
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchWorkspace(parent.index)
                    }
                }
            }

            Text {
                Layout.maximumWidth: 360
                text: root.activeWindowTitle
                color: "#d8dee9"
                elide: Text.ElideRight
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: root.powerText
                color: "#d8dee9"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: root.volumeText
                color: "#d8dee9"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: root.networkText
                color: "#d8dee9"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: root.systemText
                color: "#d8dee9"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: root.clockText
                color: "#81a1c1"
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
