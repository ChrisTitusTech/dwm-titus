#!/usr/bin/python3
"""Exercise the real worker with isolated Git/build/authorization boundaries."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile

sys.dont_write_bytecode = True
repo, base, scenario = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
loader = importlib.machinery.SourceFileLoader("worker", str(repo / "scripts/dwm-desktop-update"))
spec = importlib.util.spec_from_loader("worker", loader)
update = importlib.util.module_from_spec(spec)
loader.exec_module(update)
config, data, state = base / "config", base / "data", base / "state"
for path in (config / "quickshell", data / "config", data / "scripts", state):
    path.mkdir(parents=True, exist_ok=True)
    (path / "file").write_text("old")
personal = config / "dwm-titus/themes.toml"
personal.parent.mkdir()
personal.write_text("personal theme")
(state / "build-config.h").write_text("personal build config")
prefix = base / "prefix"
binary = prefix / "bin/dwm"
binary.parent.mkdir(parents=True)
binary.write_text("new binary")
binary.chmod(0o755)
manifest_path = prefix / "share/dwm-titus/desktop-install.json"
manifest = {"schema": 1, "source": update.SOURCE, "revision": "a" * 40, "packages": [],
            "layout": {"prefix": str(prefix), "manprefix": str(prefix / "share/man"),
                       "xsessions": str(prefix / "xsessions"), "datadir": str(prefix / "share")},
            "files": {str(binary): update.fingerprint(binary)}}
update.write_json(manifest_path, manifest)
binary.write_text("old binary")
operation = "c" * 32
directory = state / "operations" / operation
directory.mkdir(parents=True)
preview = {**update.status_default(), "available": "b" * 40, "generation": update.digest(manifest_path),
           "manifest": str(manifest_path)}
update.write_json(directory / "preview.json", preview)
update.write_json(state / "status.json", {**preview, "operation": operation, "state": "starting"})
update.paths = lambda: (config, data, state)
update.source_revision = lambda source: "b" * 40
update.missing_packages = lambda packages: []
update.running_dwm_matches = lambda path: scenario.startswith("activation-")
shell_reads = 0


def shell_processes():
    global shell_reads
    shell_reads += 1
    return {("1", "old")} if shell_reads == 1 or scenario == "activation-stale" else {("2", "new")}


def activation(prefix, identity):
    if scenario == "activation-failure":
        raise RuntimeError("restart failed")


update.quickshell_processes = shell_processes
update.start_activation = activation
update.time.sleep = lambda delay: None
update.trusted_installation = lambda path: None
update.trusted_directory = lambda path: None
update.root_owned = lambda path: True
real_sync = update.sync_directory
def sync_directory(path):
    if scenario == "durability-failure" and path == data.parent and (data / "scripts/file").read_text() == "new helper":
        raise OSError("injected directory sync failure")
    real_sync(path)
update.sync_directory = sync_directory
source, stage = directory / "source", directory / "stage"


def boundary(args, cwd=None, timeout=60, capture=True):
    args = [str(arg) for arg in args]
    if args[:2] == ["git", "init"]:
        (source / "config/quickshell").mkdir(parents=True)
        (source / "scripts").mkdir()
        (source / "config/quickshell/file").write_text("new shell")
        (source / "scripts/file").write_text("new helper")
    elif args[:3] == ["make", "clean", "all"]:
        for key in ("CC", "CFLAGS", "CPPFLAGS", "LDFLAGS"):
            if key in os.environ:
                assert key + "=" + os.environ[key] in args
        if scenario in ("build-failure", "cleanup-completion-denied"):
            raise update.CommandFailure("build failed", 2)
        assert (source / "config.h").read_text() == "personal build config"
    elif args[:2] == ["make", "install-system"]:
        staged_binary = stage / str(binary).lstrip("/")
        staged_binary.parent.mkdir(parents=True)
        staged_binary.write_text("new binary")
        staged_binary.chmod(0o755)
        candidate = {**manifest, "revision": "b" * 40,
                     "files": {str(binary): update.fingerprint(staged_binary)}}
        update.write_json(stage / str(manifest_path).lstrip("/"), candidate)
    elif args[0] == "/usr/bin/pkexec":
        if args[2] == "begin":
            if scenario == "begin-denied":
                raise update.CommandFailure("authorization denied", 126)
            (state / "reserved").write_text("reserved")
            return ""
        if args[2] == "rollback":
            (state / "reservation-released").write_text("released")
            return ""
        if args[2] == "complete":
            if scenario == "cleanup-completion-denied":
                raise update.CommandFailure("completion authorization denied", 126)
            (state / "complete-called").write_text("complete")
            return ""
        if scenario == "denied":
            raise update.CommandFailure("authorization denied", 126)
        if scenario == "apply-failure":
            raise update.CommandFailure("application interrupted", 1)
        with tarfile.open(directory / "bundle.tar") as bundle:
            binary.write_bytes(bundle.extractfile("0").read())
            candidate = json.loads(bundle.extractfile("manifest.json").read())
        update.write_json(manifest_path, candidate)
        if scenario == "killed":
            os._exit(9)
    return ""


def sandbox_boundary(args, **kwargs):
    if scenario == "sandbox-failure":
        raise RuntimeError("Build sandbox setup is unavailable")
    return boundary(args, cwd=kwargs.get("cwd"), timeout=kwargs.get("timeout", 60), capture=kwargs.get("capture", True))


update.sandbox_run = sandbox_boundary
update.run = boundary
sys.exit(update.worker(operation))
