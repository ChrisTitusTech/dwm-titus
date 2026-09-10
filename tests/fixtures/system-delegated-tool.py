#!/usr/bin/python3
"""Record a private launched child's isolation; never performs administration."""

import json
import os
import pathlib
import sys
import time

descriptors = {}
for name in os.listdir("/proc/self/fd"):
    try:
        descriptors[name] = os.readlink("/proc/self/fd/" + name)
    except FileNotFoundError:
        pass
report = pathlib.Path(sys.argv[1])
pending = report.with_suffix(".pending")
pending.write_text(json.dumps({
    "pid": os.getpid(), "sid": os.getsid(0), "descriptors": descriptors,
}), encoding="utf-8")
pending.replace(report)
if sys.argv[2] == "failed-work":
    sys.exit(42)
time.sleep(10)
