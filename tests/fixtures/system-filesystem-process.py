#!/usr/bin/python3
"""Finite filesystem JSON and hostile owned-process fixtures."""

import json
import os
import pathlib
import runpy
import sys

row = {"id": 7, "source": "/dev/fixture", "target": "/", "fstype": "ext4",
       "size": 1048576, "used": 1024, "avail": 1047552}
output = json.dumps({"filesystems": [row]}).encode()
mode = sys.argv[1]
if mode in ("success", "exact-budget", "exit"):
    os.write(1, output)
    if mode == "exact-budget":
        sys.stderr.buffer.write(b"x" * (2 * 1024 * 1024 - len(output)))
    elif mode == "exit":
        os.write(2, b"private diagnostic must not reach the result\n")
        sys.exit(int(sys.argv[2]))
elif mode == "empty-json":
    os.write(1, b'{"filesystems": []}')
elif mode == "bad-json":
    os.write(1, b'{"filesystems": [')
elif mode == "invalid-utf8":
    os.write(1, b'\xff')
else:
    # Share only the existing synthetic overflow and TERM-resistant child modes.
    assert mode in {"stdout-overflow", "stderr-overflow", "combined-overflow", "closed-pipes", "descendant"}
    runpy.run_path(str(pathlib.Path(__file__).with_name("system-locale-process.py")))
