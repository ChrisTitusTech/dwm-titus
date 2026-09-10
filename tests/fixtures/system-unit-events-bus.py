#!/usr/bin/python3
"""Exercise private systemd subscriptions without calling the host system bus."""

import fcntl
import os
import selectors
import signal
import subprocess
import sys
import time

from gi.repository import Gio, GLib

NAME = "org.freedesktop.systemd1"
PATH = "/org/freedesktop/systemd1"
MANAGER = NAME + ".Manager"
UNIT = NAME + ".Unit"
PROPERTIES = "org.freedesktop.DBus.Properties"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
context = GLib.MainContext.default()
environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=os.environ["DBUS_SESSION_BUS_ADDRESS"])
paths = {"cups.service": PATH + "/unit/CanonicalPrinter", "cups.socket": PATH + "/unit/SocketAlias",
         "firewalld.service": PATH + "/unit/FirewallAlias"}
calls, processes, held = [], [], []
subscribers = set()
mode = "normal"
manager_xml = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.freedesktop.systemd1.Manager">
<method name="Subscribe"/>
<method name="GetUnit"><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
</interface></node>
""").interfaces[0]


def pump():
    """Dispatch a bounded batch of local fixture service callbacks."""
    for _ in range(64):
        if not context.pending():
            break
        context.iteration(False)


def line(process, seconds=3):
    """Serve fixture calls while collecting exactly one bounded watcher line."""
    result = b""
    deadline = time.monotonic() + seconds
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while time.monotonic() < deadline and len(result) < 128:
            pump()
            if selector.select(min(0.005, max(0, deadline - time.monotonic()))):
                value = os.read(process.stdout.fileno(), 1)
                if not value:
                    break
                result += value
                if value == b"\n":
                    break
    return result


def wait_for(predicate, seconds=3):
    """Bound fixture progress while continuing to answer private-bus calls."""
    deadline = time.monotonic() + seconds
    while not predicate() and time.monotonic() < deadline:
        pump()
        time.sleep(0.005)
    assert predicate(), "Fixture progress deadline expired"


def emit(member, signature, values, *, path=PATH, interface=MANAGER, connection=bus, destination=None):
    """Send controlled broadcast or directly addressed fixture notifications."""
    connection.emit_signal(destination, path, interface, member, GLib.Variant(signature, values))
    connection.flush_sync(None)


def property_event(path, *, connection=bus, destination=None, malformed=False):
    """Emit only typed unit state unless explicitly testing a malformed peer."""
    values = (UNIT, {"ActiveState": GLib.Variant("s", "active")}, [])
    signature = "(sa{sv}as)"
    if malformed:
        signature, values = "(s)", ("x" * 70000,)
    emit("PropertiesChanged", signature, values, path=path, interface=PROPERTIES,
         connection=connection, destination=destination)


def called(_connection, sender, _path, _interface, method, args, invocation):
    """Implement exactly Subscribe and fixed, non-loading GetUnit reads."""
    calls.append((sender, method, args.unpack()))
    if mode == "denied":
        invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "fixture denial")
    elif mode == "stall" or mode == "stall-unit" and method == "GetUnit":
        held.append(invocation)
    elif method == "Subscribe":
        assert sender not in subscribers, "Duplicate Subscribe on one sender"
        subscribers.add(sender)
        invocation.return_value(GLib.Variant("()", ()))
    else:
        assert method == "GetUnit" and sender in subscribers
        name = args.unpack()[0]
        assert name in ("cups.service", "cups.socket", "firewalld.service")
        if mode == "burst":
            emit("UnitNew", "(so)", ("unrelated.service", PATH + "/unit/Unrelated"))
        if mode == "malformed":
            invocation.return_value(GLib.Variant("(o)", ("/wrong_scope",)))
        elif name not in paths:
            invocation.return_dbus_error("org.freedesktop.systemd1.NoSuchUnit", "not loaded")
        else:
            invocation.return_value(GLib.Variant("(o)", (paths[name],)))


def owner_changed(_connection, _sender, _path, _interface, _member, args, _data):
    """Mirror systemd's sender-owned subscription cleanup on disconnect."""
    name, old, new = args.unpack()
    if old and not new:
        subscribers.discard(name)


def launch(kind="printers", *, output=None):
    """Launch a real fixed CLI command on the disposable bus."""
    process = subprocess.Popen([sys.argv[1], "watch-units", kind], env=environment,
        stdout=subprocess.PIPE if output is None else output, stderr=subprocess.PIPE, bufsize=0)
    processes.append(process)
    return process


def stop(process, signum=signal.SIGTERM, expected=0):
    """Require bounded shutdown and no unexpected diagnostics."""
    process.send_signal(signum)
    wait_for(lambda: process.poll() is not None)
    assert process.returncode == expected, (process.returncode, process.stderr.read())
    if expected == 0:
        assert process.stderr.read() == b""


registration = bus.register_object(PATH, manager_xml, called, None, None)
owner_subscription = bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
    "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE, owner_changed, None)
