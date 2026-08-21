BarIconButton {
    id: root

    required property var controlsModel
    signal popupRequested()

    readonly property string muteIcon: "󰝟"
    readonly property string lowIcon: "󰕿"
    readonly property string mediumIcon: "󰖀"
    readonly property string highIcon: "󰕾"

    active: root.controlsModel.visible
    glyph: root.controlsModel.volumeIconState === "mute" ? root.muteIcon
        : root.controlsModel.volumeIconState === "low" ? root.lowIcon
        : root.controlsModel.volumeIconState === "medium" ? root.mediumIcon
        : root.highIcon

    onActivated: {
        root.popupRequested();
        root.controlsModel.toggle();
    }
    onWheelUp: root.controlsModel.volumeUp()
    onWheelDown: root.controlsModel.volumeDown()
}
