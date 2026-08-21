BarIconButton {
    id: root

    required property var networkModel
    signal popupRequested()

    readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    readonly property string ethernetIcon: "󰈀"
    readonly property string disconnectedIcon: "󰤮"
    readonly property int wifiIconIndex: Math.max(0, Math.min(4, Math.round(root.networkModel.wifiSignal / 25)))

    active: root.networkModel.visible
    glyph: root.networkModel.barIconState === "ethernet" ? root.ethernetIcon
        : root.networkModel.barIconState === "wifi" ? root.wifiIcons[root.wifiIconIndex]
        : root.disconnectedIcon

    onActivated: {
        root.popupRequested();
        root.networkModel.toggle();
    }
}
