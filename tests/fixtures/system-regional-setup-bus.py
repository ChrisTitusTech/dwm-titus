#!/usr/bin/python3
"""Inject real directly addressed signals at controlled service setup barriers."""

import os
import runpy
import sys

os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
from gi.repository import Gio, GLib, GLibUnix

provider = runpy.run_path(sys.argv[1], run_name="regional_setup_fixture")
accounts = len(sys.argv) == 3 and sys.argv[2] == "accounts"
address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
service = Gio.DBusConnection.new_for_address_sync(address, flags, None, None)
outsider = Gio.DBusConnection.new_for_address_sync(address, flags, None, None)


class SetupMonitor(provider["AccountEventMonitor"] if accounts else provider["RegionalEventMonitor"]):
    """Delay only callback publication, leaving actual bus setup and signals intact."""

    def inject(self, sender, oversized=False):
        """Bypass match routing using the monitor's actual unique destination."""
        if accounts:
            parameters = GLib.Variant("(s)", ("x" * 20000,)) if oversized else GLib.Variant("()", ())
            sender.emit_signal(self.connection.get_unique_name(), "/users/Setup",
                provider["ACCOUNT_INTERFACE"], "Changed", parameters)
        else:
            fields = {"x" * 20000: GLib.Variant("b", True)} if oversized else {"Timezone": GLib.Variant("s", "UTC")}
            sender.emit_signal(self.connection.get_unique_name(), self.path,
                "org.freedesktop.DBus.Properties", "PropertiesChanged",
                GLib.Variant("(sa{sv}as)", (self.name, fields, [])))
        sender.flush_sync(None)

    def owner_initialized(self, connection, result, epoch):
        """Deliver a forged oversized payload while the owner is still unknown."""
        self.inject(outsider, oversized=True)

        def resume():
            """Check that the forged signal changed neither readiness nor state."""
            assert not self.stopped and not self.dirty and not self.ready
            super(SetupMonitor, self).owner_initialized(connection, result, epoch)
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(50, resume)

    def owner_resolved(self, connection, result, epoch):
        """Test forged and authentic unicast delivery after the first owner barrier."""
        self.inject(outsider, oversized=True)
        self.inject(service)

        def resume():
            """Preserve a legitimate setup invalidation and finish the real barrier."""
            assert not self.stopped and self.dirty and not self.ready
            super(SetupMonitor, self).owner_resolved(connection, result, epoch)
            self.stop(0)
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(50, resume)


try:
    name = provider["ACCOUNTS_NAME"] if accounts else "org.freedesktop.timedate1"
    result = service.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "RequestName", GLib.Variant("(su)", (name, 0)),
        GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 3000, None)
    assert result.unpack() == (1,)
    emitted = []
    monitor = SetupMonitor(Gio, GLib, GLibUnix, emitted.append) if accounts else SetupMonitor("time", Gio, GLib, GLibUnix, emitted.append)
    assert monitor.run() == 0
    prefix = "accounts-event" if accounts else "regional-event"
    assert emitted == [prefix + "\tready", prefix + "\tchanged"]
    print(("Account" if accounts else "Regional") + " setup unicast authentication: PASS")
finally:
    outsider.close_sync(None)
    service.close_sync(None)
