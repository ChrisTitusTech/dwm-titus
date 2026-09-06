#!/usr/bin/python3
"""Qualify regional reads on a private bus with no host-service access."""

import os
import runpy
import sys
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="regional_read_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
mode = "normal"
calls = []
held = []
registrations = []
properties = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.DBus.Properties">
<method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
</interface></node>""").interfaces[0]
timedate = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.timedate1">
<method name="ListTimezones"><arg type="as" direction="out"/></method>
</interface></node>""").interfaces[0]


def name_call(method, name):
    args = GLib.Variant("(su)", (name, 0)) if method == "RequestName" else GLib.Variant("(s)", (name,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def called(_bus, _sender, path, interface, method, args, invocation):
    calls.append((path, interface, method, args.unpack()))
    if mode == "denied":
        invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
    elif mode == "stall":
        held.append(invocation)
    elif method == "GetAll":
        invocation.return_value(GLib.Variant("(a{sv})", ({
            "Timezone": GLib.Variant("s", "UTC"), "CanNTP": GLib.Variant("b", True),
            "NTP": GLib.Variant("u", 1) if mode == "malformed" else GLib.Variant("b", False),
            "NTPSynchronized": GLib.Variant("b", True)},)))
    elif method == "Get":
        invocation.return_value(GLib.Variant("(v)", (GLib.Variant("as", ["LANG=C"]),)))
    else:
        invocation.return_value(GLib.Variant("(as)", (["UTC", "Etc/UTC"],)))


def failure(kind, expected):
    try:
        provider["RegionalRead"](kind).run()
    except provider["SnapshotFailure"] as error:
        assert error.code == expected, (error.code, expected)
    else:
        raise AssertionError("regional failure reported success")


try:
    for name in ("org.freedesktop.timedate1", "org.freedesktop.locale1"):
        assert name_call("RequestName", name) == 1
    for path, info in (("/org/freedesktop/timedate1", timedate),
                       ("/org/freedesktop/timedate1", properties),
                       ("/org/freedesktop/locale1", properties)):
        registrations.append(bus.register_object(path, info, called, None, None))
    assert provider["RegionalRead"]("time-state").run().timezone == "UTC"
    assert provider["RegionalRead"]("locale-state").run().assignments == ("LANG=C",)
    assert provider["RegionalRead"]("timezone-choices").run() == ("UTC", "Etc/UTC")
    assert [call[2:] for call in calls] == [
        ("GetAll", ("org.freedesktop.timedate1",)),
        ("Get", ("org.freedesktop.locale1", "Locale")), ("ListTimezones", ())]
    mode = "malformed"
    failure("time-state", "malformed")
    mode = "denied"
    failure("locale-state", "permission-denied")
    mode = "normal"
    assert name_call("ReleaseName", "org.freedesktop.locale1") == 1
    failure("locale-state", "missing-provider")
    mode = "stall"
    started = time.monotonic()
    failure("timezone-choices", "timeout")
    elapsed = time.monotonic() - started
    assert 9.5 <= elapsed < 15, elapsed
    assert len(held) == 1
    held.pop().return_value(GLib.Variant("(as)", (["Late/Reply"],)))
    mode = "normal"
    assert provider["RegionalRead"]("timezone-choices").run() == ("UTC", "Etc/UTC")
    assert all(call[2] in {"Get", "GetAll", "ListTimezones"} for call in calls)
    print("Private-bus regional reads: PASS (typed replies, denial, absence, deadline, late reply)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
