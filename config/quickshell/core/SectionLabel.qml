import QtQuick
import QtQuick.Layouts
import qs.core

Text {
    required property string label

    Layout.fillWidth: true
    text: label
    color: Theme.textMuted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.smallFontSize
    font.bold: true
    elide: Text.ElideRight
}
