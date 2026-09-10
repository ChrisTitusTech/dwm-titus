"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Settings fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
model = qml / "settings/SettingsModel.qml"
text = model.read_text()
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
    'return ["true"];\n        const argv = args || [];',
)
commands.write_text(text)
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Settings fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
