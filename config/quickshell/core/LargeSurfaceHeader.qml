import QtQuick
import QtQuick.Layouts
import qs.core

RowLayout {
    id: root

    default property alias actions: headerActions.data
    required property string title
    property string eyebrow: ""
    property string subtitle: ""
    property string status: ""
    property color statusColor: Theme.accent

    spacing: Theme.spacingHuge

    Rectangle {
        Layout.preferredWidth: 4
        Layout.preferredHeight: 50
        color: root.statusColor
        radius: 2
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXxs

        UiText {
            Layout.fillWidth: true
            visible: root.eyebrow.length > 0
            text: root.eyebrow.toUpperCase()
            color: root.statusColor
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
            font.letterSpacing: Theme.panelMetaLetterSpacing
            elide: Text.ElideRight
        }

        UiText {
            Layout.fillWidth: true
            text: root.title
            color: Theme.popupText
            font.pixelSize: Theme.largeSurfaceTitleSize
            font.bold: true
            elide: Text.ElideRight
        }

        UiText {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontBodySmallSize
            elide: Text.ElideRight
        }
    }

    Rectangle {
        visible: root.status.length > 0
        implicitWidth: headerStatus.implicitWidth + (Theme.controlPaddingX * 2)
        implicitHeight: Theme.pillHeight
        color: Theme.controlNormalFill
        border.color: root.statusColor
        border.width: Theme.controlBorderWidth
        radius: Theme.pillRadius
        Layout.alignment: Qt.AlignVCenter

        UiText {
            id: headerStatus

            anchors.centerIn: parent
            text: root.status.toUpperCase()
            color: root.statusColor
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
            font.letterSpacing: 0.6
        }
    }

    RowLayout {
        id: headerActions

        spacing: Theme.spacingLg
        Layout.alignment: Qt.AlignVCenter
    }
}
