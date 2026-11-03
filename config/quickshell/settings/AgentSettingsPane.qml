pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core

Flickable {
    id: root

    required property var agentModel
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    component ToggleCard: Rectangle {
        id: toggleCard

        required property string title
        required property string detail
        required property bool checked
        signal toggled

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(64, toggleContent.implicitHeight + Theme.spacingLg * 2)
        color: Theme.controlNormalFill
        border.color: Theme.controlNormalBorder
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius

        RowLayout {
            id: toggleContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingLg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                UiText {
                    Layout.fillWidth: true
                    text: toggleCard.title
                    color: Theme.controlNormalText
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                UiText {
                    Layout.fillWidth: true
                    text: toggleCard.detail
                    color: Theme.menuMutedText
                    wrapMode: Text.WordWrap
                }
            }

            PanelToggleSwitch {
                checked: toggleCard.checked
                busy: root.agentModel.busy
                accessibleName: toggleCard.title
                accessibleDescription: toggleCard.detail
                onToggled: toggleCard.toggled()
            }
        }
    }

    component Badge: Rectangle {
        id: badge

        required property string label
        required property color stateColor

        implicitWidth: badgeText.implicitWidth + (Theme.controlPaddingX * 2)
        implicitHeight: Theme.pillHeight
        color: Theme.transparent
        border.color: badge.stateColor
        border.width: Theme.controlBorderWidth
        radius: Theme.pillRadius

        UiText {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label.toUpperCase()
            color: badge.stateColor
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: "Choose Diagnose with AI on a notification to open your default agent"
                color: Theme.menuMutedText
                elide: Text.ElideRight
            }
            ShellButton {
                label: root.agentModel.busy ? "Applying..." : "Refresh"
                enabled: !root.agentModel.busy
                onActivated: root.agentModel.refresh()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.agentModel.message.length > 0
            text: root.agentModel.message
            color: Theme.danger
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Agents" }

        UiText {
            Layout.fillWidth: true
            text: "Install and sign-in open in a terminal. Installation requires mise. Press Refresh when they finish to see the new state. Diagnosis preserves your agent permissions and asks for read-only inspection."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        UiText {
            Layout.fillWidth: true
            visible: root.agentModel.agents.length === 0
            text: "No agents reported"
            color: Theme.menuMutedText
        }

        Repeater {
            model: root.agentModel.agents
            delegate: Rectangle {
                id: agentCard

                required property var modelData
                readonly property bool signedIn: agentCard.modelData.signedIn === "yes"

                Layout.fillWidth: true
                Layout.preferredHeight: agentColumn.implicitHeight + Theme.spacingLg * 2
                color: Theme.controlNormalFill
                border.color: agentCard.modelData.isDefault ? Theme.controlSelectedBorder : Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                ColumnLayout {
                    id: agentColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        UiText {
                            text: agentCard.modelData.label
                            color: Theme.controlNormalText
                            font.bold: true
                        }
                        UiText {
                            Layout.fillWidth: true
                            text: agentCard.modelData.version.length > 0 ? agentCard.modelData.version : ""
                            color: Theme.menuMutedText
                            font.pixelSize: Theme.fontBodySmallSize
                            elide: Text.ElideRight
                        }
                        Badge {
                            label: agentCard.modelData.installed ? "Installed" : "Not installed"
                            stateColor: agentCard.modelData.installed ? Theme.success : Theme.menuMutedText
                        }
                        Badge {
                            visible: agentCard.modelData.installed
                            label: agentCard.signedIn ? "Signed in"
                                : agentCard.modelData.signedIn === "no" ? "Not signed in" : "Sign-in unknown"
                            stateColor: agentCard.signedIn ? Theme.success : Theme.warning
                        }
                        Badge {
                            visible: agentCard.modelData.isDefault
                            label: "Default"
                            stateColor: Theme.accent
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        // Decide from the data: a child's visible is false while this Flow is
                        // hidden, so reading it here would keep the row hidden for good.
                        visible: !agentCard.modelData.installed || !agentCard.signedIn
                            || !agentCard.modelData.isDefault
                        spacing: Theme.spacingSm

                        ShellButton {
                            id: installButton
                            visible: !agentCard.modelData.installed
                            label: "Install..."
                            accessibleDescription: "Install " + agentCard.modelData.label
                                + ", make it the default and sign in, in a terminal"
                            onActivated: root.agentModel.openTerminal("setup", agentCard.modelData.name)
                        }
                        ShellButton {
                            id: signInButton
                            visible: agentCard.modelData.installed && !agentCard.signedIn
                            label: "Sign in..."
                            accessibleDescription: "Sign in to " + agentCard.modelData.label + " in a terminal"
                            onActivated: root.agentModel.openTerminal("login", agentCard.modelData.name)
                        }
                        ShellButton {
                            id: defaultButton
                            visible: agentCard.modelData.installed && !agentCard.modelData.isDefault
                            enabled: !root.agentModel.busy
                            label: "Make default"
                            accessibleDescription: "Open " + agentCard.modelData.label + " for Diagnose with AI"
                            onActivated: root.agentModel.makeDefault(agentCard.modelData.name)
                        }
                    }
                }
            }
        }

        SectionLabel { label: "Alerts" }

        ToggleCard {
            title: "Crash notifications"
            detail: "Tell me when one of my programs crashes and offer to diagnose it."
            checked: root.agentModel.crashNotifications
            onToggled: root.agentModel.setToggle("crash-notifications", !root.agentModel.crashNotifications)
        }

        ToggleCard {
            title: "Hang detection"
            detail: "dwm checks every few seconds that windows still answer and tells you when one stops for 10 seconds. "
                + "Games, virtual machines and apps that are busy on purpose can show up as not responding when they are fine."
            checked: root.agentModel.hangDetection
            onToggled: root.agentModel.setToggle("hang-detection", !root.agentModel.hangDetection)
        }

        SectionLabel { label: "Skills" }

        UiText {
            Layout.fillWidth: true
            text: root.agentModel.skills === "linked"
                ? "Diagnosis skills: linked"
                : "Diagnosis skills: missing. Installing an agent links them, or run: dwm-agent link-skills"
            color: root.agentModel.skills === "linked" ? Theme.success : Theme.warning
            wrapMode: Text.WordWrap
        }
    }
}
