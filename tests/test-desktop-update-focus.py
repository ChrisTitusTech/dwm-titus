#!/usr/bin/python3
"""Prove progress never covers a pending authorization dialog under real dwm."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("progress", str(repo / "scripts/dwm-desktop-update-progress"))
spec = importlib.util.spec_from_loader("progress", loader)
ui = importlib.util.module_from_spec(spec)
loader.exec_module(ui)


def pump(condition, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        while ui.GLib.MainContext.default().pending():
            ui.GLib.MainContext.default().iteration(False)
        if condition():
            return True
        time.sleep(0.01)
    return condition()


def focus():
    return subprocess.check_output(["xdotool", "getwindowfocus"], text=True).strip()


with tempfile.TemporaryDirectory(prefix="desktop-focus-") as tmp, patch.dict(os.environ):
    base = Path(tmp)
    for key, suffix in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                        ("XDG_DATA_HOME", "data"), ("XDG_STATE_HOME", "state")):
        path = base / suffix
        path.mkdir()
        os.environ[key] = str(path)
    state = base / "state/dwm-titus/desktop-update"
    state.mkdir(parents=True)
    value = dict(schema=1, state="starting", detail="Waiting for approval", operation="a" * 32,
                 authorization="begin", percent=-1, startedAt=time.time())
    def publish(**changes):
        value.update(changes)
        temporary = state / "status.tmp"
        temporary.write_text(json.dumps(value))
        temporary.replace(state / "status.json")
    publish()
    wm = subprocess.Popen([str(repo / "dwm")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    app = ui.ProgressApp()
    auth = None
    try:
        app.register(None)
        auth = ui.Gtk.Window(title="Authorization fixture")
        auth.set_type_hint(ui.Gdk.WindowTypeHint.DIALOG)
        auth.set_default_size(320, 160)
        auth.add(ui.Gtk.Entry(visibility=False))
        auth.show_all()
        auth.present()
        pump(lambda: False, 0.4)
        assert wm.poll() is None, "Nested dwm failed to start"
        original = focus()
        app.activate()
        pump(lambda: False, 0.3)
        assert focus() == original, "Progress took focus from the existing password dialog"
        assert not app.window.get_visible(), "New progress window covered the password dialog"
        auth.hide()
        publish(state="building", detail="Building desktop", authorization="")
        assert pump(lambda: app.window.get_visible()), "Progress was not revealed after approval"
        assert app.window.get_accept_focus(), "Progress did not regain normal keyboard interaction"
        auth.show_all()
        auth.present()
        pump(lambda: False, 0.3)
        original = focus()
        publish(state="verifying", detail="Verifying desktop", percent=50)
        assert pump(lambda: app.bar.get_fraction() == 0.5)
        pump(lambda: False, 0.2)
        assert focus() == original and app.window.get_visible(), "Progress update stole focus or closed the window"
        print("Actual dwm: pending authorization remains visible and focused; approval reveals progress; status changes preserve focus: PASS")
    finally:
        if auth:
            auth.destroy()
        if app.window:
            app.window.destroy()
            for monitor in app.monitors:
                monitor.cancel()
            app.release()
        wm.terminate()
        wm.wait(timeout=5)
