#!/usr/bin/python3
"""Private native update-owner fixture; no service, privilege or host journal."""

import os
from pathlib import Path
import sys
import time


DIRECTORY = Path(os.environ["DWM_UPDATE_ACTION_FIXTURE"])
SCENARIO = os.environ["DWM_UPDATE_ACTION_SCENARIO"]
OPERATION_ID = "op-" + "b" * 32


def row(*fields):
    print("\t".join(fields), flush=True)


def main():
    command = sys.argv[1]
    if command not in ("updates-refresh", "updates-install-all", "updates-cancel",
                       "watch-operation", "ack-operation"):
        return 2
    expected = ["c" * 64] if command == "updates-install-all" else (
        [] if command == "updates-refresh" else [OPERATION_ID])
    if sys.argv[2:] != expected:
        (DIRECTORY / "invalid-arguments").touch()
        return 2
    counter = DIRECTORY / command
    counter.write_text(str(int(counter.read_text()) + 1 if counter.exists() else 1))
    if command == "ack-operation":
        if (DIRECTORY / "control-active").exists():
            (DIRECTORY / "control-overlap").touch()
        return 0
    if command == "updates-cancel":
        (DIRECTORY / "control-active").touch()
        (DIRECTORY / "cancel-sent").touch()
        if SCENARIO == "cancel-timeout":
            time.sleep(15)  # Frontend's 10-second deadline must kill only this control.
        elif SCENARIO in ("cancel-race", "cancel-recovery", "cancel-recovery-denied",
                          "cancel-recovery-failure", "cancel-pending-snapshot"):
            time.sleep(0.3)
        elif SCENARIO == "cancel-output":
            row("unexpected", "control output")
        elif SCENARIO == "cancel-error-overflow":
            sys.stderr.write("x" * 9000)
            sys.stderr.flush()
            time.sleep(15)
        else:
            time.sleep(0.08)
        (DIRECTORY / "control-active").unlink(missing_ok=True)
        return 3 if SCENARIO == "cancel-conflict" else 1 if SCENARIO in (
            "cancel-denied", "cancel-recovery-denied", "cancel-uncertain-recover") else 0

    replay = command == "watch-operation"
    action = "updates-install-all" if SCENARIO == "install" else "updates-refresh"
    kind = "update" if action == "updates-install-all" else "refresh"
    row("system-management-protocol", "1", "0")
    row("operation", OPERATION_ID, action, kind, "pending", "unknown", "no", "Pending fixture")
    time.sleep(0.05)
    failed = SCENARIO in ("rejected", "wrong-exit")
    denied = SCENARIO == "denied"
    result = "permission-denied" if denied else "failed" if failed else "succeeded"
    if not failed:
        row("operation", OPERATION_ID, action, kind, "authorizing" if denied else "running",
            "30", "yes" if SCENARIO.startswith("cancel-") or SCENARIO == "revoked" else "no", "Live fixture")
        if SCENARIO == "uncertain" and not replay:
            return 1  # No complete result: recovery must watch, never reissue.
        if SCENARIO.startswith("cancel-"):
            deadline = time.monotonic() + 3
            while not (DIRECTORY / "cancel-sent").exists():
                if time.monotonic() >= deadline:
                    return 1
                time.sleep(0.01)
            if SCENARIO == "cancel-accepted":
                time.sleep(0.15)
                row("operation", OPERATION_ID, action, kind, "cancel-requested", "30", "no", "Request accepted")
                result = "canceled"
            elif SCENARIO == "cancel-timeout":
                time.sleep(10.5)
                (DIRECTORY / "control-active").unlink(missing_ok=True)
            else:
                time.sleep(0.15)
                if SCENARIO == "cancel-error-overflow":
                    (DIRECTORY / "control-active").unlink(missing_ok=True)
                if SCENARIO == "cancel-uncertain-recover" and not replay:
                    return 1  # Lost observation after an unconfirmed Cancel.
        if SCENARIO == "revoked":
            time.sleep(0.1)
            row("operation", OPERATION_ID, action, kind, "running", "80", "no", "Cancellation unsafe")
            time.sleep(0.1)
    if failed:
        row("error", "updates", "conflict", "Confirmed generation changed")
    row("operation", OPERATION_ID, action, kind, result, "100", "no", "Terminal fixture")
    row("audit", OPERATION_ID, action, kind, result,
        "2026-09-06T03:00:00Z", "2026-09-06T03:01:00Z", "Audited fixture")
    row("complete", "operation")
    time.sleep(0.08)  # Terminal records are provisional until normal exit.
    if SCENARIO == "wrong-exit" and not replay:
        return 0  # Invalid for an originating failed result; valid for its replay.
    return 0 if replay or result == "succeeded" else 1


if __name__ == "__main__":
    sys.exit(main())
