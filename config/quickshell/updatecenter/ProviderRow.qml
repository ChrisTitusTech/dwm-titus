import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property var provider
    property bool expanded: false
    property bool globalBusy: false
    property bool providerRecoverable: false
    property bool providerActive: false
    property bool scanning: false
    property bool online: true
    readonly property bool providerBusy: root.globalBusy && !root.providerRecoverable
    readonly property var providerIcons: ({
        "fedora": "../assets/update-center/fedora.svg",
        "dwm-titus": "../assets/update-center/dwm-titus.png",
        "flatpak": "../assets/update-center/flatpak.svg",
        "mise": "../assets/update-center/mise.svg",
        "other": "../assets/update-center/other.svg"
    })

    signal updateRequested(string providerId)
    signal recoverRequested(string providerId)

    function iconFor(providerId) {
        return root.providerIcons[providerId] || root.providerIcons.other;
    }

    function statusSummary() {
        if (root.providerRecoverable) return "Recovery required";
        if (root.providerActive) return "Active";
        if (root.scanning) return "Checking";
        if (!root.online) return "Offline";
        if (root.provider.freshness === "stale") return "Stale";
        if (root.provider.freshness === "error") return "Failed";
        if (root.provider.status === "restricted") return "Restricted";
        if (root.provider.status === "partial") return "Partial";
        if (root.provider.pending > 0) return root.provider.pending + " pending";
        return "Up to date";
    }

    function checkAge() {
        const seconds = Number(root.provider.lastSuccess || 0);
        if (seconds <= 0) return "Not checked";
        if (seconds < 60) return seconds + "s ago";
        if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago";
        return Math.floor(seconds / 86400) + "d ago";
    }

    implicitHeight: rowColumn.implicitHeight + Theme.spacingXl * 2
    color: Theme.controlNormalFill
    border.color: root.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
    radius: Theme.controlRadius
    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.name: root.provider.name + ", " + root.statusSummary()
    Accessible.description: "Managed items " + (root.provider.managed === null ? "unknown" : root.provider.managed)

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.expanded = !root.expanded;
            event.accepted = true;
        }
    }

    ColumnLayout {
        id: rowColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingXl
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXl

            Image {
                Layout.preferredWidth: Theme.scaledSize(32)
                Layout.preferredHeight: Theme.scaledSize(32)
                source: root.iconFor(root.provider.id)
                fillMode: Image.PreserveAspectFit
                smooth: true
                Accessible.role: Accessible.Graphic
                Accessible.name: root.provider.name + " logo"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.compactSpacing

                UiText {
                    Layout.fillWidth: true
                    text: root.provider.name
                    color: Theme.menuText
                    font.bold: true
                    elide: Text.ElideRight
                }

                UiText {
                    Layout.fillWidth: true
                    text: root.statusSummary() + "  |  Managed "
                        + (root.provider.managed === null ? "unknown" : root.provider.managed)
                        + "  |  " + root.checkAge()
                    color: root.provider.freshness === "error" ? Theme.danger
                        : root.provider.freshness === "stale" ? Theme.warning : Theme.menuMutedText
                    font.pixelSize: Theme.fontBodySmallSize
                    elide: Text.ElideRight
                }
            }

            ShellButton {
                label: root.providerBusy ? "Busy" : root.providerRecoverable ? "Recover" : "Update"
                accessibleDescription: root.provider.name + " provider action"
                enabled: root.providerRecoverable || !root.globalBusy
                primary: root.providerRecoverable
                onActivated: {
                    if (root.providerRecoverable) root.recoverRequested(root.provider.id);
                    else root.updateRequested(root.provider.id);
                }
            }

            ShellButton {
                label: root.expanded ? "Collapse" : "Details"
                accessibleDescription: root.provider.name + " update details"
                enabled: root.provider.items.length > 0
                onActivated: root.expanded = !root.expanded
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.provider.detail.length > 0
            text: root.provider.detail
            color: root.provider.errorCode.length > 0 ? Theme.danger : Theme.menuMutedText
            font.pixelSize: Theme.fontBodySmallSize
            wrapMode: Text.Wrap
        }

        Flickable {
            id: itemViewport

            objectName: "providerItemsViewport"
            Layout.fillWidth: true
            Layout.preferredHeight: root.expanded ? Math.min(itemColumn.implicitHeight, Theme.scaledSize(180)) : 0
            visible: root.expanded && root.provider.items.length > 0
            contentWidth: width
            contentHeight: itemColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Accessible.role: Accessible.List
            Accessible.name: root.provider.name + " update items"

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Theme.animationFast }
            }

            ColumnLayout {
                id: itemColumn

                width: itemViewport.width
                spacing: Theme.spacingSm

                Repeater {
                    model: root.provider.items

                    Rectangle {
                        id: itemRow

                        required property var modelData
                        readonly property var item: modelData

                        Layout.fillWidth: true
                        implicitHeight: itemText.implicitHeight + Theme.spacingLg * 2
                        color: Theme.menuBackground
                        border.color: Theme.controlNormalBorder
                        border.width: Theme.controlBorderWidth
                        radius: Theme.controlRadius
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + ", " + modelData.current + " to " + modelData.available

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLg
                            spacing: Theme.spacingLg

                            UiText {
                                id: itemText

                                Layout.fillWidth: true
                                text: itemRow.item.name + (itemRow.item.scope.length > 0 ? " (" + itemRow.item.scope + ")" : "")
                                    + "\n" + itemRow.item.current + " -> " + itemRow.item.available
                                color: Theme.menuText
                                font.pixelSize: Theme.fontBodySmallSize
                                wrapMode: Text.Wrap
                            }

                            ShellButton {
                                visible: itemRow.item.url.length > 0
                                label: "Open"
                                accessibleDescription: "Open trusted project link for " + itemRow.item.name
                                onActivated: {
                                    const item = itemRow.item;
                                    if (/^https:\/\/[^\s]+$/.test(item.url)) Qt.openUrlExternally(item.url);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
