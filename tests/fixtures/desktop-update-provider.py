#!/usr/bin/python3
"""Disposable desktop update service fixture; never installs files."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

directory = Path(os.environ["XDG_STATE_HOME"]) / "dwm-titus/desktop-update"
directory.mkdir(parents=True, exist_ok=True)
path = directory / "status.json"
value = {"schema": 1, "state": "unknown", "detail": "Check for desktop updates", "canUpdate": False,
         "installed": "a" * 40, "available": "b" * 40, "checkedAt": 1, "percent": -1,
         "packages": ["gcc"], "log": "/fixture/update.log", "backup": "/fixture/backup", "restart": "none"}


def write(**changes):
    value.update(changes)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


if sys.argv[1:] == ["status"]:
    if path.exists():
        value = json.loads(path.read_text())
elif sys.argv[1:] in (["check"], ["check", "--force"]):
    if "--force" in sys.argv:
        time.sleep(3)
    write(state="available", detail="A desktop update is available", canUpdate=True)
elif sys.argv[1:] == ["start", "b" * 40]:
    write(state="building", detail="Building the desktop update...", canUpdate=False)
    subprocess.Popen([sys.executable, __file__, "fixture-worker"], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
elif sys.argv[1:] == ["fixture-worker"]:
    time.sleep(0.5)
    write(state="verifying", detail="Verifying system files: 50 / 100", percent=50)
    time.sleep(0.5)
    write(state="restart-required", detail="Installed and verified. Log out and back in.", percent=100, restart="session")
else:
    sys.exit(2)
print(json.dumps(value))
