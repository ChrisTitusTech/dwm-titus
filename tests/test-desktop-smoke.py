#!/usr/bin/env python3
"""Start the managed desktop and exercise its launcher in a private X11 session."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def main():
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    for command in ("Xvfb", "dbus-daemon", "quickshell", "xdotool", "xprop"):
        if not shutil.which(command):
            raise RuntimeError(f"Missing required smoke-test command: {command}")
    # Quickshell's IPC socket must fit Linux's 108-byte Unix socket path limit.
    # Keep runtime files out of the deeply nested managed test workspace.
    runtime_parent = os.environ["XDG_RUNTIME_DIR"]
    with tempfile.TemporaryDirectory(prefix="qs-", dir=runtime_parent) as runtime, \
            tempfile.TemporaryDirectory(prefix="desktop-smoke-") as directory:
        work = Path(directory)
        config = work / "config"
        data = work / "data"
        shutil.copytree(REPO / "config/quickshell", config / "quickshell")
        (config / "dwm-titus").mkdir()
        for source in (REPO / "config").glob("*.toml"):
            shutil.copy(source, config / "dwm-titus")
        (data / "dwm-titus").mkdir(parents=True)
        (data / "dwm-titus/scripts").symlink_to(REPO / "scripts", target_is_directory=True)
        applications = data / "applications"
        applications.mkdir()
        (applications / "smoke.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=DwmSmokeApp\n"
            f'Exec=touch "{work}/launched"\nTerminal=false\nCategories=Utility;\n')
        env = {**os.environ, "HOME": str(work), "XDG_CONFIG_HOME": str(config),
               "XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data),
               "XDG_STATE_HOME": str(work / "state"), "XDG_CACHE_HOME": str(work / "cache"),
               "XDG_RUNTIME_DIR": runtime, "QT_QPA_PLATFORM": "xcb",
               "QT_QUICK_BACKEND": "software", "QT_QPA_PLATFORMTHEME": "",
               "PATH": f"{REPO / 'scripts'}:{os.environ['PATH']}"}
        processes = []
        with (work / "desktop.log").open("w+") as log:
            def start(args, **kwargs):
                process = subprocess.Popen(args, env=env, stdout=log, stderr=log, **kwargs)
                processes.append(process)
                return process

            def run(*args):
                return subprocess.run(args, env=env, capture_output=True, text=True, timeout=3)

            def wait_for(label, predicate):
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if any(process.poll() is not None for process in processes):
                        raise RuntimeError(f"Desktop process exited while waiting for {label}")
                    if predicate():
                        return
                    time.sleep(0.1)
                raise RuntimeError(f"Timed out waiting for {label}")

            def ipc(method):
                return run("quickshell", "ipc", "--path", str(config / "quickshell/shell.qml"),
                           "call", "launcher", method)

            def launcher_visible():
                return run("xdotool", "search", "--onlyvisible", "--name", "^dwm launcher$").returncode == 0

            try:
                with (work / "display").open("w+") as display_file:
                    start(["Xvfb", "-displayfd", str(display_file.fileno()), "-screen", "0",
                           "1024x768x24", "-nolisten", "tcp"], pass_fds=(display_file.fileno(),))
                    wait_for("Xvfb display", lambda: (work / "display").stat().st_size > 0)
                    env["DISPLAY"] = ":" + (work / "display").read_text().strip()
                wait_for("X11 readiness", lambda: run("xprop", "-root").returncode == 0)
                env.pop("DBUS_SESSION_BUS_ADDRESS", None)
                with (work / "bus-address").open("w+") as bus_file:
                    start(["dbus-daemon", "--session", "--nofork",
                           f"--print-address={bus_file.fileno()}"], pass_fds=(bus_file.fileno(),))
                    wait_for("private D-Bus", lambda: (work / "bus-address").stat().st_size > 0)
                    env["DBUS_SESSION_BUS_ADDRESS"] = (work / "bus-address").read_text().strip()
                start([str(REPO / "dwm")])
                wait_for("dwm readiness", lambda: "= 0" in run("xprop", "-root", "_NET_CURRENT_DESKTOP").stdout)
                shell = start(["quickshell", "--no-duplicate"])
                wait_for("Quickshell IPC", lambda: ipc("close").returncode == 0)

                def panel_visible():
                    windows = run("xdotool", "search", "--onlyvisible", "--pid", str(shell.pid)).stdout.split()
                    for window in windows:
                        geometry = run("xdotool", "getwindowgeometry", "--shell", window).stdout.splitlines()
                        if "HEIGHT=30" in geometry and "WIDTH=1024" in geometry:
                            return True
                    return False

                wait_for("managed panel", panel_visible)
                run("xdotool", "key", "--clearmodifiers", "super+r").check_returncode()
                wait_for("launcher hotkey", launcher_visible)
                wait_for("application index", lambda: int(ipc("indexCount").stdout.strip() or "0") > 0)
                run("xdotool", "key", "Escape").check_returncode()
                wait_for("launcher dismissal", lambda: not launcher_visible())
                run("xdotool", "key", "--clearmodifiers", "super+r").check_returncode()
                wait_for("launcher reopen", launcher_visible)
                run("xdotool", "type", "--clearmodifiers", "--delay", "1", "DwmSmokeApp").check_returncode()
                run("xdotool", "key", "Return").check_returncode()
                wait_for("application launch", lambda: (work / "launched").exists())
                wait_for("launcher close after launch", lambda: not launcher_visible())
                ipc("indexCount").check_returncode()
                print("PASS: dwm, Quickshell panel, Super+R, Escape, and application launch", flush=True)
            except BaseException:
                log.flush()
                print((work / "desktop.log").read_text(), file=sys.stderr)
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                for process in reversed(processes):
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    main()
