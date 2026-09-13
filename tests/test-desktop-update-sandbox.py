#!/usr/bin/python3
"""Exercise mutable source isolation with real namespaces and a hostile recipe."""
import os
from pathlib import Path
import runpy
import socket
import tempfile

repo = Path(__file__).resolve().parents[1]
update = runpy.run_path(str(repo / "scripts/dwm-desktop-update"))
with tempfile.TemporaryDirectory(prefix="desktop-sandbox-") as temporary:
    base = Path(temporary)
    source = base / "source"
    source.mkdir()
    outside = base / "host-marker"
    outside.write_text("unchanged")
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(source / "host-proxy.sock"))
    server.listen(1)
    try:
        with socket.socket(socket.AF_UNIX) as baseline:
            baseline.connect(str(source / "host-proxy.sock"))
        (source / "attack.py").write_text("""import errno, os, socket, subprocess
from pathlib import Path
outside = Path(""" + repr(str(outside)) + """)
assert not outside.exists(), 'Host files leaked into sandbox'
assert not Path('/run/dbus/system_bus_socket').exists()
assert not os.environ.get('DBUS_SESSION_BUS_ADDRESS')
status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
assert status['NoNewPrivs'].strip() == '1'
assert int(status['CapEff'].strip(), 16) == 0
try:
    socket.socket(socket.AF_UNIX)
except PermissionError as error:
    assert error.errno == errno.EPERM
else:
    raise AssertionError('Host proxy sockets remain accessible')
result = subprocess.run(['/usr/bin/pkexec', '/bin/sh', '-c', 'echo compromised > ' + str(outside)],
                        capture_output=True, text=True, timeout=10)
if os.getuid() != 0:
    assert result.returncode != 0, 'Unprivileged source obtained authorization'
Path('sandbox-passed').write_text('isolated')
""")
        (source / "Makefile").write_text("all:\n\t/usr/bin/python3 attack.py\n")
        update["sandbox_run"](["make"], writable=(source,), cwd=source)
        assert (source / "sandbox-passed").read_text() == "isolated"
        assert outside.read_text() == "unchanged", "Mutable source changed an unexposed host file"
        with update["sandbox_filter"]() as descriptor:
            try:
                os.write(descriptor, b"tamper")
            except PermissionError:
                pass
            else:
                raise AssertionError("Sandbox filter is writable after publication")
        print("Mutable builds cannot reach host authorization, proxy sockets, or private files: PASS")
    finally:
        server.close()
