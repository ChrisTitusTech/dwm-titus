pragma ComponentBehavior: Bound

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
    property int nowSeconds: Math.floor(Date.now() / 1000)
    property int instantiatedItemDelegates: 0
    readonly property bool providerBusy: root.globalBusy && !root.providerRecoverable
    readonly property string relativeCheckAge: root.formatCheckAge(root.provider.lastSuccess, root.nowSeconds)
    readonly property var providerIcons: ({
        "fedora": "../assets/update-center/fedora.svg",
        "dwm-titus": "../assets/update-center/dwm-titus.png",
        "flatpak": "../assets/update-center/flatpak.svg",
        "mise": "../assets/update-center/mise.svg",
        "other": "../assets/update-center/other.svg"
    })

    signal updateRequested(string providerId)
    signal recoverRequested(string providerId)
    signal openUrlRequested(string url)

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
        if (root.provider.restart === "session") return "Restart session";
        if (root.provider.restart === "system") return "Restart system";
        return "Up to date";
    }

    function visibleDetail() {
        if (root.provider.detail.length > 0) return root.provider.detail;
        if (root.provider.restart === "session") return "Sign out and back in to complete this update.";
        if (root.provider.restart === "system") return "Restart the system to complete this update.";
        return "";
    }

    function formatCheckAge(lastSuccess, nowSeconds) {
        const timestamp = Number(lastSuccess || 0);
        if (timestamp <= 0) return "Not checked";
        const seconds = Math.max(0, Math.floor(Number(nowSeconds)) - timestamp);
        if (seconds < 60) return seconds + "s ago";
        if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago";
        return Math.floor(seconds / 86400) + "d ago";
    }

    function checkAge() {
        return root.relativeCheckAge;
    }

    function itemDescription(item) {
        return item.name + (item.scope.length > 0 ? " (" + item.scope + ")" : "")
            + "\n" + item.current + " -> " + item.available;
    }

    function toggleExpanded() {
        if (root.provider.items.length === 0) return false;
        root.expanded = !root.expanded;
        return true;
    }

    function requestAction() {
        if (root.providerBusy) return false;
        if (root.providerRecoverable) root.recoverRequested(root.provider.id);
        else root.updateRequested(root.provider.id);
        return true;
    }

    function requestOpen(item) {
        if (!item || typeof item.url !== "string" || !/^https:\/\/[^\s]+$/.test(item.url)) return false;
        root.openUrlRequested(item.url);
        return true;
    }

    implicitHeight: rowColumn.implicitHeight + Theme.spacingXl * 2
    color: Theme.controlNormalFill
    border.color: root.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
    radius: Theme.controlRadius
    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.name: root.provider.name + ", " + root.statusSummary()
    Accessible.description: root.provider.managed !== null ? "Managed items " + root.provider.managed : root.provider.name + " updates"

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.toggleExpanded();
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

            Item {
                Layout.preferredWidth: Theme.scaledSize(32)
                Layout.preferredHeight: Theme.scaledSize(32)
                Accessible.role: Accessible.Graphic
                Accessible.name: root.provider.name + " logo"

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    source: root.iconFor(root.provider.id)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
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
                    text: root.statusSummary()
                        + (root.provider.managed !== null ? "  |  Managed " + root.provider.managed : "")
                        + "  |  " + root.relativeCheckAge
                    color: root.provider.freshness === "error" ? Theme.danger
                        : root.provider.freshness === "stale" ? Theme.warning : Theme.menuMutedText
                    font.pixelSize: Theme.fontBodySmallSize
                    elide: Text.ElideRight
                }
            }

            ShellButton {
                label: root.providerBusy ? "Busy" : root.providerRecoverable ? "Recover" : "Update"
                accessibleDescription: root.provider.name + " provider action"
                enabled: root.providerRecoverable || (!root.globalBusy && root.provider.updateAvailable)
                primary: root.providerRecoverable
                onActivated: root.requestAction()
            }

            ShellButton {
                label: root.expanded ? "Collapse" : "Details"
                accessibleDescription: root.provider.name + " update details"
                enabled: root.provider.items.length > 0
                onActivated: root.toggleExpanded()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.visibleDetail().length > 0
            text: root.visibleDetail()
            color: root.provider.errorCode.length > 0 ? Theme.danger : Theme.menuMutedText
            font.pixelSize: Theme.fontBodySmallSize
            wrapMode: Text.Wrap
        }

        ListView {
            id: itemViewport

            objectName: "providerItemsViewport"
            Layout.fillWidth: true
            Layout.preferredHeight: root.expanded
                ? Math.min(root.provider.items.length * Theme.scaledSize(56), Theme.scaledSize(180)) : 0
            visible: root.expanded && root.provider.items.length > 0
            model: root.expanded ? root.provider.items : []
            spacing: Theme.spacingSm
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            cacheBuffer: 0
            activeFocusOnTab: visible
            Accessible.role: Accessible.List
            Accessible.name: root.provider.name + " update items"

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Theme.animationFast }
            }

            delegate: Rectangle {
                id: itemRow

                required property var modelData
                readonly property var item: modelData

                width: ListView.view.width
                height: Math.max(Theme.scaledSize(52), itemText.implicitHeight + Theme.spacingLg * 2)
                color: Theme.menuBackground
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + ", " + modelData.current + " to " + modelData.available
                Component.onCompleted: root.instantiatedItemDelegates++
                Component.onDestruction: root.instantiatedItemDelegates--

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    UiText {
                        id: itemText

                        Layout.fillWidth: true
                        text: root.itemDescription(itemRow.item)
                        color: Theme.menuText
                        font.pixelSize: Theme.fontBodySmallSize
                        wrapMode: Text.Wrap
                    }

                    ShellButton {
                        visible: itemRow.item.url.length > 0
                        label: "Open"
                        accessibleDescription: "Open trusted project link for " + itemRow.item.name
                        onActivated: root.requestOpen(itemRow.item)
                    }
                }
            }
        }
    }
}
