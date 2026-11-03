"""Real notification D-Bus actions on a private bus and X server."""
import json
import os
from pathlib import Path
import select
import shutil
import signal
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

        # Connect real dwm ping detection to the actual helper and notification
        # server. Only the provider is fake; no account or network is touched.
        binary = work / "bin"
        binary.mkdir()
        for source in (repo / "dwm", repo / "scripts/dwm-hang-event",
                       repo / "scripts/dwm-agent-diagnose"):
            shutil.copy(source, binary / source.name)
        fake_agent = binary / "dwm-agent"
        fake_agent.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                              'if sys.argv[1:] == ["default"]: print("codex")\n'
                              'else: open(os.environ["PROMPT_CAPTURE"], "w").write(json.dumps(sys.argv[1:]))\n')
        fake_agent.chmod(0o755)
        env["PATH"] = str(binary) + ":" + env["PATH"]
        capture = work / "prompt.json"
        env["PROMPT_CAPTURE"] = str(capture)
        config = Path(env["XDG_CONFIG_HOME"]) / "dwm-titus"
        config.mkdir(parents=True, exist_ok=True)
        for source in (repo / "config").glob("*.toml"):
            shutil.copy(source, config)
        (config / "hang-detection").touch()
        subprocess.run([os.environ.get("CC", "cc"), str(repo / "tests/fixtures/ping-client.c"),
                        "-lX11", "-o", str(binary / "ping-client")], check=True)
        wm = subprocess.Popen([str(binary / "dwm")], env=env, stdout=log, stderr=log)
        processes.append(wm)
        app = subprocess.Popen([str(binary / "ping-client")], env=env,
                               stdout=subprocess.PIPE, text=True, stderr=log)
        processes.append(app)
        assert select.select([app.stdout], [], [], 10)[0]
        assert app.stdout.readline().startswith("0x")
        time.sleep(1)
        app.send_signal(signal.SIGSTOP)
        wait_for(lambda: bool(state()["keys"]), 25)
        key = state()["keys"][0]
        ipc("invoke", key, "diagnose")
        wait_for(capture.exists)
        prompt_args = json.loads(capture.read_text())
        assert prompt_args[0] == "--prompt" and "read-only diagnosis" in prompt_args[1]
        assert "AI assistance ping fixture" not in prompt_args[1]
        app.send_signal(signal.SIGCONT)
        time.sleep(1)
        app.send_signal(signal.SIGSTOP)
        wait_for(lambda: bool(state()["keys"]), 25)
        app.send_signal(signal.SIGCONT)
        wait_for(lambda: not state()["keys"])
        app.send_signal(signal.SIGSTOP)
        wait_for(lambda: bool(state()["keys"]), 25)
        ipc("invoke", state()["keys"][0], "kill")
        time.sleep(0.5)
        app.send_signal(signal.SIGCONT)
        assert app.wait(timeout=5) != 0
        print("AI diagnosis end-to-end: real hang offer, sanitized prompt, recovery, X11 force quit PASS")
    except BaseException:
        log.flush()
        print((work / "shell.log").read_text(), file=sys.stderr)
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.send_signal(signal.SIGCONT)
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        log.close()
