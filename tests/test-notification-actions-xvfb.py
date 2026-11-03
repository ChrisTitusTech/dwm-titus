"""Real notification D-Bus actions on a private bus and X server."""
import json
import os
import re
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

if "--inside" not in sys.argv:
    session = subprocess.Popen(["dbus-run-session", "--", sys.executable,
                                __file__, "--inside"], start_new_session=True)
    try:
        raise SystemExit(session.wait(timeout=300))
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        os.killpg(session.pid, signal.SIGCONT)
        os.killpg(session.pid, signal.SIGTERM)
        try:
            session.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        finally:
            try:
                os.killpg(session.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            session.wait()
        raise SystemExit("notification actions test timed out")

# Let the inner test clean up its workspace and children on the outer deadline.
def terminate_test(*_):
    raise SystemExit("notification actions test terminated")

signal.signal(signal.SIGTERM, terminate_test)

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
    work = Path(directory)
    qml = work / "qml"
    shutil.copytree(repo / "config/quickshell", qml)
    (qml / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "notifications" as Notifications
import "settings" as Settings
import qs.core
ShellRoot {
    Notifications.NotificationModel { id: model }
    Settings.AgentSettingsModel { id: agentModel }
    PanelWindow { id: panel; anchors { top: true; left: true; right: true } implicitHeight: 30 }
    Notifications.NotificationPopupWindow { notificationModel: model; panelWindow: panel }
    QtObject { id: fixtureAction; property string identifier: "fixture"; property string text: "Before" }
    QtObject {
        id: fixture
        property int id: 999999
        property bool tracked: false
        property string appName: "Signal fixture"
        property string summary: "Label signal"
        property string body: ""
        property int urgency: 2
        property var actions: [fixtureAction]
        signal closed()
        function expire() { closed(); }
        function dismiss() { closed(); }
    }
    IpcHandler {
        target: "test"
        function agentState(): string { return JSON.stringify({loaded:agentModel.loaded, busy:agentModel.busy, hang:agentModel.hangDetection}); }
        function agentRefresh(): void { agentModel.refresh(); }
        function agentToggle(enabled: bool): void { agentModel.setToggle("hang-detection", enabled); }
        function addFixture(): void { model.add(fixture); }
        function relabelFixture(): void { fixtureAction.text = "After"; }
        function state(): string {
            return JSON.stringify({policy: model.policyState,
                visible: model.notifications.map(n => n.key),
                items: model.notifications.map(n => ({key:n.key, summary:n.summary,
                    actions:n.actions, hasDefaultAction:n.hasDefaultAction, timeoutMs:n.timeoutMs})),
                keys: Object.keys(model.actionable), history: model.history});
        }
        function invoke(key: string, action: string): bool { return model.invokeAction(key, action); }
        function clear(): void { model.clearHistory(); }
        function dnd(enabled: bool): void { model.setDoNotDisturb(enabled); }
        function terminal(argument: string): string {
            return JSON.stringify(Commands.agentTerminalCommand("login", [argument]));
        }
    }
}
''')
    env = {**os.environ, "HOME": str(work / "home"), "XDG_CONFIG_HOME": str(work / "config"),
           "XDG_DATA_HOME": str(work / "data"), "XDG_CACHE_HOME": str(work / "cache"),
           "XDG_STATE_HOME": str(work / "state"), "XDG_RUNTIME_DIR": str(work / "r"),
           "QT_QPA_PLATFORMTHEME": "", "QT_QUICK_BACKEND": "software", "QSG_RHI_BACKEND": "software"}
    managed = Path(env["XDG_DATA_HOME"]) / "dwm-titus/scripts"
    managed.mkdir(parents=True)
    agent_calls = work / "agent-calls"
    slow_list = work / "slow-list"
    env["DWM_TEST_AGENT_CALLS"] = str(agent_calls)
    env["DWM_TEST_SLOW_LIST"] = str(slow_list)
    agent_fixture = managed / "dwm-agent"
    agent_fixture.write_text("""#!/usr/bin/python3
import os, sys, time
from pathlib import Path
action = sys.argv[1]
with open(os.environ['DWM_TEST_AGENT_CALLS'], 'a') as log: log.write(action + '\\n')
toggle = Path(os.environ['DWM_TEST_AGENT_CALLS'] + '.toggle')
if action == 'list':
    if Path(os.environ['DWM_TEST_SLOW_LIST']).exists(): time.sleep(5)
    print('agent\\tcodex\\tCodex\\tyes\\t1.0\\tyes\\tyes')
elif action == 'status':
    print('hang-detection\\t' + ('on' if toggle.exists() else 'off'))
elif action == 'set':
    time.sleep(0.4)
    if sys.argv[3] == 'on': toggle.touch()
    else: toggle.unlink(missing_ok=True)
""")
    agent_fixture.chmod(0o755)
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
            raise AssertionError("Notification condition timed out: " + json.dumps(state()))

        wait_for(lambda: state()["policy"] in ("available", "defaults"))
        def agent_state():
            return json.loads(ipc("agentState"))
        ipc("agentRefresh")
        wait_for(lambda: agent_state()["loaded"] and not agent_state()["busy"])
        slow_list.touch()
        ipc("agentToggle", "true")
        wait_for(lambda: agent_state()["hang"] and not agent_state()["busy"], 3)
        assert agent_calls.read_text().splitlines().count("list") == 1
        slow_list.unlink()
        ipc("agentToggle", "false")
        ipc("agentRefresh")  # Reopen/refresh while the mutation is pending.
        wait_for(lambda: not agent_state()["hang"] and not agent_state()["busy"])
        assert agent_calls.read_text().splitlines().count("list") == 2
        print("Agent Settings: toggle avoids slow probes; pending-action refresh reads final state PASS")
        agent_fixture.unlink()
        terminal_bin = work / "terminal-bin"
        terminal_bin.mkdir()
        terminal = terminal_bin / "dwm-terminal"
        terminal.write_text('#!/bin/sh\nshift\nexec "$@"\n')
        terminal.chmod(0o755)
        agent = terminal_bin / "dwm-agent"
        agent.write_text('#!/bin/sh\nprintf "helper error: %s\\n" "$2"\nexit 7\n')
        agent.chmod(0o755)
        argument = "fixture; touch SHOULD_NOT_EXIST"
        terminal_process = subprocess.Popen(json.loads(ipc("terminal", argument)),
            env={**env, "PATH": str(terminal_bin) + ":" + env["PATH"]},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        processes.append(terminal_process)
        assert select.select([terminal_process.stdout], [], [], 5)[0]
        assert terminal_process.stdout.readline().strip() == "helper error: " + argument
        assert terminal_process.poll() is None, "Error terminal closed before acknowledgement"
        output = terminal_process.communicate("\n", timeout=5)[0]
        assert terminal_process.returncode == 7 and "Press Enter" in output
        assert not (repo / "SHOULD_NOT_EXIST").exists()
        print("Agent error terminal: visible error, argv integrity, exit status PASS")
        # Persist an actionable entry, restart the server, then reuse its
        # numerical ID. Saved entries must never acquire the new live actions.
        old_client = subprocess.Popen(["notify-send", "--urgency=critical",
                                       "--action=kill=Force quit", "Before restart"], env=env)
        processes.append(old_client)
        wait_for(lambda: len(state()["keys"]) == 1)
        old_key = state()["keys"][0]
        history_path = Path(env["XDG_CACHE_HOME"]) / "dwm-titus/notification-history.json"
        wait_for(lambda: history_path.exists() and old_key in history_path.read_text())
        shell.terminate()
        shell.wait(timeout=5)
        shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")],
                                 env=env, stdout=log, stderr=log)
        processes.append(shell)
        wait_for(lambda: state()["policy"] in ("available", "defaults"))
        wait_for(lambda: any(n["key"] == old_key for n in state()["history"]))
        current = subprocess.Popen(["notify-send", "--urgency=critical", "--action=kill=Force quit",
                                    "After restart"], env=env, stdout=subprocess.PIPE, text=True)
        processes.append(current)
        wait_for(lambda: len(state()["keys"]) == 1)
        current_key = state()["keys"][0]
        assert current_key.rsplit("-", 2)[-2:] == old_key.rsplit("-", 2)[-2:], "Fixture must reuse both counters"
        assert current_key != old_key
        assert ipc("invoke", old_key, "kill") == "false"
        assert current.poll() is None
        ipc("dnd", "true")
        wait_for(lambda: state()["policy"] == "available")
        for index in range(50):
            subprocess.run(["notify-send", "Suppressed " + str(index)], env=env, check=True, timeout=5)
        wait_for(lambda: not any(n["key"] == current_key for n in state()["history"]))
        assert current_key in state()["visible"] and current.poll() is None
        for index in range(4):
            client = subprocess.Popen(["notify-send", "--urgency=critical", "--action=wait=Wait",
                                       "Overflow " + str(index)], env=env)
            processes.append(client)
            wait_for(lambda: state()["history"][0]["summary"] == "Overflow " + str(index))
        current.wait(timeout=5)
        assert current_key not in state()["keys"], "Evicted offer has no UI but is still open"
        ipc("clear")
        ipc("dnd", "false")
        wait_for(lambda: not state()["keys"] and state()["policy"] == "available")
        print("Notification restart isolation and DND/history overflow: PASS")

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

        def notify_replace(identifier, summary, actions, urgency):
            result = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                "replacement fixture", str(identifier), "", summary, "body", json.dumps(actions),
                "{'urgency': <byte " + str(urgency) + ">}", "0"], env=env, text=True,
                capture_output=True, check=True, timeout=5)
            return int(re.search(r"uint32 (\d+)", result.stdout).group(1))

        identifier = notify_replace(0, "No actions", [], 2)
        wait_for(lambda: state()["items"] and state()["items"][0]["summary"] == "No actions")
        replacement_key = state()["items"][0]["key"]
        assert notify_replace(identifier, "Added actions", ["go", "Old label", "default", "Open"], 2) == identifier
        wait_for(lambda: replacement_key in state()["keys"] and state()["items"][0]["hasDefaultAction"])
        assert state()["items"][0]["timeoutMs"] == 0
        version = subprocess.run(["quickshell", "--version"], env=env, capture_output=True, text=True,
                                 check=True, timeout=5).stdout
        # This exact Fedora build has an inverted comparison in setText(): it
        # discards changed labels before QML receives them. Keep other native
        # replacement assertions active, and test our textChanged handler below.
        broken_labels = "dacfa9de829ac7cb173825f593236bf2c21f637e" in version
        replacement_action = "new-go" if broken_labels else "go"
        notify_replace(identifier, "Changed label", [replacement_action, "New label"], 2)
        wait_for(lambda: state()["items"][0]["actions"] == [{"identifier":replacement_action, "text":"New label"}])
        assert not state()["items"][0]["hasDefaultAction"]
        if broken_labels:
            print("SKIP native same-identifier relabel: installed Quickshell dacfa9d setText defect")
        else:
            notify_replace(identifier, "Changed label", ["go", "Label only"], 2)
            wait_for(lambda: state()["items"][0]["actions"] == [{"identifier":"go", "text":"Label only"}])
        notify_replace(identifier, "Removed actions", [], 1)
        wait_for(lambda: replacement_key not in state()["keys"] and state()["items"][0]["timeoutMs"] == 6000)
        assert ipc("invoke", replacement_key, replacement_action) == "false"
        assert len([n for n in state()["history"] if n["key"] == replacement_key]) == 1
        ipc("clear")
        print("Notification replacements: additions, changed identifiers, removal, urgency and history PASS")
        ipc("addFixture")
        wait_for(lambda: any(n["summary"] == "Label signal" for n in state()["items"]))
        ipc("relabelFixture")
        wait_for(lambda: state()["items"][0]["actions"] == [{"identifier":"fixture", "text":"After"}])
        ipc("clear")
        print("Notification label-only textChanged signal: model refresh PASS")

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
                        "-lX11", "-o", str(binary / "ping-client")], check=True, timeout=30)
        wm = subprocess.Popen([str(binary / "dwm")], env=env, stdout=log, stderr=log)
        processes.append(wm)
        app = subprocess.Popen([str(binary / "ping-client")], env=env,
                               stdout=subprocess.PIPE, text=True, stderr=log)
        processes.append(app)
        assert select.select([app.stdout], [], [], 10)[0]
        app_window = app.stdout.readline().strip()
        assert app_window.startswith("0x")
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
        # Even a matching dwm record must not kill a window whose server-side
        # identity is missing/replaced (as when an XID is recycled).
        generation_output = subprocess.check_output(["xprop", "-id", app_window,
            "_DWM_TITUS_HANG_GENERATION"], env=env, text=True, timeout=5)
        low, high = [int(v.strip()) for v in generation_output.split("=", 1)[1].split(",")]
        generation = low + (high << 32)
        def request_kill(value):
            subprocess.run(["xprop", "-id", app_window, "-f", "_DWM_TITUS_HANG_KILL", "8s", "-set",
                            "_DWM_TITUS_HANG_KILL", app_window + " " + str(value)], env=env, check=True, timeout=5)
            wait_for(lambda: "not found" in subprocess.check_output(["xprop", "-id", app_window,
                "_DWM_TITUS_HANG_KILL"], env=env, text=True, timeout=5))
            subprocess.run(["xwininfo", "-id", app_window], env=env, check=True, capture_output=True, timeout=5)
        request_kill(generation + 1)
        subprocess.run(["xprop", "-id", app_window, "-remove", "_DWM_TITUS_HANG_GENERATION"], env=env, check=True, timeout=5)
        request_kill(generation)
        subprocess.run(["xprop", "-id", app_window, "-f", "_DWM_TITUS_HANG_GENERATION", "32c",
                        "-set", "_DWM_TITUS_HANG_GENERATION", str(low) + ", " + str(high)], env=env, check=True, timeout=5)
        ipc("invoke", state()["keys"][0], "kill")
        time.sleep(0.5)
        app.send_signal(signal.SIGCONT)
        assert app.wait(timeout=5) != 0
        print("AI diagnosis end-to-end: real hang offer, sanitized prompt, recovery, X11 force quit PASS")
        pair = []
        for _ in range(2):
            client = subprocess.Popen([str(binary / "ping-client")], env=env,
                stdout=subprocess.PIPE, text=True, stderr=log)
            processes.append(client)
            assert select.select([client.stdout], [], [], 10)[0]
            window = client.stdout.readline().strip()
            pair.append((client, window))
        time.sleep(1)
        for client, _ in pair:
            client.send_signal(signal.SIGSTOP)
        wait_for(lambda: len(state()["keys"]) == 2, 25)
        wm.send_signal(signal.SIGSTOP)
        try:
            # Hold the consumer so both requests are pending simultaneously.
            for _, window in pair:
                value = subprocess.check_output(["xprop", "-id", window,
                    "_DWM_TITUS_HANG_GENERATION"], env=env, text=True, timeout=5)
                low, high = [int(v.strip()) for v in value.split("=", 1)[1].split(",")]
                subprocess.run(["xprop", "-id", window, "-f", "_DWM_TITUS_HANG_KILL", "8s",
                    "-set", "_DWM_TITUS_HANG_KILL", window + " " + str(low + (high << 32))],
                    env=env, check=True, timeout=5)
        finally:
            wm.send_signal(signal.SIGCONT)
        for client, window in pair:
            wait_for(lambda: subprocess.run(["xwininfo", "-id", window], env=env,
                capture_output=True, timeout=5).returncode != 0)
            client.send_signal(signal.SIGCONT)
            assert client.wait(timeout=5) != 0
        print("Concurrent Force quit: both queued window requests consumed PASS")
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
