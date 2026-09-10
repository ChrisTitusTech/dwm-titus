#!/usr/bin/python3
"""Interrupt actual native CLI children against private services and journals."""

import os
import runpy
import signal
import sys

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="regional_interruption_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
time_name = "org.freedesktop.timedate1"
locale_name = "org.freedesktop.locale1"
interfaces = Gio.DBusNodeInfo.new_for_xml("""
<node>
<interface name="org.freedesktop.DBus.Properties">
<method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
</interface>
<interface name="org.freedesktop.timedate1">
<method name="ListTimezones"><arg type="as" direction="out"/></method>
<method name="SetTimezone"><arg type="s" direction="in"/><arg type="b" direction="in"/></method>
<method name="SetNTP"><arg type="b" direction="in"/><arg type="b" direction="in"/></method>
</interface>
<interface name="org.freedesktop.locale1">
<method name="SetLocale"><arg type="as" direction="in"/><arg type="b" direction="in"/></method>
</interface>
</node>""").interfaces
registrations = []
current = None


def called(_bus, _sender, _path, interface, method, args, invocation):
    case = current
    try:
        case["calls"].append(method)
        if method == "GetAll":
            assert args.unpack() == (time_name,)
            reply = GLib.Variant("(a{sv})", ({
                "Timezone": GLib.Variant("s", case["zone"]),
                "CanNTP": GLib.Variant("b", True),
                "NTP": GLib.Variant("b", case["ntp"]),
                "NTPSynchronized": GLib.Variant("b", True)},))
        elif method == "Get":
            assert args.unpack() == (locale_name, "Locale")
            reply = GLib.Variant("(v)", (GLib.Variant("as", case["locale"]),))
        elif method == "ListTimezones":
            reply = GLib.Variant("(as)", (["UTC", "Etc/UTC"],))
        else:
            assert method == case["method"] and interface in (time_name, locale_name)
            assert args.unpack()[-1] is True
            assert invocation.get_message().get_flags() & Gio.DBusMessageFlags.ALLOW_INTERACTIVE_AUTHORIZATION
            if method == "SetTimezone":
                assert args.unpack()[0] == "Etc/UTC"
                case["zone"] = "Etc/UTC"
            elif method == "SetNTP":
                assert args.unpack()[0] is True
                case["ntp"] = True
            else:
                assert args.unpack()[0] == ["LANG=C"]
                case["locale"] = ["LANG=C"]
            reply = GLib.Variant("()", ())
        if ((case["stage"] == "before" and len(case["calls"]) == 1)
                or method.startswith("Set")):
            case["held"].append((invocation, reply))
            case["stop_source"] = GLib.timeout_add(100, case["stop"])
        else:
            invocation.return_value(reply)
    except Exception as error:
        # Callback exceptions must fail the fixture, not disappear in GLib.
        case["callback_error"] = error
        invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", "Fixture assertion failed")
        case["child"].force_exit()


def journal_state():
    with provider["open_journal_directory"]() as chain, provider["retain_writable_journal"](chain) as journal:
        with provider["lock_writable_journal"](journal):
            state = provider["load_writable_journal_state"](journal)
            assert provider["_try_native_owner_lock"](journal.descriptor("active"))
            provider["_unlock_native_owner"](journal.descriptor("active"))
            return state


