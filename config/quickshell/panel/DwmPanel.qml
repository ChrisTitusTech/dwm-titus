import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// qmllint disable uncreatable-type
PanelWindow {
    id: root

    signal popupRequested(var panelWindow, string popupId)

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel
    required property var bluetoothModel
    required property var controlCenterModel
    required property var powerMenuModel
    required property bool primaryPanel

    readonly property color barForeground: Theme.dwmBarForeground
    readonly property color barInactive: Theme.dwmBarInactive
    readonly property color barActive: Theme.dwmBarActive
    readonly property color barUrgent: Theme.dwmBarUrgent

    function namedChildLayout(container) {
        const names = [];
        const children = container.children;

        for (let index = 0; index < children.length; index++) {
            const name = children[index].objectName;
            if (name && name.length > 0) names.push(name);
        }

        return names.join(",");
    }

    function layoutSignature() {
        const left = root.namedChildLayout(leftContent);
        const right = root.namedChildLayout(rightContent);
        const centerX = clockLabel.x + clockLabel.width / 2;
        const centered = clockLabel.parent === barLayout
            && Math.abs(centerX - barLayout.width / 2) <= 0.5;
        const center = centered ? clockLabel.objectName : clockLabel.objectName + "-off-center";

        return left + "|" + center + "|" + right;
    }

    function systemIconSizes(): string {
        return "bluetooth=" + bluetooth.iconPixelSize
            + ",network=" + network.iconPixelSize
            + ",volume=" + volume.iconPixelSize;
    }

    implicitHeight: 30
    color: Theme.dwmBarBackground
    exclusiveZone: 30
    aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(
        root.state.screenIndex(root.screen)) === -1

    anchors {
        top: true
        left: true
        right: true
    }

    RowLayout {
        id: barLayout

        anchors.fill: parent
        anchors.leftMargin: Theme.panelGap
        anchors.rightMargin: Theme.panelGap
        spacing: Theme.panelGap

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            RowLayout {
                id: leftContent

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width)
                height: parent.height
                spacing: Theme.panelGap

                LogoButton {
                    id: logoButton
                    objectName: "logo"

                    onActivated: {
                        root.popupRequested(root, "controlcenter");
                        root.controlCenterModel.toggle();
                    }
                }

                RowLayout {
                    id: workspaceRow
                    objectName: "workspaces"

                    spacing: 1

                    Repeater {
                        model: root.state.barWorkspaceIndexes(root.screen, root.primaryPanel)

                        delegate: WorkspaceButton {
                            required property int modelData

                            label: root.state.workspaceNames[modelData]
                            selected: modelData === root.state.currentWorkspaceForScreen(root.screen)
                            occupied: root.state.workspaceOccupied(modelData)
                            onClicked: root.primaryPanel ? root.state.switchWorkspace(modelData)
                                : root.state.switchWorkspaceForScreen(root.screen, modelData)
                        }
                    }
                }
            }
        }

        UiText {
            id: clockLabel
            objectName: "clock"

            text: Qt.formatDateTime(root.clock.date, "ddd, d MMM hh:mm")
            color: root.barForeground
            font.pixelSize: Theme.dwmBarFontSize
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            RowLayout {
                id: rightContent

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width)
                height: parent.height
                spacing: Theme.panelGap

                RunningAppsArea {
                    objectName: "running-apps"
                    state: root.state
                }

                BarIconButton {
                    id: bluetooth
                    objectName: "bluetooth"

                    active: root.bluetoothModel.visible
                    glyph: "󰂯"
                    onActivated: {
                        root.popupRequested(root, "bluetooth");
                        root.bluetoothModel.toggle();
                    }
                }

                NetworkBarModule {
                    id: network
                    objectName: "network"
                    networkModel: root.networkModel
                    onPopupRequested: root.popupRequested(root, "network")
                }

                VolumeBarModule {
                    id: volume
                    objectName: "volume"
                    controlsModel: root.controlsModel
                    onPopupRequested: root.popupRequested(root, "controls")
                }
            }
        }
    }
}
