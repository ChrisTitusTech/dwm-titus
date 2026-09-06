import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var systemManagementModel
    required property var capabilities
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    activeFocusOnTab: true

    function scrollTo(position) {
        root.contentY = Math.max(0, Math.min(position, Math.max(0, root.contentHeight - root.height)));
    }

    Keys.onPressed: event => {
        const lineStep = Math.max(Theme.spacingXl, 40);
        const pageStep = Math.max(lineStep, root.height - Theme.spacingXl);
        if (event.key === Qt.Key_Down) root.scrollTo(root.contentY + lineStep);
        else if (event.key === Qt.Key_Up) root.scrollTo(root.contentY - lineStep);
        else if (event.key === Qt.Key_PageDown) root.scrollTo(root.contentY + pageStep);
        else if (event.key === Qt.Key_PageUp) root.scrollTo(root.contentY - pageStep);
        else if (event.key === Qt.Key_Home) root.scrollTo(0);
        else if (event.key === Qt.Key_End) root.scrollTo(root.contentHeight - root.height);
        else return;
        event.accepted = true;
    }

    function statusColor(status) {
        if (status === "available" || status === "ready") return Theme.success;
        if (status === "partial" || status === "restricted") return Theme.warning;
        if (status === "unavailable" || status === "failure") return Theme.danger;
        return Theme.menuMutedText;
    }

    function severityColor(severity) {
        if (severity === "critical" || severity === "security") return Theme.danger;
        if (severity === "important" || severity === "bugfix") return Theme.warning;
        return Theme.accent;
    }

    function restartLabel(value) {
        if (value === "none") return "No restart required";
        if (value === "application") return "Restart applications";
        if (value === "session") return "Log out and back in";
        if (value === "system") return "Restart the computer";
        if (value === "security-session") return "Security update / log out required";
        if (value === "security-system") return "Security update / restart required";
        return "Restart requirement unknown";
    }

    function ageLabel(value) {
        if (!/^(0|[1-9][0-9]*)$/.test(value)) return "Unknown";
        const seconds = Number(value);
        if (seconds < 60) return seconds + "s ago";
        if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago";
        return Math.floor(seconds / 86400) + "d ago";
    }

    component StatusCard: Rectangle {
        id: statusCard

        required property string label
        required property string status
        required property string value
        required property string detail
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(72, statusContent.implicitHeight + Theme.spacingLg * 2)
        color: Theme.controlNormalFill
        border.color: root.statusColor(status)
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius

        ColumnLayout {
            id: statusContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                PlainText {
                    Layout.fillWidth: true
                    text: statusCard.label
                    color: Theme.controlNormalText
                    font.bold: true
                    elide: Text.ElideRight
                }
                PlainText {
                    text: statusCard.value
                    color: root.statusColor(statusCard.status)
                    font.bold: true
                }
            }
            PlainText {
                Layout.fillWidth: true
                text: statusCard.detail
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }
    }

    component DataList: ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 320)
        clip: true
        spacing: Theme.spacingSm
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        keyNavigationEnabled: true
    }

    component PlainText: UiText {
        textFormat: Text.PlainText
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            PlainText {
                Layout.fillWidth: true
                text: root.systemManagementModel.providerDetail
                color: root.statusColor(root.systemManagementModel.providerState)
                font.bold: true
                elide: Text.ElideRight
            }
            PlainText {
                text: "READ-ONLY STATUS"
                color: Theme.menuMutedText
                font.pixelSize: Theme.fontCaptionSize
                font.bold: true
            }
            ShellButton {
                label: root.systemManagementModel.busy ? "Loading..." : "Reload status"
                enabled: !root.systemManagementModel.busy
                onActivated: root.systemManagementModel.refresh()
            }
        }

        PlainText {
            Layout.fillWidth: true
            visible: root.systemManagementModel.snapshotState === "loading"
                || root.systemManagementModel.snapshotState === "failure"
                || root.systemManagementModel.snapshotState === "partial"
            text: root.systemManagementModel.message
            color: root.statusColor(root.systemManagementModel.snapshotState)
            wrapMode: Text.WordWrap
        }

        PlainText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.systemManagementModel.discoveryDetail
            color: Theme.warning
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Fedora updates" }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 720 ? 1 : 3
            rowSpacing: Theme.spacingMd
            columnSpacing: Theme.spacingMd

            StatusCard {
                label: "Available updates"
                status: root.systemManagementModel.updateSummary.status
                value: root.systemManagementModel.updateSummary.value === "unknown"
                    ? "Unknown" : root.systemManagementModel.updateSummary.value
                detail: root.systemManagementModel.updateSummary.detail
            }
            StatusCard {
                label: "Last refresh"
                status: root.systemManagementModel.updateLastRefresh.status
                value: root.ageLabel(root.systemManagementModel.updateLastRefresh.value)
                detail: root.systemManagementModel.updateLastRefresh.detail
            }
            StatusCard {
                label: "Restart guidance"
                status: root.systemManagementModel.updateRestart.status
                value: root.restartLabel(root.systemManagementModel.updateRestart.value)
                detail: root.systemManagementModel.updateRestart.detail
            }
        }

        StatusCard {
            readonly property var operation: root.systemManagementModel.operation.progress
                || root.systemManagementModel.activeOperation
            visible: operation !== null
            label: operation === null ? "Active operation" : operation.actionId
            status: "partial"
            value: operation === null ? "" : operation.percent === "unknown"
                ? operation.state : operation.state + " / " + operation.percent + "%"
            detail: operation === null ? "" : operation.detail
        }

        StatusCard {
            readonly property var result: root.systemManagementModel.operation.result
            visible: result !== null
            label: result === null ? "Verified operation result" : result.actionId
            status: result !== null && result.state === "succeeded" ? "available" : "partial"
            value: result === null ? "" : result.state
            detail: result === null ? "" : result.detail
        }

        PlainText {
            Layout.fillWidth: true
            visible: root.systemManagementModel.operation.detail.length > 0
            text: root.systemManagementModel.operation.detail
            color: root.systemManagementModel.operation.blocked ? Theme.danger : Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        StatusCard {
            visible: root.systemManagementModel.terminalHandoff !== null
            label: "Update result awaiting recovery"
            status: "partial"
            value: root.systemManagementModel.terminalHandoff === null ? ""
                : root.systemManagementModel.terminalHandoff.kind
            detail: "The durable operation result is being reconciled before another update action can start."
        }

        SectionLabel {
            visible: root.systemManagementModel.updates.length > 0
            label: "Update details"
        }

        DataList {
            visible: count > 0
            model: root.systemManagementModel.updates

            delegate: Rectangle {
                id: updateRow
                required property var modelData
                width: ListView.view.width
                height: Math.max(66, updateContent.implicitHeight + Theme.spacingMd * 2)
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                ColumnLayout {
                    id: updateContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        PlainText {
                            Layout.fillWidth: true
                            text: updateRow.modelData.name + " " + updateRow.modelData.version
                            color: Theme.controlNormalText
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        PlainText {
                            text: updateRow.modelData.installability === "blocked"
                                ? "BLOCKED" : updateRow.modelData.severity.toUpperCase()
                            color: updateRow.modelData.installability === "blocked"
                                ? Theme.danger : root.severityColor(updateRow.modelData.severity)
                            font.pixelSize: Theme.fontCaptionSize
                            font.bold: true
                        }
                    }
                    PlainText {
                        Layout.fillWidth: true
                        text: updateRow.modelData.summary
                        color: Theme.menuMutedText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        SectionLabel {
            visible: root.systemManagementModel.packageChanges.length > 0
            label: "Planned package changes"
        }

        DataList {
            visible: count > 0
            model: root.systemManagementModel.packageChanges

            delegate: Rectangle {
                id: changeRow
                required property var modelData
                width: ListView.view.width
                height: Math.max(58, changeContent.implicitHeight + Theme.spacingMd * 2)
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                RowLayout {
                    id: changeContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingMd

                    PlainText {
                        text: changeRow.modelData.action.toUpperCase()
                        color: Theme.accent
                        font.pixelSize: Theme.fontCaptionSize
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXxs
                        PlainText {
                            Layout.fillWidth: true
                            text: changeRow.modelData.name + " " + changeRow.modelData.version
                            color: Theme.controlNormalText
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        PlainText {
                            Layout.fillWidth: true
                            text: changeRow.modelData.summary
                            color: Theme.menuMutedText
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        SectionLabel {
            visible: root.systemManagementModel.errors.length > 0
            label: "System diagnostics"
        }

        DataList {
            visible: count > 0
            model: root.systemManagementModel.errors

            delegate: Rectangle {
                id: errorRow
                required property var modelData
                width: ListView.view.width
                height: Math.max(58, errorContent.implicitHeight + Theme.spacingMd * 2)
                color: Theme.controlNormalFill
                border.color: Theme.danger
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                RowLayout {
                    id: errorContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingMd
                    PlainText {
                        text: errorRow.modelData.provider.toUpperCase() + " / "
                            + errorRow.modelData.code.toUpperCase()
                        color: Theme.danger
                        font.pixelSize: Theme.fontCaptionSize
                        font.bold: true
                    }
                    PlainText {
                        Layout.fillWidth: true
                        text: errorRow.modelData.detail
                        color: Theme.menuText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        SectionLabel { label: "Administration boundaries" }

        Repeater {
            model: root.capabilities
            delegate: StatusCard {
                id: capabilityCard
                required property var modelData
                label: capabilityCard.modelData.label
                status: capabilityCard.modelData.status
                value: capabilityCard.modelData.capabilityClass.toUpperCase()
                detail: capabilityCard.modelData.detail + " / " + capabilityCard.modelData.provider
            }
        }

        StatusCard {
            label: "Operation recovery"
            status: root.systemManagementModel.recoveryProvider.status
            value: root.systemManagementModel.recoveryProvider.status.toUpperCase()
            detail: root.systemManagementModel.recoveryProvider.detail
        }

        PlainText {
            Layout.fillWidth: true
            text: "This pane only reads PackageKit and recovery state. Update installation, cache refresh, and cancellation require a separate confirmed operation workflow."
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
            wrapMode: Text.WordWrap
        }
    }
}
