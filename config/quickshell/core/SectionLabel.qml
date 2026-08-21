import QtQuick
import QtQuick.Layouts
import qs.core

Text {
    required property string label

    Layout.fillWidth: true
    text: label
    color: Theme.menuMutedText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBodySmallSize
    font.bold: true
    elide: Text.ElideRight
}
