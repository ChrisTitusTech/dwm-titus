#!/usr/bin/python3
"""Private capture-allocation and child-termination fixture."""

import os
from pathlib import Path
import signal
import sys
import tempfile


directory = Path(os.environ["DWM_CAPTURE_DIRECTORY"])
scenario = os.environ["DWM_CAPTURE_SCENARIO"]


def main():
    if Path(sys.argv[0]).name == "mktemp":
        if len(sys.argv) != 2:
            raise ValueError("Unexpected allocation arguments")
        template = Path(sys.argv[1])
        prefixes = {"dwm-checked-command.XXXXXX": "first",
                    "dwm-checked-command-error.XXXXXX": "second"}
        if template.parent != directory or template.name not in prefixes:
            raise ValueError("Allocation escaped the private fixture")
        stage = prefixes[template.name]
        if scenario == stage + "-fail":
            return 1
        fd, name = tempfile.mkstemp(prefix=template.name[:-6], dir=directory)
        os.close(fd)
        if scenario == stage + "-term":
            os.kill(int(os.environ["DWM_CAPTURE_PARENT"]), signal.SIGTERM)
        print(name, flush=True)
        return 0
    if sys.argv[1:] != ["fixture-helper"]:
        raise ValueError("Unexpected helper arguments")
    (directory / "helper-started").touch()
    if scenario == "stop-child":
        def stopped(_signal, _frame):
            (directory / "helper-stopped").touch()
            raise SystemExit(0)
        signal.signal(signal.SIGTERM, stopped)
        os.kill(int(os.environ["DWM_CAPTURE_PARENT"]), signal.SIGTERM)
        signal.pause()
        raise RuntimeError("Child unexpectedly resumed")
    print("fixture-output", flush=True)
    print("fixture-error", file=sys.stderr, flush=True)
    return 1 if scenario == "helper-fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
