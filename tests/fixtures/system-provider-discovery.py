#!/usr/bin/python3
"""Private fixed monitor fixture; no host service or journal access.

Expected event-pipe failures exit 3 with one fixture-event-error diagnostic.
"""

import errno
import fcntl
import os
from pathlib import Path
import signal
import stat
import sys


directory = Path(os.environ["DWM_PROVIDER_DISCOVERY_FIXTURE"])
definitions = {
    ("watch-updates",): ("updates", "update-event"),
    ("watch-time",): ("time", "time-event"),
    ("watch-regional", "locale"): ("locale", "regional-event"),
    ("watch-accounts",): ("accounts", "accounts-event"),
    ("watch-units", "printers"): ("printers", "units-event"),
}


class FixtureEventFailure(Exception):
    """An expected rejection of a private event-pipe endpoint."""


def main():
    arguments = tuple(sys.argv[1:])
    if len(arguments) == 3 and arguments[0] == "fixture-control":
        domain, action = arguments[1:]
        if domain not in {item[0] for item in definitions.values()}:
            raise ValueError("Unknown fixture domain")
        if action in {"quiet", "wrong-prefix"}:
            (directory / "mode").write_text(action)
            return
        if action == "assert-active":
            if (not (directory / (domain + ".active")).is_file()
                    or len(tuple(directory.glob("*.active"))) != 1):
                raise RuntimeError("Wrong or overlapping fixed monitor command")
            return
        if action not in {"emit", "exit"}:
            raise ValueError("Unknown fixture control")
        fifo = directory / (domain + ".events")
        try:
            descriptor = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        except OSError as error:
            if error.errno not in {errno.ENOENT, errno.ENXIO}:
                raise
            raise FixtureEventFailure("missing-pipe" if error.errno == errno.ENOENT else "missing-reader") from error
        with os.fdopen(descriptor, "w") as stream:
            if not stat.S_ISFIFO(os.fstat(stream.fileno()).st_mode):
                raise FixtureEventFailure("not-pipe")
            stream.write("changed\n" * 100 if action == "emit" else "exit\n")
        return
    if arguments not in definitions:
        (directory / "unexpected-command").touch()
        raise ValueError("Unexpected monitor arguments")
    domain, prefix = definitions[arguments]
    mode_path = directory / "mode"
    mode = mode_path.read_text() if mode_path.exists() else "quiet"
    marker = directory / (domain + ".active")
    fifo = directory / (domain + ".events")

    def stop(_signal, _frame):
        raise SystemExit(0)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)
    with (directory / (domain + ".lock")).open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (directory / "overlap").touch()
            raise
        try:
            marker.write_text(str(os.getpid()))
            if not fifo.exists():
                os.mkfifo(fifo, 0o600)
            with os.fdopen(os.open(fifo, os.O_RDWR | os.O_NOFOLLOW), "r") as stream:
                print(("wrong-event" if mode == "wrong-prefix" else prefix) + "\tready", flush=True)
                for line in stream:
                    if line == "exit\n":
                        return
                    if line != "changed\n":
                        raise ValueError("Invalid fixture event")
                    print(prefix + "\tchanged", flush=True)
        finally:
            marker.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except FixtureEventFailure as error:
        print("fixture-event-error\t" + str(error), file=sys.stderr)
        sys.exit(3)
