#!/usr/bin/python3
"""Real source build, user worker, and polkit install in a disposable container."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

if os.geteuid() != 0 or not Path("/run/.containerenv").exists():
    sys.exit("Run only as root in a disposable Fedora container")
os.umask(0o002)
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="desktop-integration-", dir="/opt") as temporary:
    base = Path(temporary)
    base.chmod(0o755)
    source = base / "source"
    prefix = base / "installed"
    source.mkdir()
    subprocess.run(["useradd", "-m", "desktop-test"], check=True)
    uid = int(subprocess.check_output(["id", "-u", "desktop-test"], text=True))
    for name in (".gitignore", "Makefile", "config.mk", "config.def.h", "dwm.c", "drw.c", "util.c", "tomlparser.c",
                 "drw.h", "util.h", "tomlparser.h", "dwm.1", "dwm.desktop", "scripts", "config", "assets"):
        if (repo / name).is_dir():
            shutil.copytree(repo / name, source / name, symlinks=True)
        else:
            shutil.copyfile(repo / name, source / name)
    subprocess.run(["chown", "-R", "desktop-test:desktop-test", source], check=True)
    env = {"HOME": "/home/desktop-test", "USER": "desktop-test", "PATH": str(prefix / "bin") + ":/usr/bin:/bin",
           "XDG_STATE_HOME": "/home/desktop-test/state with spaces"}

    def user(*args):
        subprocess.run(["runuser", "-u", "desktop-test", "--", "env", *(key + "=" + val for key, val in env.items()),
                        *(str(arg) for arg in args)], check=True, cwd=source)

    user("git", "init", "-b", "main")
    user("git", "config", "user.email", "desktop-test@example.invalid")
    user("git", "config", "user.name", "Desktop update test")
    user("git", "add", ".")
    user("git", "commit", "-m", "Baseline desktop")
    user("make", "clean", "all")
    journal = Path("/var/lib/dwm-titus/desktop-updates") / ("e" * 32) / "journal.json"
    previous_umask = os.umask(0o022)
    journal.parent.mkdir(parents=True, mode=0o700)
    os.umask(previous_umask)
    try:
        for pending in ("applying", "applied", "rolling-back", "rolled-back-pending"):
            journal.write_text(json.dumps({"state": pending, "uid": uid}))
            rejected = subprocess.run(["make", "install-system", "PREFIX=" + str(prefix)], cwd=source,
                                      capture_output=True, text=True)
            assert rejected.returncode != 0 and "before source installation" in rejected.stderr, rejected.stderr
            assert not prefix.exists(), "Blocked source installation replaced system files"
        print("Source installation refuses unfinished update journals before writing files: PASS", flush=True)
    finally:
        journal.unlink()
        journal.parent.rmdir()
    subprocess.run(["make", "install-system", "PREFIX=" + str(prefix)], cwd=source, check=True)
    config = Path("/home/desktop-test/.config")
    data = Path("/home/desktop-test/.local/share/dwm-titus")
    state = Path(env["XDG_STATE_HOME"]) / "dwm-titus/desktop-update"
    for original, target in ((source / "config", data / "config"), (source / "scripts", data / "scripts"),
                             (source / "config/quickshell", config / "quickshell")):
        shutil.copytree(original, target, symlinks=True)
    (config / "dwm-titus").mkdir()
    (config / "dwm-titus/themes.toml").write_text("personal-theme-marker")
    subprocess.run(["chown", "-R", "desktop-test:desktop-test", "/home/desktop-test"], check=True)
    user("python3", source / "scripts/dwm-desktop-update", "record-user", source)
    # A real new commit changes managed QML without changing the privileged layout.
    marker = source / "config/quickshell/update-integration-marker"
    marker.write_text("updated desktop\n")
    os.chown(marker, uid, uid)
    user("git", "add", "config/quickshell/update-integration-marker")
    user("git", "commit", "-m", "Update managed shell")
    revision = subprocess.check_output(["git", "-c", "safe.directory=" + str(source), "-C", source, "rev-parse", "HEAD"], text=True).strip()
    rule = Path("/etc/polkit-1/rules.d/00-desktop-update-test.rules")
    helper = str(prefix / "libexec/dwm-titus/dwm-desktop-update-root")
    rule.write_text('polkit.addRule(function(action, subject) { if (action.id === "org.freedesktop.policykit.exec" '
                    '&& action.lookup("program") === ' + json.dumps(helper) + ' && subject.user === "desktop-test") '
                    'return polkit.Result.YES; });\n')
    Path("/run/dbus").mkdir(exist_ok=True)
    subprocess.run(["dbus-daemon", "--system", "--fork", "--nopidfile"], check=True)
    polkit = subprocess.Popen(["/usr/lib/polkit-1/polkitd", "--no-debug"])
    try:
        time.sleep(1)
        runner = base / "run-worker.py"
        runner.write_text('''import importlib.machinery, importlib.util, json, sys
from pathlib import Path
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("desktop", sys.argv[1] + "/scripts/dwm-desktop-update")
spec = importlib.util.spec_from_loader("desktop", loader)
update = importlib.util.module_from_spec(spec)
loader.exec_module(update)
update.SOURCE = sys.argv[1]
official_trust = update.trusted_installation
def trust(path):
    local_source = update.SOURCE
    update.SOURCE = "https://github.com/ChrisTitusTech/dwm-titus.git"
    try: official_trust(path)
    finally: update.SOURCE = local_source
update.trusted_installation = trust
state = update.paths()[2]
operation = "d" * 32
directory = state / "operations" / operation
directory.mkdir(parents=True)
manifest = Path(sys.argv[2]) / "share/dwm-titus/desktop-install.json"
preview = dict(update.status_default(), available=sys.argv[3], generation=update.digest(manifest), manifest=str(manifest))
update.write_json(directory / "preview.json", preview)
update.write_json(state / "status.json", dict(preview, operation=operation, state="starting"))
sys.exit(update.worker(operation))
''')
        try:
            user("python3", runner, source, prefix, revision)
        except subprocess.CalledProcessError:
            log = state / "operations" / ("d" * 32) / "update.log"
            print(log.read_text() if log.exists() else "Worker did not create a log")
            raise
        status = json.loads((state / "status.json").read_text())
        assert status["state"] == "restart-required", status
        assert json.loads((prefix / "share/dwm-titus/desktop-install.json").read_text())["revision"] == revision
        assert (config / "quickshell/update-integration-marker").read_text() == "updated desktop\n"
        assert (config / "dwm-titus/themes.toml").read_text() == "personal-theme-marker"
        assert (prefix / "bin/dwm").stat().st_uid == 0
        assert (prefix / "share/icons/Capitaine-Cursors-White/cursors").stat().st_uid == 0
        user("python3", prefix / "bin/dwm-desktop-update", "verify-receipts", source,
             prefix / "share/dwm-titus/desktop-install.json")
        print("Real Fedora build / user worker / polkit installation: PASS", flush=True)
    finally:
        polkit.terminate()
        polkit.wait(timeout=10)
        rule.unlink(missing_ok=True)
