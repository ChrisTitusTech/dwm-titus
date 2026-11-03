"""Exercise opt-in, real ping/reply, recovery and disable on a private X server."""
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]


def wait_for(predicate, seconds=22):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for hang detector state")


with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
    work = Path(directory)
    processes = []
    config = work / "config/dwm-titus"
    config.mkdir(parents=True)
    for path in (repo / "config").glob("*.toml"):
        shutil.copy(path, config)
    binary = work / "bin"
    binary.mkdir()
    shutil.copy(repo / "dwm", binary / "dwm")
    helper = binary / "dwm-hang-event"
    helper.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$DWM_TEST_EVENTS"\n')
    helper.chmod(0o755)
    stub = binary / "notify-send"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    subprocess.run([os.environ.get("CC", "cc"), str(repo / "tests/fixtures/ping-client.c"),
                    "-lX11", "-o", str(binary / "ping-client")], check=True)
    events = work / "events"
    events.touch()
    env = {**os.environ, "HOME": str(work / "home"), "XDG_CONFIG_HOME": str(work / "config"),
           "XDG_DATA_HOME": str(work / "data"), "XDG_STATE_HOME": str(work / "state"),
           "XDG_CACHE_HOME": str(work / "cache"), "DWM_TEST_EVENTS": str(events), "DWM_TEST_LEGACY_PING": "1",
           "PATH": str(binary) + ":" + os.environ["PATH"]}
    read_fd, write_fd = os.pipe()
    try:
        with (work / "xvfb.log").open("w") as log:
            xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0",
                                     "800x600x24", "-nolisten", "tcp"],
                                    pass_fds=(write_fd,), stdout=log, stderr=log)
        processes.append(xvfb)
        os.close(write_fd)
        assert select.select([read_fd], [], [], 10)[0]
        env["DISPLAY"] = ":" + os.read(read_fd, 32).decode().strip()
        os.close(read_fd)
        with (work / "dwm.log").open("w") as log:
            wm = subprocess.Popen([str(binary / "dwm")], env=env, stdout=log, stderr=log)
        processes.append(wm)
        wait_for(lambda: "_NET_SUPPORTED(ATOM)" in subprocess.run(
            ["xprop", "-root", "_NET_SUPPORTED"], env=env, capture_output=True,
            text=True, check=False).stdout, 10)
        client = subprocess.Popen([str(binary / "ping-client")], env=env,
                                  stdout=subprocess.PIPE, text=True)
        processes.append(client)
        assert select.select([client.stdout], [], [], 10)[0]
        window = client.stdout.readline().strip()
        assert window.startswith("0x")
        time.sleep(1)
        client.send_signal(signal.SIGSTOP)
        # Cover a complete five-second ping interval plus ten-second timeout.
        time.sleep(16)
        assert not events.read_text(), "Detection was enabled without opting in"
        toggle = config / "hang-detection"
        toggle.touch()
        wait_for(lambda: "hung" in events.read_text())
        # Focus and close protocols must not corrupt the outstanding ping.
        other = subprocess.Popen([str(binary / "ping-client")], env=env,
                                 stdout=subprocess.PIPE, text=True)
        processes.append(other)
        assert select.select([other.stdout], [], [], 10)[0]
        other_window = other.stdout.readline().strip()
        wait_for(lambda: int(other_window, 16) == int(subprocess.check_output(
            ["xdotool", "getactivewindow"], env=env, text=True).strip()))
        subprocess.run(["xdotool", "windowactivate", "--sync", window], env=env, check=True)
        subprocess.run(["xdotool", "key", "super+q"], env=env, check=True)
        client.send_signal(signal.SIGCONT)
        wait_for(lambda: "recovered" in events.read_text(), 5)
        client.send_signal(signal.SIGSTOP)
        wait_for(lambda: events.read_text().splitlines().count("hung") == 2)
        subprocess.run(["xprop", "-id", window, "-remove", "WM_PROTOCOLS"], env=env, check=True)
        wait_for(lambda: events.read_text().splitlines().count("recovered") == 2, 5)
        subprocess.run(["xprop", "-id", window, "-f", "WM_PROTOCOLS", "32a", "-set",
                        "WM_PROTOCOLS", "_NET_WM_PING"], env=env, check=True)
        wait_for(lambda: events.read_text().splitlines().count("hung") == 3)
        toggle.unlink()
        wait_for(lambda: events.read_text().splitlines().count("recovered") == 3, 5)
        staged = config / "hang-detection.new"
        staged.touch()
        staged.rename(toggle)
        wait_for(lambda: events.read_text().splitlines().count("hung") == 4)
        toggle.rename(staged)
        wait_for(lambda: events.read_text().splitlines().count("recovered") == 4, 5)
        # Losing the watched directory must fall back to bounded rechecks.
        config.rename(config.with_name("old-config"))
        config.mkdir()
        toggle.touch()
        wait_for(lambda: events.read_text().splitlines().count("hung") == 5, 27)
        toggle.unlink()
        wait_for(lambda: events.read_text().splitlines().count("recovered") == 5, 7)
        assert wm.poll() is None
        print("AI assist Xvfb: opt-in, hang, focus/close during pending ping, legacy replies, protocol removal/re-addition, disable PASS")
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.send_signal(signal.SIGCONT)
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
