#!/usr/bin/env python3
"""Private finite preflight fixture; never calls a host service or journal."""
import fcntl
import os
from pathlib import Path
import signal
import sys
import time

directory = Path(os.environ["DWM_PREFLIGHT_DIRECTORY"])
scenario = os.environ["DWM_PREFLIGHT_SCENARIO"]
args = sys.argv[1:]
allowed = [["regional-choices", "timezone"], ["regional-choices", "locale"],
           ["regional-preview", "timezone-set", "Etc/UTC"],
           ["regional-preview", "ntp-set", "enabled"],
           ["regional-preview", "locale-set", "LANG=C"]]
if args not in allowed:
    (directory / "invalid-arguments").touch()
    raise SystemExit(2)
with (directory / "lock").open("a") as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        (directory / "overlap").touch()
        raise
    counter = directory / "calls"
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    (directory / "pid").write_text(str(os.getpid()))
    choices = args[0] == "regional-choices"
    header = args[0] + "-protocol\t1\t0" + ("\t" + args[1] if choices else "") + "\n"
    completion = "complete\t" + args[0] + "\n"
    if choices:
        values = ["America/Chicago", "Etc/UTC"] if args[1] == "timezone" else ["C", "en_US.utf8"]
        payload = "".join("choice\t" + value + "\n" for value in values)
    else:
        current = "America/Chicago" if args[1] == "timezone-set" else "disabled" if args[1] == "ntp-set" else "en_US.utf8"
        target = args[2][5:] if args[1] == "locale-set" else args[2]
        payload = "\t".join(["preview", args[1], args[2], "c" * 64, current, target, "Full fixture detail"]) + "\n"
    if count == 1 and scenario in {"close", "kill-close", "timeout"}:
        if scenario != "close":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        print(header, end="", flush=True)
        time.sleep(60)
    if scenario == "stderr-overflow":
        sys.stderr.write("x" * 8200)
        sys.stderr.flush()
        time.sleep(60)
    if scenario == "stdout-overflow":
        print("x" * 8193, flush=True)
        time.sleep(60)
    code = 0
    if scenario == "typed-error":
        payload = "error\tregional\tpermission-denied\tFixture read denied\n"
        code = 1
    elif scenario == "wrong-exit":
        code = 1
    elif scenario == "malformed":
        payload = "unexpected\tfixture\n"
    elif scenario == "truncated":
        completion = ""
    print(header + payload + completion, end="", flush=True)
    # A complete byte stream is provisional until this process actually exits.
    time.sleep(0.2)
    raise SystemExit(code)
