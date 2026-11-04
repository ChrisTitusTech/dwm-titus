#!/usr/bin/env python3
"""Exercise calendar and weather popups, explicit networking and panel persistence on private X11."""
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


from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading

sample = {"current_condition": [{"temp_C": "22", "temp_F": "72", "FeelsLikeC": "25", "FeelsLikeF": "76",
    "humidity": "76", "windspeedKmph": "7", "windspeedMiles": "4", "weatherDesc": [{"value": "Overcast"}]}]}


class Handler(BaseHTTPRequestHandler):
    requests = []
    code = 200
    delay = 0
    def do_GET(self):
        Handler.requests.append(self.path)
        time.sleep(Handler.delay)
        self.send_response(Handler.code)
        self.end_headers()
        self.wfile.write(json.dumps(sample).encode())
    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
    work = Path(directory)
    with tempfile.TemporaryDirectory(prefix="qs-widgets-", dir="/tmp") as runtime:
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
        for helper in ("dwm-panel-settings", "dwm-window-overview", "dwm-layout-settings"):
            (helpers / helper).symlink_to(repo / "scripts" / helper)
        os.environ["PATH"] = str(helpers) + os.pathsep + os.environ["PATH"]
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        wrapper = helpers / "dwm-weather"
        wrapper.write_text("#!/usr/bin/env python3\nimport importlib.machinery,sys\nsys.dont_write_bytecode=True\n"
            + "module=importlib.machinery.SourceFileLoader('weather'," + repr(str(repo / "scripts/dwm-weather")) + ").load_module()\n"
            + "module.PROVIDER=" + repr(f"http://127.0.0.1:{server.server_port}/") + "\nsys.exit(module.main())\n")
        wrapper.chmod(0o755)
        qml = work / "config/quickshell"
        shutil.copytree(repo / "config/quickshell", qml)
        shell_source = (qml / "shell.qml").read_text()
        integration = """
    IpcHandler {
        target: "widgetTest"
        function state(): string { return JSON.stringify({weather:weatherModel.weather, fetched:weatherModel.fetched,
            location:weatherModel.location, unit:weatherModel.unit, busy:weatherModel.busy, message:weatherModel.message,
            weatherVisible:weatherModel.visible, calendarVisible:calendarModel.visible, month:calendarModel.month,
            year:calendarModel.year, days:calendarModel.days, widgets:panelSettingsModel.values,
            provider:panelSettingsModel.providerState, utilityVisible:controlCenterModel.utilityVisible, clipboardVisible:clipboardModel.visible,
            overviewVisible:windowOverviewModel.visible, overviewBusy:windowOverviewModel.busy}); }
        function calendar(): void {
            calendarModel.timestamp = new Date(2024, 1, 29, 12).getTime();
            root.requestPanelPopup(root.defaultPanelWindow, "calendar");
        }
        function weather(): void { root.requestPanelPopup(root.defaultPanelWindow, "weather"); }
        function month(delta:int): void { calendarModel.changeMonth(delta); }
        function widget(id:string, enabled:bool): void { panelSettingsModel.setWidget(id, enabled); }
        function fetch(city:string, unit:string): void { weatherModel.fetch(city, unit); }
    }
"""
        (qml / "shell.qml").write_text(shell_source.rsplit("}", 1)[0] + integration + "}\n")
        processes = []
        try:
            log = open(work / "dwm.log", "w")
            wm = subprocess.Popen([str(repo / "dwm")], stdout=log, stderr=log)
            processes.append(wm)
            time.sleep(.3)
            with open(work / "qml.log", "w") as qlog:
                shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")], stdout=qlog, stderr=qlog)
            processes.append(shell)

            def ipc(method, *args):
                return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "widgetTest", method, *args, check=False)

            def state():
                result = ipc("state")
                return json.loads(result.stdout) if result.returncode == 0 else {}

            wait(lambda: state().get("provider") in ("defaults", "available"), "Widget provider failed to load")
            assert not state()["widgets"]["calendar"] and not state()["widgets"]["weather"]
            assert not Handler.requests, "Weather contacted the service at startup"
            ipc("widget", "calendar", "true")
            wait(lambda: state()["widgets"]["calendar"], "Calendar toggle did not persist")
            ipc("calendar")
            wait(lambda: state()["calendarVisible"], "Calendar did not open")
            days = state()["days"]
            assert len(days) == 42 and sum(day["current"] for day in days) == 29
            assert sum(day["today"] for day in days) == 1
            ipc("month", "10")
            assert (state()["year"], state()["month"]) == (2024, 11)
            run("xdotool", "key", "Right")
            wait(lambda: state()["year"] == 2025 and state()["month"] == 0, "Calendar keyboard year rollover failed")
            evidence = os.environ.get("DWM_FEATURE_EVIDENCE_DIR")
            if evidence:
                from PIL import ImageGrab
                Path(evidence).mkdir(parents=True, exist_ok=True)
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "calendar-widget.png")
            run("xdotool", "key", "Escape")
            wait(lambda: not state()["calendarVisible"], "Calendar Escape failed")
            # Exercise the actual production root, IPC and default shortcut.
            ipc("calendar")
            run("xdotool", "key", "super+v")
            wait(lambda: state()["clipboardVisible"] and not state()["calendarVisible"], "Clipboard shortcut left Calendar above the clipboard")
            run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "clipboard", "close")
            for widget in ("calendar",):
                ipc(widget)
                run("xdotool", "key", "super+slash")
                wait(lambda: state()["utilityVisible"] and not state()["calendarVisible"], "Keybinds shortcut left Calendar above its utility")
                run("xdotool", "key", "Escape")
                wait(lambda: not state()["utilityVisible"], "Keybinds Escape failed")
            ipc("widget", "weather", "true")
            wait(lambda: state()["widgets"]["weather"], "Weather toggle did not persist")
            ipc("weather")
            wait(lambda: state()["weatherVisible"] and not state()["busy"], "Weather status did not load")
            assert not Handler.requests, "Opening Weather made an unsolicited request"
            run("xdotool", "type", "Salt Lake City")
            run("xdotool", "key", "Return")
            wait(lambda: state()["fetched"] > 0 and not state()["busy"], "Explicit Enter fetch did not finish")
            assert Handler.requests == ["/Salt%20Lake%20City?format=j1"]
            assert state()["weather"]["temperature"] == "22"
            if evidence:
                ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(Path(evidence) / "weather-widget.png")
            run("xdotool", "key", "super+v")
            wait(lambda: state()["clipboardVisible"] and not state()["weatherVisible"], "Clipboard shortcut left Weather above the clipboard")
            run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "clipboard", "close")
            ipc("weather")
            run("xdotool", "key", "super+slash")
            wait(lambda: state()["utilityVisible"] and not state()["weatherVisible"], "Keybinds shortcut left Weather above its utility")
            run("xdotool", "key", "Escape")
            wait(lambda: not state()["utilityVisible"], "Weather keybinds Escape failed")
            request_count = len(Handler.requests)
            for widget in ("calendar", "weather"):
                ipc(widget)
                wait(lambda: state()[widget + "Visible"], f"{widget} did not reopen for overview")
                run("xdotool", "key", "super+Tab")
                wait(lambda: state()["overviewVisible"] and not state()["overviewBusy"], "Super+Tab did not open overview over a panel popup")
                assert not state()["calendarVisible"] and not state()["weatherVisible"], "Panel widget remained visible over the overview"
                run("xdotool", "key", "Escape")
                wait(lambda: not state()["overviewVisible"] and not state()["overviewBusy"], "Overview Escape did not dismiss")
            assert len(Handler.requests) == request_count, "Opening overview fetched weather"
            ipc("weather")
            Handler.code = 503
            ipc("fetch", "London", "f")
            wait(lambda: state()["message"].startswith("Weather unavailable") and not state()["busy"], "Offline failure was not reported")
            assert state()["location"] == "Salt Lake City" and state()["weather"]["temperature"] == "22"
            request_count = len(Handler.requests)
            ipc("weather")
            ipc("weather")
            time.sleep(.2)
            assert len(Handler.requests) == request_count, "Reopening Weather made a network request"
            run("xdotool", "mousemove", "20", "600", "click", "1")
            wait(lambda: not state()["weatherVisible"], "Weather click-away failed")
            ipc("weather")
            wait(lambda: state()["weatherVisible"] and not state()["busy"], "Weather did not reopen for delayed fetch")
            Handler.code = 200
            Handler.delay = 2
            run("xdotool", "key", "Return")
            wait(lambda: state()["busy"], "Delayed fetch did not start")
            run("xdotool", "key", "Escape")
            wait(lambda: not state()["weatherVisible"] and state()["busy"], "Escape did not dismiss Weather during a fetch")
            wait(lambda: not state()["busy"], "Dismissed fetch did not finish")
            Handler.delay = 0
            ipc("weather")
            ipc("widget", "weather", "false")
            wait(lambda: not state()["weatherVisible"], "Disabling Weather left its popup visible")
            before = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            time.sleep(2)
            after = sum(map(int, Path(f"/proc/{shell.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            assert after - before <= 15
            print(f"Calendar leap year/navigation, popup Escape (including fetch)/click-away/clipboard/keybinds/overview hotkeys, persisted toggles, no automatic weather requests, explicit fetch/failure cache: PASS; closed idle ticks/2s={after-before}")
        finally:
            if sys.exc_info()[0]:
                print((work / "qml.log").read_text() if (work / "qml.log").exists() else "No QML log", file=sys.stderr)
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            server.shutdown()
            server.server_close()