outsider = Gio.DBusConnection.new_for_address_sync(os.environ["DBUS_SESSION_BUS_ADDRESS"],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
try:
    reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        "RequestName", GLib.Variant("(su)", (NAME, 0)), GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 3000, None)
    assert reply.unpack() == (1,)
    process = launch()
    assert line(process) == b"units-event\tready\n"
    assert [call[1] for call in calls] == ["Subscribe", "GetUnit", "GetUnit"], calls
    first_sender = calls[0][0]
    assert first_sender != bus.get_unique_name()
    before = len(calls)
    assert line(process, 0.2) == b"" and len(calls) == before
    property_event(paths["cups.service"])
    assert line(process) == b"units-event\tchanged\n"
    property_event(paths["cups.service"], connection=outsider, destination=first_sender, malformed=True)
    property_event(PATH + "/unit/Unrelated")
    assert line(process, 0.2) == b"" and process.poll() is None
    emit("UnitNew", "(so)", ("unrelated.service", PATH + "/unit/Unrelated"))
    assert line(process, 0.2) == b""
    assert len(calls) == before + 2
    # A requested alias can resolve to an unrelated-looking canonical name.
    paths["cups.service"] = PATH + "/unit/NewCanonical"
    emit("UnitNew", "(so)", ("canonical.service", paths["cups.service"]))
    assert line(process) == b"units-event\tchanged\n"
    property_event(paths["cups.service"])
    assert line(process) == b"units-event\tchanged\n"
    old_path = paths.pop("cups.socket")
    emit("UnitRemoved", "(so)", ("canonical.socket", old_path))
    assert line(process) == b"units-event\tchanged\n"
    assert line(process) == b"units-event\tchanged\n"
    assert line(process, 0.1) == b""
    # Another monitor's subscription survives the first private connection.
    second = launch("security")
    assert line(second) == b"units-event\tready\n"
    second_sender = next(sender for sender in subscribers if sender != first_sender)
    stop(process)
    wait_for(lambda: first_sender not in subscribers)
    assert second_sender in subscribers
    property_event(paths["firewalld.service"])
    assert line(second) == b"units-event\tchanged\n"
    stop(second, signal.SIGKILL, -signal.SIGKILL)
    wait_for(lambda: not subscribers)
    # Initially unloaded fixed names remain dormant until a canonical arrival.
    paths.clear()
    process = launch()
    assert line(process) == b"units-event\tready\n"
    paths["cups.socket"] = PATH + "/unit/LaterSocket"
    emit("UnitNew", "(so)", ("other-name.socket", paths["cups.socket"]))
    assert line(process) == b"units-event\tchanged\n"
    stop(process, signal.SIGINT)
    wait_for(lambda: not subscribers)
    for signum in (signal.SIGHUP, signal.SIGTERM):
        process = launch("security")
        assert line(process) == b"units-event\tready\n"
        stop(process, signum)
        wait_for(lambda: not subscribers)
    for mode in ("denied", "malformed", "burst"):
        before = len(calls)
        process = launch()
        assert line(process) == b""
        wait_for(lambda: process.poll() is not None)
        assert process.returncode == 1 and b"reload status explicitly" in process.stderr.read()
        assert len(calls) - before <= 5, calls[before:]
        wait_for(lambda: not subscribers)
    mode = "stall"
    process = launch()
    started = time.monotonic()
    assert line(process, 12) == b""
    wait_for(lambda: process.poll() is not None)
    assert 9 <= time.monotonic() - started < 12
    assert process.returncode == 1 and b"reload status explicitly" in process.stderr.read()
    assert len(held) == 1
    held.pop().return_dbus_error("org.freedesktop.DBus.Error.NoReply", "late fixture reply")
    mode = "stall-unit"
    process = launch()
    wait_for(lambda: len(held) == 2)
    assert len(subscribers) == 1
    stop(process)
    wait_for(lambda: not subscribers)
    for invocation in held:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.NoReply", "late canceled lookup")
    held.clear()
    mode = "normal"
    for closed in (False, True):
        read_fd, write_fd = os.pipe()
        try:
            if closed:
                os.close(read_fd)
                read_fd = -1
            else:
                os.set_blocking(write_fd, False)
                try:
                    while True:
                        os.write(write_fd, b"x" * 4096)
                except BlockingIOError:
                    pass
                os.set_blocking(write_fd, True)
            flags = fcntl.fcntl(write_fd, fcntl.F_GETFL)
            process = launch(output=write_fd)
            wait_for(lambda: process.poll() is not None)
            assert process.returncode == 1
            assert fcntl.fcntl(write_fd, fcntl.F_GETFL) == flags
            wait_for(lambda: not subscribers)
        finally:
            os.close(write_fd)
            if read_fd >= 0:
                os.close(read_fd)
    process = launch()
    assert line(process) == b"units-event\tready\n"
    bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ReleaseName",
        GLib.Variant("(s)", (NAME,)), GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 3000, None)
    wait_for(lambda: process.poll() is not None)
    assert process.returncode == 1
    wait_for(lambda: not subscribers)
    process = launch()
    assert line(process) == b""
    wait_for(lambda: process.poll() is not None)
    assert process.returncode == 1
    print("Private-bus unit events: PASS")
finally:
    for process in processes:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=3)
        if process.stdout is not None:
            process.stdout.close()
        process.stderr.close()
    outsider.close_sync(None)
    bus.signal_unsubscribe(owner_subscription)
    bus.unregister_object(registration)
