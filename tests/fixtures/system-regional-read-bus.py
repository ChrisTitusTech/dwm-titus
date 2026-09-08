#!/usr/bin/python3
"""Qualify regional reads on a private bus with no host-service access."""

import contextlib
import io
import os
import runpy
import signal
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
after_stalled = None
stalled_count = 2
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
    """Manage only the selected fixture-owned name on the private bus."""
    args = GLib.Variant("(su)", (name, 0)) if method == "RequestName" else GLib.Variant("(s)", (name,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def called(_bus, _sender, path, interface, method, args, invocation):
    """Serve typed read-only replies and retain deliberate stalled requests."""
    calls.append((path, interface, method, args.unpack()))
    if mode == "denied":
        invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
    elif mode == "stall":
        held.append(invocation)
        if len(held) == stalled_count and after_stalled is not None:
            after_stalled()
    elif method == "GetAll":
        invocation.return_value(GLib.Variant("(a{sv})", ({
            "Timezone": GLib.Variant("s", "UTC"), "CanNTP": GLib.Variant("b", True),
            "NTP": GLib.Variant("u", 1) if mode == "malformed" else GLib.Variant("b", False),
            "NTPSynchronized": GLib.Variant("b", True)},)))
    elif method == "Get":
        if path == "/org/freedesktop/timedate1":
            assert args.unpack() in (("org.freedesktop.timedate1", "CanNTP"),
                                     ("org.freedesktop.timedate1", "NTPSynchronized"))
            value = GLib.Variant("s", "invalid") if mode == "malformed" else GLib.Variant("b", True)
        else:
            value = GLib.Variant("as", ["LANG=C"])
        invocation.return_value(GLib.Variant("(v)", (value,)))
    else:
        invocation.return_value(GLib.Variant("(as)", (["UTC", "Etc/UTC"],)))


def interrupted_command(signum, command="ntp-sample"):
    """Stop the actual CLI while Gio is waiting, with a private forced-stop bound."""
    global after_stalled, stalled_count
    stalled_count = 1 if command == "time-status" else 2
    assert not held
    loop = GLib.MainLoop()
    result = {}
    timers = {"stop": 0, "deadline": 0}
    child = Gio.Subprocess.new(["/usr/bin/python3", sys.argv[1], command],
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)

    def terminate():
        timers["stop"] = 0
        child.send_signal(signum)
        return GLib.SOURCE_REMOVE

    def expired():
        timers["deadline"] = 0
        result["expired"] = True
        child.force_exit()
        return GLib.SOURCE_REMOVE

    def finished(process, reply, _data):
        try:
            result["output"] = process.communicate_utf8_finish(reply)
        finally:
            result["done"] = True
            loop.quit()

    def schedule_stop():
        timers["stop"] = GLib.timeout_add(100, terminate)

    after_stalled = schedule_stop
    child.communicate_utf8_async(None, None, finished, None)
    timers["deadline"] = GLib.timeout_add(4000, expired)
    try:
        loop.run()
        assert not result.get("expired", False), result
        assert child.get_if_exited() and child.get_exit_status() == 1, result
        assert result["output"][1:] == ("", ""), result
        assert len(held) == stalled_count
    finally:
        after_stalled = None
        for timer in timers.values():
            if timer:
                GLib.source_remove(timer)
        if not result.get("done", False):
            child.force_exit()
            child.wait(None)
        for invocation in held:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.NoReply", "Late fixture reply")
        held.clear()


def failure(kind, expected):
    """Require a scoped failure without publishing a successful value."""
    try:
        (provider["NtpRead"]() if kind == "ntp" else provider["RegionalRead"](kind)).run()
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
    assert provider["NtpRead"]().run() == provider["NtpSample"](True, True)
    assert [call[2:] for call in calls[-2:]] == [
        ("Get", ("org.freedesktop.timedate1", "CanNTP")),
        ("Get", ("org.freedesktop.timedate1", "NTPSynchronized"))]
    for arguments in (["ntp-sample"], ["time-status"], ["regional-choices", "timezone"],
                      ["regional-preview", "timezone-set", "Etc/UTC"],
                      ["regional-preview", "ntp-set", "enabled"],
                      ["regional-preview", "locale-set", "LANG=C"]):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            assert provider["main"](arguments) == 0, arguments
        assert output.getvalue().startswith(arguments[0] + "-protocol\t1\t0")
        assert output.getvalue().endswith("complete\t" + arguments[0] + "\n")
    mode = "malformed"
    failure("time-state", "malformed")
    failure("ntp", "malformed")
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["ntp-sample"]) == 1
    assert "error\tntp-sample\tmalformed\t" in output.getvalue()
    assert "\nsample\t" not in output.getvalue()
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["time-status"]) == 1
    assert "error\ttime-status\tmalformed\t" in output.getvalue()
    assert "\ntime\t" not in output.getvalue()
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["regional-preview", "ntp-set", "enabled"]) == 1
    assert "error\tregional\tmalformed\t" in output.getvalue()
    assert "\npreview\t" not in output.getvalue()
    mode = "denied"
    failure("locale-state", "permission-denied")
    failure("ntp", "permission-denied")
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["ntp-sample"]) == 1
    assert "error\tntp-sample\tpermission-denied\t" in output.getvalue()
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["time-status"]) == 1
    assert "error\ttime-status\tpermission-denied\t" in output.getvalue()
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
    mode = "stall"
    started = time.monotonic()
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["ntp-sample"]) == 1
    assert "error\tntp-sample\ttimeout\t" in output.getvalue()
    assert "\nsample\t" not in output.getvalue()
    elapsed = time.monotonic() - started
    assert 9.5 <= elapsed < 15, elapsed
    assert len(held) == 2
    for invocation in held:
        invocation.return_value(GLib.Variant("(v)", (GLib.Variant("b", False),)))
    held.clear()
    mode = "normal"
    assert provider["NtpRead"]().run() == provider["NtpSample"](True, True)
    mode = "stall"
    started = time.monotonic()
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["time-status"]) == 1
    assert "error\ttime-status\ttimeout\t" in output.getvalue()
    assert "\ntime\t" not in output.getvalue()
    assert 9.5 <= time.monotonic() - started < 15
    assert len(held) == 1
    held.pop().return_dbus_error("org.freedesktop.DBus.Error.NoReply", "Late fixture reply")
    mode = "normal"
    with contextlib.redirect_stdout(io.StringIO()) as output:
        assert provider["main"](["time-status"]) == 0
    assert output.getvalue() == "time-status-protocol\t1\t0\ntime\tUTC\tyes\tno\tyes\ncomplete\ttime-status\n"
    mode = "stall"
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        interrupted_command(signum)
        interrupted_command(signum, "time-status")
    assert all(call[2] in {"Get", "GetAll", "ListTimezones"} for call in calls)
    print("Private-bus regional reads: PASS (typed replies, readonly preflight, denial, absence, deadline, late reply, interruption)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
