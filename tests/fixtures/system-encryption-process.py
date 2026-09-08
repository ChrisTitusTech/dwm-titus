#!/usr/bin/python3
"""Finite root topology with the shared hostile owned-process fixture modes."""

import json
import os
import pathlib
import runpy
import sys

mode = sys.argv[1]
if mode in ("success", "exact-budget", "exit"):
    row = {"name": "fixture", "type": "disk", "fstype": "ext4", "mountpoints": ["/"], "pkname": None}
    output = json.dumps({"blockdevices": [row]}).encode()
    os.write(1, output)
    if mode == "exact-budget":
        sys.stderr.buffer.write(b"x" * (2 * 1024 * 1024 - len(output)))
    elif mode == "exit":
        os.write(2, b"private diagnostic must not reach the result\n")
        sys.exit(int(sys.argv[2]))
else:
    assert mode in {"empty-json", "bad-json", "invalid-utf8", "stdout-overflow", "stderr-overflow",
                   "combined-overflow", "closed-pipes", "descendant"}
    runpy.run_path(str(pathlib.Path(__file__).with_name("system-filesystem-process.py")))
