#!/usr/bin/python3
"""Exercise the real native CLI and journal using exclusively private bus services."""

import os
import pathlib
import runpy
import subprocess
import sys
import tempfile
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider_path = str(pathlib.Path(sys.argv[1]).resolve())
p = runpy.run_path(provider_path, run_name="regional_owner_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
registrations = []
calls = []
errors = []
child = None
mode = "success"
zone, ntp, locale = "UTC", False, ["LANG=POSIX", "LC_TIME=POSIX"]
journal_path = None
fresh_reads = 0

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


def journal_state():
    """Read the fixture journal without sharing the child's descriptors or locks."""
    with p["open_journal_directory_chain"](str(journal_path)) as chain:
        return p["load_journal_state"](chain)


def called(_bus, _sender, _path, _interface, method, args, invocation):
    """Serve fixed test methods and surface callback assertions to the parent."""
    global zone, ntp, locale, fresh_reads
    try:
        calls.append(method)
        if method.startswith("Set"):
            assert args.unpack()[-1] is True
            assert invocation.get_message().get_flags() & Gio.DBusMessageFlags.ALLOW_INTERACTIVE_AUTHORIZATION
            state = journal_state()
            assert state.active.state == "authorizing" and state.handoff is None
            descriptor = os.open(journal_path / "active", os.O_RDWR | os.O_CLOEXEC)
            try:
                assert not p["_try_native_owner_lock"](descriptor)
            finally:
                os.close(descriptor)
            if mode == "denied":
                invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Fixture denial")
                return
            if method == "SetTimezone":
                zone = args.unpack()[0]
            elif method == "SetNTP":
                ntp = args.unpack()[0]
            else:
                locale = args.unpack()[0]
                assert locale == ["LANG=C", "LC_TIME=POSIX"]
            if mode == "ambiguous":
                invocation.return_dbus_error("org.freedesktop.DBus.Error.NoReply", "Fixture lost reply")
                return
            if mode == "lost-output":
                child.stdout.close()
            invocation.return_value(GLib.Variant("()", ()))
        elif method == "GetAll":
            if mode == "ambiguous" and "SetTimezone" in calls:
                state = journal_state()
                assert state.active is None
                assert state.terminals[state.handoff.slot].state == "interrupted"
                descriptor = os.open(journal_path / "active", os.O_RDWR | os.O_CLOEXEC)
                try:
                    assert p["_try_native_owner_lock"](descriptor)
                    p["_unlock_native_owner"](descriptor)
                finally:
                    os.close(descriptor)
                fresh_reads += 1
            invocation.return_value(GLib.Variant("(a{sv})", ({
                "Timezone": GLib.Variant("s", zone), "CanNTP": GLib.Variant("b", True),
                "NTP": GLib.Variant("b", ntp), "NTPSynchronized": GLib.Variant("b", True)},)))
        elif method == "Get":
            invocation.return_value(GLib.Variant("(v)", (GLib.Variant("as", locale),)))
        else:
            assert method == "ListTimezones"
            invocation.return_value(GLib.Variant("(as)", (["UTC", "Etc/UTC"],)))
    except Exception as error:
        errors.append(error)
        invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", "Fixture assertion failed")


def command(arguments, environment):
    """Bound each real CLI child while keeping the private service loop responsive."""
    global child
    child = subprocess.Popen(["/usr/bin/python3", provider_path, *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    loop = GLib.MainLoop()
    deadline = time.monotonic() + 10
    expired = []

    def poll():
        if child.poll() is not None:
            loop.quit()
            return False
        if time.monotonic() >= deadline:
            expired.append(True)
            loop.quit()
            return False
        return True

    source = GLib.timeout_add(10, poll)
    try:
        loop.run()
        assert not expired, "Fixture CLI exceeded ten seconds"
        output = b"" if child.stdout.closed else child.stdout.read()
        diagnostic = child.stderr.read()
        assert not errors, errors
        return child.returncode, output.decode(), diagnostic.decode()
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2)
        if GLib.MainContext.default().find_source_by_id(source) is not None:
            GLib.source_remove(source)
        child.stdout.close()
        child.stderr.close()
        child = None


try:
    for name in ("org.freedesktop.timedate1", "org.freedesktop.locale1"):
        reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "RequestName", GLib.Variant("(su)", (name, 0)), GLib.VariantType.new("(u)"),
            Gio.DBusCallFlags.NONE, 3000, None)
        assert reply.unpack() == (1,)
    for path, interface in (("/org/freedesktop/timedate1", timedate),
                             ("/org/freedesktop/timedate1", properties),
                             ("/org/freedesktop/locale1", localed),
                             ("/org/freedesktop/locale1", properties)):
        registrations.append(bus.register_object(path, interface, called, None, None))
    for mode, action, argument in (("success", "timezone-set", "Etc/UTC"),
            ("success", "ntp-set", "enabled"), ("success", "locale-set", "LANG=C"),
            ("denied", "timezone-set", "Etc/UTC"), ("stale", "timezone-set", "Etc/UTC"),
            ("ambiguous", "timezone-set", "Etc/UTC"), ("lost-output", "timezone-set", "Etc/UTC")):
        with tempfile.TemporaryDirectory() as directory:
            journal_path = pathlib.Path(directory) / "state/dwm-titus/system-management"
            environment = dict(os.environ, XDG_STATE_HOME=str(pathlib.Path(directory) / "state"))
            zone, ntp, locale = "UTC", False, ["LANG=POSIX", "LC_TIME=POSIX"]
            calls.clear()
            code, preview, diagnostic = command(["regional-preview", action, argument], environment)
            assert code == 0 and not diagnostic, (code, preview, diagnostic)
            state = p["parse_locale_configuration"](locale) if action == "locale-set" else p["RegionalTimeState"](zone, True, ntp, True)
            generation = p["make_regional_preview"](action, argument, state,
                ["C", "POSIX"] if action == "locale-set" else ["UTC", "Etc/UTC"]).generation
            assert generation in preview
            code, output, diagnostic = command([action, argument, "0" * 64 if mode == "stale" else generation], environment)
            state = journal_state()
            assert state.active is None
            if mode == "stale":
                assert state.handoff is None and not any(call.startswith("Set") for call in calls)
                assert code == 1 and "no regional mutation was dispatched" in output
                continue
            terminal = state.terminals[state.handoff.slot]
            expected = "permission-denied" if mode == "denied" else "interrupted" if mode == "ambiguous" else "succeeded"
            assert terminal.state == expected, (mode, terminal, output, diagnostic)
            assert code == (0 if mode == "success" else 1), (mode, code, output, diagnostic)
            assert terminal.generation is None and terminal.boot_id is None
            assert len([call for call in calls if call.startswith("Set")]) == 1
            if mode == "lost-output":
                assert diagnostic == "regional result could not be confirmed; refresh state and observe the existing operation\n"
                assert calls[calls.index("SetTimezone") + 1:] == ["GetAll"]
            else:
                assert not diagnostic and output.endswith("complete\toperation\n")
            before = list(calls)
            code, replay, diagnostic = command(["watch-operation", terminal.operation_id], environment)
            assert code == 0 and not diagnostic and replay.endswith("complete\toperation\n")
            assert "\t" + expected + "\t" in replay and calls == before
            assert command(["ack-operation", terminal.operation_id], environment) == (0, "", "")
            assert journal_state().handoff is None and calls == before
    assert fresh_reads == 1, fresh_reads
    print("Private-bus regional owner: PASS (actual CLI, durable lease and handoff, denial, stale confirmation, ambiguous fresh read, lost output, replay, acknowledgment)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
