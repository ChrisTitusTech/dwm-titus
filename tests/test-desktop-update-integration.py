#!/usr/bin/python3
"""Real source build, user worker, and polkit install in a disposable container."""
import hashlib
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
    # The managed runner's root-owned TMPDIR is not writable after dropping
    # privileges. Keep installer temporaries in this fixture's cleanup scope.
    user_tmp = base / "tmp"
    user_tmp.mkdir(mode=0o700)
    os.chown(user_tmp, uid, uid)
    os.environ["TMPDIR"] = str(user_tmp)
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
        for pending in ("preparing", "applying", "applied", "rolling-back", "rolled-back-pending"):
            journal.write_text(json.dumps({"state": pending, "uid": uid}))
            rejected = subprocess.run(["make", "install-system", "PREFIX=" + str(prefix)], cwd=source,
                                      capture_output=True, text=True)
            assert rejected.returncode != 0 and "before source installation" in rejected.stderr, rejected.stderr
            assert not prefix.exists(), "Blocked source installation replaced system files"
        print("Source installation refuses unfinished update journals before writing files: PASS", flush=True)
    finally:
        journal.unlink()
        journal.parent.rmdir()
    # Both direct targets support an unprivileged, entirely user-local prefix.
    local_prefix = Path("/home/desktop-test/local-prefix")
    for target in ("install-system", "install"):
        user("make", target, "PREFIX=" + str(local_prefix),
             "XSESSIONSDIR=" + str(local_prefix / "share/xsessions"),
             "OWNER=desktop-test", "USER_HOME=/home/desktop-test")
        assert (local_prefix / "bin/dwm").stat().st_uid == uid
    print("Unprivileged local-prefix install-system and complete install: PASS", flush=True)
    # Image/bootstrap installations have no logind-created runtime directory.
    assert not (Path("/run/user") / str(uid)).exists()
    subprocess.run(["make", "install", "PREFIX=" + str(prefix), "OWNER=desktop-test",
                    "USER_HOME=/home/desktop-test", "XDG_STATE_HOME=" + env["XDG_STATE_HOME"]],
                   cwd=source, check=True)
    config = Path("/home/desktop-test/.config")
    data = Path("/home/desktop-test/.local/share/dwm-titus")
    state = Path(env["XDG_STATE_HOME"]) / "dwm-titus/desktop-update"
    (config / "dwm-titus/themes.toml").write_text("personal-theme-marker")
    subprocess.run(["chown", "-R", "desktop-test:desktop-test", "/home/desktop-test"], check=True)
    # An unprivileged check must reject readable but root-owned managed roots
    # before package, network, or privileged transaction work can begin.
    for target in (data, config / "quickshell"):
        os.chown(target, 0, 0)
        try:
            result = subprocess.run(["runuser", "-u", "desktop-test", "--", "env",
                                     *(key + "=" + val for key, val in env.items()),
                                     "/usr/bin/python3", "-I", str(prefix / "bin/dwm-desktop-update"),
                                     "check", "--force"], capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr
            rejected = json.loads(result.stdout)
            assert rejected["state"] == "failed" and not rejected["canUpdate"], rejected
            assert "owned by the desktop user" in rejected["detail"], rejected
        finally:
            os.chown(target, uid, uid)
    user("python3", source / "scripts/dwm-desktop-update", "record-user", source)
    # A real new commit changes managed QML, the session binary, commands, and
    # the privileged helper itself, adds a palette, and retires a managed asset.
    before_manifest = json.loads((prefix / "share/dwm-titus/desktop-install.json").read_text())
    changed_commands = ("dwm-settings-wallpaper", "dwm-xsettings", "dwm-desktop-update")
    for name in (*changed_commands, "dwm-desktop-update-root"):
        path = source / "scripts" / name
        path.write_text(path.read_text() + "\n# Desktop integration update marker\n")
    core = source / "dwm.c"
    core.write_text(core.read_text().replace('die("dwm-"VERSION);', 'die("dwm-integration-"VERSION);'))
    marker = source / "config/quickshell/update-integration-marker"
    marker.write_text("updated desktop\n")
    os.chown(marker, uid, uid)
    file_link = marker.parent / "update-integration-file-link"
    directory_link = marker.parent / "update-integration-dir-link"
    file_link.symlink_to(marker.name)
    directory_link.symlink_to("settings")
    theme = source / "assets/themes/Dwm-Integration"
    shutil.copytree(source / "assets/themes/Dwm-dracula", theme)
    retired = source / "assets/themes/Dwm-dracula/gtk-2.0/gtkrc"
    retired.unlink()
    subprocess.run(["chown", "-R", "desktop-test:desktop-test", theme], check=True)
    user("git", "add", "config/quickshell", "scripts", "dwm.c", "assets/themes")
    user("git", "commit", "-m", "Update managed shell and system executables")
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
original_popen = update.subprocess.Popen
elevations = []
def counted_popen(args, *positional, **kwargs):
    if str(args[0]) == "/usr/bin/pkexec":
        elevations.append(args)
    return original_popen(args, *positional, **kwargs)
update.subprocess.Popen = counted_popen
state = update.paths()[2]
operation = "d" * 32
directory = state / "operations" / operation
directory.mkdir(parents=True)
manifest = Path(sys.argv[2]) / "share/dwm-titus/desktop-install.json"
preview = dict(update.status_default(), available=sys.argv[3], generation=update.digest(manifest), manifest=str(manifest))
update.write_json(directory / "preview.json", preview)
update.write_json(state / "status.json", dict(preview, operation=operation, state="starting"))
result = update.worker(operation)
assert len(elevations) == 1, elevations
assert elevations[0][2:5] == ["session", "update", operation], elevations
sys.exit(result)
''')
        try:
            user("python3", runner, source, prefix, revision)
        except subprocess.CalledProcessError:
            log = state / "operations" / ("d" * 32) / "update.log"
            print(log.read_text() if log.exists() else "Worker did not create a log")
            raise
        status = json.loads((state / "status.json").read_text())
        assert status["state"] == "restart-required", status
        after_manifest = json.loads((prefix / "share/dwm-titus/desktop-install.json").read_text())
        assert after_manifest["revision"] == revision
        assert str(prefix / "share/themes/Dwm-Integration/gtk-3.0/gtk.css") in after_manifest["files"]
        assert (prefix / "share/themes/Dwm-Integration/gtk-3.0/gtk.css").is_file()
        assert not (prefix / "share/themes/Dwm-dracula/gtk-2.0/gtkrc").exists()
        changed_system = [prefix / "bin" / name for name in ("dwm", *changed_commands)]
        changed_system.append(Path(helper))
        for path in changed_system:
            record = after_manifest["files"][str(path)]
            assert record["sha256"] != before_manifest["files"][str(path)]["sha256"], path
            assert record["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest(), path
            assert path.stat().st_uid == 0 and path.stat().st_mode & 0o7777 == 0o755, path
        assert (config / "quickshell/update-integration-marker").read_text() == "updated desktop\n"
        assert (config / "dwm-titus/themes.toml").read_text() == "personal-theme-marker"
        assert (config / "quickshell" / file_link.name).read_text() == marker.read_text()
        assert not (config / "quickshell" / file_link.name).is_symlink()
        assert (config / "quickshell" / directory_link.name / "DesktopUpdateModel.qml").is_file()
        assert not (config / "quickshell" / directory_link.name).is_symlink()
        assert (prefix / "bin/dwm").stat().st_uid == 0
        assert (prefix / "share/icons/Capitaine-Cursors-White/cursors").stat().st_uid == 0
        user("python3", prefix / "bin/dwm-desktop-update", "verify-receipts", source,
             prefix / "share/dwm-titus/desktop-install.json")
        print("Real Fedora build / user worker / polkit installation: PASS", flush=True)
    finally:
        polkit.terminate()
        polkit.wait(timeout=10)
        rule.unlink(missing_ok=True)
