pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.core

ClickAwayPopup {
    id: root

    required property var updateCenterModel
    required property var panelWindow
    property int anchorX: panelWindow ? panelWindow.width / 2 : 0
    property bool savePending: false
    property bool saveObservedReload: false
    property string saveStatus: ""
    property int nowSeconds: Math.floor(Date.now() / 1000)
    readonly property bool ageClockRunning: ageTimer.running
    readonly property int cardWidth: Theme.scaledSize(480)
    readonly property int maximumHeight: panelWindow && panelWindow.screen
        ? Math.max(260, panelWindow.screen.height - Theme.panelHeight - Theme.popupMargin)
        : 260

    signal exclusiveOpenRequested

    function providerRecoverable(providerId) {
        const operation = root.updateCenterModel.activeOperation;
        return operation !== null && operation.providerId === providerId
            && ["interrupted", "system-failed", "system-complete/user-failed"].indexOf(operation.phase) >= 0;
    }

    function editorFocused() {
        return refreshSpin.activeFocus || refreshSpin.contentItem.activeFocus;
    }

    function requestSave() {
        root.saveStatus = "";
        root.saveObservedReload = false;
        root.savePending = true;
        if (!root.updateCenterModel.saveSettings()) root.savePending = false;
    }

    visible: panelWindow !== null && panelWindow.screen !== null && updateCenterModel.visible
    targetWindow: panelWindow
    popupX: root.anchorX - root.cardWidth / 2
    popupY: Theme.panelHeight
    popupWidth: root.cardWidth
    popupHeight: Math.min(updateCard.implicitHeight, root.maximumHeight)
    onDismissed: updateCenterModel.close()

    onVisibleChanged: {
        if (visible) {
            root.nowSeconds = Math.floor(Date.now() / 1000);
            root.exclusiveOpenRequested();
            Qt.callLater(function() { updateCard.forceActiveFocus(); });
        }
    }

    Timer {
        id: ageTimer

        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }

    ShellSurface {
        id: updateCard

        objectName: "updateCenterCard"
        anchors.fill: parent
        implicitHeight: Math.min(contentColumn.implicitHeight + margin * 2, root.maximumHeight)
        margin: Theme.spacingXl
        focus: true
        Accessible.role: Accessible.Dialog
        Accessible.name: "Update Center"

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.updateCenterModel.close();
                event.accepted = true;
            } else if (!root.editorFocused() && event.key === Qt.Key_R) {
                root.updateCenterModel.refresh(true);
                event.accepted = true;
            } else if (!root.editorFocused() && root.updateCenterModel.settingsMode && event.key === Qt.Key_S) {
                root.requestSave();
                event.accepted = true;
            }
        }

        Connections {
            target: root.updateCenterModel

            function onSettingsLoadingChanged() {
                if (!root.savePending) return;
                if (root.updateCenterModel.settingsLoading) {
                    root.saveObservedReload = true;
                } else if (root.saveObservedReload) {
                    root.savePending = false;
                    root.saveObservedReload = false;
                    root.saveStatus = root.updateCenterModel.settingsError.length > 0 ? "" : "Preferences saved";
                }
            }

            function onSettingsErrorChanged() {
                if (root.savePending && root.updateCenterModel.settingsError.length > 0) {
                    root.savePending = false;
                    root.saveObservedReload = false;
                    root.saveStatus = "";
                }
            }
        }

        ColumnLayout {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Theme.spacingLg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingLg

                UiText {
                    Layout.fillWidth: true
                    text: "Update Center"
                    color: Theme.menuText
                    font.pixelSize: Theme.fontTitleSize
                    font.bold: true
                    Accessible.role: Accessible.Heading
                }

                ShellButton {
                    label: "Refresh"
                    accessibleDescription: "Refresh all discovered providers"
                    enabled: !root.updateCenterModel.scanning
                    onActivated: root.updateCenterModel.refresh(true)
                }

                ShellButton {
                    label: "Close"
                    accessibleDescription: "Close Update Center"
                    onActivated: root.updateCenterModel.close()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                ShellButton {
                    Layout.fillWidth: true
                    label: "Updates"
                    primary: !root.updateCenterModel.settingsMode
                    onActivated: {
                        root.updateCenterModel.settingsMode = false;
                        root.updateCenterModel.discardSettings();
                    }
                }

                ShellButton {
                    Layout.fillWidth: true
                    label: "Settings"
                    primary: root.updateCenterModel.settingsMode
                    onActivated: root.updateCenterModel.showSettings()
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.updateCenterModel.message.length > 0
                text: root.updateCenterModel.message
                color: Theme.warning
                wrapMode: Text.Wrap
            }

            Flickable {
                id: updatesViewport

                objectName: "updateCenterUpdatesViewport"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(providerColumn.implicitHeight, Theme.scaledSize(430))
                visible: !root.updateCenterModel.settingsMode
                contentWidth: width
                contentHeight: providerColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                clip: true
                Accessible.role: Accessible.List
                Accessible.name: "Update providers"

                ColumnLayout {
                    id: providerColumn

                    width: updatesViewport.width
                    spacing: Theme.spacingLg

                    Repeater {
                        model: root.updateCenterModel.providers

                        ProviderRow {
                            required property var modelData

                            Layout.fillWidth: true
                            provider: modelData
                            globalBusy: root.updateCenterModel.busy
                            providerRecoverable: root.providerRecoverable(modelData.id)
                            providerActive: root.updateCenterModel.activeOperation !== null
                                && root.updateCenterModel.activeOperation.providerId === modelData.id
                            scanning: root.updateCenterModel.scanning
                            online: root.updateCenterModel.online
                            nowSeconds: root.nowSeconds
                            onUpdateRequested: providerId => root.updateCenterModel.launch(providerId)
                            onRecoverRequested: providerId => root.updateCenterModel.recover(providerId)
                            onOpenUrlRequested: url => Qt.openUrlExternally(url)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.updateCenterModel.settingsMode
                spacing: Theme.spacingXl

                SectionLabel { label: "Discovered providers" }

                Repeater {
                    model: root.updateCenterModel.providers

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true

                        UiText {
                            Layout.fillWidth: true
                            text: parent.modelData.name
                            color: Theme.menuText
                            elide: Text.ElideRight
                        }

                        UiText {
                            text: parent.modelData.status
                            color: Theme.menuMutedText
                        }
                    }
                }

                PanelSeparator {}

                RowLayout {
                    Layout.fillWidth: true

                    UiText {
                        Layout.fillWidth: true
                        text: "Refresh interval (seconds)"
                        color: Theme.menuText
                    }

                    Controls.SpinBox {
                        id: refreshSpin

                        objectName: "updateCenterRefreshInterval"
                        from: 300
                        to: 21600
                        editable: true
                        value: root.updateCenterModel.draftRefreshSeconds
                        Accessible.name: "Refresh interval in seconds"
                        onValueModified: root.updateCenterModel.draftRefreshSeconds = value
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    UiText {
                        Layout.fillWidth: true
                        text: "Always Show"
                        color: Theme.menuText
                    }

                    PanelToggleSwitch {
                        checked: root.updateCenterModel.draftAlwaysShow
                        accessibleName: "Always show Update Center indicator"
                        onToggled: root.updateCenterModel.draftAlwaysShow = !root.updateCenterModel.draftAlwaysShow
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    visible: root.updateCenterModel.settingsError.length > 0 || root.saveStatus.length > 0
                    text: root.updateCenterModel.settingsError.length > 0 ? root.updateCenterModel.settingsError : root.saveStatus
                    color: root.updateCenterModel.settingsError.length > 0 ? Theme.danger : Theme.success
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.AlertMessage
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item { Layout.fillWidth: true }

                    ShellButton {
                        label: "Discard"
                        enabled: !root.updateCenterModel.settingsLoading
                        onActivated: {
                            root.saveStatus = "";
                            root.updateCenterModel.discardSettings();
                        }
                    }

                    ShellButton {
                        label: "Save"
                        primary: true
                        enabled: !root.updateCenterModel.settingsLoading && !root.savePending
                        onActivated: root.requestSave()
                    }
                }
            }
        }
    }
}
