#!/usr/bin/python3
"""Private regional preparation, discovery, and native-operation fixtures."""

from contextlib import contextmanager
import fcntl
import importlib.util
from pathlib import Path
import signal
import sys
import time


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


discovery = load("system-native-discovery-provider")
operation = load("system-native-action-provider")
if operation.ACTION == "ntp-set" and operation.SCENARIO == "disable":
    operation.VALUES["ntp-set"] = "disabled"
directory = operation.DIRECTORY
original_row = discovery.row
original_snapshot = discovery.snapshot


@contextmanager
def exclusive(name):
    with (directory / (name + ".lock")).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (directory / "overlap").touch()
            raise
        yield


def row(*fields):
    if fields[:2] == ("provider", "recovery"):
        fields = (*fields[:2], "partial", *fields[3:])
    elif fields[0] == "action" and fields[1] != "updates-cancel":
        fields = (*fields[:2], "available", *fields[3:-1], "Fixed private action")
    elif fields == ("complete", "snapshot"):
        if (directory / operation.ACTION).exists() and not (directory / "ack-operation").exists():
            original_row("terminal-handoff", operation.IDENTITY, operation.ACTION, operation.KINDS[operation.ACTION])
    original_row(*fields)


def snapshot():
    with exclusive("finite"):
        original_snapshot()


def preflight():
    arguments = sys.argv[1:]
    choices = arguments[0] == "regional-choices"
    allowed = (["regional-choices", "timezone"], ["regional-choices", "locale"],
               ["regional-preview", operation.ACTION, operation.VALUES[operation.ACTION]])
    if arguments not in allowed:
        (directory / "invalid-arguments").touch()
        return 2
    with exclusive("finite"), exclusive("preflight"):
        marker = directory / "preflight.pid"
        marker.touch()
        try:
            count_path = directory / "preflight-count"
            count_path.write_text(str(int(count_path.read_text()) + 1 if count_path.exists() else 1))
            if choices:
                original_row(arguments[0] + "-protocol", "1", "0", arguments[1])
            else:
                original_row(arguments[0] + "-protocol", "1", "0")
            if operation.SCENARIO in {"close-read", "required-read", "stale-read"}:
                time.sleep(2)
            if operation.SCENARIO == "error-read":
                original_row("error", "regional", "permission-denied", "Fixture regional read denied")
            elif operation.SCENARIO == "malformed-read":
                original_row("unexpected", "fixture")
            elif choices:
                values = ["America/Chicago", "Etc/UTC"] if arguments[1] == "timezone" else ["C", "en_US.UTF-8"]
                if operation.SCENARIO == "large":
                    values += ([f"Zone/{index:04d}" for index in range(2046)] if arguments[1] == "timezone"
                               else [f"zz_{index:04d}" for index in range(4094)])
                for value in sorted(values):
                    original_row("choice", value)
            else:
                target = arguments[2][5:] if operation.ACTION == "locale-set" else arguments[2]
                current = "disabled" if operation.ACTION == "ntp-set" else "Etc/UTC" if operation.ACTION == "timezone-set" else "C"
                detail = "Full fixture detail"
                if operation.SCENARIO == "large":
                    detail = (detail + " " + "LC_TIME=preserved " * 30)[:512]
                    if operation.ACTION == "locale-set":
                        current = ("C " + "LC_TIME=preserved " * 30)[:512]
                original_row("preview", operation.ACTION, arguments[2], "c" * 64, current, target, detail)
            original_row("complete", arguments[0])
            time.sleep(0.1)
            return 1 if operation.SCENARIO == "error-read" else 0
        finally:
            marker.unlink(missing_ok=True)


discovery.row = row
discovery.snapshot = snapshot
for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(signum, discovery.stop)
command = sys.argv[1] if len(sys.argv) > 1 else ""
if command in ("regional-choices", "regional-preview"):
    raise SystemExit(preflight())
if command in (operation.ACTION, "watch-operation", "ack-operation"):
    with exclusive("preflight"):
        raise SystemExit(operation.main())
discovery.main()
