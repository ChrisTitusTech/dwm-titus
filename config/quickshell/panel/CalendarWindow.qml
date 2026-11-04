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
    popupWidth: Theme.scaledSize(350)
    popupHeight: calendarColumn.implicitHeight + Theme.popupPadding * 2
    popupX: panelWindow ? (panelWindow.width - popupWidth) / 2 : 0
    onDismissed: root.model.close()
    onVisibleChanged: if (visible) Qt.callLater(function() { card.forceActiveFocus(); })
    ShellSurface {
        id: card
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.model.close();
            else if (event.key === Qt.Key_Left) root.model.changeMonth(-1);
            else if (event.key === Qt.Key_Right) root.model.changeMonth(1);
            else return;
            event.accepted = true;
        }
        ColumnLayout {
            id: calendarColumn
            anchors.fill: parent
            spacing: Theme.spacingSm
            RowLayout {
                ShellButton { label: "<"; accessibleDescription: "Previous month"; onActivated: root.model.changeMonth(-1) }
                UiText { Layout.fillWidth: true; text: root.model.monthTitle; color: Theme.menuText; horizontalAlignment: Text.AlignHCenter }
                ShellButton { label: ">"; accessibleDescription: "Next month"; onActivated: root.model.changeMonth(1) }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: Theme.spacingSm
                columnSpacing: Theme.spacingSm
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    delegate: UiText {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData; color: Theme.menuMutedText
                    }
                }
                Repeater {
                    model: root.model.days
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.controlHeight
                        color: modelData.today ? Theme.accent : Theme.transparent
                        radius: Theme.controlRadius
                        UiText {
                            anchors.centerIn: parent
                            text: String(parent.modelData.day)
                            color: parent.modelData.today ? Theme.accentText : parent.modelData.current ? Theme.menuText : Theme.menuMutedText
                            opacity: parent.modelData.current ? 1 : 0.55
                        }
                    }
                }
            }
            ShellButton { Layout.alignment: Qt.AlignHCenter; label: "Today"; onActivated: root.model.today() }
        }
    }
}
