#!/usr/bin/env python3
"""Exercise window listing, focus routing and keyboard/mouse overview navigation on private X11."""
import ctypes as C
import importlib.machinery
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse

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
    property var rememberedCard: null
    WindowOverviewModel { id: provider; property int snapshotCount: 0; onWindowsChanged: snapshotCount++ }
    LazyLoader { active: provider.visible; component: WindowOverviewWindow { id: view; model: provider; Component.onCompleted: harness.overviewWindow = view; Component.onDestruction: harness.overviewWindow = null } }
    function findItem(item: var, name: string): var {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = findItem(child, name); if (found) return found; }
        return null;
    }
    IpcHandler {
        target: "overviewTest"
        function state(): string { return JSON.stringify({windows:provider.rows, stored:provider.windows.length, visible:provider.visible, busy:provider.busy, pending:provider.thumbnailsPending, returnWindow:provider.returnWindow, message:provider.message, selected:provider.selectedIndex, snapshots:provider.snapshotCount}); }
        function open(): void { provider.openOnScreen(Quickshell.screens[0]); }
        function close(): void { provider.close(); }
        function lateSnapshot(): void { provider.parse(JSON.stringify({protocol:1, thumbnailsPending:true,
            windows:[{id:"9000001",title:"Late capture",app:"Example",tags:1,monitor:0,thumbnail:"file:///removed.png"}]})); }
        function remember(windowId:string):void { harness.rememberedCard = provider.rows.find(row => row.id === windowId); }
        function activateRemembered():void { provider.rows = [harness.rememberedCard]; provider.activate(0); }

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
            x.XSetWindowBackground.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong]
            x.XClearWindow.argtypes = [C.c_void_p, C.c_ulong]
            # Xvfb's automatic Composite redirection supplies genuine backing
            # pixmaps without depending on a GPU or a second window manager.
            composite = C.CDLL(C.util.find_library("Xcomposite") or "libXcomposite.so.1")
            composite.XCompositeRedirectWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int]
            windows = [x.XCreateSimpleWindow(d, root, 100, 100, 200, 100, 1, 0, 0x557799) for _ in range(3)]
            for index, window in enumerate(windows):
                composite.XCompositeRedirectWindow(d, window, 0)
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
            connection.exclude_pid = shell.pid

            def ipc(method, *args):
                return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "overviewTest", method, *args, check=False)

            def state():
                result = ipc("state")
                return json.loads(result.stdout) if result.returncode == 0 else {}

            wait(lambda: ipc("state").returncode == 0, "Overview failed to load: " + (work / "qml.log").read_text())
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Overview includes itself or omitted applications: " + (work / "qml.log").read_text())
            snapshot = wait(lambda: state() if not state().get("pending", True) else None, "Thumbnail batch did not finish")
            assert all(row.get("thumbnail") for row in snapshot["windows"]), snapshot
            images = {row["id"]: Path(unquote(urlparse(row["thumbnail"]).path)) for row in snapshot["windows"]}
            from PIL import Image
            for path in images.values():
                assert path.stat().st_mode & 0o777 == 0o600
                assert path.parent.stat().st_mode & 0o777 == 0o700
                with Image.open(path) as preview:
                    assert preview.width <= 320 and preview.height <= 180
                    assert preview.getpixel((preview.width // 2, preview.height // 2)) == (0x55, 0x77, 0x99), "Hidden-tag capture lost its window pixels"
            original_pixels = {key: path.read_bytes() for key, path in images.items()}
            with tempfile.TemporaryDirectory(dir=work) as race_cache:
                sampler = module.Thumbnails(connection)
                assert not sampler.capture(0xffffffff, Path(race_cache) / "closed.png")
                assert sampler.capture(windows[0], Path(race_cache) / "valid.png"), "A closed client poisoned subsequent captures"
            x.XSetWindowBackground(d, windows[0], 0x994455)
            x.XClearWindow(d, windows[0])
            x.XSync(d, False)
            # Moving up by more columns than matches must still select a valid card.
            run("xdotool", "key", "Up")
            assert 0 <= state()["selected"] < 3, "Up produced a negative card index"
            ipc("query", "Example window 0")
            wait(lambda: len(state()["windows"]) == 1, "Single card filter failed")
            run("xdotool", "key", "Up")
            assert state()["selected"] == 0, "Up invalidated the only matching card"
            ipc("query", "")
            wait(lambda: len(state()["windows"]) == 3, "Card filter reset failed")
            # Keep both same-application windows individually selectable.
            assert all(row["app"] == "ExampleApplication" for row in state()["windows"])
            x.XStoreName(d, windows[1], b"Changed while overview is open")
            x.XSync(d, False)
            wait(lambda: any(row["title"].startswith("Changed") for row in state()["windows"]), "Title watcher is stale")
            ipc("query", "Changed")
            wait(lambda: len(state()["windows"]) == 1, "Search did not filter individual windows")
            ipc("query", "")
            wait(lambda: len(state()["windows"]) == 3, "Search reset failed")
            assert all(path.read_bytes() == original_pixels[key] for key, path in images.items()), "Search, title or repaint recaptured static thumbnails"
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
            wait(lambda: all(not path.parent.exists() for path in images.values()), "Closing retained thumbnail files")
            ipc("lateSnapshot")
            assert state()["stored"] == 0 and not state()["pending"], "A late capture snapshot repopulated the closed model"
            wait(lambda: not state()["busy"] and connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[0]], "Escape did not restore focus")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [0], "Dismissal changed tags"
            # Stop a real capture worker mid-opening. Terminating its watch
            # owner must kill/reap that worker and remove the private cache.
            watch = subprocess.Popen([str(repo / "scripts/dwm-window-overview"), "watch", "--thumbnails"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                assert json.loads(watch.stdout.readline())["thumbnailsPending"]
                def capturing_child():
                    for pid in Path(f"/proc/{watch.pid}/task/{watch.pid}/children").read_text().split():
                        try:
                            command = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                            if b"--thumbnail-directory" in command:
                                return int(pid), Path(os.fsdecode(command[command.index(b"--thumbnail-directory") + 1]))
                        except FileNotFoundError:
                            pass
                    return None
                captured_child = None
                deadline = time.monotonic() + 5
                while not captured_child and time.monotonic() < deadline:
                    captured_child = capturing_child()
                    if not captured_child:
                        time.sleep(.002)
                assert captured_child, "No disposable thumbnail worker was started"
                child_pid, child_cache = captured_child
                os.kill(child_pid, signal.SIGSTOP)
                watch.terminate()
                assert watch.wait(timeout=3) == 0
                assert not Path(f"/proc/{child_pid}").exists(), "Cancelled capture child was not reaped"
                assert not child_cache.exists(), "Cancelled capture retained its cache"
            finally:
                if watch.poll() is None:
                    watch.terminate()
                    watch.wait(timeout=5)
                watch.stdout.close()
                watch.stderr.close()
            # Cancel with a non-first tiled client focused on a shared tag.
            run("xdotool", "set_desktop_for_window", str(windows[1]), "0")
            connection.activate(windows[1])
            ipc("open")
            wait(lambda: state().get("visible") and len(state()["windows"]) == 3, "Shared-tag focus scenario did not open")
            refreshed = wait(lambda: state() if not state().get("pending", True) else None, "Reopening did not finish thumbnails")
            new_url = next(row["thumbnail"] for row in refreshed["windows"] if row["id"] == str(windows[0]))
            new_path = Path(unquote(urlparse(new_url).path))
            assert new_path != images[str(windows[0])], "Reopening reused an old image URL"
            with Image.open(new_path) as preview:
                assert preview.getpixel((preview.width // 2, preview.height // 2)) == (0x99, 0x44, 0x55), "Reopening did not refresh window pixels"
            ipc("open")  # Repeated explicit open must retain the original context.
            assert state()["returnWindow"] == str(windows[1]), f"Captured incorrect cancellation context: {state()}"
            run("xdotool", "key", "Escape")
            wait(lambda: not state()["visible"] and not state()["busy"] and connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[1]], "Escape changed the non-first tiled focus")
            assert connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [0]
            ipc("open")
            wait(lambda: state()["visible"] and len(state()["windows"]) == 3, "Close focus scenario did not open")
            ipc("close")
            wait(lambda: not state()["visible"] and not state()["busy"] and connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[1]], "Close changed the non-first tiled focus")
            run("xdotool", "set_desktop_for_window", str(windows[1]), "2")
            connection.activate(windows[0])
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
            # A normal selection must be visible when a peer owns real fullscreen.
            run("xdotool", "set_desktop_for_window", str(windows[1]), "0")
            wait(lambda: next(row for row in connection.state()["windows"] if row["id"] == str(windows[1]))["tags"] == 1, "Fullscreen peer did not move to target tag")
            connection.activate(windows[0])
            event = module.Event()
            event.message = module.Message(33, 0, True, d, windows[0], connection.atom("_NET_WM_STATE"), 32, module.Data())
            event.message.data.l[0] = 1
            event.message.data.l[1] = connection.atom("_NET_WM_STATE_FULLSCREEN")
            x.XSendEvent(d, root, False, (1 << 20) | (1 << 19), C.byref(event))
            x.XFlush(d)
            wait(lambda: connection.atom("_NET_WM_STATE_FULLSCREEN") in (connection.property(windows[0], "_NET_WM_STATE") or []), "Peer did not enter fullscreen")
            connection.activate(windows[1])
            wait(lambda: connection.atom("_NET_WM_STATE_FULLSCREEN") not in (connection.property(windows[0], "_NET_WM_STATE") or []), "Fullscreen peer still covers selection")
            assert connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[1]]
            monitor_rows = connection.property(root, "_DWM_MONITOR_DESKTOPS") or []
            if len(monitor_rows) >= 10:
                # Xvfb screens overlap; leave the destination's tag empty so
                # another monitor's tiled clients cannot intercept the press.
                run("xdotool", "key", "super+4")
                wait(lambda: connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [3], "Drag destination tag did not become visible")
                # Existing Super+left drag routes tiled clients through placemouse.
                connection.activate(windows[2])
                run("xdotool", "windowraise", str(windows[2]))
                run("xdotool", "mousemove", "400", "300", "keydown", "super", "mousedown", "1")
                try:
                    time.sleep(.2)
                    run("xdotool", "mousemove", "1100", "400")
                    time.sleep(.2)
                finally:
                    run("xdotool", "mouseup", "1", "keyup", "super")
                wait(lambda: next(row for row in connection.state()["windows"] if row["id"] == str(windows[2]))["monitor"] == 0, "Tiled drag left stale monitor metadata")
                moved = next(row for row in connection.state()["windows"] if row["id"] == str(windows[2]))
                assert moved["tags"] & 31 and not moved["tags"] & ~31, "Tiled drag left stale tag metadata"
            run("xdotool", "set_desktop_for_window", str(windows[2]), "0")
            wait(lambda: next(row for row in connection.state()["windows"] if row["id"] == str(windows[2]))["tags"] == 1, "Race cancellation target did not retag")
            connection.activate(windows[2])
            ipc("open")
            wait(lambda: len(state().get("windows", [])) == 3, "Closing-window scenario did not open")
            ipc("remember", str(windows[1]))
            x.XDestroyWindow(d, windows[1])
            x.XSync(d, False)
            wait(lambda: len(state()["windows"]) == 2, "Closed client remained in overview")
            failed = run(str(repo / "scripts/dwm-window-overview"), "activate", str(windows[1]), check=False)
            assert failed.returncode != 0
            ipc("activateRemembered")
            wait(lambda: state()["visible"] and not state()["busy"] and "closed" in state()["message"], "Closed-card failure did not reopen the overview")
            assert state()["returnWindow"] == str(windows[2]), "Activation failure lost cancellation context"
            ipc("close")
            wait(lambda: not state()["visible"] and not state()["busy"] and connection.property(root, "_NET_ACTIVE_WINDOW", 33) == [windows[2]], "Cancellation after failed activation lost the non-first tiled focus")
            for window in (windows[0], windows[2]):
                x.XDestroyWindow(d, window)
            x.XSync(d, False)
            ipc("open")
            wait(lambda: state()["visible"] and len(state()["windows"]) == 0 and not connection.state()["windows"], "Empty state did not update")
            ipc("close")
            # A GUI child inherits its terminal's actual tags through swallowing.
            parent = x.XCreateSimpleWindow(d, root, 0, 0, 300, 200, 0, 0, 0x557799)
            terminal_class = b"dwmterm\0Dwmterm\0"
            x.XChangeProperty(d, parent, connection.atom("WM_CLASS"), 31, 8, 0, terminal_class, len(terminal_class))
            x.XStoreName(d, parent, b"Swallow metadata parent")
            x.XMapWindow(d, parent)
            x.XSync(d, False)
            wait(lambda: len(connection.state()["windows"]) == 1, "Terminal did not map")
            run("xdotool", "set_desktop_for_window", str(parent), "2")
            wait(lambda: connection.state()["windows"][0]["tags"] == 4, "Terminal did not retag")
            child_source = """import ctypes as C, importlib.machinery,sys,time
sys.dont_write_bytecode=True
m=importlib.machinery.SourceFileLoader('overview_child',sys.argv[1]).load_module()
c=m.Connection();x,d=c.x,c.display
x.XCreateSimpleWindow.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_int,C.c_uint,C.c_uint,C.c_uint,C.c_ulong,C.c_ulong]
x.XCreateSimpleWindow.restype=C.c_ulong
x.XMapWindow.argtypes=[C.c_void_p,C.c_ulong]
w=x.XCreateSimpleWindow(d,c.root,0,0,300,200,0,0,0x889944)
x.XMapWindow(d,w);x.XFlush(d);time.sleep(30)
"""
            child = subprocess.Popen([sys.executable, "-c", child_source, str(repo / "scripts/dwm-window-overview")])
            processes.append(child)
            wait(lambda: len(connection.state()["windows"]) == 1 and connection.state()["windows"][0]["id"] != str(parent), "GUI did not swallow terminal")
            row = connection.state()["windows"][0]
            assert row["tags"] == 4, "Swallowed child did not inherit terminal metadata"
            connection.activate(int(row["id"]))
            wait(lambda: connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [2], "Swallowed client activation did not reach its actual tag")
            run("xdotool", "set_desktop_for_window", row["id"], "4")
            wait(lambda: connection.state()["windows"][0]["tags"] == 16, "Swallowed child retag failed")
            child.terminate(); child.wait(timeout=5)
            wait(lambda: len(connection.state()["windows"]) == 1 and connection.state()["windows"][0]["id"] == str(parent), "Terminal did not restore")
            assert connection.state()["windows"][0]["tags"] == 16, "Restored terminal retained stale metadata"
            connection.activate(parent)
            wait(lambda: connection.property(root, "_NET_CURRENT_DESKTOP", 6) == [4], "Restored terminal activation did not reach its actual tag")
            x.XDestroyWindow(d, parent); x.XSync(d, False)
            wait(lambda: not connection.state()["windows"], "Restored terminal did not close")
            snapshots = state()["snapshots"]
            ipc("open")
            wait(lambda: state()["snapshots"] > snapshots and not state()["pending"], "Overview did not receive its reopened empty snapshot")
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
