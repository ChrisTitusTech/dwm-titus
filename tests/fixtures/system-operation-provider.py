#!/usr/bin/python3
"""Private Quickshell protocol fixtures. Never opens a service or host journal."""

import os
from pathlib import Path
import sys
import time
import signal


def row(*fields):
    print("\t".join(fields), flush=True)


def snapshot():
    incomplete = os.environ.get("DWM_OWNER_INCOMPLETE_RECOVERY") == "1"
    close_retry = os.environ.get("DWM_OWNER_CLOSE_RETRY") == "1"
    delayed_snapshot = os.environ.get("DWM_OWNER_DELAYED_SNAPSHOT") == "1"
    captured_handoff = False
    if delayed_snapshot:
        directory = Path(os.environ["DWM_OPERATION_FIXTURE"])
        counter = directory / "delayed-snapshots"
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        captured_handoff = not (directory / "ack-operation-16").exists()
        if count > 1:
            time.sleep(1)
    if close_retry:
        counter = Path(os.environ["DWM_OPERATION_FIXTURE"]) / "retry-snapshots"
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        if count > 1:
            time.sleep(0.2)
    row("system-management-protocol", "1", "0")
    row("snapshot-generation", "a" * 64)
    row("provider", "updates", "unsupported", "delegated", "PackageKit", "Isolated fixture")
    recovery_partial = incomplete or bool(os.environ.get("DWM_OPERATION_FIXTURE"))
    if delayed_snapshot and not captured_handoff:
        recovery_partial = False
    row("provider", "recovery", "partial" if recovery_partial else "available",
        "user-session", "dwm-system-management", "Isolated fixture")
    for name in ("update-summary", "update-last-refresh", "update-restart"):
        row("state", name, "unsupported", "unknown", "Isolated fixture")
    for action in ("updates-refresh", "updates-install-all", "updates-cancel"):
        row("action", action, "unavailable", "delegated", "updates", action, "Isolated fixture")
    fixture = os.environ.get("DWM_OPERATION_FIXTURE")
    if incomplete:
        directory = Path(fixture)
        counter = directory / "incomplete-snapshots"
        counter.write_text(str(int(counter.read_text()) + 1 if counter.exists() else 1))
        row("error", "recovery", "malformed", "Transient journal read failure")
    elif delayed_snapshot:
        if captured_handoff:
            row("terminal-handoff", f"op-{16:032x}", "updates-refresh", "refresh")
    elif fixture:
        directory = Path(fixture)
        scenario = 15 if close_retry else 10
        operation_id = f"op-{scenario:032x}"
        if not (directory / f"ack-operation-{scenario}").exists():
            if (directory / f"finished-{scenario}").exists():
                row("terminal-handoff", operation_id, "updates-refresh", "refresh")
            else:
                row("active-operation", operation_id, "updates-refresh", "refresh",
                    "running", "30", "no", "Restored fixture")
    row("complete", "snapshot")


def main():
    if sys.argv[1:] == ["watch-updates"]:
        row("update-event", "ready")
        while True:
            signal.pause()
    if sys.argv[1:] == ["snapshot"]:
        snapshot()
        return 0
    if len(sys.argv) != 3 or sys.argv[1] not in ("watch-operation", "ack-operation"):
        return 2
    operation_id = sys.argv[2]
    scenario = int(operation_id[-2:], 16)
    directory = Path(os.environ["DWM_OPERATION_FIXTURE"])
    counter = directory / (sys.argv[1] + "-" + str(scenario))
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if sys.argv[1] == "ack-operation":
        if scenario == 16 and count > 1:
            return 3  # The real provider rejects an already cleared handoff.
        if scenario in (12, 13):
            time.sleep(0.15)  # Snapshot can arrive after ack commits but before EOF.
        if scenario == 4:
            return 3
        if scenario == 9:
            print("unexpected control output")
        return 0
    if scenario == 1 and count > 1:
        return 0  # Same-ID empty second run must not reuse collector data.
    if scenario == 3:
        return 3
    if scenario == 15 and count == 1:
        return 3
    if scenario == 8:
        sys.stderr.write("x" * 9000)
        sys.stderr.flush()
        time.sleep(5)
        return 0
    action = "timezone-set" if scenario == 2 else "updates-refresh"
    kind = "timezone" if scenario == 2 else "refresh"
    row("system-management-protocol", "1", "0")
    row("operation", operation_id, action, kind, "pending", "unknown", "no", "Pending fixture")
    time.sleep(0.1)
    if scenario == 7:
        sys.stdout.buffer.write(b"future\t\xe2\x82")
        sys.stdout.buffer.flush()
        return 0
    result = "permission-denied" if scenario == 2 else "succeeded"
    row("operation", operation_id, action, kind,
        "authorizing" if scenario == 2 else "running", "50", "no", "Live fixture")
    if scenario in (10, 15):
        (directory / f"finished-{scenario}").write_text("terminal")
    row("operation", operation_id, action, kind, result, "100", "no", "Terminal fixture")
    row("audit", operation_id, action, kind, result,
        "2026-09-05T12:00:00Z", "2026-09-05T12:01:00Z", "Audit fixture")
    row("complete", "operation")
    time.sleep(0.1)  # Valid terminal text remains provisional until process exit.
    if scenario == 5:
        row("future", "after completion")
    return 0


if __name__ == "__main__":
    sys.exit(main())
