"""Build isolated custom config.h variants and exercise semantic layout requests."""
import ctypes as C
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("layout_caps", str(repo / "scripts/dwm-layout-settings"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)


def wait(predicate):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError("Custom layout state did not converge")


variants = [
    ("reordered", '{"mono", monocle}, {"float", NULL}, {"tile", tile}', "", 2, 7),
    ("floating-only", '{"float", NULL}', "", 1, 2),
    ("extra-custom", '{"custom", customlayout}, {"mono", monocle}, {"tile", tile}, {"float", NULL}',
        "static void customlayout(Monitor *m) { monocle(m); }\n", -1, 7),
]
with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
    work = Path(directory)
    modules = "x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res fontconfig freetype2".split()
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", *modules], text=True))
    for name, entries, custom, initial, choices in variants:
        build = work / name
        build.mkdir()
        for pattern in ("*.c", "*.h"):
            for source in repo.glob(pattern):
                if source.name != "config.h":
                    shutil.copy(source, build / source.name)
        header = (repo / "config.def.h").read_text()
        header, count = re.subn(r"static const Layout layouts\[\] = \{.*?\n\};",
            lambda _: custom + "static const Layout layouts[] = {" + entries + "};", header, count=1, flags=re.S)
        assert count == 1
        (build / "config.h").write_text(header)
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + ["-std=c99", "-D_DEFAULT_SOURCE", "-D_BSD_SOURCE",
            "-D_XOPEN_SOURCE=700L", '-DVERSION="layout-capability-test"', "-DXINERAMA", "-I", str(build),
            *[str(build / source) for source in ("dwm.c", "drw.c", "util.c", "tomlparser.c")],
            "-o", str(build / "dwm"), *flags], check=True)
        config = build / "config/dwm-titus"
        config.mkdir(parents=True)
        for item in ("hotkeys.toml", "themes.toml", "window-rules.toml"):
            shutil.copy(repo / "config" / item, config / item)
        env = {**os.environ, "HOME": str(build), "XDG_CONFIG_HOME": str(config.parent), "XDG_DATA_HOME": str(build / "data")}
        with (build / "dwm.log").open("w") as log:
            wm = subprocess.Popen([str(build / "dwm")], env=env, stdout=log, stderr=log)
            connection = module.Connection()
            try:
                wait(lambda: connection.state().get("available"))
                state = connection.state()
                assert (state["layout"], state["choices"]) == (initial, choices), (name, state)
                for kind in range(3):
                    args = [str(repo / "scripts/dwm-layout-settings"), "set", "layout", str(kind),
                        str(state["monitor"]), str(state["tags"]), str(state["owner"])]
                    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
                    if choices & (1 << kind):
                        assert result.returncode == 0, result.stderr
                        assert json.loads(result.stdout)["layout"] == kind
                    else:
                        assert result.returncode != 0 and "does not provide" in result.stderr
                        connection.change(0, kind, state["monitor"], state["tags"], state["owner"])
                        connection.x.XSync.argtypes = [C.c_void_p, C.c_int]
                        connection.x.XSync(connection.display, False)
                        time.sleep(.05)
                        assert connection.state()["layout"] == initial
                print(f"Custom layouts {name}: semantic requests and availability PASS")
            finally:
                wm.terminate()
                wm.wait(timeout=5)
                connection.close()
