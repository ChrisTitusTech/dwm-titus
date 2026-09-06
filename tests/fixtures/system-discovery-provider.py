#!/usr/bin/python3
"""Private event/snapshot fixture; never accesses PackageKit or a host journal."""

import fcntl
import os
from pathlib import Path
import signal
import stat
import sys
import time


directory = Path(os.environ["DWM_DISCOVERY_FIXTURE"])
fifo = directory / "events"
mode_file = directory / "mode"


def row(*fields):
    print("\t".join(fields), flush=True)


def mode():
    return mode_file.read_text() if mode_file.exists() else "quiet"


def changed(count):
    # Only the monitor creates the pipe. Missing readers fail this fixture
    # promptly instead of hanging it or accidentally creating a regular file.
    with os.fdopen(os.open(fifo, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW), "w") as stream:
        if not stat.S_ISFIFO(os.fstat(stream.fileno()).st_mode):
            raise RuntimeError("event target is not the monitor pipe")
        stream.write("update-event\tchanged\n" * count)


def main():
    action = sys.argv[1]
    if action == "fixture-control":
        if sys.argv[2] == "events":
            changed(100)
        elif sys.argv[2] == "restart-quiet":
            (directory / "require-monitored-read").touch()
            mode_file.write_text("quiet")
        else:
            mode_file.write_text(sys.argv[2])
        return
    if action == "watch-updates":
        if mode() == "fail-monitor":
            sys.exit(1)
        if mode() in ("ignore-term", "failed-stopping"):
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        with (directory / "monitor-lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if not fifo.exists():
                os.mkfifo(fifo, 0o600)
            (directory / "monitor-ready").unlink(missing_ok=True)
            with os.fdopen(os.open(fifo, os.O_RDWR), "r") as stream:
                if mode() != "no-ready":
                    malformed = mode() in ("malformed", "failed-stopping")
                    if not malformed:
                        (directory / "monitor-ready").touch()
                    row("update-event", "changed" if malformed else "ready")
                for line in stream:
                    print(line, end="", flush=True)
        return
    if action != "snapshot":
        sys.exit(2)
    with (directory / "snapshot-lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (directory / "overlap").touch()
            raise
        counter = directory / "snapshots"
        if (directory / "require-monitored-read").exists() and not (directory / "monitor-ready").exists():
            (directory / "unmonitored-read").touch()
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        if mode() == "self":
            changed(30)
        time.sleep(0.5 if mode() == "slow" else 0.1)
        row("system-management-protocol", "1", "0")
        row("snapshot-generation", f"{count:064x}")
        row("provider", "updates", "available", "delegated", "PackageKit", "Private fixture")
        row("provider", "recovery", "available", "user-session", "dwm-system-management", "Empty private journal")
        row("state", "update-summary", "available", "1", "One update")
        row("state", "update-last-refresh", "available", "10", "Recent fixture refresh")
        row("state", "update-restart", "available", "none", "No restart")
        for action_id in ("updates-refresh", "updates-install-all", "updates-cancel"):
            row("action", action_id, "unavailable", "delegated", "updates", action_id, "Private fixture")
        row("update", "alpha;1;x86_64;updates", "security", "installable", "alpha", "1", "Fixture update")
        row("package-change", "alpha;1;x86_64;updates", "update", "alpha", "1", "Fixture update")
        row("complete", "snapshot")


if __name__ == "__main__":
    main()
