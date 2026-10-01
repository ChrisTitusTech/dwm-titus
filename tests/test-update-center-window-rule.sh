#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

python3 - "$repo/config/window-rules.toml" "$repo/scripts/dwm-update-center-terminal" <<'PY'
import re
import sys
import tomllib
from pathlib import Path

rules = tomllib.loads(Path(sys.argv[1]).read_text())["rules"]
runner = Path(sys.argv[2]).read_text()

expected = {
    "title": "dwm update center",
    "instance": "dwm-update-center",
    "class": "DwmUpdateCenter",
    "isfloating": 1,
    "noswallow": 1,
}
matches = [rule for rule in rules if all(rule.get(key) == value for key, value in expected.items())]
assert len(matches) == 1, "missing exact Update Center floating/no-swallow rule"
assert not any(rule.get("class") in {"Dwmterm", "St", "kitty", "Alacritty", "Terminator"}
                   and rule.get("isfloating") == 1 for rule in rules), "broad terminal floating rule"

rule = matches[0]
def applies(title, instance, class_name):
    return rule["title"] in title and rule["instance"] in instance and rule["class"] in class_name

assert applies("dwm update center", "dwm-update-center", "DwmUpdateCenter")
assert not applies("dwm update center", "terminal", "kitty")
assert not applies("dwm update", "dwm-update-center", "DwmUpdateCenter")
assert not applies("update center", "dwm-update-center", "DwmUpdateCenter")
assert not applies("dwm update center", "dwm-update", "DwmUpdate")

for name, value in (("TERMINAL_TITLE", "dwm update center"),
                    ("TERMINAL_INSTANCE", "dwm-update-center"),
                    ("TERMINAL_CLASS", "DwmUpdateCenter")):
    pattern = rf'^{name}\s*=\s*(?:b)?["\']{re.escape(value)}["\']$'
    assert re.search(pattern, runner, re.MULTILINE), f"runner {name} disagrees with window rule"
PY

printf '%s\n' 'Update Center exact floating/no-swallow window rule: PASS'
