#!/usr/bin/python3
"""Qualify fixed printer unit reads without touching the host system bus."""

import os
import runpy
import sys
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="cups_read_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
service = provider["SYSTEMD_NAME"]
mode = "normal"
calls, held = [], []
manager = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.systemd1.Manager">
<method name="ListUnitsByNames"><arg type="as" direction="in"/>
<arg type="a(ssssssouso)" direction="out"/></method>
</interface></node>""").interfaces[0]


def name_call(method):
    args = GLib.Variant("(su)", (service, 0)) if method == "RequestName" else GLib.Variant("(s)", (service,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def called(_bus, _sender, path, interface, method, args, invocation):
    assert (path, interface, method) == (provider["SYSTEMD_PATH"], provider["SYSTEMD_MANAGER"], "ListUnitsByNames")
    names = args.unpack()[0]
    assert len(names) == 1 and names[0] in provider["CUPS_UNITS"]
    unit = names[0]
    calls.append(unit)
    if mode == "denied":
        invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
    elif mode == "absent":
        invocation.return_dbus_error("org.freedesktop.systemd1.NoSuchUnit", "fixture absence")
    elif mode == "stall-" + unit.split(".")[1]:
        held.append(invocation)
    else:
        load, active, sub = "loaded", "active", "running" if unit.endswith("service") else "listening"
        if unit.endswith("service") and mode in ("socket-ready", "stopped"):
            active, sub = "inactive", "dead"
        if unit.endswith("socket") and mode == "stopped":
            load, active, sub = "not-found", "inactive", "dead"
        if mode == "malformed":
            active = "bad\nstate"
        row = (unit, "Fixture", load, active, sub, "", provider["SYSTEMD_PATH"] + "/unit/fixture", 0, "", "/")
        invocation.return_value(GLib.Variant(provider["UNIT_REPLY_TYPE"], ([row],)))


registration = None
try:
    assert name_call("RequestName") == 1
    registration = bus.register_object(provider["SYSTEMD_PATH"], manager, called, None, None)
    for mode, expected in (("normal", ("available", "running")),
                           ("socket-ready", ("available", "socket-ready")),
                           ("stopped", ("available", "stopped")),
                           ("absent", ("unsupported", "unknown")),
                           ("denied", ("unavailable", "unknown")),
                           ("malformed", ("partial", "unknown"))):
        result = provider["CupsRead"]().run()
        assert (result.status, result.value) == expected, result
    for mode in ("stall-service", "stall-socket"):
        held.clear()
        started = time.monotonic()
        reader = provider["CupsRead"]()
        result = reader.run()
        elapsed = time.monotonic() - started
        assert 9 <= elapsed < 15, elapsed
        expected = ("available", "running") if mode == "stall-socket" else ("unavailable", "unknown")
        assert (result.status, result.value) == expected, result
        assert [error.code for error in result.errors] == ["timeout"]
        assert len(held) == 1
        held[0].return_dbus_error("org.freedesktop.DBus.Error.Failed", "late reply")
        mode = "normal"
        assert provider["CupsRead"]().run().value == "running"
        assert reader.value is result
    assert name_call("ReleaseName") == 1
    result = provider["CupsRead"]().run()
    assert (result.status, result.value) == ("unavailable", "unknown")
    assert all(error.code == "missing-provider" for error in result.errors)
    assert set(calls) == set(provider["CUPS_UNITS"])
    print("Private-bus printer reads: PASS (typed states, denial, absence, aggregate deadlines, late replies)")
finally:
    if registration is not None:
        bus.unregister_object(registration)
