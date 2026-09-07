#!/usr/bin/python3
"""Private cumulative snapshot and subscription fixture; no host services."""

import fcntl
import os
from pathlib import Path
import signal
import stat
import sys


DIRECTORY = Path(os.environ["DWM_NATIVE_DISCOVERY_FIXTURE"])
MONITORS = {
    ("watch-updates",): ("updates", "update-event"),
    ("watch-regional", "time"): ("time", "regional-event"),
    ("watch-regional", "locale"): ("locale", "regional-event"),
    ("watch-accounts",): ("accounts", "accounts-event"),
    ("watch-units", "printers"): ("printers", "units-event"),
}
DOMAINS = {item[0] for item in MONITORS.values()}


def row(*fields):
    print("\t".join(fields), flush=True)


def read_mode(name):
    path = DIRECTORY / (name + ".mode")
    return path.read_text() if path.exists() else "quiet"


def send(name, value):
    with os.fdopen(os.open(DIRECTORY / (name + ".events"),
                           os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW), "w") as stream:
        if not stat.S_ISFIFO(os.fstat(stream.fileno()).st_mode):
            raise RuntimeError("Not a private fixture pipe")
        stream.write(value)


def pipe(name):
    path = DIRECTORY / (name + ".events")
    if not path.exists():
        os.mkfifo(path, 0o600)
    return os.fdopen(os.open(path, os.O_RDWR | os.O_NOFOLLOW), "r")


def monitor(domain, prefix):
    marker = DIRECTORY / (domain + ".active")
    with (DIRECTORY / (domain + ".lock")).open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (DIRECTORY / "overlap").touch()
            raise
        try:
            with pipe(domain) as stream:
                marker.write_text(str(os.getpid()))
                if read_mode(domain) == "hold":
                    if stream.readline() != "ready\n":
                        raise ValueError("Expected readiness release")
                row("wrong-event" if read_mode(domain) == "fail" else prefix, "ready")
                for event in stream:
                    if event != "changed\n":
                        raise ValueError("Invalid fixture event")
                    row(prefix, "changed")
        finally:
            marker.unlink(missing_ok=True)


def snapshot():
    marker = DIRECTORY / "snapshot.active"
    with (DIRECTORY / "snapshot.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (DIRECTORY / "overlap").touch()
            raise
        try:
            count_path = DIRECTORY / "count"
            count = int(count_path.read_text()) + 1 if count_path.exists() else 1
            count_path.write_text(str(count))
            with pipe("snapshot") as stream:
                marker.write_text(str(os.getpid()))
                mode = read_mode("snapshot")
                if mode == "hold" and stream.readline() != "finish\n":
                    raise ValueError("Expected snapshot release")
                row("system-management-protocol", "1", "1")
                row("snapshot-generation", f"{count:064x}")
                row("provider", "updates", "available", "delegated", "PackageKit", "Fixture updates")
                row("provider", "recovery", "available", "user-session", "Journal", "Empty private journal")
                for owner in ("regional", "accounts", "printers", "sources"):
                    row("provider", owner, "available", "delegated", "Fixture", "Readable " + owner)
                for identifier, value in (("update-summary", "1"), ("update-last-refresh", "10"),
                        ("update-restart", "none"), ("timezone", "America/Chicago"),
                        ("ntp-enabled", "yes"), ("ntp-synchronized", "no"),
                        ("locale", "en_US.UTF-8"), ("accounts-count", "1"), ("cups-service", "running")):
                    row("state", identifier, "available", value, "Readable " + identifier)
                for action, owner in (("updates-refresh", "updates"), ("updates-install-all", "updates"),
                        ("updates-cancel", "updates"), ("timezone-set", "regional"), ("ntp-set", "regional"),
                        ("locale-set", "regional"), ("accounts-open", "accounts"), ("password-open", "accounts"),
                        ("printers-open", "printers"), ("sources-open", "sources")):
                    row("action", action, "unavailable", "delegated", owner, action, "Read-only fixture")
                row("update", "alpha;1;x86_64;updates", "normal", "installable", "alpha", "1", "Fixture")
                row("package-change", "alpha;1;x86_64;updates", "update", "alpha", "1", "Fixture")
                row("account", "/opaque/current", "current", "Fixture User", "fixture")
                row("repository", "fedora", "enabled", "Fixture repository")
                row("complete", "snapshot")
        finally:
            marker.unlink(missing_ok=True)


def main():
    arguments = tuple(sys.argv[1:])
    if arguments in MONITORS:
        monitor(*MONITORS[arguments])
        return
    if arguments == ("snapshot",):
        snapshot()
        return
    if len(arguments) == 4 and arguments[:1] == ("fixture-mode",):
        _, domain, action, value = arguments
        modes = {"quiet", "hold"} if domain == "snapshot" else {"quiet", "hold", "fail"}
        if domain in DOMAINS | {"snapshot"} and action == "set" and value in modes:
            (DIRECTORY / (domain + ".mode")).write_text(value)
            return
    if len(arguments) == 3 and arguments[0] == "fixture-event":
        _, domain, action = arguments
        if domain in DOMAINS and action in {"emit", "ready"}:
            send(domain, "changed\n" * 100 if action == "emit" else "ready\n")
            return
        if domain == "snapshot" and action == "finish":
            send(domain, "finish\n")
            return
    if len(arguments) == 2 and arguments[0] == "fixture-count" and arguments[1].isdecimal():
        if int((DIRECTORY / "count").read_text()) != int(arguments[1]):
            raise RuntimeError("Unexpected snapshot count")
        return
    (DIRECTORY / "unexpected-command").touch()
    raise ValueError("Unexpected fixture command")


def stop(_signal, _frame):
    raise SystemExit(0)


if __name__ == "__main__":
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)
    main()
