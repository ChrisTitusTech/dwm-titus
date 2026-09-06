#!/usr/bin/python3
"""Exercise the real update monitor on a private bus, never host PackageKit."""

import fcntl
import os
import pathlib
import selectors
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


NAME = "org.freedesktop.PackageKit"
PATH = "/org/freedesktop/PackageKit"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address)
processes = []
retained_writers = []


def name_call(method, connection=bus):
    parameters = GLib.Variant("(su)", (NAME, 0)) if method == "RequestName" else GLib.Variant("(s)", (NAME,))
    return connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", method, parameters, GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def launch(monitor_environment=environment):
    process = subprocess.Popen([sys.argv[1], "watch-updates"], env=monitor_environment,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    processes.append(process)
    return process


def line(process, timeout=3):
    output = b""
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while b"\n" not in output and time.monotonic() < deadline:
            if selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(process.stdout.fileno(), 1)
                if not chunk:
                    break
                output += chunk
    return output


def emit(member, *, path=PATH, interface=NAME, parameters=None, connection=bus):
    connection.emit_signal(None, path, interface, member, parameters)
    connection.flush_sync(None)


try:
    assert name_call("RequestName") == 1
    process = launch()
    assert line(process) == b"update-event\tready\n"
    # No PackageKit methods are exported. Reaching ready proves setup only
    # calls the bus daemon, without activating a transaction or reading state.
    for member in ("UpdatesChanged", "InstalledChanged", "RepoListChanged"):
        emit(member)
        assert line(process) == b"update-event\tchanged\n", member

    emit("TransactionListChanged", parameters=GLib.Variant("(ao)", (["/18_fixture"],)))
    emit("UpdatesChanged", path="/18_fixture", interface=NAME + ".Transaction")
    emit("Finished", path="/18_fixture", interface=NAME + ".Transaction",
        parameters=GLib.Variant("(uu)", (1, 0)))
    outsider = Gio.DBusConnection.new_for_address_sync(address,
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    emit("UpdatesChanged", connection=outsider)
    assert line(process, 0.2) == b"", "Unrelated signals triggered discovery"
    outsider.close_sync(None)

    assert name_call("ReleaseName") == 1
    assert line(process) == b"update-event\tchanged\n"
    assert name_call("RequestName") == 1
    assert line(process) == b"update-event\tchanged\n"
    emit("InstalledChanged")
    assert line(process) == b"update-event\tchanged\n", "Replacement owner not monitored"
    for _ in range(100):
        emit("UpdatesChanged")
    assert all(line(process) == b"update-event\tchanged\n" for _ in range(100))
    assert line(process, 0.2) == b"", "Idle monitor emitted output"
    process.send_signal(signal.SIGTERM)
    assert process.wait(timeout=3) == 0
    assert process.stderr.read() == b""

    # Lost stdout is not a successful monitor or an interpreter flush failure.
    broken = launch()
    assert line(broken) == b"update-event\tready\n"
    broken.stdout.close()
    emit("UpdatesChanged")
    assert broken.wait(timeout=3) == 1
    error = broken.stderr.read()
    assert b"reload status explicitly" in error and b"Traceback" not in error

    # Shell groups can retain the same write-side open-file description for
    # later commands. Restore its original mode on both clean and failed exits.
    for originally_blocking, overflow, merged in ((True, False, False), (False, False, False),
            (True, True, False), (True, True, True)):
        reader, writer = os.pipe()
        retained_writers.append(writer)
        os.set_blocking(writer, originally_blocking)
        inherited = subprocess.Popen([sys.argv[1], "watch-updates"], env=environment,
            stdout=writer, stderr=subprocess.STDOUT if merged else subprocess.PIPE, bufsize=0)
        processes.append(inherited)
        inherited.stdout = os.fdopen(reader, "rb", buffering=0)
        fcntl.fcntl(writer, fcntl.F_SETPIPE_SZ, 4096)
        assert line(inherited) == b"update-event\tready\n"
        if overflow:
            for _ in range(1000):
                emit("UpdatesChanged")
                if inherited.poll() is not None:
                    break
        else:
            inherited.send_signal(signal.SIGTERM)
        assert inherited.wait(timeout=3) == int(overflow)
        assert os.get_blocking(writer) == originally_blocking, "Inherited stdout mode was not restored"

    # A reader that remains open but stops draining cannot pin the GLib loop
    # and its subscriptions. Overflow exits explicitly, with no event queue.
    stalled = launch()
    fcntl.fcntl(stalled.stdout.fileno(), fcntl.F_SETPIPE_SZ, 4096)
    assert line(stalled) == b"update-event\tready\n"
    for _ in range(1000):
        emit("UpdatesChanged")
        if stalled.poll() is not None:
            break
    assert stalled.wait(timeout=3) == 1, "Full stdout pipe prevented monitor shutdown"
    error = stalled.stderr.read()
    assert b"reload status explicitly" in error and b"Traceback" not in error

    # Missing PackageKit does not prevent an installed subscription; finite
    # discovery separately reports capability availability.
    assert name_call("ReleaseName") == 1
    absent = launch()
    assert line(absent) == b"update-event\tready\n"
    absent.send_signal(signal.SIGINT)
    assert absent.wait(timeout=3) == 0

    # A separate disposable bus lets the fixture prove connection loss without
    # terminating its own control bus or touching any host session/system bus.
    daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    processes.append(daemon)
    private_address = line(daemon).decode().strip()
    assert private_address.startswith("unix:")
    disconnected = launch(dict(environment, DBUS_SYSTEM_BUS_ADDRESS=private_address))
    assert line(disconnected) == b"update-event\tready\n"
    daemon.terminate()
    daemon.wait(timeout=3)
    assert disconnected.wait(timeout=3) == 1
    assert b"reload status explicitly" in disconnected.stderr.read()

    denied_bus = subprocess.Popen(["dbus-daemon", "--nofork", "--print-address=1",
        "--config-file=" + str(pathlib.Path(__file__).with_name("system-update-events-denied.conf")),
        "--address=unix:tmpdir=" + os.environ.get("TMPDIR", "/tmp")],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    processes.append(denied_bus)
    denied_address = line(denied_bus).decode().strip()
    assert denied_address.startswith("unix:")
    denied_connection = Gio.DBusConnection.new_for_address_sync(denied_address,
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    try:
        assert name_call("RequestName", denied_connection) == 1
        denied = launch(dict(environment, DBUS_SYSTEM_BUS_ADDRESS=denied_address))
        assert denied.wait(timeout=3) == 1
        assert denied.stdout.read() == b"", "Denied sender lookup falsely reported readiness"
        assert b"reload status explicitly" in denied.stderr.read()
    finally:
        denied_connection.close_sync(None)
    print("PackageKit private-bus event monitor: PASS")
finally:
    for process in processes:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()
    for writer in retained_writers:
        os.close(writer)
