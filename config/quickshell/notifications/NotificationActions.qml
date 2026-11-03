import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

// Buttons for the actions a client attached to a notification. The "default"
// action has no button in popups, where clicking the body invokes it; history
// entries have no body click, so they show it as an "Open" button.
Flow {
    id: root

    property var actions: []
    property bool critical: false
    property bool showDefault: false

    signal invoked(string identifier)

    readonly property var buttonActions: (root.actions || []).filter(action => root.showDefault || action.identifier !== "default")

    Layout.fillWidth: true
    visible: root.buttonActions.length > 0
    spacing: Theme.listSpacing * 2

    Repeater {
        model: root.buttonActions

        delegate: ShellButton {
            id: actionButton

            required property var modelData

            label: actionButton.modelData.identifier === "default" && !actionButton.modelData.text
                ? "Open" : (actionButton.modelData.text || actionButton.modelData.identifier)
            danger: root.critical
            onActivated: root.invoked(actionButton.modelData.identifier)
        }
    }
}
