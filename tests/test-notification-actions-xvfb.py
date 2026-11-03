"""Real notification D-Bus actions on a private bus and X server."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time

if "--inside" not in sys.argv:
    raise SystemExit(subprocess.run(["dbus-run-session", "--", sys.executable,
                                    __file__, "--inside"], check=False).returncode)

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
    work = Path(directory)
    qml = work / "qml"
    shutil.copytree(repo / "config/quickshell", qml)
    (qml / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "notifications" as Notifications
ShellRoot {
    Notifications.NotificationModel { id: model }
    PanelWindow { id: panel; anchors { top: true; left: true; right: true } implicitHeight: 30 }
    Notifications.NotificationPopupWindow { notificationModel: model; panelWindow: panel }
    IpcHandler {
        target: "test"
        function state(): string {
            return JSON.stringify({policy: model.policyState,
                visible: model.notifications.map(n => n.key),
                keys: Object.keys(model.actionable), history: model.history});
        }
        function invoke(key: string, action: string): bool { return model.invokeAction(key, action); }
        function clear(): void { model.clearHistory(); }
    }
}
''')
    env = {**os.environ, "HOME": str(work / "home"), "XDG_CONFIG_HOME": str(work / "config"),
           "XDG_DATA_HOME": str(work / "data"), "XDG_CACHE_HOME": str(work / "cache"),
           "XDG_STATE_HOME": str(work / "state"), "XDG_RUNTIME_DIR": str(work / "r"),
           "QT_QPA_PLATFORMTHEME": "", "QT_QUICK_BACKEND": "software", "QSG_RHI_BACKEND": "software"}
    Path(env["XDG_RUNTIME_DIR"]).mkdir(mode=0o700)
    processes = []
    read_fd, write_fd = os.pipe()
    log = (work / "shell.log").open("w")
    try:
        server = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0",
                                   "1024x768x24", "-nolisten", "tcp"],
                                  pass_fds=(write_fd,), stdout=log, stderr=log)
        processes.append(server)
        os.close(write_fd)
        assert select.select([read_fd], [], [], 10)[0]
        env["DISPLAY"] = ":" + os.read(read_fd, 32).decode().strip()
        os.close(read_fd)
        shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")],
                                 env=env, stdout=log, stderr=log)
        processes.append(shell)

        def ipc(*args):
            return subprocess.run(["quickshell", "ipc", "--path", str(qml / "shell.qml"),
                                   "call", "test", *args], env=env, capture_output=True,
                                  text=True, timeout=5, check=True).stdout.strip()

        def state():
            return json.loads(ipc("state"))

        def wait_for(predicate, seconds=10):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                try:
                    if predicate():
                        return
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                time.sleep(0.1)
            raise AssertionError("Notification condition timed out")

        wait_for(lambda: state()["policy"] in ("available", "defaults"))
        clients = []
        for index in range(5):
            client = subprocess.Popen(["notify-send", "--urgency=critical", "--action=diagnose=Diagnose",
                                       "--action=default=Open", "Fixture " + str(index)],
                                      env=env, stdout=subprocess.PIPE, text=True)
            processes.append(client)
            clients.append(client)
            wait_for(lambda: len(state()["keys"]) == index + 1)
        snapshot = state()
        assert len(snapshot["visible"]) == 4
        first = snapshot["history"][-1]["key"]
        assert first not in snapshot["visible"] and first in snapshot["keys"]
        time.sleep(10.5)
        assert len(state()["keys"]) == 5, "Critical actions expired"
        ipc("invoke", first, "diagnose")
        assert clients[0].communicate(timeout=5)[0].strip() == "diagnose"
        latest = state()["history"][0]["key"]
        ipc("invoke", latest, "default")
        assert clients[-1].communicate(timeout=5)[0].strip() == "default"
        ipc("clear")
        wait_for(lambda: not state()["keys"])
        for client in clients:
            client.wait(timeout=5)
        print("Notification actions Xvfb: buttons, default, overflow history, persistence, cleanup PASS")
    except BaseException:
        log.flush()
        print((work / "shell.log").read_text(), file=sys.stderr)
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        log.close()
