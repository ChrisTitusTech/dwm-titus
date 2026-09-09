import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    signal revealRequested(var target)
    Layout.fillWidth: true
    spacing: Theme.spacingMd
    readonly property var healthAction: model.actions.find(action => action.id === "health-open") || null
    readonly property var information: [
        {id: "os-name", label: "Operating system"}, {id: "os-version", label: "Version"},
        {id: "kernel-release", label: "Kernel"}, {id: "architecture", label: "Architecture"},
        {id: "hardware-vendor", label: "Hardware vendor"}, {id: "hardware-model", label: "Hardware model"},
        {id: "cpu-model", label: "Processor"}, {id: "logical-cpus", label: "Logical processors"},
        {id: "memory-total-bytes", label: "Memory total"}, {id: "memory-available-bytes", label: "Memory available"},
        {id: "swap-total-bytes", label: "Swap total"}, {id: "swap-free-bytes", label: "Swap free"},
        {id: "uptime-seconds", label: "Uptime"}
    ]
    readonly property var security: [
        {id: "selinux", label: "SELinux"}, {id: "secure-boot", label: "Secure Boot"},
        {id: "firewalld", label: "Firewall service"}, {id: "root-encryption", label: "Root filesystem encryption"},
        {id: "screen-lock", label: "Automatic screen lock"}
    ]

    function bytes(value) {
        if (!/^(0|[1-9][0-9]*)$/.test(value)) return "Unknown";
        const amount = Number(value);
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"];
        const unit = amount > 0 ? Math.min(6, Math.floor(Math.log(amount) / Math.log(1024))) : 0;
        return (unit === 0 ? value : (amount / Math.pow(1024, unit)).toFixed(1)) + " " + units[unit];
    }
    function value(identifier, state) {
        if (state.value === "unknown" || state.status === "unavailable" || state.status === "unsupported") return "Unknown";
        if (identifier.indexOf("-bytes") >= 0) return bytes(state.value) + " (" + state.value + " bytes)";
        if (identifier === "uptime-seconds") {
            const seconds = Number(state.value);
            return Math.floor(seconds / 86400) + "d " + Math.floor(seconds % 86400 / 3600) + "h "
                + Math.floor(seconds % 3600 / 60) + "m";
        }
        return state.value;
    }
    function revealFocusedControl() {
        if (healthButton.activeFocus) root.revealRequested(healthButton);
        if (filesystems.activeFocus) root.revealRequested(filesystems);
    }
    onYChanged: Qt.callLater(root.revealFocusedControl)
    onImplicitHeightChanged: Qt.callLater(root.revealFocusedControl)

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component StateRow: ColumnLayout {
        id: row
        required property var definition
        readonly property var stateView: root.model.nativeStateView(definition.id)
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        PlainText { text: row.definition.label; font.bold: true }
        PlainText {
            objectName: "information-value-" + row.definition.id
            text: root.value(row.definition.id, row.stateView)
            color: row.stateView.status === "available" ? Theme.menuText : Theme.warning
        }
        PlainText {
            text: row.stateView.detail
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
        }
    }
    component ProviderNote: PlainText {
        id: note
        required property string owner
        readonly property var provider: root.model.nativeProviderView(owner)
        text: provider.status.toUpperCase() + " / " + provider.detail
        color: provider.status === "available" ? Theme.menuMutedText : Theme.warning
        font.pixelSize: Theme.fontCaptionSize
    }

    SectionLabel { label: "System information" }
    ProviderNote { owner: "information" }
    Repeater {
        model: root.information
        delegate: StateRow { required property var modelData; definition: modelData }
    }

    SectionLabel { label: "Storage overview" }
    ProviderNote { owner: "storage" }
    PlainText {
        objectName: "filesystemFreshness"
        text: root.model.filesystemsRetained
            ? "Showing last known filesystems. Mount monitoring is unavailable; this list may be stale. Use Reload status to retry."
            : root.model.nativeStateView("filesystem-summary").detail
        color: root.model.filesystemsRetained ? Theme.warning : Theme.menuMutedText
    }
    ListView {
        id: filesystems
        objectName: "systemFilesystems"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 240)
        model: root.model.filesystems
        clip: true
        spacing: Theme.spacingSm
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: count > 0
        keyNavigationEnabled: true
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(filesystems); }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) { currentIndex = 0; positionViewAtBeginning(); }
            else if (event.key === Qt.Key_End) { currentIndex = count - 1; positionViewAtEnd(); }
            else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
                contentY = Math.max(originY, Math.min(originY + Math.max(0, contentHeight - height),
                    contentY + (event.key === Qt.Key_PageDown ? height : -height)));
            else return;
            root.revealRequested(filesystems);
            event.accepted = true;
        }
        delegate: Rectangle {
            id: filesystem
            required property var modelData
            width: ListView.view.width
            height: filesystemContent.implicitHeight + Theme.spacingMd * 2
            radius: Theme.controlRadius
            color: Theme.controlNormalFill
            border.color: ListView.isCurrentItem && filesystems.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
            ColumnLayout {
                id: filesystemContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingXs
                PlainText { text: filesystem.modelData.target; font.bold: true }
                PlainText { text: filesystem.modelData.source + " / " + filesystem.modelData.fstype }
                PlainText {
                    text: "Used " + root.bytes(filesystem.modelData.usedBytes) + " / Total " + root.bytes(filesystem.modelData.sizeBytes)
                        + " / Available " + root.bytes(filesystem.modelData.availableBytes)
                }
                PlainText {
                    text: "Bytes (used / total / available): " + filesystem.modelData.usedBytes + " / "
                        + filesystem.modelData.sizeBytes + " / " + filesystem.modelData.availableBytes
                    color: Theme.menuMutedText
                    font.pixelSize: Theme.fontCaptionSize
                }
                PlainText { text: filesystem.modelData.detail; color: Theme.menuMutedText; font.pixelSize: Theme.fontCaptionSize }
            }
        }
    }
    PlainText {
        text: "Read-only mounted filesystem overview. Partitioning, formatting, encryption changes and filesystem repair belong in a trusted Fedora administration tool with a verified backup. Settings does not perform these operations."
        color: Theme.menuMutedText
    }

    SectionLabel { label: "Privacy and security status" }
    ProviderNote { owner: "security" }
    Repeater {
        model: root.security
        delegate: StateRow { required property var modelData; definition: modelData }
    }
    PlainText {
        text: "These indicators describe detected configuration, not a security audit. Firewall service status does not describe firewall rules. Root encryption does not cover every disk. Automatic locking depends on the current X11 session. Review update availability and restart requirements above. Firewall policy and service administration remain in trusted Fedora tools."
        color: Theme.menuMutedText
    }

    SectionLabel { label: "Diagnostics and recovery" }
    ProviderNote { owner: "diagnostics" }
    ShellButton {
        id: healthButton
        objectName: "openSystemHealth"
        label: "Open System Health"
        enabled: root.healthAction !== null && root.healthAction.availability === "available"
        accessibleDescription: "Open a read-only diagnostic scan. Repairs require separate confirmation."
        onActivated: root.model.openHealth()
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(healthButton); }
    }
    PlainText {
        text: root.healthAction === null ? "System Health is unavailable. Reload status to retry discovery." : root.healthAction.detail
        color: Theme.menuMutedText
    }
    PlainText {
        text: "System Health scans this desktop and offers only its named, confirmed repairs. Review diagnostic details before exporting or sharing them; paths and device names may identify your system. For an interrupted operation, reload status and read its recovery result before deciding whether to retry. A denied change leaves readable information available."
        color: Theme.menuMutedText
    }
    SectionLabel { label: "Reset guidance" }
    PlainText {
        text: "For a desktop preference, use the relevant Settings section's reset or revert control and review its scope first. Keep a backup of personal configuration before restoring it. System Health owns its listed desktop repairs; Fedora administration tools own system changes. A factory reset, account deletion, disk erase or operating-system reinstall is not offered here. Back up personal files before those separate recovery procedures."
        color: Theme.menuMutedText
    }
}
