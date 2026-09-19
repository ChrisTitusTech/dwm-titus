"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Settings fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
model = qml / "settings/SettingsModel.qml"
text = replace_once(model.read_text(), "id: root",
                    "id: root\n    property bool testInitialLoading: false")
for method, counter in (
    ("activateSection(id)", "testActivations"),
    ("refreshDisplays()", "testDisplayReads"),
    ("refreshInput()", "testInputReads"),
):
    signature = f"function {method} {{"
    text = replace_once(
        text, signature,
        f"property int {counter}: 0\n    {signature}\n        {counter}++;",
    )
for flag, process in (("capabilityRefreshPending", "providerProcess"),
                      ("displayRefreshPending", "displayDiscoverProcess"),
                      ("inputRefreshPending", "inputDiscoverProcess"),
                      ("automaticDisplayRefreshPending", "automaticDisplayStatusProcess")):
    text = replace_once(text, "id: root", "id: root\n    on" + flag[0].upper() + flag[1:]
                        + "Changed: if (!" + flag + " && !" + process
                        + ".running && visible) testQueuedGap = true")
text = replace_once(text, "id: root", "id: root\n    property bool testQueuedGap: false")
model.write_text(text)
commands = qml / "core/Commands.qml"
text = replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (action === "preview-status" && (helper === "dwm-settings-display" || helper === "dwm-settings-input")) return ["sleep", "0.75"];\n        if (action === "status" && (helper === "dwm-accessibility-settings" || helper === "dwm-panel-settings")) return ["sleep", "0.75"];\n        return ["true"];\n        const argv = args || [];',
)
commands.write_text(text)
appearance = qml / "appearance/AppearanceModel.qml"
text = replace_once(appearance.read_text(), 'id: root',
                    'id: root\n    property alias testTypographyMonitor: typographyMonitor')
# Isolate the subscription lifecycle from the host's GSettings backend.
text = replace_once(text, '["gsettings", "monitor", "org.gnome.desktop.interface"]',
                    '["sleep", "60"]')
appearance.write_text(text)
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Settings fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])

window = qml / "settings/SettingsWindow.qml"
window.write_text(window.read_text().replace(
    "dataLoading: ", "dataLoading: root.settingsModel.testInitialLoading || "))

# Keep the updater fixture isolated from the installed host updater.
updater = qml / "settings/DesktopUpdateModel.qml"
text = replace_once(updater.read_text(),
                    'readonly property var updaterCommand: ["/usr/bin/python3", "-I", "-c", updaterBootstrap]',
                    'readonly property var updaterCommand: ["true"]')
updater.write_text(text)
for relative, visible in (("defaults/AutostartModel.qml", "settingsVisible"),
                          ("defaults/DefaultAppsModel.qml", "settingsVisible"),
                          ("power/PowerModel.qml", "sectionVisible")):
    path = qml / relative
    text = replace_once(path.read_text(), "id: root", "id: root\n"
                        "    property bool testQueuedGap: false\n"
                        "    onSnapshotPendingChanged: if (!snapshotPending && !snapshotProcess.running && "
                        + visible + ") testQueuedGap = true")
    path.write_text(text)

window = qml / "settings/SettingsWindow.qml"
text = replace_once(window.read_text(), "id: root", """id: root
    property bool testEarlyPresentation: false
    function testPresentation(item) {
        const type = String(item);
        let pending = false;
        if (type.startsWith("DisplaySettingsPane")) pending = settingsModel.displayActionBusy || settingsModel.displayRefreshPending || settingsModel.automaticDisplayRefreshPending;
        if (type.startsWith("InputSettingsPane")) pending = settingsModel.inputActionBusy || settingsModel.inputRefreshPending;
        if (type.startsWith("AppearanceSettingsPane")) pending = appearanceModel.initialLoading
            || accessibilityModel.initialLoading || panelSettingsModel.initialLoading || notificationModel.initialLoading;
        if (type.startsWith("SystemSettingsPane")) pending = desktopUpdateModel.initialLoading;
        if (pending) {
            testEarlyPresentation = true;
            console.error("Responsiveness FAILED: First presentation preceded provider completion: " + type);
        }
    }""")
text = text.replace("DeferredSettingsPane {", "DeferredSettingsPane {\n                                onPresentedChanged: if (presented) root.testPresentation(item)")
window.write_text(text)
