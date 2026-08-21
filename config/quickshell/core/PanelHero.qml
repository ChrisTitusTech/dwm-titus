import QtQuick
import QtQuick.Layouts
import qs.core

RowLayout {
    id: root

    default property alias actions: heroActions.data
    required property string title
    property string subtitle: ""
    property string iconText: ""
    property color iconColor: Theme.popupText

    spacing: Theme.sectionSpacing

    IconText {
        visible: root.iconText.length > 0
        text: root.iconText
        color: root.iconColor
        font.pixelSize: Theme.panelHeroIconSize
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXxs

        UiText {
            Layout.fillWidth: true
            text: root.title
            color: Theme.popupText
            font.pixelSize: Theme.fontTitleSize
            font.bold: true
            elide: Text.ElideRight
        }

        UiText {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle.toUpperCase()
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
            font.letterSpacing: Theme.panelMetaLetterSpacing
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: heroActions

        spacing: Theme.spacingMd
        Layout.alignment: Qt.AlignVCenter
    }
}
