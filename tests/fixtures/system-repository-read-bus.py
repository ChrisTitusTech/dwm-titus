#!/usr/bin/python3
"""Exercise repository discovery on a private bus, never the host PackageKit."""

import os
import runpy
import sys
import time

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib

provider = runpy.run_path(sys.argv[1], run_name="repository_read_fixture")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
service = provider["PACKAGEKIT_NAME"]
interface = provider["TRANSACTION_INTERFACE"]
mode = "normal"
registrations, calls, held = [], [], []
manager = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.PackageKit">
<method name="CreateTransaction"><arg type="o" direction="out"/></method>
</interface></node>""").interfaces[0]
transaction = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.PackageKit.Transaction">
<method name="SetHints"><arg type="as" direction="in"/></method>
<method name="GetRepoList"><arg type="t" direction="in"/></method>
<method name="Cancel"/>
</interface></node>""").interfaces[0]


def name_call(method):
    args = GLib.Variant("(su)", (service, 0)) if method == "RequestName" else GLib.Variant("(s)", (service,))
    return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, args, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def emit(path, member, signature, values):
    bus.emit_signal(None, path, interface, member, GLib.Variant(signature, values))


def called(_bus, _sender, path, _interface, method, args, invocation):
    calls.append((path, method))
    if method == "CreateTransaction":
        path = f"/{len(registrations)}_fixture"
        registrations.append(bus.register_object(path, transaction, called, None, None))
        invocation.return_value(GLib.Variant("(o)", (path,)))
    elif method == "SetHints":
        assert args.unpack() == (["background=true", "interactive=false", "cache-age=4294967295"],)
        invocation.return_value(None)
    elif method == "Cancel":
        invocation.return_value(None)
    else:
        assert method == "GetRepoList" and args.unpack() == (2,)
        if mode in ("denied", "unsupported"):
            error = "RefusedByPolicy" if mode == "denied" else "NotSupported"
            invocation.return_dbus_error(interface + "." + error, "fixture")
            return
        if mode != "empty":
            emit(path, "RepoDetail", "(ssb)", ("z-disabled", "Disabled", False))
            emit(path, "RepoDetail", "(ssb)", ("a-enabled", "Enabled", True))
        if mode == "duplicate":
            emit(path, "RepoDetail", "(ssb)", ("a-enabled", "Duplicate", True))
        if mode == "error":
            emit(path, "ErrorCode", "(us)", (18, "fixture repository error"))
        if mode == "stall":
            held.append((path, invocation))
            return
        emit(path, "Finished", "(uu)", (2 if mode == "error" else 1, 1))
        if mode == "lost-owner":
            assert name_call("ReleaseName") == 1
        invocation.return_value(None)


try:
    assert name_call("RequestName") == 1
    registrations.append(bus.register_object(provider["PACKAGEKIT_PATH"], manager, called, None, None))
    for mode in ("normal", "empty", "denied", "unsupported", "duplicate", "error", "lost-owner"):
        expected = {"denied": "permission-denied", "unsupported": "unsupported",
                    "duplicate": "malformed", "error": "repository", "lost-owner": "missing-provider"}.get(mode)
        current = provider["RepositoryRead"]()
        try:
            result = current.run()
        except provider["SnapshotFailure"] as error:
            assert expected == error.code, (mode, error.code, current.stage, calls)
        else:
            assert expected is None, mode
            assert len(result) == (0 if mode == "empty" else 2), result
            if result:
                assert [row.enabled for row in result] == [True, False]
        if mode == "lost-owner":
            assert name_call("RequestName") == 1
    mode = "stall"
    reader = provider["RepositoryRead"]()
    started = time.monotonic()
    try:
        reader.run()
    except provider["SnapshotFailure"] as error:
        assert error.code == "timeout", error.code
    else:
        raise AssertionError("stalled repository read succeeded")
    elapsed = time.monotonic() - started
    assert 29 <= elapsed < 36, elapsed
    assert reader.value is None and reader.rows == {} and len(held) == 1
    path, invocation = held.pop()
    invocation.return_value(None)
    emit(path, "Finished", "(uu)", (1, 30))
    mode = "normal"
    assert len(provider["RepositoryRead"]().run()) == 2
    assert (path, "Cancel") in calls
    assert reader.value is None and reader.failure.code == "timeout"
    assert name_call("ReleaseName") == 1
    try:
        provider["RepositoryRead"]().run()
    except provider["SnapshotFailure"] as error:
        assert error.code == "missing-provider", error.code
    else:
        raise AssertionError("absent PackageKit succeeded")
    assert set(method for _path, method in calls) == {"CreateTransaction", "SetHints", "GetRepoList", "Cancel"}
    print("Private-bus repository reads: PASS (fixed filter, denial, absence, bounds, owner loss, 30-second deadline, late replies)")
finally:
    for registration in reversed(registrations):
        bus.unregister_object(registration)
