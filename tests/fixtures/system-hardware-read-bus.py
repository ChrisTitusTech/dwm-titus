#!/usr/bin/python3
"""Qualify fixed hardware reads and aggregate deadlines on a private bus."""

import os
import runpy
import sys
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="hardware_read_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
name = "org.freedesktop.hostname1"
path = "/org/freedesktop/hostname1"
fields = {"HardwareVendor": "hardware-vendor", "HardwareModel": "hardware-model"}
mode = "normal"
selected = "HardwareVendor"
late_peer = False
held = []
calls = []
properties = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.DBus.Properties">
<method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
</interface></node>""").interfaces[0]


def name_call(method):
    """Manage only the fixture's well-known name, never a host service."""
    args = GLib.Variant("(su)", (name, 0)) if method == "RequestName" else GLib.Variant("(s)", (name,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        method, args, GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def respond(invocation, field):
    invocation.return_value(GLib.Variant("(v)", (GLib.Variant("s", field),)))


def called(_bus, _sender, object_path, interface, method, args, invocation):
    """Serve only two allowlisted read-only properties with typed replies."""
    target, field = args.unpack()
    assert (object_path, interface, method, target) == (path, "org.freedesktop.DBus.Properties", "Get", name)
    assert field in fields
    calls.append(field)
    if mode == "stall" and (field == selected or late_peer):
        held.append((invocation, field))
    elif field == selected and mode in ("denied", "missing"):
        error = "AccessDenied" if mode == "denied" else "UnknownProperty"
        invocation.return_dbus_error("org.freedesktop.DBus.Error." + error, "Private fixture detail")
    elif field == selected and mode in ("malformed", "oversized"):
        value = GLib.Variant("b", True) if mode == "malformed" else GLib.Variant("s", "x" * 513)
        invocation.return_value(GLib.Variant("(v)", (value,)))
    else:
        respond(invocation, field)


def fresh_read():
    start = len(calls)
    read = provider["HardwareRead"]()
    result = read.run()
    assert sorted(calls[start:]) == sorted(fields), calls[start:]
    assert read.done and read.cancellable.is_cancelled()
    assert not bus.is_closed()
    return read, result


registration = 0
try:
    assert name_call("RequestName") == 1
    registration = bus.register_object(path, properties, called, None, None)
    _read, result = fresh_read()
    assert all(state.status == "available" for state in result.values()), result
    for selected in fields:
        peer = next(field for field in fields if field != selected)
        for mode, status, code in (("denied", "restricted", "permission-denied"),
                ("missing", "unsupported", "unsupported"), ("malformed", "partial", "malformed"),
                ("oversized", "partial", "malformed")):
            _read, result = fresh_read()
            failed = result[fields[selected]]
            assert (failed.status, failed.value, failed.error_code) == (status, "unknown", code), result
            assert result[fields[peer]].status == "available", result
            assert "Private fixture detail" not in repr(result)
        for late_peer in (False, True):
            mode = "stall"
            started = time.monotonic()
            read, result = fresh_read()
            assert 9.5 <= time.monotonic() - started < 15
            failed = result[fields[selected]]
            assert (failed.status, failed.value, failed.error_code) == ("unavailable", "unknown", "timeout"), result
            assert result[fields[peer]].status == ("unavailable" if late_peer else "available"), result
            assert len(held) == (2 if late_peer else 1)
            saved = dict(result)
            for invocation, field in held:
                respond(invocation, field)
            held.clear()
            # A new read dispatches the old callbacks on the shared context too.
            mode = "normal"
            _next, current = fresh_read()
            assert all(state.status == "available" for state in current.values()), current
            assert read.value == saved, (read.value, saved)
    assert name_call("ReleaseName") == 1
    result = provider["HardwareRead"]().run()
    assert all(state.status == "unavailable" and state.error_code == "missing-provider"
               for state in result.values()), result
    print("Private-bus hardware reads: PASS (fixed properties, isolation, four real deadlines, late replies, shared bus)")
finally:
    for invocation, _field in held:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.NoReply", "Fixture cleanup")
    if registration:
        bus.unregister_object(registration)
