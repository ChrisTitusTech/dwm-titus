#!/usr/bin/python3
"""Compose private discovery and native-owner fixtures without host calls."""

import importlib.util
from pathlib import Path
import signal
import sys


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


discovery = load("system-native-discovery-provider")
operation = load("system-native-action-provider")
original_row = discovery.row


def row(*fields):
    if operation.SCENARIO == "large":
        if fields[:2] == ("state", "accounts-count"):
            fields = (*fields[:3], "256", *fields[4:])
        elif fields[0] == "account":
            original_row(*fields)
            for index in range(1, 256):
                original_row("account", f"/opaque/{index}", "other", f"Fixture User {index}", f"fixture-{index}")
            return
        elif fields[0] == "repository":
            original_row(*fields)
            for index in range(1, 512):
                original_row("repository", f"fixture-{index:03}", "disabled", "Bounded fixture repository " + str(index))
            return
    if fields[:2] == ("provider", "recovery"):
        fields = (*fields[:2], "partial", *fields[3:])
    elif fields[0] == "action" and fields[1] != "updates-cancel":
        fields = (*fields[:2], "available", *fields[3:-1], "Fixed private action")
    elif fields == ("complete", "snapshot"):
        if (operation.DIRECTORY / operation.ACTION).exists() and not (operation.DIRECTORY / "ack-operation").exists():
            original_row("terminal-handoff", operation.IDENTITY, operation.ACTION, "delegate")
    original_row(*fields)


discovery.row = row
for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(signum, discovery.stop)
if sys.argv[1] in (operation.ACTION, "watch-operation", "ack-operation"):
    raise SystemExit(operation.main())
discovery.main()
