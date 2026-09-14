#!/usr/bin/python3
"""Real GTK/X11 progress lifecycle with isolated update records and D-Bus."""
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


def pump(condition=lambda: False, timeout=1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        while ui.GLib.MainContext.default().pending():
            ui.GLib.MainContext.default().iteration(False)
        if condition():
            return True
        time.sleep(0.01)
    return condition()


with tempfile.TemporaryDirectory(prefix="desktop-progress-") as temporary, patch.dict(os.environ):
    base = Path(temporary)
    os.environ["XDG_STATE_HOME"] = str(base)
    state = base / "dwm-titus/desktop-update"
    state.mkdir(parents=True)
    value = dict(schema=1, state="starting", detail="Waiting for approval", percent=-1,
                 operation="a" * 32, authorization="begin", startedAt=time.time() - 65)
    def publish(**changes):
        value.update(changes)
        temporary = state / "status.tmp"
        temporary.write_text(json.dumps(value))
        temporary.replace(state / "status.json")
    publish()
    notifications = []
    pending_notifications = []
    bus = ui.Gio.bus_get_sync(ui.Gio.BusType.SESSION, None)
    bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                  ui.GLib.Variant("(su)", ("org.freedesktop.Notifications", 0)), None,
                  ui.Gio.DBusCallFlags.NONE, 5000, None)
    interface = ui.Gio.DBusNodeInfo.new_for_xml("""<node><interface name="org.freedesktop.Notifications">
      <method name="GetCapabilities"><arg type="as" direction="out"/></method>
      <method name="GetServerInformation"><arg type="s" direction="out"/><arg type="s" direction="out"/>
        <arg type="s" direction="out"/><arg type="s" direction="out"/></method>
      <method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
        <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
        <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/></method>
    </interface></node>""").interfaces[0]
    def notification_call(_bus, _sender, _path, _interface, method, parameters, invocation):
        if method == "GetCapabilities":
            invocation.return_value(ui.GLib.Variant("(as)", (["body"],)))
        elif method == "GetServerInformation":
            invocation.return_value(ui.GLib.Variant("(ssss)", ("fixture", "fixture", "1", "1.2")))
        elif method == "Notify":
            notifications.append(parameters.unpack())
            if len(notifications) == 2:
                pending_notifications.append(invocation)
            else:
                invocation.return_value(ui.GLib.Variant("(u)", (1,)))
    registration = bus.register_object("/org/freedesktop/Notifications", interface, notification_call, None, None)
    app = ui.ProgressApp()
    assert app.register(None)
    app.activate()
    assert not app.window.get_visible(), "Initial window must not cover authorization"
    assert not app.window.get_accept_focus(), "Approval must be allowed to take focus"
    assert app.heading.get_text() == "Administrator approval needed"
    assert app.elapsed.get_text().startswith("Elapsed: 1m")
    window = app.window
    publish(state="building", detail="Building the desktop", authorization="")
    assert pump(lambda: app.heading.get_text() == "Building desktop"), "Atomic status replacement was not watched"
    assert window.get_visible() and window.get_accept_focus(), "Approval must reveal an interactive progress window"
    app.hide()
    assert not window.get_visible() and value["state"] == "building"
    remote = subprocess.Popen([sys.executable, repo / "scripts/dwm-desktop-update-progress"])
    assert pump(lambda: remote.poll() is not None, 5), "Second activation did not return"
    assert remote.returncode == 0 and window.get_visible(), "Hidden singleton was not reopened"
    assert app.window is window and len(app.get_windows()) == 1

    # A managed-shell process can exit while this independent GTK window stays.
    shell = base / "shell.qml"
    shell.write_text("import Quickshell\nShellRoot {}\n")
    with (base / "shell.log").open("w") as log:
        process = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(shell)], stdout=log, stderr=log)
        try:
            assert not pump(lambda: process.poll() is not None, 0.5), "Fixture shell failed"
            process.terminate()
            process.wait(timeout=5)
            assert app.window.get_visible(), "Shell exit closed progress"
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    log_dir = state / "operations" / value["operation"]
    log_dir.mkdir(parents=True)
    (log_dir / "update.log").write_text("Installing files\n<literal untrusted markup>\n")
    app.show_log()
    buffer = app.log_text.get_buffer()
    assert "<literal untrusted markup>" in buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)
    app.log_close_button.clicked()
    assert not app.log_window.get_visible() and window.get_visible(), "Closing the log must leave progress visible"
    app.show_log()
    assert app.log_window.get_visible(), "Closed log must reopen"
    (log_dir / "update.log").write_bytes(b"x" * (256 * 1024))
    assert len(ui.log_tail(state, value)) == 128 * 1024
    fifo = base / "fifo"
    os.mkfifo(fifo)
    try:
        ui.read_status(fifo)
        raise AssertionError("FIFO status was accepted")
    except ValueError:
        pass
    publish(state="activating", detail="Restarting desktop", percent=-1)
    assert pump(lambda: app.heading.get_text() == "Restarting desktop")
    publish(state="restart-required", detail="Log out to activate", percent=100)
    assert pump(lambda: app.heading.get_text() == "Logout required")
    assert window.get_visible() and app.hide_button.get_label() == "Close"
    assert app.bar.get_fraction() == 1
    assert app.notified == {value["operation"]}
    assert pump(lambda: len(notifications) == 1, 5), "Completion notification was not delivered"
    assert notifications[0][3] == "Logout required"
    app.reload()
    pump(timeout=0.1)
    assert len(notifications) == 1, "Completion notification repeated"
    quits = []
    app.quit = lambda: quits.append(True)
    publish(operation="b" * 32, state="building", detail="A second update", percent=-1)
    assert pump(lambda: app.value.get("operation") == "b" * 32)
    app.hide()
    assert not quits and not window.get_visible(), "Hide must not end active monitoring"
    publish(state="failed", detail="Build failed <fixture>")
    assert pump(lambda: len(notifications) == 2, 5)
    assert not quits, "Hidden service exited before notification delivery"
    app.hide()
    assert not quits, "Close exited while notification delivery was pending"
    pending_notifications.pop().return_value(ui.GLib.Variant("(u)", (1,)))
    assert pump(lambda: bool(quits), 5), "Hidden service did not exit after notification delivery"
    assert not window.get_visible(), "Hidden completion stole focus"
    assert notifications[1][4] == "Build failed &lt;fixture&gt;", "Notification body markup was not escaped"
    bad = state / "invalid.json"
    bad.write_text(json.dumps(dict(value, startedAt=float("inf"))))
    try:
        ui.read_status(bad)
        raise AssertionError("Non-finite elapsed time was accepted")
    except ValueError:
        pass
    bad.write_text(json.dumps(dict(value, state="not-a-state")))
    try:
        ui.read_status(bad)
        raise AssertionError("Unknown state was accepted")
    except ValueError:
        pass
    for name in ("unknown", "checking", "available", "blocked", "drift"):
        bad.write_text(json.dumps(dict(value, state=name, operation="")))
        assert ui.read_status(bad)["state"] == name, "Valid idle state was rejected"
    bus.unregister_object(registration)
    app.hide()
    for monitor in app.monitors:
        monitor.cancel()
    app.window.destroy()
    if app.log_window:
        app.log_window.destroy()
    app.release()
print("Independent GTK progress, atomic status watch, authorization focus, hide/reopen singleton, shell exit, logs and completion: PASS")
