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
model.write_text(text)
commands = qml / "core/Commands.qml"
text = replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (action === "status" && (helper === "dwm-accessibility-settings" || helper === "dwm-panel-settings")) return ["sleep", "0.75"];\n        return ["true"];\n        const argv = args || [];',
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