def check(action, argument, method, signum, stage):
    global current
    case = {"calls": [], "held": [], "zone": "UTC", "ntp": False,
            "locale": ["LANG=POSIX"], "method": method, "stage": stage,
            "stop_source": 0, "deadline_source": 0, "done": False}
    current = case
    state_home = os.path.join(os.environ["DWM_TEST_WORKSPACE"], f"regional-{action}-{signum}-{stage}")
    os.mkdir(state_home, 0o700)
    os.environ["XDG_STATE_HOME"] = state_home
    state = (provider["parse_locale_configuration"](case["locale"]) if action == "locale-set"
             else provider["RegionalTimeState"]("UTC", True, False, True))
    choices = ["C", "POSIX"] if action == "locale-set" else ["UTC", "Etc/UTC"]
    generation = provider["make_regional_preview"](action, argument, state, choices).generation
    loop = GLib.MainLoop()

    def stop():
        case["stop_source"] = 0
        case["child"].send_signal(signum)
        return GLib.SOURCE_REMOVE

    def expired():
        case["deadline_source"] = 0
        case["expired"] = True
        case["child"].force_exit()
        return GLib.SOURCE_REMOVE

    def finished(process, reply, _data):
        try:
            case["output"] = process.communicate_utf8_finish(reply)
        except Exception as error:
            case["callback_error"] = error
        finally:
            case["done"] = True
            loop.quit()

    case["stop"] = stop
    child = Gio.Subprocess.new(["/usr/bin/python3", sys.argv[1], action, argument, generation],
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
    case["child"] = child
    child.communicate_utf8_async(None, None, finished, None)
    case["deadline_source"] = GLib.timeout_add(4000, expired)
    try:
        loop.run()
        assert not case.get("expired", False), (action, signum, stage, "forced stop")
        assert "callback_error" not in case, case.get("callback_error")
        assert child.get_if_exited() and child.get_exit_status() == 1
        _, output, diagnostic = case["output"]
        assert diagnostic == "", diagnostic
        assert output.endswith("complete\toperation\n"), output
        assert "\nerror\tregional\tinterrupted\t" in output, output
        durable = journal_state()
        assert durable.active is None
        if stage == "before":
            assert case["calls"] == ["Get" if action == "locale-set" else "GetAll"]
            assert durable.handoff is None and all(item is None for item in durable.terminals)
            assert "no regional mutation was dispatched" in output
        else:
            expected = (["Get", "Get", method] if action == "locale-set" else
                        ["GetAll", "ListTimezones", "GetAll", method] if action == "timezone-set" else
                        ["GetAll", "GetAll", method])
            assert case["calls"] == expected, case["calls"]  # No retry or post-stop service read.
            assert durable.handoff is not None
            terminal = durable.terminals[durable.handoff.slot]
            assert terminal.operation_id == durable.handoff.operation_id
            assert (terminal.action_id, terminal.state, terminal.error_code) == (action, "interrupted", "interrupted")
            assert "may still complete" in terminal.detail
            operations = [line.split("\t") for line in output.splitlines() if line.startswith("operation\t")]
            assert [row[4] for row in operations] == ["pending", "authorizing", "interrupted"]
            assert all(row[6] == "no" for row in operations)  # Never claim cancellation is available.
        for invocation, reply in case["held"]:
            invocation.return_value(reply)
        case["held"].clear()
        assert journal_state() == durable  # A late service reply cannot change the terminal.
        print(f"Regional signal case: PASS ({action}/{stage}/{signum})")
    finally:
        for key in ("stop_source", "deadline_source"):
            if case[key]:
                GLib.source_remove(case[key])
        if not case["done"]:
            child.force_exit()
            child.wait(None)
        for invocation, reply in case["held"]:
            invocation.return_value(reply)


try:
    for name in (time_name, locale_name):
        result = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "RequestName", GLib.Variant("(su)", (name, 0)), GLib.VariantType.new("(u)"),
            Gio.DBusCallFlags.NONE, 3000, None)
        assert result.unpack()[0] == 1
    for path, info in (("/org/freedesktop/timedate1", interfaces[0]),
                       ("/org/freedesktop/timedate1", interfaces[1]),
                       ("/org/freedesktop/locale1", interfaces[0]),
                       ("/org/freedesktop/locale1", interfaces[2])):
        registrations.append(bus.register_object(path, info, called, None, None))
    for action, argument, method in (("timezone-set", "Etc/UTC", "SetTimezone"),
                                     ("ntp-set", "enabled", "SetNTP"),
                                     ("locale-set", "LANG=C", "SetLocale")):
        for stage in ("before", "after"):
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                check(action, argument, method, signum, stage)
    print("Private-bus regional interruption: PASS (18 actual child cases)")
finally:
    for registration in registrations:
        bus.unregister_object(registration)
