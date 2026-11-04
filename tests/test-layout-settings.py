#!/usr/bin/env python3
"""Exercise layout requests, tag state, geometry and the QML pane on private X11."""
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
loader = importlib.machinery.SourceFileLoader("layout", str(repo / "scripts/dwm-layout-settings"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)


def wait(predicate, message):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError(message)


def run(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check, timeout=15)


with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
    work = Path(directory)
    # A short runtime avoids the Unix socket path length limit.
    with tempfile.TemporaryDirectory(prefix="qs-layout-", dir="/tmp") as runtime:
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
        (helpers / "dwm-layout-settings").symlink_to(repo / "scripts/dwm-layout-settings")
        qml = work / "qml"
        qml.mkdir()
        for name in ("core", "settings"):
            (qml / name).symlink_to(repo / "config/quickshell" / name)
        (qml / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "settings"
import qs.core
ShellRoot {
    id: harness
    property bool paneSelected: true
    readonly property var pane: deferred.item
    function findItem(item: var, name: string): var {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = findItem(child, name); if (found) return found; }
        return null;
    }
    FloatingWindow {
        visible: true; title: "Layout settings test"
        implicitWidth: 520; implicitHeight: 480; color: Theme.bg
        DeferredSettingsPane { id: deferred; anchors.fill: parent; anchors.margins: 20
            selected: harness.paneSelected; windowVisible: true
            sourceComponent: LayoutSettingsPane { active: harness.paneSelected }
        }
    }
    IpcHandler {
        target: "layoutTest"
        function state(): string { return JSON.stringify(pane ? pane.snapshot : {available:false}); }
        function setValue(key: string, value: int): void { pane.setValue(key, value); }
        function active(value: bool): void { harness.paneSelected = value; }
        function rect(name:string): string {
            const item = harness.findItem(pane, name);
            const point = item.mapToGlobal(0, 0);
            return JSON.stringify({x:point.x, y:point.y, width:item.width, height:item.height, pressed:item.pressed});
        }
    }
}
''')
        processes = []
        connection = None
        try:
            log = open(work / "dwm.log", "w")
            wm = subprocess.Popen([str(repo / "dwm")], stdout=log, stderr=log)
            processes.append(wm)
            connection = module.Connection()
            wait(lambda: connection.state().get("available"), "dwm did not publish layout state")
            x, d, root = connection.x, connection.display, connection.root
            x.XCreateSimpleWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, C.c_ulong, C.c_ulong]
            x.XCreateSimpleWindow.restype = C.c_ulong
            x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
            x.XSync.argtypes = [C.c_void_p, C.c_int]
            windows = [x.XCreateSimpleWindow(d, root, 100, 100, 200, 100, 1, 0, 0x557799) for _ in range(3)]
            for window in windows:
                x.XMapWindow(d, window)
            x.XSync(d, False)
            time.sleep(.2)

            def set_value(key, value):
                state = connection.state()
                result = run(str(repo / "scripts/dwm-layout-settings"), "set", key, str(value), str(state["monitor"]), str(state["tags"]), str(state["owner"]))
                assert json.loads(result.stdout)[key] == value

            for key, value in (("master", 5), ("master", 95), ("master", 65), ("gap", 16), ("count", 2), ("layout", 1), ("layout", 2), ("layout", 0)):
                set_value(key, value)
            geometry = run("xdotool", "getwindowgeometry", "--shell", str(windows[-1])).stdout
            assert "X=16" in geometry or "Y=16" in geometry, geometry
            run("xdotool", "key", "super+2")
            wait(lambda: connection.state()["tags"] == 2, "tag switch failed")
            assert connection.state()["gap"] == 0
            set_value("gap", 8)
            run("xdotool", "key", "super+1")
            wait(lambda: connection.state()["tags"] == 1, "tag restoration failed")
            assert connection.state()["gap"] == 16
            stale = run(str(repo / "scripts/dwm-layout-settings"), "set", "gap", "20", "0", "2", "2", check=False)
            assert stale.returncode != 0 and connection.state()["gap"] == 16
            wrong_monitor = run(str(repo / "scripts/dwm-layout-settings"), "set", "gap", "20", "999", "1", "1", check=False)
            assert wrong_monitor.returncode != 0 and connection.state()["gap"] == 16
            # Out-of-range messages are also rejected by the C endpoint.
            connection.change(3, 999, 0, 1, 1)
            connection.x.XSync(d, False)
            time.sleep(.1)
            assert connection.state()["gap"] == 16
            # Identical visible masks can still belong to different per-tag owners.
            run("xdotool", "key", "super+ctrl+2")
            wait(lambda: connection.state()["tags"] == 3 and connection.state()["owner"] == 1, "First multitag owner failed")
            old_view = connection.state()
            run("xdotool", "key", "super+2", "super+ctrl+1")
            wait(lambda: connection.state()["tags"] == 3 and connection.state()["owner"] == 2, "Second multitag owner failed")
            stale = run(str(repo / "scripts/dwm-layout-settings"), "set", "gap", "20", str(old_view["monitor"]), "3", "1", check=False)
            assert stale.returncode != 0 and connection.state()["gap"] == 8
            connection.change(3, 20, old_view["monitor"], 3, 1)
            connection.x.XSync(d, False)
            time.sleep(.1)
            assert connection.state()["gap"] == 8, "C accepted stale settings owner"
            run("xdotool", "key", "super+1")
            wait(lambda: connection.state()["tags"] == 1, "Multitag test did not restore tag")
            with open(work / "qml.log", "w") as qlog:
                shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")], stdout=qlog, stderr=qlog)
            processes.append(shell)

            def ipc(method, *args):
                return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "layoutTest", method, *args, check=False)

            wait(lambda: ipc("state").returncode == 0, "QML pane failed to load: " + (work / "qml.log").read_text())
            wait(lambda: json.loads(ipc("state").stdout).get("available"), "QML watch did not load")
            ipc("setValue", "gap", "24")
            wait(lambda: connection.state()["gap"] == 24, "QML action failed")
            run("xdotool", "key", "super+f")
            wait(lambda: json.loads(ipc("state").stdout).get("layout") == 1, "QML did not observe hotkey")
            pane_window = run("xdotool", "search", "--name", "^Layout settings test$").stdout.splitlines()[0]
            run("xdotool", "windowsize", pane_window, "560", "480")
            run("xdotool", "windowmove", pane_window, "20", "20")
            time.sleep(.2)
            evidence = os.environ.get("DWM_FEATURE_EVIDENCE_DIR")
            if evidence:
                from PIL import ImageGrab
                Path(evidence).mkdir(parents=True, exist_ok=True)
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "layout-settings.png")
            # A real drag must never move an edit to a tag selected mid-gesture.
            run("xdotool", "key", "super+t")
            wait(lambda: connection.state()["layout"] == 0, "Tile layout did not restore")
            rect = json.loads(ipc("rect", "windowTileGaps").stdout)
            run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] * .4)), str(round(rect["y"] + rect["height"] / 2)), "mousedown", "1")
            try:
                wait(lambda: json.loads(ipc("rect", "windowTileGaps").stdout)["pressed"], "Mouse did not begin the gap slider drag")
                run("xdotool", "key", "super+2")
                wait(lambda: connection.state()["tags"] == 2, "Drag tag switch failed")
                run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] - 2)), str(round(rect["y"] + rect["height"] / 2)))
                time.sleep(.1)
            finally:
                run("xdotool", "mouseup", "1")
            time.sleep(.2)
            assert connection.state()["gap"] == 8, "Cross-tag drag changed the new tag"
            run("xdotool", "key", "super+1")
            wait(lambda: connection.state()["tags"] == 1, "Original drag tag did not restore")
            assert connection.state()["gap"] == 24, "Canceled drag changed the original tag"
            # Returning to the pane permits a new drag on the current view.
            rect = json.loads(ipc("rect", "windowTileGaps").stdout)
            run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] / 2)), str(round(rect["y"] + rect["height"] / 2)), "click", "1")
            wait(lambda: 30 <= connection.state()["gap"] <= 34, "Normal slider gesture did not apply")
            # Capture the settings owner as well as the mask during real drags.
            original_gap = connection.state()["gap"]
            run("xdotool", "key", "super+ctrl+2")
            wait(lambda: json.loads(ipc("state").stdout).get("tags") == 3 and json.loads(ipc("state").stdout).get("owner") == 1, "Pane did not observe first multitag owner")
            rect = json.loads(ipc("rect", "windowTileGaps").stdout)
            run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] * .4)), str(round(rect["y"] + rect["height"] / 2)), "mousedown", "1")
            try:
                wait(lambda: json.loads(ipc("rect", "windowTileGaps").stdout)["pressed"], "Owner drag did not begin")
                run("xdotool", "key", "super+2", "super+ctrl+1")
                wait(lambda: json.loads(ipc("state").stdout).get("tags") == 3 and json.loads(ipc("state").stdout).get("owner") == 2, "Pane did not observe second multitag owner")
                run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] - 2)), str(round(rect["y"] + rect["height"] / 2)))
            finally:
                run("xdotool", "mouseup", "1")
            time.sleep(.2)
            assert connection.state()["gap"] == 8, "Same-mask drag changed a different settings owner"
            run("xdotool", "key", "super+1")
            wait(lambda: connection.state()["tags"] == 1, "Owner drag did not restore tag")
            assert connection.state()["gap"] == original_gap
            # Existing hotkeys may exceed the graphical range; minus must recover.
            run("xdotool", "key", "--repeat", "22", "--delay", "15", "super+i")
            wait(lambda: json.loads(ipc("state").stdout).get("count", 0) > 21, "High master hotkey count failed")
            rect = json.loads(ipc("rect", "windowMasterMinus").stdout)
            run("xdotool", "mousemove", str(round(rect["x"] + rect["width"] / 2)), str(round(rect["y"] + rect["height"] / 2)), "click", "1")
            wait(lambda: connection.state()["count"] == 20, "Minus did not recover a hotkey count above its range")
            ticks_before = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            time.sleep(2)
            ticks_after = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            assert ticks_after - ticks_before <= 15, f"Pane consumed {ticks_after - ticks_before} CPU ticks while idle"
            ipc("active", "false")
            wait(lambda: not json.loads(ipc("state").stdout).get("available"), "Hidden pane kept its watch active")
            ipc("active", "true")
            wait(lambda: json.loads(ipc("state").stdout).get("available"), "Pane watcher did not resume")
            print(f"Layout requests, gaps, per-tag restoration, stale/invalid rejection, QML actions, hotkey updates: PASS; idle ticks/2s={ticks_after - ticks_before}")
        finally:
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if connection:
                connection.close()
