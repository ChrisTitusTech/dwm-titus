#!/usr/bin/python3
"""Exercise the real GTK offer and NetworkManager signal path on isolated D-Bus/X11."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk

sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("initial_client", str(
    Path(__file__).resolve().parents[1] / "scripts/dwm-initial-update"))
spec = importlib.util.spec_from_loader("initial_client", loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)

# The test owns the session bus; never impersonate NetworkManager on the host.
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
owner = Gio.bus_own_name_on_connection(bus, "org.freedesktop.NetworkManager", Gio.BusNameOwnerFlags.NONE, None, None)

with tempfile.TemporaryDirectory() as name:
    work = Path(name)
    os.environ["XDG_RUNTIME_DIR"] = str(work)
    marker = work / "pending"
    marker.touch()
    complete = work / "complete"
    helper = work / "probe"
    connected = work / "connected"
    helper.write_text('#!/bin/sh\n[ -f "' + str(connected) + '" ]\n')
    helper.chmod(0o755)
    seen = []

    def connect():
        assert not Gtk.Window.list_toplevels(), "Offline login must not display an update offer"
        connected.touch()
        bus.emit_signal(None, "/org/freedesktop/NetworkManager", "org.freedesktop.DBus.Properties",
                        "PropertiesChanged", GLib.Variant("(sa{sv}as)", (
                            "org.freedesktop.NetworkManager", {"Connectivity": GLib.Variant("u", 4)}, [])))
        return False

    def respond():
        dialogs = [window for window in Gtk.Window.list_toplevels() if isinstance(window, Gtk.MessageDialog)]
        if not dialogs:
            return True
        dialog = dialogs[0]
        screenshot = os.environ.get("DWM_INITIAL_UPDATE_SCREENSHOT")
        if screenshot:
            window = dialog.get_window()
            Gdk.pixbuf_get_from_window(window, 0, 0, window.get_width(), window.get_height()).savev(screenshot, "png", [], [])
        seen.append(dialog.get_property("text"))
        dialog.response(Gtk.ResponseType.OK)
        return False

    def timeout():
        print("Initial update UI did not respond to repository connectivity", file=sys.stderr, flush=True)
        os._exit(1)

    GLib.timeout_add(300, connect)
    GLib.timeout_add(100, respond)
    timeout_id = GLib.timeout_add_seconds(10, timeout)
    with patch.object(client, "PENDING", marker), patch.object(client, "COMPLETE", complete), \
            patch.object(client, "HELPER", helper), patch.object(client, "trusted"), \
            patch.object(client, "open_terminal") as launch:
        client.watch()
        launch.assert_called_once_with()
        assert seen == ["Update your new Fedora desktop?"]
        complete.touch()
        client.watch()
        launch.assert_called_once_with()
    GLib.source_remove(timeout_id)
Gio.bus_unown_name(owner)
print("PASS: offline login, NetworkManager-triggered repository probe, real GTK confirmation, completed-login suppression")
