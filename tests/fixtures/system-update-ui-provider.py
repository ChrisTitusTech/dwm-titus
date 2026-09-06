#!/usr/bin/python3
"""Private UI workflow fixture; no platform service, privilege or host journal."""

import os
from pathlib import Path
import signal
import sys
import time


DIRECTORY = Path(os.environ["DWM_UPDATE_UI_FIXTURE"])
GENERATION = "c" * 64


def row(*fields):
    print("\t".join(fields), flush=True)


def mode():
    path = DIRECTORY / "mode"
    return path.read_text() if path.exists() else "quiet"


def identity():
    action = (DIRECTORY / "action").read_text()
    return (f"op-{int((DIRECTORY / 'origins').read_text()):032x}", action,
            "update" if action == "updates-install-all" else "refresh")


def snapshot():
    row("system-management-protocol", "1", "0")
    row("snapshot-generation", GENERATION)
    row("provider", "updates", "available", "delegated", "PackageKit", "Private UI fixture")
    row("provider", "recovery", "partial" if mode() == "partial" else "available",
        "user-session", "dwm-system-management", "Private recovery fixture")
    row("state", "update-summary", "available", "1", "One requested update")
    row("state", "update-last-refresh", "available", "10", "Recent refresh")
    row("state", "update-restart", "available", "none", "No restart")
    active = (DIRECTORY / "action").exists()
    for action in ("updates-refresh", "updates-install-all", "updates-cancel"):
        available = not active and action != "updates-cancel" and mode() != "unavailable"
        row("action", action, "available" if available else "unavailable", "delegated",
            "updates", action, "Fixture action" if available else "")
    row("update", "alpha;2;x86_64;updates", "security", "installable", "alpha", "2", "Security update")
    for name, action, version in (("alpha", "update", "2"), ("dependency", "install", "1"), ("legacy", "remove", "1")):
        row("package-change", f"{name};{version};x86_64;updates", action, name, version, "Complete fixture preview")
    if mode() == "large":
        for index in range(4093):
            name = f"additional-dependency-{index}"
            row("package-change", f"{name};1;x86_64;updates", "install", name, "1",
                "A complete dependency row in the maximum-size preview")
    if active:
        if (DIRECTORY / "terminal").exists():
            row("terminal-handoff", *identity())
        else:
            row("active-operation", *identity(), "running", "30", "no", "Private running operation")
    row("complete", "snapshot")


def main():
    command = sys.argv[1]
    if command == "fixture-control" and len(sys.argv) == 3:
        value = sys.argv[2]
        if value == "event":
            with os.fdopen(os.open(DIRECTORY / "events", os.O_WRONLY | os.O_NONBLOCK), "w") as stream:
                stream.write("update-event\tchanged\n")
        elif value in ("finish", "revoke"):
            (DIRECTORY / value).touch()
        elif value in ("quiet", "unavailable", "partial", "deny", "monitorfail", "large"):
            (DIRECTORY / "mode").write_text(value)
        else:
            return 2
        return 0
    if command == "watch-updates" and len(sys.argv) == 2:
        if mode() == "monitorfail":
            return 1
        fifo = DIRECTORY / "events"
        if not fifo.exists():
            os.mkfifo(fifo, 0o600)
        with os.fdopen(os.open(fifo, os.O_RDWR), "r") as stream:
            row("update-event", "ready")
            for line in stream:
                print(line, end="", flush=True)
        return 0
    if command == "snapshot" and len(sys.argv) == 2:
        snapshot()
        return 0
    if command in ("ack-operation", "updates-cancel") and len(sys.argv) == 3:
        if not (DIRECTORY / "action").exists() or sys.argv[2] != identity()[0]:
            return 3
        if command == "updates-cancel":
            (DIRECTORY / "cancel").touch()
        else:
            (DIRECTORY / "action").unlink()
            (DIRECTORY / "terminal").unlink()
        return 0
    expected = [GENERATION] if command == "updates-install-all" else []
    if command not in ("updates-refresh", "updates-install-all") or sys.argv[2:] != expected:
        (DIRECTORY / "invalid-arguments").touch()
        return 2
    if (DIRECTORY / "action").exists():
        (DIRECTORY / "overlap").touch()
        return 3
    count = DIRECTORY / "origins"
    count.write_text(str(int(count.read_text()) + 1 if count.exists() else 1))
    for name in ("finish", "revoke", "cancel"):
        (DIRECTORY / name).unlink(missing_ok=True)
    (DIRECTORY / "action").write_text(command)
    current = identity()
    row("system-management-protocol", "1", "0")
    row("operation", *current, "pending", "unknown", "no", "Starting private fixture")
    if mode() == "deny":
        row("operation", *current, "authorizing", "unknown", "no", "Private authorization fixture")
        result = "permission-denied"
    else:
        row("operation", *current, "running", "30", "yes", "Private update running")
        deadline = time.monotonic() + (120 if os.environ.get("DWM_UPDATE_UI_MANUAL") == "1" else 15)
        revoked = False
        while not (DIRECTORY / "finish").exists() and not (DIRECTORY / "cancel").exists():
            if time.monotonic() > deadline:
                return 1
            if not revoked and (DIRECTORY / "revoke").exists():
                row("operation", *current, "running", "80", "no", "Private cancellation revoked")
                revoked = True
            time.sleep(0.02)
        result = "canceled" if (DIRECTORY / "cancel").exists() else "succeeded"
        if result == "canceled":
            row("operation", *current, "cancel-requested", "30", "no", "Private cancellation accepted")
    (DIRECTORY / "terminal").touch()
    row("operation", *current, result, "100", "no", "Verified private outcome")
    row("audit", *current, result, "2026-09-06T05:00:00Z", "2026-09-06T05:01:00Z", "Private fixture audit")
    row("complete", "operation")
    return 0 if result == "succeeded" else 1


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    sys.exit(main())
