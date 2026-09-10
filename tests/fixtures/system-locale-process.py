#!/usr/bin/python3
"""Finite and hostile locale catalog fixtures; never invokes host services."""

import os
import pathlib
import signal
import sys
import time


def write_pid(filename, pid):
    destination = pathlib.Path(filename)
    pending = destination.with_suffix(".pending")
    pending.write_text(str(pid))
    pending.replace(destination)


mode = sys.argv[1]
if mode == "collector":
    import importlib.machinery
    import importlib.util
    import subprocess
    from unittest import mock

    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_loader("locale_provider",
        importlib.machinery.SourceFileLoader("locale_provider", sys.argv[2]))
    provider = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = provider
    spec.loader.exec_module(provider)
    popen = subprocess.Popen

    def launch(command, **options):
        process = popen(command[:4] + ["/usr/bin/python3", __file__, "descendant", sys.argv[3]], **options)
        write_pid(sys.argv[4], process.pid)
        return process

    with mock.patch.object(provider.subprocess, "Popen", side_effect=launch):
        provider.read_locale_choices()
elif mode == "success":
    os.write(1, b"C\nC.utf8\nPOSIX\nen_US.utf8\n")
elif mode == "empty":
    pass
elif mode == "exact-budget":
    os.write(1, b"C\n")
    sys.stderr.buffer.write(b"x" * (2 * 1024 * 1024 - 2))
elif mode == "exit":
    os.write(1, b"C\n")
    os.write(2, b"private diagnostic must not reach the protocol\n")
    sys.exit(int(sys.argv[2]))
elif mode == "duplicate":
    os.write(1, b"C\nC\n")
elif mode == "nonascii":
    os.write(1, b"C\n\xff\n")
elif mode == "blank":
    os.write(1, b"C\n\n")
elif mode == "oversized-name":
    os.write(1, b"x" * 129 + b"\n")
elif mode == "too-many":
    sys.stdout.write("".join(f"locale{index}\n" for index in range(4097)))
elif mode in ("stdout-overflow", "stderr-overflow", "combined-overflow"):
    streams = (1, 2) if mode == "combined-overflow" else ((1,) if mode == "stdout-overflow" else (2,))
    for _ in range(257):
        for stream in streams:
            os.write(stream, b"x" * 8192)
elif mode in ("closed-pipes", "descendant"):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode == "descendant":
        child = os.fork()
        if child:
            write_pid(sys.argv[2], child)
    else:
        os.close(1)
        os.close(2)
    while True:
        time.sleep(1)
else:
    raise RuntimeError("Unknown locale fixture")
