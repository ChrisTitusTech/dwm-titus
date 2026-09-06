#!/usr/bin/python3
"""Fixed regional writes on a private bus; never connect to host services."""

import os
import runpy
import sys
import time
from unittest import mock

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="regional_mutation_fixture")
client_class = provider["RegionalMutation"]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
mode = "normal"
zone = "UTC"
ntp = False
locale = ["LANG=C", "LANGUAGE=C", "LC_TIME=C"]
calls = []
held = []
registrations = []
events = []
properties = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.DBus.Properties">
<method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
</interface></node>""").interfaces[0]
timedate = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.timedate1">
<method name="ListTimezones"><arg type="as" direction="out"/></method>
<method name="SetTimezone"><arg type="s" direction="in"/><arg type="b" direction="in"/></method>
<method name="SetNTP"><arg type="b" direction="in"/><arg type="b" direction="in"/></method>
</interface></node>""").interfaces[0]
localed = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.locale1">
<method name="SetLocale"><arg type="as" direction="in"/><arg type="b" direction="in"/></method>
</interface></node>""").interfaces[0]


def name_call(method, name):
    args = GLib.Variant("(su)", (name, 0)) if method == "RequestName" else GLib.Variant("(s)", (name,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def notify(path, interface, values):
    bus.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                    GLib.Variant("(sa{sv}as)", (interface, values, [])))


def called(_bus, _sender, path, interface, method, args, invocation):
    global zone, ntp, locale
    calls.append((path, interface, method, args.unpack()))
    if method.startswith("Set"):
        assert args.unpack()[-1] is True
        assert invocation.get_message().get_flags() & Gio.DBusMessageFlags.ALLOW_INTERACTIVE_AUTHORIZATION
        if mode == "denied":
            invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
            return
        if mode == "bad-arguments":
            invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", "fixture rejection")
            return
        if mode == "owner-lost":
            assert name_call("ReleaseName", interface) == 1
            held.append(invocation)
            return
        if method == "SetTimezone":
            zone = args.unpack()[0]
            values = {"Timezone": GLib.Variant("s", zone)}
        elif method == "SetNTP":
            ntp = args.unpack()[0]
            values = {"NTP": GLib.Variant("b", ntp)}
        else:
            locale = args.unpack()[0]
            values = {"Locale": GLib.Variant("as", locale)}
        if mode == "conflict":
            notify(path, interface, {"Timezone": GLib.Variant("s", "Europe/London")})
        notify(path, interface, values)
        if mode == "stall":
            held.append(invocation)
        else:
            invocation.return_value(GLib.Variant("()", ()))
    elif method == "GetAll":
        invocation.return_value(GLib.Variant("(a{sv})", ({
            "Timezone": GLib.Variant("s", zone), "CanNTP": GLib.Variant("b", True),
            "NTP": GLib.Variant("b", ntp), "NTPSynchronized": GLib.Variant("b", True)},)))
    elif method == "Get":
        invocation.return_value(GLib.Variant("(v)", (GLib.Variant("as", locale),)))
    else:
        invocation.return_value(GLib.Variant("(as)", (["UTC", "Etc/UTC"],)))


def client(action="timezone-set", argument="Etc/UTC"):
    state = (provider["parse_locale_configuration"](locale) if action == "locale-set" else
             provider["RegionalTimeState"](zone, True, ntp, True))
    choices = ["C", "en_US.utf8"] if action == "locale-set" else ["UTC", "Etc/UTC"]
    preview = provider["make_regional_preview"](action, argument, state, choices)
    return client_class(action, argument, preview.generation,
        lambda current: events.append(("authorizing", current)), lambda: events.append(("running", None)))


def fail(operation, code):
    try:
        operation.run()
    except provider["SnapshotFailure"] as error:
        assert error.code == code, (error.code, code)
    else:
        raise AssertionError("regional failure reported success")


try:
    for name in ("org.freedesktop.timedate1", "org.freedesktop.locale1"):
        assert name_call("RequestName", name) == 1
    for path, info in (("/org/freedesktop/timedate1", timedate),
                       ("/org/freedesktop/timedate1", properties),
                       ("/org/freedesktop/locale1", properties),
                       ("/org/freedesktop/locale1", localed)):
        registrations.append(bus.register_object(path, info, called, None, None))
    with mock.patch.dict(client_class.run.__globals__,
                         read_fedora_identity=lambda: {"ID": "fedora"},
                         read_locale_choices=lambda: ("C", "en_US.utf8")):
        assert client().run().timezone == "Etc/UTC"
        assert client("ntp-set", "enabled").run().ntp_enabled
        assert client("locale-set", "LANG=en_US.utf8").run().assignments == (
            "LANG=en_US.utf8", "LANGUAGE=C", "LC_TIME=C")
        assert [event[0] for event in events] == ["authorizing", "running"] * 3
        stale = client()
        zone = "UTC"
        before = len([call for call in calls if call[2].startswith("Set")])
        fail(stale, "conflict")
        assert len([call for call in calls if call[2].startswith("Set")]) == before
        for scenario, code in (("denied", "permission-denied"), ("bad-arguments", "malformed"),
                               ("conflict", "conflict"), ("owner-lost", "interrupted")):
            mode = scenario
            operation = client()
            fail(operation, code)
            assert operation.sent
            assert operation.acknowledged is (scenario == "conflict")
        assert name_call("RequestName", "org.freedesktop.timedate1") == 1
        for invocation in held:
            invocation.return_value(GLib.Variant("()", ()))
        held.clear()
        mode = "stall"
        operation = client("timezone-set", "UTC")
        started = time.monotonic()
        fail(operation, "timeout")
        elapsed = time.monotonic() - started
        assert 59.5 <= elapsed < 70, elapsed
        assert operation.sent and not operation.acknowledged and operation.value is None
        assert zone == "UTC"  # Timeout does not imply the platform did nothing.
        assert len(held) == 1
        held.pop().return_value(GLib.Variant("()", ()))
        mode = "normal"
        assert client().run().timezone == "Etc/UTC"
        assert operation.value is None and operation.failure.code == "timeout"
        assert all(call[2] in {"Get", "GetAll", "ListTimezones", "SetTimezone", "SetNTP", "SetLocale"} for call in calls)
        print("Private-bus regional mutations: PASS (fixed calls, confirmation, signals, denial, owner loss, real 60-second timeout, late reply)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
