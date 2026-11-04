import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root
    required property var model
    required property var panelWindow
    visible: root.model.visible && root.panelWindow !== null
    targetWindow: root.panelWindow
    popupWidth: Theme.scaledSize(380)
    popupHeight: weatherColumn.implicitHeight + Theme.popupPadding * 2
    popupX: panelWindow ? (panelWindow.width - popupWidth) / 2 : 0
    property string draftLocation: ""
    property string draftUnit: "c"
    onDismissed: root.model.close()
    function synchronize() { root.draftLocation = root.model.location; root.draftUnit = root.model.unit; }
    onVisibleChanged: if (visible) { root.synchronize(); Qt.callLater(function() { city.forceActiveFocus(); }); }
    Connections {
        target: root.model
        function onLocationChanged() { root.synchronize(); }
        function onUnitChanged() { root.synchronize(); }
    }
    ShellSurface {
        anchors.fill: parent
        Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { root.model.close(); event.accepted = true; } }
        ColumnLayout {
            id: weatherColumn
            anchors.fill: parent
            spacing: Theme.spacingSm
            SectionLabel { label: "Weather / wttr.in" }
            UiText {
                Layout.fillWidth: true
                text: "Enter a city and fetch to send it to wttr.in. There are no automatic requests or location detection."
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.controlHeight
                color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                TextInput {
                    id: city
                    objectName: "weatherCity"
                    anchors.fill: parent; anchors.margins: Theme.spacingSm
                    color: Theme.menuText; font.family: Theme.fontFamily; font.pixelSize: Theme.inputFontSize
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.draftLocation
                    clip: true
                    readOnly: root.model.busy
                    maximumLength: 120
                    Accessible.name: "Weather city"
                    onTextEdited: root.draftLocation = text
                    onAccepted: if (!root.model.busy && text.trim()) root.model.fetch(root.draftLocation, root.draftUnit)
                }
            }
            RowLayout {
                ShellButton { label: "Celsius"; primary: root.draftUnit === "c"; onActivated: root.draftUnit = "c" }
                ShellButton { label: "Fahrenheit"; primary: root.draftUnit === "f"; onActivated: root.draftUnit = "f" }
                ShellButton {
                    label: root.model.busy ? "Fetching..." : "Fetch"
                    enabled: !root.model.busy && root.draftLocation.trim().length > 0
                    onActivated: root.model.fetch(root.draftLocation, root.draftUnit)
                }
            }
            UiText { Layout.fillWidth: true; visible: text.length > 0; text: root.model.message; color: Theme.warning; wrapMode: Text.WordWrap }
            UiText {
                Layout.fillWidth: true
                visible: root.model.weather !== null
                text: root.model.weather ? root.model.location + ": " + root.model.weather.temperature + " \u00b0" + root.model.unit.toUpperCase() + " / " + root.model.weather.description : ""
                textFormat: Text.PlainText
                color: Theme.menuText
                wrapMode: Text.WordWrap
            }
            UiText {
                Layout.fillWidth: true
                visible: root.model.weather !== null
                text: root.model.weather ? "Feels like " + root.model.weather.feels + " \u00b0" + root.model.unit.toUpperCase()
                    + " / Humidity " + root.model.weather.humidity + "% / Wind " + root.model.weather.wind + (root.model.unit === "c" ? " km/h" : " mph") : ""
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
            UiText {
                Layout.fillWidth: true
                text: root.model.fetched > 0 ? "Saved report / fetched " + Qt.formatDateTime(new Date(root.model.fetched * 1000), "ddd dd MMM HH:mm") : "No saved report. Fetch when you want fresh conditions."
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }
    }
}
