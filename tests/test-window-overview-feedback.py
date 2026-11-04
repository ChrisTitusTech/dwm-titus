"""Verify overview review regressions in the production shell on private X11."""
import ctypes as C
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("overview_feedback", str(repo / "scripts/dwm-window-overview"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=15)


def wait(predicate, message):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError(message)


class Hints(C.Structure):
    _fields_ = [("flags", C.c_long), ("input", C.c_int), ("initial_state", C.c_int),
        ("icon_pixmap", C.c_ulong), ("icon_window", C.c_ulong), ("icon_x", C.c_int),
        ("icon_y", C.c_int), ("icon_mask", C.c_ulong), ("window_group", C.c_ulong)]


with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory, tempfile.TemporaryDirectory(prefix="qs-overview-feedback-", dir="/tmp") as runtime:
    work = Path(directory)
    os.environ.update(HOME=str(work / "home"), XDG_CONFIG_HOME=str(work / "config"),
        XDG_DATA_HOME=str(work / "data"), XDG_STATE_HOME=str(work / "state"),
        XDG_CACHE_HOME=str(work / "cache"), XDG_RUNTIME_DIR=runtime,
        QT_QUICK_BACKEND="software", QSG_RHI_BACKEND="software")
    config = work / "config/dwm-titus"
    config.mkdir(parents=True)
    for name in ("hotkeys.toml", "themes.toml", "window-rules.toml"):
        shutil.copy(repo / "config" / name, config / name)
    helpers = work / "data/dwm-titus/scripts"
    helpers.mkdir(parents=True)
    (helpers / "dwm-window-overview").symlink_to(repo / "scripts/dwm-window-overview")
    os.environ["PATH"] = str(helpers) + os.pathsep + os.environ["PATH"]
    qml = work / "config/quickshell"
    shutil.copytree(repo / "config/quickshell", qml)
    source = (qml / "shell.qml").read_text()
    source = source.rsplit("}", 1)[0] + '''
    IpcHandler {
        target: "overviewFeedbackTest"
        function state(): string { return JSON.stringify({visible:windowOverviewModel.visible,
            busy:windowOverviewModel.busy, returnWindow:windowOverviewModel.returnWindow,
            rows:windowOverviewModel.rows, message:windowOverviewModel.message,
            launcher:launcherModel.visible, menu:commandMenuModel.visible, clipboard:clipboardModel.visible,
            settings:settingsModel.visible, systemhealth:systemHealthModel.visible}); }
    }
}
'''
    (qml / "shell.qml").write_text(source)
    processes = []
    connection = None
    try:
        with (work / "dwm.log").open("w") as log:
            wm = subprocess.Popen([str(repo / "dwm")], stdout=log, stderr=log)
        processes.append(wm)
        connection = module.Connection()
        wait(lambda: connection.state()["available"], "dwm overview capability missing")
        x, d, root = connection.x, connection.display, connection.root
        x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
        x.XStoreName.argtypes = [C.c_void_p, C.c_ulong, C.c_char_p]
        x.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
        x.XSync.argtypes = [C.c_void_p, C.c_int]
        x.XSetWMHints.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(Hints)]
        x.XSetWMProtocols.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.c_int]

        def make_window(title, local_focus=False):
            window = x.XCreateSimpleWindow(d, root, 100, 100, 300, 200, 1, 0, 0x557799)
            x.XStoreName(d, window, title.encode())
            pid = C.c_ulong(os.getpid())
            x.XChangeProperty(d, window, connection.atom("_NET_WM_PID"), 6, 32, 0, C.byref(pid), 1)
            if local_focus:
                hints = Hints()
                hints.flags, hints.input = 1, 0  # InputHint, Input=false
                x.XSetWMHints(d, window, C.byref(hints))
                take_focus = C.c_ulong(connection.atom("WM_TAKE_FOCUS"))
                x.XSetWMProtocols(d, window, C.byref(take_focus), 1)
            x.XMapWindow(d, window)
            x.XSync(d, False)
            wait(lambda: window in (connection.property(root, "_NET_CLIENT_LIST", 33) or []), "Application did not map")
            return window

        earlier = make_window("Earlier hidden peer")
        selected = make_window("Hidden selection target")
        same_title = make_window("dwm window overview")
        for window in (earlier, selected):
            run("xdotool", "set_desktop_for_window", str(window), "2")
        connection.activate(same_title)
        with (work / "qml.log").open("w") as log:
            shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")], stdout=log, stderr=log)
        processes.append(shell)
        connection.exclude_pid = shell.pid

        def ipc(target, method, *args):
            return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", target, method, *args, check=False)

        def state():
            result = ipc("overviewFeedbackTest", "state")
            return json.loads(result.stdout) if result.returncode == 0 else {}

        def open_overview():
            assert ipc("windowOverview", "open").returncode == 0
            wait(lambda: state().get("visible") and not state()["busy"] and state()["rows"], "Production overview did not open")

        def choose(title):
            run("xdotool", "type", "--clearmodifiers", title)
            wait(lambda: len(state()["rows"]) == 1, "Search did not isolate the application")
            run("xdotool", "key", "Return")
            wait(lambda: not state()["visible"] and not state()["busy"], "Successful selection reopened the overview")

        wait(lambda: bool(state()), "Production root did not load")
        # Exercise the shipped TOML binding through real dwm dispatch and helper IPC.
        run("xdotool", "key", "super+Tab")
        wait(lambda: state().get("visible") and not state()["busy"] and state()["rows"], "Default Super+Tab did not open the overview")
        run("xdotool", "key", "super+Tab")
        wait(lambda: not state()["visible"] and not state()["busy"], "Default Super+Tab did not close the overview")
        assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [0], "Super+Tab changed the tag"
        open_overview()
        assert any(row["id"] == str(same_title) for row in state()["rows"]), "Application title collided with the overview identity"
        choose("Hidden selection target")
        time.sleep(.4)  # Catch queued EnterNotify stealing focus after acknowledgement.
        assert connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [selected]
        assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [2]

        for surface in ("launcher", "menu", "clipboard", "settings", "systemhealth"):
            connection.activate(selected)
            assert ipc(surface, "open").returncode == 0
            wait(lambda: state().get(surface), f"{surface} did not open")
            wait(lambda: (connection.property(root, "_NET_ACTIVE_WINDOW", 33) or [0])[0] not in (selected, earlier), f"{surface} did not acquire focus")
            open_overview()
            assert not state()[surface], f"{surface} remained mapped beneath the overview"
            assert state()["returnWindow"] == str(selected), f"{surface} hid the underlying focus context"
            run("xdotool", "key", "Escape")
            wait(lambda: not state()["visible"] and not state()["busy"] and connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [selected], f"Cancellation over {surface} did not restore the underlying client")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [2]

        local = make_window("Locally active application", local_focus=True)
        run("xdotool", "set_desktop_for_window", str(local), "3")
        connection.activate(same_title)
        while x.XPending(d):
            event = module.Event()
            x.XNextEvent(d, C.byref(event))
        open_overview()
        choose("Locally active application")
        assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [3]
        received = False
        while x.XPending(d):
            event = module.Event()
            x.XNextEvent(d, C.byref(event))
            if event.message.type == 33 and event.message.window == local and event.message.message_type == connection.atom("WM_PROTOCOLS") and event.message.data.l[0] == connection.atom("WM_TAKE_FOCUS"):
                received = True
        assert received, "WM_TAKE_FOCUS was not delivered"
        assert connection.property(root, "_NET_ACTIVE_WINDOW", 33) != [local], "Fixture did not exercise input-independent acknowledgement"
        before = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
        time.sleep(2)
        after = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
        assert after - before <= 15, f"Closed production shell consumed {after-before} CPU ticks/2s"
        print(f"Production shell: Super+Tab toggle, hidden-peer warp, title collision, Launcher/Menu/Clipboard/Settings/System Health cancellation, WM_TAKE_FOCUS acknowledgement: PASS; idle ticks/2s={after-before}")
    finally:
        if sys.exc_info()[0]:
            for name in ("dwm.log", "qml.log"):
                path = work / name
                if path.exists():
                    print(path.read_text(), file=sys.stderr)
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        if connection:
            connection.close()
