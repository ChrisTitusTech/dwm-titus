#!/usr/bin/python3
"""Qualify fixed AccountsService reads without accessing the host system bus."""

import os
import runpy
import sys
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="account_read_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
service = provider["ACCOUNTS_NAME"]
current = "/users/Current"
others = ("/users/Other", "/users/System")
mode = "normal"
calls, held, registrations = [], [], []
manager = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.Accounts">
<method name="ListCachedUsers"><arg type="ao" direction="out"/></method>
<method name="FindUserById"><arg type="x" direction="in"/><arg type="o" direction="out"/></method>
</interface></node>""").interfaces[0]
properties = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.DBus.Properties">
<method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
</interface></node>""").interfaces[0]


def name_call(method):
    args = GLib.Variant("(su)", (service, 0)) if method == "RequestName" else GLib.Variant("(s)", (service,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def called(_bus, _sender, path, interface, method, args, invocation):
    calls.append((path, interface, method, args.unpack()))
    if mode == "denied":
        invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
    elif method == "ListCachedUsers":
        invocation.return_value(GLib.Variant("(ao)", ([others[1], others[0], others[0]],)))
    elif method == "FindUserById":
        assert args.unpack() == (os.getuid(),)
        invocation.return_value(GLib.Variant("(o)", (current,)))
    elif mode == "stall" and path != current:
        held.append(invocation)
    else:
        account_interface, name = args.unpack()
        assert account_interface == provider["ACCOUNT_INTERFACE"]
        values = {"UserName": GLib.Variant("s", "fixture"),
            "RealName": GLib.Variant("s", "Fixture User"),
            "SystemAccount": GLib.Variant("b", path != others[0]),
            "LocalAccount": GLib.Variant("b", path != others[0])}
        assert name in values
        if mode == "missing" and path == others[0] and name == "UserName":
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownProperty", "fixture missing")
        else:
            value = GLib.Variant("u", 0) if mode == "malformed" and path == others[0] else values[name]
            invocation.return_value(GLib.Variant("(v)", (value,)))


try:
    assert name_call("RequestName") == 1
    registrations.append(bus.register_object(provider["ACCOUNTS_PATH"], manager, called, None, None))
    for path in (current, *others):
        registrations.append(bus.register_object(path, properties, called, None, None))
    result = provider["AccountRead"]().run()
    assert result.status == "available", result.errors
    assert [row.path for row in result.records] == [current, others[0]]
    assert [row.scope for row in result.records] == ["current", "other"]
    assert not result.records[1].local_account
    assert len(calls) == 14
    for mode in ("malformed", "missing"):
        result = provider["AccountRead"]().run()
        assert result.status == "partial"
        assert [row.path for row in result.records] == [current]
        assert {error.code for error in result.errors} == {"malformed"}
    mode = "denied"
    result = provider["AccountRead"]().run()
    assert result.status == "restricted", result.status
    assert {error.code for error in result.errors} == {"permission-denied"}
    mode = "stall"
    started = time.monotonic()
    reader = provider["AccountRead"]()
    result = reader.run()
    elapsed = time.monotonic() - started
    assert 2.5 <= elapsed < 8, elapsed
    assert result.status == "partial"
    assert [row.path for row in result.records] == [current]
    assert {error.code for error in result.errors} == {"timeout"}
    assert held and len(held) <= 8
    for invocation in held:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", "late fixture reply")
    mode = "normal"
    assert provider["AccountRead"]().run().status == "available"
    assert reader.value is result
    assert name_call("ReleaseName") == 1
    result = provider["AccountRead"]().run()
    assert result.status == "unavailable"
    assert {error.code for error in result.errors} == {"missing-provider"}
    assert all(call[2] in {"ListCachedUsers", "FindUserById", "Get"} for call in calls)
    print("Private-bus account reads: PASS (typed rows, filtering, denial, absence, deadline, late replies)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
