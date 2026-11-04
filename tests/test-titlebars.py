"""Exercise opt-in native decorations under an isolated real dwm."""
import os
from pathlib import Path
import select
import shlex
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
    work = Path(directory)
    env = {**os.environ, "HOME": str(work / "home"), "XDG_CONFIG_HOME": str(work / "config"),
        "XDG_DATA_HOME": str(work / "data"), "XDG_STATE_HOME": str(work / "state"), "XDG_CACHE_HOME": str(work / "cache")}
    config = work / "config/dwm-titus"
    config.mkdir(parents=True)
    for name in ("hotkeys.toml", "themes.toml", "window-rules.toml"):
        shutil.copy(repo / "config" / name, config / name)
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "x11"], text=True)
    subprocess.run(shlex.split(os.environ.get("CC", "cc")) + ["-std=c99", "-Wall", "-Wextra", "-Werror",
        str(repo / "tests/fixtures/titlebar-client.c"), "-o", str(work / "client")] + shlex.split(flags), check=True)
    processes = []
    with open(work / "dwm.log", "w") as log:
        try:
            wm = subprocess.Popen([str(repo / "dwm")], env=env, stdout=log, stderr=log)
            processes.append(wm)
            time.sleep(.3)
            fixture = subprocess.Popen([str(work / "client"), str(config / "themes.toml")], env=env,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append(fixture)
            assert select.select([fixture.stdout], [], [], 20)[0], "Fixture did not reach screenshot checkpoint"
            line = fixture.stdout.readline()
            if line.strip() != "SCREENSHOT_READY":
                raise AssertionError(f"Fixture startup failed: {line} {fixture.stderr.read()}\n{(work / 'dwm.log').read_text()}")
            evidence = os.environ.get("DWM_FEATURE_EVIDENCE_DIR")
            if evidence:
                from PIL import ImageGrab
                Path(evidence).mkdir(parents=True, exist_ok=True)
                ImageGrab.grab(xdisplay=env["DISPLAY"]).save(Path(evidence) / "floating-titlebars.png")
            before = sum(map(int, Path(f"/proc/{wm.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            time.sleep(2)
            after = sum(map(int, Path(f"/proc/{wm.pid}/stat").read_text().rsplit(")", 1)[1].split()[11:13]))
            assert after - before <= 15, f"Native titlebar idle CPU ticks/2s: {after-before}"
            output, error = fixture.communicate("\n", timeout=60)
            assert fixture.returncode == 0, f"{output}\n{error}\n{(work / 'dwm.log').read_text()}"
            print(output.strip())
            print(f"Native dwm idle CPU ticks/2s={after-before}")
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
