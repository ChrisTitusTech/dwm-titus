#!/usr/bin/env python3
"""Compare PR 425's text cards and static thumbnails on a private Xvfb display.

Run through scripts/run-tests and xvfb-run. Only synthetic fixture windows are
captured. Output JSON is suitable for keeping alongside the benchmark report.
"""
import argparse
import ctypes as C
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("overview_benchmark", str(repo / "scripts/dwm-window-overview"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)


def run(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check, timeout=20)


def wait(predicate, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError(message)


def process_stats(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        # Include reaped descendants; still-running descendants are added below.
        ticks = sum(int(fields[index]) for index in (11, 12, 13, 14))
        rss = int(fields[21]) * os.sysconf("SC_PAGE_SIZE")
        children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        return ticks, rss, [int(child) for child in children]
    except (FileNotFoundError, ProcessLookupError):
        return 0, 0, []


def tree_stats(pid):
    ticks, rss, children = process_stats(pid)
    for child in children:
        child_ticks, child_rss = tree_stats(child)
        ticks += child_ticks
        rss += child_rss
    return ticks, rss


def xserver_pid():
    display = os.environ["DISPLAY"].split(".")[0].encode()
    for path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            command = path.read_bytes().split(b"\0")
            if command and Path(os.fsdecode(command[0])).name == "Xvfb" and display in command:
                return int(path.parent.name)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    raise RuntimeError("Benchmark requires a private Xvfb server")


def summarize(samples, name):
    values = sorted(sample[name] for sample in samples)
    return {"median": round(statistics.median(values), 3),
        "p95": round(values[(95 * len(values) + 99) // 100 - 1], 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="0cae78af16cc2c0a94befe62eac092fe013624be")
    parser.add_argument("--windows", type=int, default=20)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--reverse-order", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args()
    if not 1 <= args.windows <= module.Thumbnails.LIMIT or args.iterations < 2:
        parser.error("use 1..64 windows and at least two iterations")
    if not 1 <= args.width <= 16384 or not 1 <= args.height <= 16384:
        parser.error("use source dimensions in 1..16384")
    server = xserver_pid()
    processes = []
    connection = None
    with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory, tempfile.TemporaryDirectory(prefix="qs-overview-bench-", dir="/tmp") as runtime:
        work = Path(directory)
        os.environ.update(HOME=str(work / "home"), XDG_CONFIG_HOME=str(work / "config"),
            XDG_DATA_HOME=str(work / "data"), XDG_STATE_HOME=str(work / "state"),
            XDG_CACHE_HOME=str(work / "cache"), XDG_RUNTIME_DIR=runtime,
            QT_QUICK_BACKEND="software", QSG_RHI_BACKEND="software")
        config = work / "config/dwm-titus"
        config.mkdir(parents=True)
        for name in ("hotkeys.toml", "themes.toml", "window-rules.toml"):
            shutil.copy(repo / "config" / name, config / name)
        baseline = work / "baseline"
        baseline.mkdir()
        archive = run("git", "rev-parse", args.baseline).stdout.strip()
        data = subprocess.check_output(["git", "archive", archive, "scripts/dwm-window-overview", "config/quickshell"])
        with tarfile.open(fileobj=io.BytesIO(data)) as source:
            source.extractall(baseline, filter="data")
        try:
            with (work / "dwm.log").open("w") as log:
                wm = subprocess.Popen([str(repo / "dwm")], stdout=log, stderr=log)
            processes.append(wm)
            connection = module.Connection()
            wait(lambda: connection.state().get("available"), "dwm did not start")
            x, d, root = connection.x, connection.display, connection.root
            x.XGetSelectionOwner.argtypes = [C.c_void_p, C.c_ulong]
            x.XGetSelectionOwner.restype = C.c_ulong
            with (work / "picom.log").open("w") as log:
                compositor = subprocess.Popen(["picom", "--config", "/dev/null", "--backend", "xrender"], stdout=log, stderr=log)
            processes.append(compositor)
            wait(lambda: x.XGetSelectionOwner(d, connection.atom("_NET_WM_CM_S0")), "Picom did not start")
            x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
            x.XStoreName.argtypes = [C.c_void_p, C.c_ulong, C.c_char_p]
            x.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
            x.XSync.argtypes = [C.c_void_p, C.c_int]
            x.XCreateGC.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_void_p]
            x.XCreateGC.restype = C.c_void_p
            x.XSetForeground.argtypes = [C.c_void_p, C.c_void_p, C.c_ulong]
            x.XFillRectangle.argtypes = [C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint]
            x.XFreeGC.argtypes = [C.c_void_p, C.c_void_p]
            ids = []
            for index in range(args.windows):
                window = x.XCreateSimpleWindow(d, root, 0, 0, args.width, args.height, 0, 0, 0xf1f3f5)
                x.XStoreName(d, window, f"Benchmark document {index + 1}".encode())
                dialog = C.c_ulong(connection.atom("_NET_WM_WINDOW_TYPE_DIALOG"))
                x.XChangeProperty(d, window, connection.atom("_NET_WM_WINDOW_TYPE"), 4, 32, 0, C.byref(dialog), 1)
                x.XMapWindow(d, window)
                x.XSync(d, False)
                wait(lambda: any(row["id"] == str(window) for row in connection.state()["windows"]), "Fixture window not managed")
                # Retain exact source sizes; floating clients are not tiled by
                # the overview. A deterministic document-like pattern avoids a
                # misleading all-solid-color PNG workload.
                gc = x.XCreateGC(d, window, 0, None)
                for line in range(180):
                    x.XSetForeground(d, gc, (0x34506a, 0x7194a8, 0xc1d4de)[(line + index) % 3])
                    x.XFillRectangle(d, window, gc, 35 + (line % 5) * 9,
                        20 + line * max(3, args.height // 190),
                        max(30, args.width * (3 + line % 7) // 12), 2 + line % 5)
                x.XFreeGC(d, gc)
                x.XSync(d, False)
                run("xdotool", "set_desktop_for_window", str(window), str(index % 9))
                ids.append(window)
            attributes = module.WindowAttributes()
            x.XGetWindowAttributes.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(module.WindowAttributes)]
            dimensions = []
            for window in ids:
                x.XGetWindowAttributes(d, window, C.byref(attributes))
                dimensions.append([attributes.width, attributes.height])
            assert all(size == [args.width, args.height] for size in dimensions), dimensions
            time.sleep(.3)
            results = {}
            variants = [("text_cards", baseline), ("static_thumbnails", repo)]
            if args.reverse_order:
                variants.reverse()
            for name, source in variants:
                helpers = work / "data/dwm-titus/scripts"
                helpers.mkdir(parents=True, exist_ok=True)
                helper = helpers / "dwm-window-overview"
                helper.unlink(missing_ok=True)
                helper.symlink_to(source / "scripts/dwm-window-overview")
                qml = work / name
                qml.mkdir()
                for component in ("core", "overview", "assets"):
                    (qml / component).symlink_to(source / "config/quickshell" / component)
                (qml / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "overview"
ShellRoot {
    id: harness
    property var view: null
    property double started: 0
    property double visibleAt: 0
    property double readyAt: 0
    WindowOverviewModel { id: provider; onVisibleChanged: if (visible) harness.visibleAt = Date.now() }
    LazyLoader { active: provider.visible; component: WindowOverviewWindow {
        model: provider; Component.onCompleted: harness.view = this; Component.onDestruction: harness.view = null
    } }
    function loaded(item: var): bool {
        if (item.objectName.startsWith("windowThumbnail") && item.source.toString() && item.status !== Image.Ready) return false;
        for (const child of item.children || []) if (!loaded(child)) return false;
        return true;
    }
    Timer {
        interval: 5; repeat: true; running: provider.visible && harness.readyAt === 0
        onTriggered: {
            if (provider.windows.length !== WINDOW_COUNT || !harness.view) return;
            if (WITH_THUMBNAILS && (provider.thumbnailsPending || provider.windows.some(row => !row.thumbnail))) return;
            if (harness.loaded(harness.view.contentItem)) harness.readyAt = Date.now();
        }
    }
    IpcHandler {
        target: "overviewBenchmark"
        function open(): void { harness.started = Date.now(); harness.visibleAt = 0; harness.readyAt = 0; provider.openOnScreen(Quickshell.screens[0]); }
        function close(): void { provider.close(); }
        function state(): string { return JSON.stringify({visible:provider.visible,busy:provider.busy,
            opened:harness.visibleAt ? harness.visibleAt - harness.started : -1,
            ready:harness.readyAt ? harness.readyAt - harness.started : -1, rows:provider.windows}); }
    }
}
'''.replace("WINDOW_COUNT", str(args.windows)).replace("WITH_THUMBNAILS", "true" if name == "static_thumbnails" else "false"))
                with (work / f"{name}.log").open("w") as log:
                    shell = subprocess.Popen(["quickshell", "--no-duplicate", "--path", str(qml / "shell.qml")], stdout=log, stderr=log)
                processes.append(shell)
                connection.exclude_pid = shell.pid
                def ipc(method):
                    return run("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "overviewBenchmark", method, check=False)
                def state():
                    reply = ipc("state")
                    return json.loads(reply.stdout) if reply.returncode == 0 else {}
                wait(lambda: ipc("state").returncode == 0, "QML did not load: " + (work / f"{name}.log").read_text())
                samples = []
                monitored = [shell.pid, wm.pid, compositor.pid, server]
                def totals():
                    stats = [tree_stats(pid) for pid in monitored]
                    return sum(value[0] for value in stats), sum(value[1] for value in stats)
                for iteration in range(args.iterations + 2):
                    done = threading.Event()
                    peak = [0, 0]
                    def sample_memory():
                        while not done.is_set():
                            peak[0] = max(peak[0], totals()[1])
                            peak[1] = max(peak[1], tree_stats(shell.pid)[1])
                            done.wait(.005)
                    sampler = threading.Thread(target=sample_memory)
                    before_cpu, before_rss = totals()
                    sampler.start()
                    try:
                        assert ipc("open").returncode == 0
                        ready = wait(lambda: (value if value.get("ready", -1) >= 0 else None) if (value := state()) else None,
                            "Opening did not finish: " + (work / f"{name}.log").read_text())
                    finally:
                        done.set()
                        sampler.join()
                    after_cpu, open_rss = totals()
                    image_bytes = 0
                    for row in ready["rows"]:
                        if row.get("thumbnail"):
                            from urllib.parse import unquote, urlparse
                            image_bytes += Path(unquote(urlparse(row["thumbnail"]).path)).stat().st_size
                    sample = {"open_ms": ready["opened"], "ready_ms": ready["ready"],
                        "cpu_ms": (after_cpu - before_cpu) * 1000 / os.sysconf("SC_CLK_TCK"),
                        "open_rss_mib": open_rss / 1048576, "peak_rss_mib": peak[0] / 1048576,
                        "open_shell_rss_mib": tree_stats(shell.pid)[1] / 1048576,
                        "peak_shell_rss_mib": peak[1] / 1048576,
                        "opening_rss_delta_mib": (peak[0] - before_rss) / 1048576,
                        "image_files_kib": image_bytes / 1024}
                    if iteration >= 2:
                        samples.append(sample)
                    if iteration == args.iterations + 1:
                        if name == "static_thumbnails" and args.screenshot:
                            from PIL import ImageGrab
                            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
                            time.sleep(.1)
                            ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(args.screenshot)
                        idle_before = totals()[0]
                        time.sleep(2)
                        open_idle_cpu = (totals()[0] - idle_before) * 1000 / os.sysconf("SC_CLK_TCK")
                    assert ipc("close").returncode == 0
                    wait(lambda: not state().get("visible", True) and not state().get("busy", True), "Close did not finish")
                    time.sleep(.05)
                closed_cpu = totals()[0]
                time.sleep(2)
                idle_cpu = (totals()[0] - closed_cpu) * 1000 / os.sysconf("SC_CLK_TCK")
                results[name] = {"summary": {key: summarize(samples, key) for key in samples[0]},
                    "open_idle_cpu_ms_per_2s": open_idle_cpu,
                    "closed_idle_cpu_ms_per_2s": idle_cpu, "samples": samples}
                shell.terminate()
                shell.wait(timeout=5)
                processes.remove(shell)
            runtime_paths = ["scripts/dwm-window-overview", "config/quickshell/overview/WindowOverviewModel.qml",
                "config/quickshell/overview/WindowOverviewWindow.qml"]
            report = {"baseline_commit": archive, "candidate_head": run("git", "rev-parse", "HEAD").stdout.strip(),
                "candidate_uncommitted": bool(run("git", "status", "--porcelain").stdout),
                "candidate_sources_sha256": {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in runtime_paths},
                "environment": {"platform": platform.platform(),
                    "processor": next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), platform.processor()),
                    "quickshell": run("quickshell", "--version").stdout.strip(),
                    "picom": run("picom", "--version").stdout.strip(), "renderer": "Xvfb + Picom XRender + Qt software",
                    "server_screen": run("xdpyinfo").stdout.split("dimensions:", 1)[1].splitlines()[0].strip()},
                "workload": {"windows": args.windows, "source_pixels": [args.width, args.height],
                    "iterations": args.iterations, "warmups_per_variant": 2, "memory_sample_ms": 5,
                    "cpu_tick_ms": 1000 / os.sysconf("SC_CLK_TCK"), "variant_order": list(results)},
                "results": results}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({name: value["summary"] for name, value in results.items()}, indent=2))
        finally:
            if sys.exc_info()[0]:
                for log in work.glob("*.log"):
                    print(log.name + ": " + log.read_text()[-4000:], file=sys.stderr)
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            if connection:
                connection.close()


if __name__ == "__main__":
    main()
