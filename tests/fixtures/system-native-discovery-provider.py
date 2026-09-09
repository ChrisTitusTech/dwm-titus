#!/usr/bin/python3
"""Private cumulative snapshot and subscription fixture; no host services."""

import fcntl
import os
from pathlib import Path
import signal
import stat
import sys

SNAPSHOT_MODE = sys.argv[1] if len(sys.argv) > 1 else ""

# These fixtures reuse one projection for the fixed bounded snapshot modes.
if sys.argv[1:] in (["snapshot-core"], ["snapshot-without-storage"]):
    sys.argv[1] = "snapshot"
import time


DIRECTORY = Path(os.environ["DWM_NATIVE_DISCOVERY_FIXTURE"])
MONITORS = {
    ("watch-updates",): ("updates", "update-event"),
    ("watch-time",): ("time", "time-event"),
    ("watch-regional", "locale"): ("locale", "regional-event"),
    ("watch-accounts",): ("accounts", "accounts-event"),
    ("watch-units", "printers"): ("printers", "units-event"),
    ("watch-units", "security"): ("security", "units-event"),
    ("watch-mounts",): ("storage", "mount-change"),
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
                if domain == "storage" and read_mode(domain) != "fail":
                    row("mount-monitor-ready")
                else:
                    row("wrong-event" if read_mode(domain) == "fail" else prefix, "ready")
                for event in stream:
                    if event != "changed\n" and not (domain == "time" and event == "owner-arrived\n"):
                        raise ValueError("Invalid fixture event")
                    row(prefix, "mount" if domain == "storage" else event.rstrip("\n"))
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
                if SNAPSHOT_MODE == "snapshot-core" and mode == "fail-core":
                    raise SystemExit(1)
                if SNAPSHOT_MODE == "snapshot-core" and mode == "malformed-core":
                    row("malformed")
                    return
                row("system-management-protocol", "1", "1" if SNAPSHOT_MODE == "snapshot-core" else "2")
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
                if SNAPSHOT_MODE != "snapshot-core":
                    for owner in ("information", "storage", "security", "diagnostics"):
                        row("provider", owner, "partial" if owner == "storage" and SNAPSHOT_MODE == "snapshot-without-storage" else "available", "user-session" if owner == "diagnostics" else "read-only", "Fixture", "Read only")
                    for identifier in ("os-name", "os-version", "kernel-release", "architecture", "hardware-vendor", "hardware-model", "cpu-model"):
                        row("state", identifier, "available", "Fixture", "Text")
                    for identifier in ("logical-cpus", "memory-total-bytes", "memory-available-bytes", "swap-total-bytes", "swap-free-bytes", "uptime-seconds"):
                        row("state", identifier, "available", "1", "Counter")
                    for identifier in ("selinux", "secure-boot", "firewalld", "root-encryption", "screen-lock"):
                        row("state", identifier, "available", "enforcing" if identifier == "selinux" else "encrypted" if identifier == "root-encryption" else "enabled", "Security")
                    if SNAPSHOT_MODE == "snapshot-without-storage":
                        row("state", "filesystem-summary", "partial", "unknown", "Unmonitored storage")
                    else:
                        row("state", "filesystem-summary", "available", "1", "One fixture mount")
                        row("filesystem", "42", "available", "/dev/test", "/", "ext4", "100", str(count), str(100 - count), "Fixture bytes")
                    row("action", "health-open", "available", "user-session", "diagnostics", "Health", "Navigation")
                row("complete", "snapshot")
        finally:
            marker.unlink(missing_ok=True)


def time_status():
    count_path = DIRECTORY / "time-count"
    count = int(count_path.read_text()) + 1 if count_path.exists() else 1
    count_path.write_text(str(count))
    scenario = os.environ.get("DWM_NATIVE_ACTION_SCENARIO", "")
    if scenario == "owner-required" and count > 1:
        time.sleep(0.3)
    row("time-status-protocol", "1", "0")
    if scenario == "owner-fail" and count > 1:
        row("error", "time-status", "permission-denied", "Private read denied")
        row("complete", "time-status")
        raise SystemExit(1)
    zone = "Etc/UTC" if scenario == "owner-change" and count > 1 else "America/Chicago"
    can_ntp = "no" if ((scenario == "owner-capability" and count > 1)
                       or (scenario == "sample-capability" and (DIRECTORY / "sample-count").exists())) else "yes"
    synchronized = "yes" if scenario == "owner-sync" and count > 1 else "no"
    row("time", zone, can_ntp, "yes", synchronized)
    row("complete", "time-status")


def ntp_sample():
    count_path = DIRECTORY / "sample-count"
    count_path.write_text(str(int(count_path.read_text()) + 1 if count_path.exists() else 1))
    scenario = os.environ.get("DWM_NATIVE_ACTION_SCENARIO", "")
    time.sleep(0.15)
    row("ntp-sample-protocol", "1", "0")
    if scenario == "sample-error":
        row("error", "ntp-sample", "permission-denied", "Private sample denied")
        row("complete", "ntp-sample")
        raise SystemExit(1)
    row("sample", "no" if scenario == "sample-capability" else "yes", "yes")
    row("complete", "ntp-sample")


def main():
    arguments = tuple(sys.argv[1:])
    if arguments in MONITORS:
        monitor(*MONITORS[arguments])
        return
    if arguments == ("snapshot",):
        snapshot()
        return
    if arguments == ("time-status",):
        time_status()
        return
    if arguments == ("ntp-sample",):
        ntp_sample()
        return
    if len(arguments) == 4 and arguments[:1] == ("fixture-mode",):
        _, domain, action, value = arguments
        modes = {"quiet", "hold", "fail-core", "malformed-core"} if domain == "snapshot" else {"quiet", "hold", "fail"}
        if domain in DOMAINS | {"snapshot"} and action == "set" and value in modes:
            (DIRECTORY / (domain + ".mode")).write_text(value)
            return
    if len(arguments) == 3 and arguments[0] == "fixture-event":
        _, domain, action = arguments
        if domain == "time" and action == "owner-arrived":
            send(domain, "owner-arrived\n")
            return
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
