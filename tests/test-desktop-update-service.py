#!/usr/bin/python3
"""Prove launch() hands work to a real user service after its caller exits."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="desktop-service-") as temporary:
    base = Path(temporary)
    unit = "dwm-desktop-update-test-" + uuid.uuid4().hex + ".service"
    operation = uuid.uuid4().hex
    activation_unit = "dwm-desktop-activation-" + operation + ".service"
    driver_unit = "dwm-desktop-driver-test-" + operation + ".service"
    fixture = base / "worker.py"
    fixture.write_text('''import os, time
from pathlib import Path
state = Path(os.environ["XDG_STATE_HOME"])
(state / "started").write_text("started")
time.sleep(2)
(state / "finished").write_text("finished")
''')
    launcher = base / "launcher.py"
    launcher.write_text('''import importlib.machinery, importlib.util, sys
from pathlib import Path
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("desktop", sys.argv[1])
spec = importlib.util.spec_from_loader("desktop", loader)
update = importlib.util.module_from_spec(spec)
loader.exec_module(update)
update.UNIT = sys.argv[3]
update.__file__ = sys.argv[2]
state = update.paths()[2]
update.write_json(state / "status.json", dict(update.status_default(), canUpdate=True, available="b" * 40))
update.launch("b" * 40)
''')
    env = {**os.environ, "XDG_STATE_HOME": str(base), "XDG_DATA_HOME": str(base / "data"),
           "XDG_CONFIG_HOME": str(base / "config")}
    try:
        subprocess.run([sys.executable, launcher, repo / "scripts/dwm-desktop-update", fixture, unit], env=env, check=True)
        # The initiating process has exited. The worker must still be running.
        for _ in range(40):
            if (base / "started").exists():
                break
            time.sleep(0.05)
        assert (base / "started").exists(), "Transient worker never started"
        active = subprocess.check_output(["systemctl", "--user", "show", unit, "--property=ActiveState", "--value"], text=True)
        assert active.strip() == "active", active
        for _ in range(80):
            if (base / "finished").exists():
                break
            time.sleep(0.05)
        assert (base / "finished").exists(), "Worker did not survive its initiating process"
        print("Real user service survives updater caller exit: PASS")

        prefix = base / "prefix"
        (prefix / "bin").mkdir(parents=True)
        helper = prefix / "bin/dwm-quickshell-controlcenter"
        helper.write_text('''#!/usr/bin/python3
import os, subprocess, time
from pathlib import Path
time.sleep(0.5)
child = subprocess.Popen(["/usr/bin/sleep", "60"], start_new_session=True)
(Path(os.environ["XDG_STATE_HOME"]) / "shell-pid").write_text(str(child.pid))
time.sleep(0.5)
(Path(os.environ["XDG_STATE_HOME"]) / "helper-finished").write_text("finished")
''')
        helper.chmod(0o755)
        driver = base / "activation.py"
        driver.write_text('''import importlib.machinery, importlib.util, sys
from pathlib import Path
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("desktop", sys.argv[1])
spec = importlib.util.spec_from_loader("desktop", loader)
update = importlib.util.module_from_spec(spec)
loader.exec_module(update)
update.start_activation(Path(sys.argv[2]), sys.argv[3])
''')
        subprocess.run(["systemd-run", "--user", "--quiet", "--collect", "--unit=" + driver_unit,
                        "--setenv=XDG_STATE_HOME=" + str(base), sys.executable, driver,
                        repo / "scripts/dwm-desktop-update", prefix, operation], check=True)
        for _ in range(100):
            if (base / "shell-pid").exists():
                break
            time.sleep(0.05)
        assert (base / "shell-pid").exists(), "Activation did not create its shell child"
        for _ in range(100):
            active = subprocess.run(["systemctl", "--user", "is-active", driver_unit], capture_output=True)
            if active.returncode != 0:
                break
            time.sleep(0.05)
        assert active.returncode != 0, "Updater driver did not exit"
        assert (base / "helper-finished").exists(), "Activation returned before its restart helper completed"
        time.sleep(0.2)
        subprocess.run(["systemctl", "--user", "is-active", "--quiet", activation_unit], check=True)
        os.kill(int((base / "shell-pid").read_text()), 0)
        print("Managed shell activation survives updater service exit: PASS")
    finally:
        subprocess.run(["systemctl", "--user", "stop", unit, driver_unit, activation_unit],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
