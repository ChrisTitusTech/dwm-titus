import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Widgets
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root
    required property var model
    title: "dwm window overview"
    screen: root.model.targetScreen
    visible: root.model.visible
    fullscreen: true
    color: Theme.bg
    onVisibleChanged: if (visible) Qt.callLater(function() { search.forceActiveFocus(); })

    ShellSurface {
        anchors.fill: parent
        radius: 0
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { root.model.close(); event.accepted = true; }
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingLg
            LargeSurfaceHeader {
                Layout.fillWidth: true
                eyebrow: "Windows across all tags"
                title: "Window overview"
                subtitle: "Snapshots from opening / Type to filter / Enter to focus / Esc to close"
                status: String(root.model.rows.length) + " windows"
                statusColor: Theme.accent
                ShellButton { label: "Close"; onActivated: root.model.close() }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.largeSurfaceSearchHeight
                color: Theme.controlNormalFill
                border.color: search.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                radius: Theme.controlRadius
                TextInput {
                    id: search
                    objectName: "windowOverviewSearch"
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    color: Theme.menuText
                    text: root.model.query
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    clip: true
                    Accessible.name: "Search windows"
                    onTextChanged: root.model.query = text
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Left && search.text.length === 0) root.model.selectRelative(-1);
                        else if (event.key === Qt.Key_Right && search.text.length === 0) root.model.selectRelative(1);
                        else if (event.key === Qt.Key_Down) root.model.selectRelative(grid.columns);
                        else if (event.key === Qt.Key_Up) root.model.selectRelative(-grid.columns);
                        else if (event.key === Qt.Key_Tab) root.model.selectRelative(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.model.activate(root.model.selectedIndex);
                        else if (event.key === Qt.Key_Escape) root.model.close();
                        else return;
                        event.accepted = true;
                    }
                }
                UiText {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: "Search by application, title or tag"
                    color: Theme.menuMutedText
                }
            }
            UiText {
                Layout.fillWidth: true
                visible: root.model.message.length > 0
                text: root.model.message
                color: Theme.warning
                wrapMode: Text.WordWrap
            }
            GridView {
                id: grid
                objectName: "windowOverviewGrid"
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property int columns: Math.max(1, Math.floor(width / Theme.scaledSize(260)))
                cellWidth: width / columns
                cellHeight: Theme.scaledSize(280)
                clip: true
                model: root.model.rows
                currentIndex: root.model.selectedIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                delegate: Rectangle {
                    id: card
                    objectName: "windowCard" + modelData.id
                    required property var modelData
                    required property int index
                    width: grid.cellWidth - Theme.spacingSm
                    height: grid.cellHeight - Theme.spacingSm
                    radius: Theme.controlRadius
                    color: root.model.selectedIndex === index ? Theme.controlSelectedFill : Theme.controlNormalFill
                    border.color: root.model.selectedIndex === index ? Theme.controlSelectedBorder : Theme.controlNormalBorder
                    border.width: Theme.controlFocusBorderWidth
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.title + ", " + modelData.app + ", tags " + root.model.tagLabel(modelData.tags)
                    Accessible.onPressAction: root.model.activate(card.index)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingLg
                        spacing: Theme.spacingSm
                        RowLayout {
                            Layout.fillWidth: true
                            IconImage { implicitSize: Theme.scaledSize(24); source: Icons.launcherIcon(card.modelData.app) }
                            UiText {
                                Layout.fillWidth: true
                                text: card.modelData.app
                                textFormat: Text.PlainText
                                color: Theme.menuMutedText
                                elide: Text.ElideRight
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Image {
                                id: thumbnail
                                objectName: "windowThumbnail" + card.modelData.id
                                anchors.fill: parent
                                source: card.modelData.thumbnail || ""
                                sourceSize.width: 320
                                sourceSize.height: 180
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                            }
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: Theme.scaledSize(48)
                                source: Icons.launcherIcon(card.modelData.app)
                                visible: thumbnail.status !== Image.Ready
                            }
                        }
                        UiText {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.scaledSize(36)
                            text: card.modelData.title
                            textFormat: Text.PlainText
                            color: Theme.menuText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        UiText {
                            Layout.fillWidth: true
                            text: "Tags " + root.model.tagLabel(card.modelData.tags) + " / Monitor " + (card.modelData.monitor + 1)
                            color: Theme.menuMutedText
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.model.activate(card.index)
                    }
                }
                UiText {
                    anchors.centerIn: parent
                    visible: root.model.rows.length === 0
                    text: root.model.query.length ? "No matching windows" : "No application windows are open"
                    color: Theme.menuMutedText
                }
            }
        }
    }
}
