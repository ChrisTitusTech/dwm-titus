#!/usr/bin/env python3
"""Exercise window listing, focus routing and keyboard/mouse overview navigation on private X11."""
import ctypes as C
import importlib.machinery
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
module = importlib.machinery.SourceFileLoader("overview", str(repo / "scripts/dwm-window-overview")).load_module()


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
    with tempfile.TemporaryDirectory(prefix="qs-overview-", dir="/tmp") as runtime:
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
        qml = work / "qml"
        qml.mkdir()
        for name in ("core", "overview", "assets"):
            (qml / name).symlink_to(repo / "config/quickshell" / name)
        (qml / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "overview"
import qs.core
ShellRoot {
    id: harness
    property var overviewWindow: null
    WindowOverviewModel { id: provider }
    LazyLoader { active: provider.visible; component: WindowOverviewWindow { id: view; model: provider; Component.onCompleted: harness.overviewWindow = view; Component.onDestruction: harness.overviewWindow = null } }
    function findItem(item: var, name: string): var {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = findItem(child, name); if (found) return found; }
        return null;
    }
    IpcHandler {
        target: "overviewTest"
        function state(): string { return JSON.stringify({windows:provider.rows, visible:provider.visible, message:provider.message, selected:provider.selectedIndex}); }
        function open(): void { provider.openOnScreen(Quickshell.screens[0]); }
        function close(): void { provider.close(); }
        function query(value: string): void { provider.query = value; }
        function colors(value: string, dark: bool): void { Theme.applyAppearanceColors(JSON.parse(value), dark); }
        function many(): void {
            provider.windows = Array.from({length:80}, function(_, index) { return {
                id:String(9000000 + index), title:"A long application window title for virtual scrolling " + index,
                app:"ExampleApplication", tags:1 << (index % 9), monitor:index % 2 }; });
            provider.filter();
        }
        function select(index:int): void { provider.selectedIndex = index; }
        function point(windowId: string): string {
            const win = harness.overviewWindow;
            if (win) {
                const card = findItem(win.contentItem, "windowCard" + windowId);
                if (card) { const point = card.mapToGlobal(card.width / 2, card.height / 2); return JSON.stringify({x:point.x, y:point.y}); }
            }
            return "{}";
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
            wait(lambda: connection.state().get("available"), "dwm did not publish overview support")
            x, d, root = connection.x, connection.display, connection.root
            x.XCreateSimpleWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, C.c_ulong, C.c_ulong]
            x.XCreateSimpleWindow.restype = C.c_ulong
            x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
            x.XDestroyWindow.argtypes = [C.c_void_p, C.c_ulong]
            x.XStoreName.argtypes = [C.c_void_p, C.c_ulong, C.c_char_p]
            x.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
            x.XSync.argtypes = [C.c_void_p, C.c_int]
            windows = [x.XCreateSimpleWindow(d, root, 100, 100, 200, 100, 1, 0, 0x557799) for _ in range(3)]
            for index, window in enumerate(windows):
                x.XStoreName(d, window, f"Example window {index}".encode())
                app = b"example\0ExampleApplication\0"
                x.XChangeProperty(d, window, connection.atom("WM_CLASS"), 31, 8, 0, app, len(app))
                x.XMapWindow(d, window)
            x.XSync(d, False)
            wait(lambda: len(connection.state()["windows"]) == 3, "Not all clients were listed")
            run("xdotool", "set_desktop_for_window", str(windows[1]), "2")
            run("xdotool", "set_desktop_for_window", str(windows[2]), "5")
            wait(lambda: any(row["id"] == str(windows[2]) and row["tags"] == 32 for row in connection.state()["windows"]), "Tag assignment did not update")
            # Invalid optional title metadata must not remove a managed client.
            invalid_title = C.c_ulong(42)
            x.XChangeProperty(d, windows[0], connection.atom("_NET_WM_NAME"), 6, 32, 0, C.byref(invalid_title), 1)
            x.XSync(d, False)
            assert len(connection.state()["windows"]) == 3
            assert next(row for row in connection.state()["windows"] if row["id"] == str(windows[0]))["title"] == "Example window 0"
            for window in windows:
                connection.activate(window)
                assert connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [window]
            connection.activate(windows[0])
            run("xdotool", "key", "super+ctrl+shift+2")
            wait(lambda: any(row["id"] == str(windows[0]) and row["tags"] == 3 for row in connection.state()["windows"]), "Multi-tag metadata lost a tag")
            run("xdotool", "key", "super+2")
            connection.activate(windows[0])
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [1], "Activation unnecessarily switched a visible multi-tag window"
            run("xdotool", "key", "super+1")
            connection.activate(windows[0])
            initial_info = {row["id"]: (row["tags"], row["monitor"]) for row in connection.state()["windows"]}
            with open(work / "qml.log", "w") as qlog:
                shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")], stdout=qlog, stderr=qlog)
            processes.append(shell)

            def ipc(method, *args):
                return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "overviewTest", method, *args, check=False)

            def state():
                result = ipc("state")
                return json.loads(result.stdout) if result.returncode == 0 else {}

            wait(lambda: ipc("state").returncode == 0, "Overview failed to load: " + (work / "qml.log").read_text())
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Overview includes itself or omitted applications: " + (work / "qml.log").read_text())
            # Keep both same-application windows individually selectable.
            assert all(row["app"] == "ExampleApplication" for row in state()["windows"])
            x.XStoreName(d, windows[1], b"Changed while overview is open")
            x.XSync(d, False)
            wait(lambda: any(row["title"].startswith("Changed") for row in state()["windows"]), "Title watcher is stale")
            ipc("query", "Changed")
            wait(lambda: len(state()["windows"]) == 1, "Search did not filter individual windows")
            ipc("query", "")
            wait(lambda: len(state()["windows"]) == 3, "Search reset failed")
            evidence = os.environ.get("DWM_FEATURE_EVIDENCE_DIR")
            if evidence:
                from PIL import ImageGrab
                Path(evidence).mkdir(parents=True, exist_ok=True)
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "window-overview.png")
                # Use the actual shipped light palette through the same provider
                # records consumed by AppearanceModel, without mutation helpers.
                theme_path = config / "themes.toml"
                original = theme_path.read_text()
                theme_path.write_text(original.replace('theme = "nord"', 'theme = "catppuccin-latte"', 1))
                snapshot = run(str(repo / "scripts/dwm-settings-appearance"), "snapshot").stdout
                colors = {}
                for line in snapshot.splitlines():
                    fields = line.split("\t")
                    if fields[0] == "color" and len(fields) == 4:
                        colors[fields[1]] = fields[2]
                assert len(colors) >= 18, snapshot
                ipc("colors", json.dumps(colors), "false")
                time.sleep(.2)
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "window-overview-light.png")
                theme_path.write_text(original)
            before = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            time.sleep(2)
            after = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            assert after - before <= 15, f"Overview idle CPU ticks/2s: {after - before}"
            run("xdotool", "key", "Escape")
            wait(lambda: not state().get("visible"), "Escape did not dismiss overview")
            wait(lambda: connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[0]], "Escape did not restore focus")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [0], "Dismissal changed tags"
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Overview reopen failed")
            ipc("query", "Changed")
            wait(lambda: len(state()["windows"]) == 1, "Keyboard search failed")
            run("xdotool", "key", "Return")
            wait(lambda: connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[1]], "Enter did not focus the selected window")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [2]
            connection.activate(windows[0])
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Overview reopen for click failed")
            point = wait(lambda: json.loads(ipc("point", str(windows[2])).stdout) or None, "Window card could not be located")
            run("xdotool", "mousemove", "--sync", str(round(point["x"])), str(round(point["y"])), "click", "1")
            wait(lambda: connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[2]], "Click did not focus the selected window")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [5]
            assert initial_info == {row["id"]: (row["tags"], row["monitor"]) for row in connection.state()["windows"]}, "Selection changed assignments"
            connection.activate(windows[0])
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Closing-window scenario did not open")
            x.XDestroyWindow(d, windows[1])
            x.XSync(d, False)
            wait(lambda: len(state()["windows"]) == 2, "Closed client remained in overview")
            failed = run(str(repo / "scripts/dwm-window-overview"), "activate", str(windows[1]), check=False)
            assert failed.returncode != 0
            for window in (windows[0], windows[2]):
                x.XDestroyWindow(d, window)
            x.XSync(d, False)
            wait(lambda: len(state()["windows"]) == 0, "Empty state did not update")
            ipc("many")
            wait(lambda: len(state()["windows"]) == 80, "Large window list did not render")
            ipc("select", "79")
            last = wait(lambda: json.loads(ipc("point", "9000079").stdout) or None, "Last window card was not virtualized into view")
            assert 0 < last["y"] < 800, f"Selected card was outside the viewport: {last}"
            if evidence:
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "window-overview-many.png")
            monitors = connection.property(root, "_DWM_MONITOR_DESKTOPS") or []
            print(f"Individual cards, titles, keyboard/mouse selection, Escape focus, multi-tag preservation, close race, empty/80-card virtual scrolling: PASS; monitors={len(monitors)//5}; idle ticks/2s={after-before}")
        finally:
            if sys.exc_info()[0]:
                print((work / "qml.log").read_text() if (work / "qml.log").exists() else "No QML log", file=sys.stderr)
                print(run("xprop", "-root", "_NET_ACTIVE_WINDOW").stdout, file=sys.stderr)
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if connection:
                connection.close()
