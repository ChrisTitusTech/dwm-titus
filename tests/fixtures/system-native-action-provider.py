#!/usr/bin/python3
"""Private fixed native-origin fixture; never calls services or real tools."""

import fcntl
import os
from pathlib import Path
import sys
import time


DIRECTORY = Path(os.environ["DWM_NATIVE_ACTION_FIXTURE"])
ACTION = os.environ["DWM_NATIVE_ACTION"]
SCENARIO = os.environ["DWM_NATIVE_ACTION_SCENARIO"]
IDENTITY = "op-" + "d" * 32
VALUES = {"timezone-set": "America/Chicago", "ntp-set": "enabled", "locale-set": "LANG=en_US.UTF-8"}
KINDS = {"timezone-set": "timezone", "ntp-set": "ntp", "locale-set": "locale",
         "accounts-open": "delegate", "password-open": "delegate", "printers-open": "delegate", "sources-open": "delegate"}


def row(*fields):
    print("\t".join(fields), flush=True)


def main():
    command = sys.argv[1]
    expected = ([VALUES[ACTION], "c" * 64] if ACTION in VALUES else []) if command == ACTION else [IDENTITY]
    if ACTION not in KINDS or command not in (ACTION, "watch-operation", "ack-operation") or sys.argv[2:] != expected:
        (DIRECTORY / "invalid-arguments").touch()
        return 2
    with (DIRECTORY / "owner.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            (DIRECTORY / "overlap").touch()
            raise
        counter = DIRECTORY / command
        counter.write_text(str(int(counter.read_text()) + 1 if counter.exists() else 1))
        if command == "ack-operation":
            return 0
        replay = command == "watch-operation"
        kind = KINDS[ACTION]
        owner = "regional" if ACTION in VALUES else "accounts" if ACTION in ("accounts-open", "password-open") else ACTION.removesuffix("-open")
        row("system-management-protocol", "1", "0")
        row("operation", IDENTITY, ACTION, kind, "pending", "unknown", "no", "Pending fixture")
        time.sleep(0.05)
        denied = SCENARIO == "denied"
        failed = SCENARIO in ("rejected", "unsupported", "wrong-exit")
        result = "permission-denied" if denied else "failed" if failed else "succeeded"
        if not failed:
            row("operation", IDENTITY, ACTION, kind, "authorizing" if denied else "running", "unknown", "no", "Live fixture")
            if SCENARIO == "uncertain" and not replay:
                return 1
        if failed:
            row("error", owner, "unsupported" if SCENARIO == "unsupported" else "conflict", "Fixture unavailable")
        detail = "Launch accepted; tool work is not verified" if kind == "delegate" and result == "succeeded" else "Verified fixture result"
        row("operation", IDENTITY, ACTION, kind, result, "unknown", "no", detail)
        row("audit", IDENTITY, ACTION, kind, result, "2026-09-07T09:00:00Z", "2026-09-07T09:01:00Z", detail)
        row("complete", "operation")
        time.sleep(0.08)
        return 0 if replay or result == "succeeded" or SCENARIO == "wrong-exit" else 1


if __name__ == "__main__":
    sys.exit(main())
