pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core

Flickable {
    id: root

    required property var defaultsModel
    required property var autostartModel
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    function statusColor(state) {
        if (state === "available" || state === "ready" || state === "enabled") return Theme.success;
        if (state === "partial" || state === "degraded" || state === "restricted"
                || state === "conditional" || state === "non-applicable") return Theme.warning;
        if (state === "unavailable" || state === "malformed" || state === "unsupported") return Theme.danger;
        return Theme.menuMutedText;
    }

    function titleForRole(role) {
        if (role === "file-manager") return "File manager";
        return role.charAt(0).toUpperCase() + role.slice(1);
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: root.defaultsModel.providerDetail
                color: root.statusColor(root.defaultsModel.providerState)
                font.bold: true
                elide: Text.ElideRight
            }
            ShellButton {
                label: root.defaultsModel.busy || root.autostartModel.busy
                    ? "Applying..." : "Refresh"
                enabled: !root.defaultsModel.busy && !root.autostartModel.busy
                onActivated: {
                    root.defaultsModel.refresh();
                    root.autostartModel.refresh();
                }
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.defaultsModel.messageFor("settings").length > 0
            text: root.defaultsModel.messageFor("settings")
            color: text === "Defaults updated" ? Theme.success : Theme.danger
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Default applications" }

        Repeater {
            model: root.defaultsModel.roles
            delegate: Rectangle {
                id: roleCard
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: roleColumn.implicitHeight + Theme.spacingLg * 2
                color: Theme.controlNormalFill
                border.color: root.statusColor(roleCard.modelData.state)
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                ColumnLayout {
                    id: roleColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: root.titleForRole(roleCard.modelData.id)
                            color: Theme.controlNormalText
                            font.bold: true
                        }
                        UiText {
                            text: roleCard.modelData.label.length > 0
                                ? roleCard.modelData.label : "Not configured"
                            color: root.statusColor(roleCard.modelData.state)
                            font.bold: true
                        }
                    }

                    UiText {
                        Layout.fillWidth: true
                        text: roleCard.modelData.detail
                        color: Theme.menuMutedText
                        wrapMode: Text.WordWrap
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        Repeater {
                            model: root.defaultsModel.candidates.filter(function(candidate) {
                                return candidate.role === roleCard.modelData.id;
                            })
                            delegate: ShellButton {
                                id: roleCandidate
                                required property var modelData
                                label: roleCandidate.modelData.label
                                    + (roleCandidate.modelData.desktopId === roleCard.modelData.desktopId
                                        ? " / Active" : "")
                                enabled: roleCandidate.modelData.state === "available"
                                    && roleCandidate.modelData.desktopId !== roleCard.modelData.desktopId
                                    && !root.defaultsModel.busy
                                onActivated: root.defaultsModel.setRole(roleCard.modelData.id,
                                    roleCandidate.modelData.desktopId, "settings")
                            }
                        }
                        ShellButton {
                            visible: root.defaultsModel.recoveries.some(function(recovery) {
                                return recovery.scope === roleCard.modelData.id
                                    && recovery.state === "available";
                            })
                            label: "Restore previous"
                            enabled: !root.defaultsModel.busy
                            onActivated: root.defaultsModel.resetRole(roleCard.modelData.id, "settings")
                        }
                    }
                }
            }
        }

        SectionLabel { label: "File type handlers" }

        Repeater {
            model: root.defaultsModel.mimes
            delegate: Rectangle {
                id: mimeCard
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: mimeColumn.implicitHeight + Theme.spacingLg * 2
                color: Theme.controlNormalFill
                border.color: root.statusColor(mimeCard.modelData.state)
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                ColumnLayout {
                    id: mimeColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingSm
                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: mimeCard.modelData.mime
                            color: Theme.controlNormalText
                            font.bold: true
                        }
                        UiText {
                            text: mimeCard.modelData.label.length > 0
                                ? mimeCard.modelData.label : "Not configured"
                            color: root.statusColor(mimeCard.modelData.state)
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        Repeater {
                            model: root.defaultsModel.mimeCandidates.filter(function(candidate) {
                                return candidate.mime === mimeCard.modelData.mime;
                            })
                            delegate: ShellButton {
                                id: mimeCandidate
                                required property var modelData
                                label: mimeCandidate.modelData.label
                                    + (mimeCandidate.modelData.desktopId === mimeCard.modelData.desktopId
                                        ? " / Active" : "")
                                enabled: mimeCandidate.modelData.state === "available"
                                    && mimeCandidate.modelData.desktopId !== mimeCard.modelData.desktopId
                                    && !root.defaultsModel.busy
                                onActivated: root.defaultsModel.setMime(mimeCard.modelData.mime,
                                    mimeCandidate.modelData.desktopId, "settings")
                            }
                        }
                        ShellButton {
                            visible: root.defaultsModel.recoveries.some(function(recovery) {
                                return recovery.scope === mimeCard.modelData.mime
                                    && recovery.state === "available";
                            })
                            label: "Restore previous"
                            enabled: !root.defaultsModel.busy
                            onActivated: root.defaultsModel.resetMime(mimeCard.modelData.mime, "settings")
                        }
                    }
                }
            }
        }

        SectionLabel { label: "Startup applications" }

        UiText {
            Layout.fillWidth: true
            text: root.autostartModel.providerDetail
            color: root.statusColor(root.autostartModel.providerState)
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            color: autostartSearch.activeFocus ? Theme.controlFocusFill : Theme.controlNormalFill
            border.color: autostartSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth
            radius: Theme.controlRadius
            TextInput {
                id: autostartSearch
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.controlFocusText
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.inputFontSize
                onTextChanged: root.autostartModel.setSearch(text)

                Component.onCompleted: text = root.autostartModel.searchQuery

                Connections {
                    target: root.autostartModel
                    function onSearchQueryChanged() {
                        if (autostartSearch.text !== root.autostartModel.searchQuery)
                            autostartSearch.text = root.autostartModel.searchQuery;
                    }
                }
            }
            UiText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingLg
                anchors.verticalCenter: parent.verticalCenter
                visible: autostartSearch.text.length === 0
                text: "Search startup applications"
                color: Theme.placeholder
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.autostartModel.messageFor("settings").length > 0
            text: root.autostartModel.messageFor("settings")
            color: text === "Autostart change saved for next login" ? Theme.success : Theme.danger
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.autostartModel.confirming && root.autostartModel.pendingOrigin === "settings"
            Layout.preferredHeight: confirmationColumn.implicitHeight + Theme.spacingLg * 2
            color: Theme.controlNormalFill
            border.color: Theme.warning
            border.width: Theme.controlBorderWidth
            radius: Theme.controlRadius
            ColumnLayout {
                id: confirmationColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                spacing: Theme.spacingSm
                UiText {
                    Layout.fillWidth: true
                    text: "Confirm session component change"
                    color: Theme.warning
                    font.bold: true
                }
                UiText {
                    Layout.fillWidth: true
                    text: "This change takes effect at the next login and may remove desktop functionality."
                    color: Theme.menuText
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    ShellButton {
                        label: "Cancel"
                        onActivated: root.autostartModel.cancelConfirmation("settings")
                    }
                    ShellButton {
                        label: "Confirm for next login"
                        onActivated: root.autostartModel.confirmAction("settings")
                    }
                }
            }
        }

        Repeater {
            model: root.autostartModel.filteredEntries
            delegate: Rectangle {
                id: entryCard
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: entryColumn.implicitHeight + Theme.spacingLg * 2
                color: Theme.controlNormalFill
                border.color: root.statusColor(entryCard.modelData.state)
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius
                ColumnLayout {
                    id: entryColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingSm
                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: entryCard.modelData.name
                            color: Theme.controlNormalText
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        UiText {
                            text: entryCard.modelData.state.toUpperCase()
                            color: root.statusColor(entryCard.modelData.state)
                            font.bold: true
                        }
                    }
                    UiText {
                        Layout.fillWidth: true
                        text: entryCard.modelData.id + " / " + entryCard.modelData.origin
                            + (entryCard.modelData.risk === "session-critical" ? " / session critical" : "")
                        color: Theme.menuMutedText
                        elide: Text.ElideRight
                    }
                    UiText {
                        Layout.fillWidth: true
                        text: entryCard.modelData.detail
                        color: Theme.menuText
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        ShellButton {
                            visible: entryCard.modelData.canEnable || entryCard.modelData.canDisable
                            label: entryCard.modelData.canDisable ? "Disable next login" : "Enable next login"
                            enabled: !root.autostartModel.busy
                                && (entryCard.modelData.canEnable || entryCard.modelData.canDisable)
                            onActivated: root.autostartModel.requestSet(entryCard.modelData,
                                entryCard.modelData.canDisable ? "disabled" : "enabled", "settings")
                        }
                        ShellButton {
                            visible: entryCard.modelData.canReset
                            label: "Reset to vendor"
                            enabled: !root.autostartModel.busy
                            onActivated: root.autostartModel.requestReset(entryCard.modelData, "settings")
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: Theme.spacingLg }
    }
}
