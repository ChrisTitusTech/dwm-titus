#!/usr/bin/env python3
"""Exercise real Picom, configuration watching and Appearance on an isolated X server."""

import ctypes
import ctypes.util
import importlib.machinery
import importlib.util
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import ImageGrab

repo = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    "picom_runtime", str(repo / "scripts/dwm-settings-picom")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
picom = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
loader.exec_module(picom)


def wait_until(callback, description, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if callback():
            return
        time.sleep(0.05)
    raise AssertionError(description() if callable(description) else description)


def main():
    for command in ("Xvfb", "picom", "quickshell", "dbus-run-session", "inotifywait"):
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required")
    primary = picom.processes()
    xvfb = shell = connection = None
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
        work = Path(directory)
        home, config, data, runtime = [
            work / p for p in ("home", "config", "data", "runtime")
        ]
        for path in (home, config, data, runtime):
            path.mkdir(mode=0o700)
        env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(config),
            "XDG_CONFIG_DIRS": str(work / "vendor"),
            "XDG_DATA_HOME": str(data),
            "XDG_STATE_HOME": str(work / "state"),
            "XDG_RUNTIME_DIR": str(runtime),
            "DWM_PICOM_CONFIG": "",
            "PICOM_BACKEND": "",
            "QT_QUICK_BACKEND": "software",
            "QSG_RHI_BACKEND": "software",
            "QT_QPA_PLATFORMTHEME": "",
        }
        read_fd, write_fd = os.pipe()
        try:
            with open(work / "xvfb.log", "w") as log:
                xvfb = subprocess.Popen(
                    [
                        "Xvfb",
                        "-displayfd",
                        str(write_fd),
                        "-screen",
                        "0",
                        "1024x768x24",
                        "-nolisten",
                        "tcp",
                    ],
                    pass_fds=(write_fd,),
                    stdout=log,
                    stderr=log,
                )
            os.close(write_fd)
            if not select.select([read_fd], [], [], 10)[0]:
                raise AssertionError("Xvfb startup timed out")
            display = ":" + os.read(read_fd, 32).decode().strip()
            os.close(read_fd)
            env["DISPLAY"] = display

            def helper(*args, success=True):
                result = subprocess.run(
                    [str(repo / "scripts/dwm-settings-picom"), *args],
                    env=env,
                    text=True,
                    capture_output=True,
                    timeout=25,
                    check=False,
                )
                if success and result.returncode:
                    raise AssertionError(result.stderr)
                return json.loads(result.stdout) if success else result

            conf = config / "picom.conf"
            helper("start")
            fresh = helper("status")
            assert fresh["editable"] and not conf.exists()
            helper("set-opacity", "100", "100", fresh["revision"])
            assert conf.exists()
            helper("stop")
            print("PASS: first edit after startup without configuration", flush=True)
            conf.write_text(
                'backend="xrender";\nactive-opacity=1.0;\ninactive-opacity=1.0;\nfading=false;\nshadow=false;\nuse-ewmh-active-win=true;\n'
            )
            helper("start")
            before = helper("status")
            assert before["running"] and before["effective"] == "xrender"
            with ThreadPoolExecutor(max_workers=4) as pool:
                snapshots = list(pool.map(lambda _: helper("status"), range(8)))
            assert all(s["editable"] and s["running"] for s in snapshots)
            print(
                "PASS: diagnostic probes never appear as duplicate compositors",
                flush=True,
            )
            helper("set-opacity", "90", "50", before["revision"])
            assert helper("status")["inactive"] == 50

            lib = ctypes.CDLL(ctypes.util.find_library("X11"))
            lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
            lib.XOpenDisplay.restype = ctypes.c_void_p
            lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
            lib.XDefaultRootWindow.restype = ctypes.c_ulong
            lib.XCreateSimpleWindow.argtypes = [
                ctypes.c_void_p,
                ctypes.c_ulong,
                ctypes.c_int,
                ctypes.c_int,
                ctypes.c_uint,
                ctypes.c_uint,
                ctypes.c_uint,
                ctypes.c_ulong,
                ctypes.c_ulong,
            ]
            lib.XCreateSimpleWindow.restype = ctypes.c_ulong
            lib.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
            lib.XSetInputFocus.argtypes = [
                ctypes.c_void_p,
                ctypes.c_ulong,
                ctypes.c_int,
                ctypes.c_ulong,
            ]
            lib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
            lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
            connection = lib.XOpenDisplay(display.encode())
            root = lib.XDefaultRootWindow(connection)
            first = lib.XCreateSimpleWindow(
                connection, root, 20, 20, 180, 180, 0, 0, 0xFF0000
            )
            second = lib.XCreateSimpleWindow(
                connection, root, 240, 20, 180, 180, 0, 0, 0xFF0000
            )
            lib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
            lib.XInternAtom.restype = ctypes.c_ulong
            lib.XChangeProperty.argtypes = [
                ctypes.c_void_p,
                ctypes.c_ulong,
                ctypes.c_ulong,
                ctypes.c_ulong,
                ctypes.c_int,
                ctypes.c_int,
                ctypes.c_void_p,
                ctypes.c_int,
            ]
            wm_state = lib.XInternAtom(connection, b"WM_STATE", 0)
            normal_state = (ctypes.c_ulong * 2)(1, 0)
            type_atom = lib.XInternAtom(connection, b"_NET_WM_WINDOW_TYPE", 0)
            normal_type = ctypes.c_ulong(
                lib.XInternAtom(connection, b"_NET_WM_WINDOW_TYPE_NORMAL", 0)
            )
            for window in (first, second):
                lib.XChangeProperty(
                    connection, window, wm_state, wm_state, 32, 0, normal_state, 2
                )
                lib.XChangeProperty(
                    connection,
                    window,
                    type_atom,
                    4,
                    32,
                    0,
                    ctypes.byref(normal_type),
                    1,
                )
                lib.XMapWindow(connection, window)
            lib.XSync(connection, 0)
            lib.XSetInputFocus(connection, first, 1, 0)
            active_atom = lib.XInternAtom(connection, b"_NET_ACTIVE_WINDOW", 0)
            window_atom = lib.XInternAtom(connection, b"WINDOW", 0)
            value = ctypes.c_ulong(first)
            lib.XChangeProperty(
                connection,
                root,
                active_atom,
                window_atom,
                32,
                0,
                ctypes.byref(value),
                1,
            )
            lib.XSync(connection, 0)
            # Let Picom import the synthetic clients before delivering a focus
            # transition, as a window manager would after managing MapRequest.
            time.sleep(0.3)
            lib.XSetInputFocus(connection, second, 1, 0)
            lib.XSync(connection, 0)
            time.sleep(0.1)
            lib.XSetInputFocus(connection, first, 1, 0)
            lib.XSync(connection, 0)
            lib.XChangeProperty(
                connection,
                root,
                active_atom,
                window_atom,
                32,
                0,
                ctypes.byref(value),
                1,
            )
            lib.XSync(connection, 0)
            samples = []

            def opacity_visible():
                image = ImageGrab.grab(xdisplay=display)
                a, b = image.getpixel((80, 80))[0], image.getpixel((280, 80))[0]
                samples.append((a, b))
                return abs(a - 230) < 12 and abs(b - 128) < 12

            wait_until(
                opacity_visible,
                lambda: (
                    f"Active/inactive opacity must change actual rendered pixels: {samples[-5:]}"
                ),
            )
            print("PASS: real XRender focus-dependent opacity", flush=True)

            # Modern rules use the same global controls while preserving custom rules.
            conf.write_text(
                'backend="xrender";\nrules=({match="window_type = \'dock\'"; opacity=1.0;});\n'
            )
            helper("set-opacity", "85", "65", helper("status")["revision"])
            assert helper("status")["active"] == 85
            assert "window_type = 'dock'" in conf.read_text()
            helper("restart")
            helper("set-backend", "auto", helper("status")["revision"])
            assert helper("status")["policy"] == "auto"
            assert (
                helper("status")["effective"] == "xrender"
            )  # Xvfb is software-rendered.
            print(
                "PASS: modern rules, restart, and software-renderer selection",
                flush=True,
            )

            # Use the actual managed-path QML model and controls, with IPC for assertions.
            qml = config / "quickshell"
            shutil.copytree(repo / "config/quickshell", qml)
            scripts = data / "dwm-titus/scripts"
            scripts.mkdir(parents=True)
            shutil.copy2(repo / "scripts/dwm-settings-picom", scripts)
            (qml / "shell.qml").write_text("""import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "appearance"
import "settings"
import qs.core
ShellRoot {
    PicomModel { id: provider; active: true }
    FloatingWindow {
        visible: true
        color: Theme.bg
        implicitWidth: 700
        implicitHeight: 600
        ColumnLayout { anchors.fill: parent; anchors.margins: 20; PicomSettingsPane { model: provider } }
    }
    IpcHandler {
        target: "picomTest"
        function state(): string { return JSON.stringify(provider.snapshot); }
        function error(): string { return provider.failure; }
        function opacity(a: int, b: int): void { provider.setOpacity(a, b); }
        function enabled(value: bool): void { provider.active = value; }
    }
}
""")
            with open(work / "qml.log", "w") as log:
                shell = subprocess.Popen(
                    [
                        "dbus-run-session",
                        "--",
                        "quickshell",
                        "--no-duplicate",
                        "--path",
                        str(qml / "shell.qml"),
                    ],
                    env=env,
                    stdout=log,
                    stderr=log,
                    start_new_session=True,
                )

            def ipc(method, *args):
                return subprocess.run(
                    [
                        "quickshell",
                        "ipc",
                        "--path",
                        str(qml / "shell.qml"),
                        "call",
                        "picomTest",
                        method,
                        *args,
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=8,
                    check=False,
                )

            def ui_matches(key, expected):
                result = ipc("state")
                if result.returncode:
                    return False
                return json.loads(result.stdout).get(key) == expected

            wait_until(lambda: ui_matches("active", 85), "QML did not load Picom state")
            if os.environ.get("DWM_TEST_PICOM_CAPTURE"):
                ImageGrab.grab(xdisplay=display).save(
                    os.environ["DWM_TEST_PICOM_CAPTURE"]
                )
            assert ipc("opacity", "80", "60").returncode == 0
            wait_until(
                lambda: ui_matches("active", 80), "QML mutation did not converge"
            )
            final_state = helper("status")
            assert final_state["inactive"] == 60, (
                final_state,
                ipc("state").stdout,
                ipc("error").stdout,
                conf.read_text(),
            )
            conf.write_text(
                conf.read_text().replace("opacity = 0.8;", "opacity = 0.7;")
            )
            wait_until(
                lambda: ui_matches("active", 70),
                "External configuration edit was not observed",
            )
            helper("stop")
            assert ui_matches("active", 70)
            assert ipc("enabled", "false").returncode == 0
            assert ipc("enabled", "true").returncode == 0
            wait_until(
                lambda: ui_matches("running", False),
                "Stopped compositor state did not load",
            )
            assert ui_matches("editable", True)
            assert ipc("error").stdout.strip() == ""
            conf.write_text(
                'backend="xrender"; daemon=true; active-opacity=.8; inactive-opacity=.6;'
            )
            helper("start")
            helper("set-opacity", "75", "55", helper("status")["revision"])
            assert helper("status")["running"]
            conf.write_text("malformed configuration")
            helper("stop")
            nested = work / "nested-wintypes.conf"
            nested.write_text("tooltip = { opacity = 0.8; };")
            native_text = (
                'backend="xrender"; wintypes = {\n@include "' + str(nested) + '"\n};'
            )
            conf.write_text(native_text)
            helper("start")
            assert helper("status")["running"]
            assert not helper("status")["editable"]
            helper("reload")
            helper("restart")
            assert helper("status")["running"]
            assert conf.read_text() == native_text
            helper("stop")
            print(
                "PASS: daemonized Picom, malformed-config stop, and native nested-include sessions",
                flush=True,
            )
            log_text = (work / "qml.log").read_text()
            assert not any(
                text in log_text
                for text in (
                    "ReferenceError:",
                    "TypeError:",
                    "Failed to load configuration",
                )
            )
            print(
                "PASS: real QML controls, mutations, file watch, and stable stopped-compositor controls",
                flush=True,
            )
        except Exception:
            for path in (
                work / "xvfb.log",
                work / "qml.log",
                work / "state/dwm-titus/picom/session.log",
            ):
                if path.exists():
                    print(path.name + ":\n" + path.read_text()[-6000:])
            raise
        finally:
            if shell:
                os.killpg(shell.pid, 15)
                shell.wait(timeout=8)
            if "display" in locals():
                subprocess.run(
                    [str(repo / "scripts/dwm-settings-picom"), "stop"],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=10,
                    check=False,
                )
            if connection:
                lib.XCloseDisplay(connection)
            if xvfb:
                xvfb.terminate()
                xvfb.wait(timeout=8)
        assert picom.processes() == primary, (
            "The primary display compositor was changed"
        )
        print("PASS: primary display compositor unchanged", flush=True)


if __name__ == "__main__":
    main()
