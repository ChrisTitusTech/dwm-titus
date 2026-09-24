#!/usr/bin/python3
"""Run as root only in a disposable Fedora container."""
import copy
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import runpy
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import uuid
from unittest.mock import patch

sys.dont_write_bytecode = True
if os.geteuid() != 0 or not (Path("/run/.containerenv").exists() or Path("/.dockerenv").exists()):
    sys.exit("This test requires root inside a disposable container")
REPO = Path(__file__).resolve().parents[1]


class Security(unittest.TestCase):
    def setUp(self):
        # Model a normal root-owned installation even under run-tests' umask 077.
        previous_umask = os.umask(0o022)
        self.addCleanup(os.umask, previous_umask)
        self.temporary = tempfile.TemporaryDirectory(prefix="desktop-security-", dir="/opt")
        self.addCleanup(self.temporary.cleanup)
        self.prefix = Path(self.temporary.name)
        self.helper = self.prefix / "libexec/dwm-titus/dwm-desktop-update-root"
        self.helper.parent.mkdir(parents=True)
        self.helper.write_text((REPO / "scripts/dwm-desktop-update-root").read_text().replace("@PREFIX@", str(self.prefix)))
        self.helper.chmod(0o755)
        self.binary = self.prefix / "bin/dwm"
        self.binary.parent.mkdir()
        self.binary.write_bytes(b"original")
        self.binary.chmod(0o755)
        self.manifest_path = self.prefix / "share/dwm-titus/desktop-install.json"
        self.manifest_path.parent.mkdir(parents=True)
        self.manifest = {"schema": 1, "source": "https://github.com/ChrisTitusTech/dwm-titus.git",
                         "revision": "a" * 40, "layout": {"prefix": str(self.prefix)}, "packages": ["gcc"],
                         "files": {str(self.binary): {"mode": 0o755, "sha256": hashlib.sha256(b"updated").hexdigest()}}}
        self.manifest_path.write_text(json.dumps(self.manifest, sort_keys=True) + "\n")
        self.operation = uuid.uuid4().hex
        self.bundle = self.prefix / "candidate.tar"
        self.addCleanup(shutil.rmtree, Path("/var/lib/dwm-titus/desktop-updates") / self.operation, True)

    def archive(self, mutation=None, payload=b"updated"):
        candidate = copy.deepcopy(self.manifest)
        candidate["revision"] = "b" * 40
        candidate["files"][str(self.binary)]["sha256"] = hashlib.sha256(payload).hexdigest()
        if mutation:
            mutation(candidate)
        with tarfile.open(self.bundle, "w:") as archive:
            for name, content in (("manifest.json", json.dumps(candidate).encode()), ("0", payload)):
                item = tarfile.TarInfo(name)
                item.size = len(content)
                archive.addfile(item, io.BytesIO(content))
        os.chown(self.bundle, 1000, 1000)

    def migration_archive(self):
        candidate = copy.deepcopy(self.manifest)
        candidate["revision"] = "b" * 40
        self.added = self.prefix / "share/themes/Dwm-New/gtk-3.0/gtk.css"
        self.alias = self.added.with_name("gtk-dark.css")
        candidate["files"] = {str(self.added): {"mode": 0o644, "sha256": hashlib.sha256(b"theme").hexdigest()},
                              str(self.alias): {"link": "gtk.css"}}
        self.manifest["layout"]["datadir"] = str(self.prefix / "share")
        self.manifest["files"][str(self.binary)]["sha256"] = hashlib.sha256(b"original").hexdigest()
        self.manifest_path.write_text(json.dumps(self.manifest))
        candidate["layout"] = self.manifest["layout"]
        with tarfile.open(self.bundle, "w:") as archive:
            for name, content in (("manifest.json", json.dumps(candidate).encode()), ("0", b""), ("1", b"theme")):
                item = tarfile.TarInfo(name)
                item.size = len(content)
                archive.addfile(item, io.BytesIO(content))
        os.chown(self.bundle, 1000, 1000)

    def test_added_theme_and_removed_command_roll_back(self):
        self.migration_archive()
        original = self.manifest_path.read_bytes()
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.added.read_bytes(), b"theme")
        self.assertEqual(self.added.stat().st_uid, 0)
        self.assertTrue(self.alias.is_symlink())
        self.assertEqual(self.alias.read_bytes(), b"theme")
        self.assertFalse(self.binary.exists())
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.added.exists())
        self.assertFalse(self.alias.is_symlink())
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(self.manifest_path.read_bytes(), original)

    def test_failed_migration_restores_added_and_removed_files(self):
        self.migration_archive()
        module = runpy.run_path(str(self.helper))
        apply = module["apply_archive"]
        module["STATE"].mkdir(parents=True, exist_ok=True, mode=0o700)
        original_write = apply.__globals__["write_json"]
        def fail_manifest(path, value):
            if path == self.manifest_path and value.get("revision") == "b" * 40:
                raise OSError("injected migration publication failure")
            original_write(path, value)
        with patch.dict(apply.__globals__, {"write_json": fail_manifest}):
            with self.assertRaisesRegex(OSError, "migration publication"):
                apply(self.bundle, hashlib.sha256(self.manifest_path.read_bytes()).hexdigest(), self.operation,
                      1000, hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)
        self.assertFalse(self.added.exists())
        self.assertFalse(self.alias.is_symlink())
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(json.loads(self.manifest_path.read_text())["revision"], "a" * 40)

    def test_migration_rejects_unmanaged_collision(self):
        self.migration_archive()
        self.added.parent.mkdir(parents=True)
        self.added.write_bytes(b"user theme")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(self.added.read_bytes(), b"user theme")
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_migration_rejects_symlink_parent(self):
        self.migration_archive()
        self.added.parent.parent.parent.mkdir(parents=True)
        self.added.parent.parent.symlink_to(self.prefix, target_is_directory=True)
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Untrusted", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_migration_preserves_modified_retired_file(self):
        self.migration_archive()
        self.binary.write_bytes(b"administrator edit")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Retired managed file was modified", result.stderr)
        self.assertFalse(self.added.exists())

    def test_changed_dependencies_require_reserved_plan(self):
        self.archive(lambda value: value.update(packages=["git"]))
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("prepared dependency plan", result.stderr)

    def test_session_installs_changed_package_plan(self):
        # rpm is already installed in Fedora: exercise the plan without network.
        self.archive(lambda value: value.update(packages=["rpm"]))
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        result = self.session_command([["begin", generation, self.operation],
                                      ["packages", generation, self.operation, '["rpm"]'],
                                      ["apply", str(self.bundle), generation, self.operation,
                                       hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40],
                                      ["complete", self.operation]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(json.loads(line)["ok"] for line in result.stdout.splitlines()), result.stdout)
        self.assertEqual(json.loads(self.manifest_path.read_text())["packages"], ["rpm"])

    def command(self, *args, helper=None, uid=1000):
        return subprocess.run([str(helper or self.helper), *args], capture_output=True, text=True,
                              env={**os.environ, "PKEXEC_UID": str(uid), "PYTHONPATH": str(self.prefix)})

    def apply(self, uid=1000):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        return self.command("apply", str(self.bundle), generation, self.operation,
                            hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40, uid=uid)

    def test_qml_bootstrap_rejects_path_shadowing_and_untrusted_installation(self):
        model = (REPO / "config/quickshell/settings/DesktopUpdateModel.qml").read_text()
        encoded = model.split("readonly property string updaterBootstrap: [\n", 1)[1].split('    ].join', 1)[0]
        bootstrap = "\n".join(json.loads(line.strip().rstrip(",")) for line in encoded.splitlines())
        self.prefix.chmod(0o755)
        worker = self.prefix / "bin/dwm-desktop-update"
        worker.write_text("import sys\nprint('trusted ' + sys.argv[1])\n")
        worker.chmod(0o755)
        poison = self.prefix / "poison"
        poison.mkdir()
        fake = poison / "dwm-desktop-update"
        fake.write_text("#!/usr/bin/python3\nprint('untrusted')\n")
        fake.chmod(0o755)
        os.chown(fake, 65534, 65534)
        args = ["/usr/sbin/runuser", "-u", "nobody", "--", "/usr/bin/env",
                "PATH=" + str(poison) + ":" + str(worker.parent), "/usr/bin/python3", "-I", "-c", bootstrap, "status"]
        result = subprocess.run(args, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "trusted status")
        for invalid in (worker, self.manifest_path, self.helper):
            mode = invalid.stat().st_mode & 0o777
            invalid.chmod(0o777)
            result = subprocess.run(args, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("untrusted", result.stdout)
            invalid.chmod(mode)
        # Exercise the real backend's downstream commands with the same poison.
        worker.write_text((REPO / "scripts/dwm-desktop-update").read_text())
        home = self.prefix / "desktop-home"
        status = home / "state/dwm-titus/desktop-update/status.json"
        status.parent.mkdir(parents=True)
        initial = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["status_default"]()
        status.write_text(json.dumps({**initial, "state": "starting", "operation": "f" * 32}))
        subprocess.run(["chown", "-R", "nobody:nobody", home], check=True)
        marker = home / "intercepted"
        for name in ("rpm", "systemctl"):
            shadow = poison / name
            shadow.write_text("#!/usr/bin/python3\nfrom pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('intercepted')\n")
            shadow.chmod(0o755)
            os.chown(shadow, 65534, 65534)
        user_args = args[:5] + ["HOME=" + str(home), "XDG_STATE_HOME=" + str(home / "state"),
                                "XDG_CONFIG_HOME=" + str(home / "config"), "XDG_DATA_HOME=" + str(home / "data")] + args[5:]
        baseline = user_args[:user_args.index("/usr/bin/python3")] + ["rpm"]
        subprocess.run(baseline, check=True)
        self.assertTrue(marker.exists(), "Downstream shadow fixture did not execute")
        marker.unlink()
        result = subprocess.run(user_args, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["state"], "interrupted")
        self.assertFalse(marker.exists(), "Status executed PATH-shadowed systemctl")
        status.write_text(json.dumps(initial))
        result = subprocess.run(user_args[:-1] + ["check", "--force"], text=True, capture_output=True, timeout=65)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["installed"], "a" * 40)
        self.assertFalse(marker.exists(), "Check executed PATH-shadowed rpm")

    def test_source_install_guard_holds_shared_root_lock(self):
        functions = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))
        guard = functions["guard_system_install"]
        probe = self.prefix / "lock-probe.py"
        probe.write_text("""import fcntl
with open('/var/lib/dwm-titus/desktop-updates/lock', 'a') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit(17)
raise SystemExit(1)
""")
        self.assertEqual(guard("", ["/usr/bin/python3", str(probe)]), 17)
        with Path("/var/lib/dwm-titus/desktop-updates/lock").open("a") as lock:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, "active"):
                guard("", ["/usr/bin/true"])
            self.assertEqual(guard(str(self.prefix / "stage"), ["/usr/bin/true"]), 0)

    def test_full_source_install_holds_user_and_system_locks(self):
        import pwd
        account = pwd.getpwnam("nobody")
        self.prefix.chmod(0o755)
        home = self.prefix / "user-home"
        home.mkdir(mode=0o700)
        os.chown(home, account.pw_uid, account.pw_gid)
        state = home / "state"
        probe = self.prefix / "both-locks.py"
        probe.write_text("""import fcntl, os, sys
for path in sys.argv[1:]:
    with open(path, 'a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            continue
        raise SystemExit('Installation lock not held: ' + path)
raise SystemExit(17)
""")
        guard = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["guard_system_install"]
        self.assertEqual(guard("", ["/usr/bin/python3", str(probe), str(state / "lock"),
                                    "/var/lib/dwm-titus/desktop-updates/lock"], "nobody", str(state)), 17)
        self.assertEqual(state.stat().st_uid, account.pw_uid)
        self.assertEqual((state / "lock").stat().st_uid, account.pw_uid)
        self.assertEqual(os.geteuid(), 0)
        with (state / "lock").open("a") as stream:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, "active"):
                guard("", ["/usr/bin/false"], "nobody", str(state))
        self.assertEqual(os.geteuid(), 0)

    def test_dependency_action_rejects_unfinished_transactions_before_package_commands(self):
        marker = self.prefix / "package-commands.json"
        injected = "\ndef observed_package_command(args, **kwargs):\n    path = Path(" + repr(str(marker)) + ")\n    calls = json.loads(path.read_text()) if path.exists() else []\n    calls.append(args)\n    path.write_text(json.dumps(calls))\n    return subprocess.CompletedProcess(args, 1 if args[0] == '/usr/bin/rpm' else 0)\nsubprocess.run = observed_package_command\n"
        self.helper.write_text(self.helper.read_text().replace('if __name__ == "__main__":', injected + '\nif __name__ == "__main__":'))
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        directory = Path("/var/lib/dwm-titus/desktop-updates") / self.operation
        self.assertEqual(self.command("begin", generation, self.operation).returncode, 0)
        for state in ("preparing", "applying", "applied", "rolling-back", "rolled-back-pending", "invalid"):
            (directory / "journal.json").write_text(json.dumps({"state": state, "uid": 1000}))
            result = self.command("dependencies", generation, uid=1001)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("finish or recover first", result.stderr)
            self.assertFalse(marker.exists())
        (directory / "journal.json").write_text(json.dumps({"state": "complete", "uid": 1000}))
        result = self.command("dependencies", generation, uid=1001)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(marker.read_text()), [["/usr/bin/rpm", "-q", "--quiet", "--", "gcc"],
                                                        ["/usr/bin/dnf", "install", "-y", "--", "gcc"]])

    def test_preparation_reservation_blocks_source_install_and_other_users(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        result = self.command("begin", generation, self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")
        guard = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["guard_system_install"]
        with self.assertRaisesRegex(RuntimeError, "before source installation"):
            guard("", ["/usr/bin/true"])
        self.assertNotEqual(self.command("begin", generation, uuid.uuid4().hex, uid=1001).returncode, 0)
        self.assertNotEqual(self.command("rollback", self.operation, uid=1001).returncode, 0)
        self.archive()
        self.assertNotEqual(self.apply(uid=1001).returncode, 0)
        self.assertEqual(self.apply().returncode, 0)
        self.assertEqual(self.command("complete", self.operation).returncode, 0)
        self.assertEqual(guard("", ["/usr/bin/true"]), 0)

    def test_live_uninstall_refuses_unfinished_transactions(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        self.assertEqual(self.command("begin", generation, self.operation).returncode, 0)
        journal = Path("/var/lib/dwm-titus/desktop-updates") / self.operation / "journal.json"
        args = ["make", "uninstall", "PREFIX=" + str(self.prefix),
                "XSESSIONSDIR=" + str(self.prefix / "share/xsessions")]
        for pending in ("preparing", "applying", "applied", "rolling-back", "rolled-back-pending"):
            journal.write_text(json.dumps({"state": pending, "uid": 1000}))
            result = subprocess.run(args, cwd=REPO, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("before source installation", result.stderr)
            self.assertTrue(self.helper.exists())
            self.assertTrue(self.manifest_path.exists())
            self.assertEqual(self.binary.read_bytes(), b"original")
        journal.write_text(json.dumps({"state": "complete", "uid": 1000}))
        result = subprocess.run(args, cwd=REPO, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.helper.exists())
        self.assertFalse(self.manifest_path.exists())
        self.assertFalse(self.binary.exists())

    def test_preparation_can_be_canceled_without_replacing_files(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        self.assertEqual(self.command("begin", generation, self.operation).returncode, 0)
        self.assertEqual(self.command("rollback", self.operation).returncode, 0)
        # Retry after cancellation before complete, including when a later operation starts.
        self.assertEqual(self.command("rollback", self.operation).returncode, 0)
        later = uuid.uuid4().hex
        self.addCleanup(shutil.rmtree, Path("/var/lib/dwm-titus/desktop-updates") / later, True)
        self.assertEqual(self.command("begin", generation, later).returncode, 0)
        self.assertEqual(self.command("rollback", self.operation).returncode, 0)
        self.assertEqual(self.command("complete", self.operation).returncode, 0)
        self.assertEqual(self.command("rollback", later).returncode, 0)
        self.assertEqual(self.command("complete", later).returncode, 0)
        self.assertEqual(self.binary.read_bytes(), b"original")
        guard = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["guard_system_install"]
        self.assertEqual(guard("", ["/usr/bin/true"]), 0)

    def test_extra_and_oversized_candidate_fields_never_replace_trust_anchor(self):
        original = self.manifest_path.read_bytes()
        for padding in ("extra", "x" * (4 * 1024 * 1024)):
            self.operation = uuid.uuid4().hex
            self.addCleanup(shutil.rmtree, Path("/var/lib/dwm-titus/desktop-updates") / self.operation, True)
            self.archive(lambda value: value.update(padding=padding))
            self.assertNotEqual(self.apply().returncode, 0)
            self.assertEqual(self.manifest_path.read_bytes(), original)
            self.assertEqual(self.binary.read_bytes(), b"original")

    def test_apply_and_rollback_restore_verified_original(self):
        self.archive()
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"updated")
        self.assertEqual(self.binary.stat().st_uid, 0)
        self.assertEqual(self.command("complete", self.operation).returncode, 0)
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(self.command("rollback", self.operation).returncode, 0)

    def test_another_user_cannot_supersede_unfinished_user_phase(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        first = self.operation
        self.operation = uuid.uuid4().hex
        self.addCleanup(shutil.rmtree, Path("/var/lib/dwm-titus/desktop-updates") / self.operation, True)
        os.chown(self.bundle, 1001, 1001)
        self.assertIn("requires rollback", self.apply(uid=1001).stderr)
        self.assertNotEqual(self.command("complete", first, uid=1001).returncode, 0)
        self.assertEqual(self.command("rollback", first).returncode, 0)
        self.assertIn("requires rollback", self.apply(uid=1001).stderr)
        self.assertEqual(self.command("complete", first).returncode, 0)
        result = self.apply(uid=1001)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command("complete", first).returncode, 0)

    def test_interrupted_initial_journal_can_be_recovered(self):
        module = runpy.run_path(str(self.helper))
        state = module["STATE"]
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        apply = module["apply_archive"]
        original_write = apply.__globals__["write_json"]
        for latest in (None, "e" * 32):
            with self.subTest(latest=latest):
                self.operation = uuid.uuid4().hex
                self.addCleanup(shutil.rmtree, state / self.operation, True)
                (state / "latest.json").unlink(missing_ok=True)
                if latest:
                    original_write(state / "latest.json", {"operation": latest})
                self.archive()
                def interrupted(path, value):
                    if path == state / "latest.json":
                        raise RuntimeError("interrupted initial publication")
                    original_write(path, value)
                with patch.dict(apply.__globals__, {"write_json": interrupted}):
                    with self.assertRaisesRegex(RuntimeError, "initial publication"):
                        apply(self.bundle, hashlib.sha256(self.manifest_path.read_bytes()).hexdigest(), self.operation,
                              1000, hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)
                result = self.command("rollback", self.operation)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.binary.read_bytes(), b"original")
                self.assertEqual(self.command("complete", self.operation).returncode, 0)
    def test_source_sync_manifest_trust_rejects_ownership_mode_and_parent_drift(self):
        validate = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["trusted_installation"]
        validate(self.manifest_path)
        os.chown(self.manifest_path, 1000, 1000)
        with self.assertRaisesRegex(RuntimeError, "root-owned"):
            validate(self.manifest_path)
        os.chown(self.manifest_path, 0, 0)
        self.manifest_path.chmod(0o664)
        with self.assertRaisesRegex(RuntimeError, "non-writable"):
            validate(self.manifest_path)
        self.manifest_path.chmod(0o644)
        self.manifest_path.parent.chmod(0o775)
        with self.assertRaisesRegex(RuntimeError, "untrusted parent"):
            validate(self.manifest_path)

    def test_worker_execution_requires_root_owned_installed_path(self):
        resolve = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["installed_worker"]
        worker = self.prefix / "bin/dwm-desktop-update"
        worker.write_text("installed worker")
        worker.chmod(0o755)
        self.assertEqual(resolve(self.manifest_path), worker)
        def audit():
            return subprocess.run([sys.executable, str(REPO / "scripts/dwm-desktop-update"), "verify-trust",
                                   str(self.manifest_path)], capture_output=True, text=True)
        self.assertEqual(audit().returncode, 0)
        before = worker.read_bytes()
        os.chown(worker, 1000, 1000)
        self.assertEqual(worker.read_bytes(), before)
        self.assertNotEqual(audit().returncode, 0)
        with self.assertRaisesRegex(RuntimeError, "root-owned"):
            resolve(self.manifest_path)
        os.chown(worker, 0, 0)
        worker.chmod(0o775)
        self.assertNotEqual(audit().returncode, 0)
        worker.chmod(0o755)
        worker.parent.chmod(0o775)
        self.assertNotEqual(audit().returncode, 0)
        worker.parent.chmod(0o755)
        self.assertEqual(audit().returncode, 0)

    def test_discovery_rejects_untrusted_complete_parent_chains(self):
        check = runpy.run_path(str(REPO / "scripts/dwm-desktop-update"))["unsupported_system_drift"]
        self.assertEqual(check(self.manifest), "")
        parent = self.binary.parent
        parent.chmod(0o775)
        self.assertIn("source installer", check(self.manifest))
        parent.chmod(0o755)
        os.chown(parent, 1000, 1000)
        self.assertIn("source installer", check(self.manifest))
        os.chown(parent, 0, 0)
        target = self.prefix / "real-bin"
        parent.rename(target)
        parent.symlink_to(target, target_is_directory=True)
        self.assertIn("source installer", check(self.manifest))
        parent.unlink()
        target.rename(parent)
        self.prefix.chmod(0o775)
        self.assertIn("source installer", check(self.manifest))

    def test_root_can_run_read_only_installation_audits(self):
        self.binary.write_bytes(b"updated")
        script = str(REPO / "scripts/dwm-desktop-update")
        installed_worker = self.prefix / "bin/dwm-desktop-update"
        shutil.copyfile(script, installed_worker)
        installed_worker.chmod(0o755)
        result = subprocess.run([sys.executable, script, "verify-trust", str(self.manifest_path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        (self.prefix / ".desktop-source.json").write_text(json.dumps({"revision": "a" * 40}))
        state = self.prefix / "state/dwm-titus/desktop-update"
        state.mkdir(parents=True)
        roots = [self.prefix / "config/quickshell", self.prefix / "data/dwm-titus/config", self.prefix / "data/dwm-titus/scripts"]
        fingerprints = runpy.run_path(script)["tree_manifest"]
        for root in roots:
            root.mkdir(parents=True)
            (root / "file").write_text("managed")
        (state / "installed.json").write_text(json.dumps({"schema": 1, "revision": "a" * 40,
            "checkout": str(self.prefix), "trees": {str(root): fingerprints(root) for root in roots}}))
        result = subprocess.run([sys.executable, script, "verify-receipts", str(self.prefix), str(self.manifest_path)],
                                env={**os.environ, "XDG_STATE_HOME": str(self.prefix / "state"),
                                     "XDG_CONFIG_HOME": str(self.prefix / "config"), "XDG_DATA_HOME": str(self.prefix / "data")},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_matching_user_owned_system_file_is_reinstalled_as_root(self):
        self.binary.write_bytes(b"updated")
        os.chown(self.binary, 1000, 1000)
        self.archive()
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.stat().st_uid, 0)

    def test_rollback_preserves_manifest_mode_with_group_write_umask(self):
        self.archive()
        previous = os.umask(0o002)
        try:
            result = self.apply()
            self.assertEqual(result.returncode, 0, result.stderr)
            result = self.command("rollback", self.operation)
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            os.umask(previous)
        self.assertEqual(self.manifest_path.stat().st_mode & 0o777, 0o644)

    def test_arbitrary_destination_is_rejected(self):
        self.archive(lambda value: value["files"].update({"/etc/shadow": value["files"].pop(str(self.binary))}))
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the managed desktop", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def assert_changed_payload_installed_and_restored(self, target):
        original = target.read_bytes()
        self.binary = target
        self.manifest["files"] = {str(target): {"mode": 0o755, "sha256": hashlib.sha256(original).hexdigest()}}
        self.manifest_path.write_text(json.dumps(self.manifest))
        original_manifest = self.manifest_path.read_bytes()
        # Keep the helper executable so a separate invocation of its new
        # contents can perform recovery after it replaces itself.
        updated = original + b"\n# Updated desktop contents\n"
        self.archive(payload=updated)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), updated)
        self.assertEqual(target.stat().st_uid, 0)
        self.assertEqual(target.stat().st_mode & 0o7777, 0o755)
        installed = json.loads(self.manifest_path.read_text())
        self.assertEqual(installed["revision"], "b" * 40)
        self.assertEqual(installed["files"][str(target)]["sha256"], hashlib.sha256(updated).hexdigest())
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(self.manifest_path.read_bytes(), original_manifest)

    def test_self_replacement_and_rollback(self):
        self.assert_changed_payload_installed_and_restored(self.helper)

    def test_session_binary_replacement_and_rollback(self):
        self.assert_changed_payload_installed_and_restored(self.binary)

    def test_later_administrator_edit_blocks_rollback(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        self.binary.write_bytes(b"administrator edit after update")
        result = self.command("rollback", self.operation)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after this update", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"administrator edit after update")

    def test_other_privileged_helper_replacement_and_rollback(self):
        target = self.helper.parent / "dwm-settings-display-root"
        target.write_bytes(b"original display helper")
        target.chmod(0o755)
        self.assert_changed_payload_installed_and_restored(target)

    def test_root_executed_display_setup_replacement_and_rollback(self):
        target = self.prefix / "bin/dwm-display-setup"
        target.write_bytes(b"original root-executed display setup")
        target.chmod(0o755)
        self.assert_changed_payload_installed_and_restored(target)

    def test_root_executed_system_health_replacement_and_rollback(self):
        target = self.prefix / "bin/dwm-system-health"
        target.write_bytes(b"original root-executed system health")
        target.chmod(0o755)
        self.assert_changed_payload_installed_and_restored(target)

    def test_root_executed_power_management_replacement_and_rollback(self):
        target = self.prefix / "bin/power-management.sh"
        target.write_bytes(b"original root-executed power management")
        target.chmod(0o755)
        self.assert_changed_payload_installed_and_restored(target)

    def test_unsafe_original_cannot_be_promoted_through_recovery(self):
        for mode in (0o4755, 0o2755, 0o775, 0o755):
            with self.subTest(mode=oct(mode)):
                self.operation = uuid.uuid4().hex
                self.addCleanup(shutil.rmtree, Path("/var/lib/dwm-titus/desktop-updates") / self.operation, True)
                self.binary.write_bytes(b"untrusted original")
                os.chown(self.binary, 1000, 1000)
                self.binary.chmod(mode)
                self.archive()
                result = self.apply()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unsafe installed file", result.stderr)
                self.assertEqual(self.binary.stat().st_uid, 1000)
                self.assertEqual(self.command("complete", self.operation).returncode, 0)

    def test_old_recovery_record_with_special_mode_is_rejected(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        backup = Path("/var/lib/dwm-titus/desktop-updates") / self.operation
        journal = json.loads((backup / "journal.json").read_text())
        journal["replaced"][0]["old"]["mode"] = 0o4755
        (backup / "journal.json").write_text(json.dumps(journal))
        result = self.command("rollback", self.operation)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsafe managed recovery mode", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"updated")
        self.assertEqual(self.binary.stat().st_mode & 0o7777, 0o755)

    def test_hash_tampering_is_rejected(self):
        self.archive(lambda value: value["files"][str(self.binary)].update(sha256=hashlib.sha256(b"updated").hexdigest()),
                     payload=b"tampered")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum", result.stderr)

    def test_mode_escalation_is_rejected(self):
        self.archive(lambda value: value["files"][str(self.binary)].update(mode=0o4755))
        self.assertNotEqual(self.apply().returncode, 0)

    def test_stale_preview_is_rejected(self):
        self.archive()
        result = self.command("apply", str(self.bundle), "0" * 64, self.operation,
                              hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after preview", result.stderr)

    def test_bundle_substitution_during_authorization_is_rejected(self):
        self.archive()
        digest = hashlib.sha256(self.bundle.read_bytes()).hexdigest()
        self.archive(payload=b"substituted after authorization request")
        result = self.command("apply", str(self.bundle), hashlib.sha256(self.manifest_path.read_bytes()).hexdigest(),
                              self.operation, digest, "b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after authorization", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_bundle_revision_must_match_confirmation(self):
        self.archive(lambda value: value.update(revision="c" * 40))
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("confirmed revision", result.stderr)

    def test_new_contents_must_match_candidate_hash(self):
        self.archive(lambda value: value["files"][str(self.binary)].update(sha256="c" * 64),
                     payload=b"new contents with incorrect candidate checksum")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Update bundle checksum mismatch", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_untrusted_helper_and_bundle_symlinks_are_rejected(self):
        self.archive()
        self.helper.chmod(0o777)
        self.assertNotEqual(self.apply().returncode, 0)
        self.helper.chmod(0o755)
        saved = self.bundle.with_suffix(".saved")
        self.bundle.rename(saved)
        self.bundle.symlink_to(saved)
        self.assertNotEqual(self.apply().returncode, 0)

    def test_repository_helper_cannot_be_elevated(self):
        result = self.command("rollback", self.operation, helper=REPO / "scripts/dwm-desktop-update-root")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("installed desktop updater", result.stderr)

    def test_newer_manual_install_prevents_old_rollback(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        value = json.loads(self.manifest_path.read_text())
        value["revision"] = "c" * 40
        self.manifest_path.write_text(json.dumps(value))
        result = self.command("rollback", self.operation)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("newer installation", result.stderr)

    def test_newer_manual_install_prevents_interrupted_rollback(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        journal_path = Path("/var/lib/dwm-titus/desktop-updates") / self.operation / "journal.json"
        journal = json.loads(journal_path.read_text())
        value = json.loads(self.manifest_path.read_text())
        value["revision"] = "c" * 40
        self.manifest_path.write_text(json.dumps(value))
        for state in ("applying", "rolling-back"):
            journal["state"] = state
            journal_path.write_text(json.dumps(journal))
            result = self.command("rollback", self.operation)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("newer installation", result.stderr)

    def test_interrupted_rollback_retries_after_manifest_restoration(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        loader = importlib.machinery.SourceFileLoader("retry_rollback_test", str(self.helper))
        spec = importlib.util.spec_from_loader("retry_rollback_test", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        backup = module.STATE / self.operation
        journal = json.loads((backup / "journal.json").read_text())
        original_write = module.write_json

        def fail_completion(path, value):
            if path == backup / "journal.json" and value["state"] == "rolled-back-pending":
                raise RuntimeError("interrupted rollback completion")
            original_write(path, value)

        with patch.object(module, "write_json", side_effect=fail_completion):
            with self.assertRaisesRegex(RuntimeError, "interrupted rollback completion"):
                module.restore(backup, journal)
        self.assertEqual(json.loads((backup / "journal.json").read_text())["state"], "rolling-back")
        self.assertEqual(json.loads(self.manifest_path.read_text())["revision"], "a" * 40)
        self.assertNotEqual(self.apply().returncode, 0, "An incomplete rollback must block new updates")
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((backup / "journal.json").read_text())["state"], "rolled-back-pending")

    def test_interrupted_rollback_accepts_unpublished_manifest(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        backup = Path("/var/lib/dwm-titus/desktop-updates") / self.operation
        journal = json.loads((backup / "journal.json").read_text())
        journal["state"] = "applying"
        (backup / "journal.json").write_text(json.dumps(journal))
        shutil.copyfile(backup / "manifest.json", self.manifest_path)
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_failure_after_replacement_automatically_restores_original(self):
        self.archive()
        loader = importlib.machinery.SourceFileLoader("root_rollback_test", str(self.helper))
        spec = importlib.util.spec_from_loader("root_rollback_test", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        module.STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        original_write = module.write_json

        def fail_manifest(path, value):
            if path == self.manifest_path and value["revision"] == "b" * 40:
                raise RuntimeError("injected manifest publication failure")
            original_write(path, value)

        with patch.object(module, "write_json", side_effect=fail_manifest):
            with self.assertRaisesRegex(RuntimeError, "publication failure"):
                module.apply_archive(self.bundle, hashlib.sha256(self.manifest_path.read_bytes()).hexdigest(),
                                     self.operation, 1000, hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(json.loads(self.manifest_path.read_text())["revision"], "a" * 40)
        journal = json.loads((module.STATE / self.operation / "journal.json").read_text())
        self.assertEqual(journal["state"], "rolled-back-pending")

    def test_failed_system_directory_sync_restores_original(self):
        self.archive()
        module = runpy.run_path(str(self.helper))
        module["STATE"].mkdir(parents=True, exist_ok=True, mode=0o700)
        apply = module["apply_archive"]
        original_sync = apply.__globals__["sync_directory"]
        failed = False
        def sync(path):
            nonlocal failed
            if path == self.binary.parent and not failed:
                failed = True
                raise OSError("injected system directory sync failure")
            original_sync(path)
        with patch.dict(apply.__globals__, {"sync_directory": sync}):
            with self.assertRaisesRegex(OSError, "directory sync failure"):
                apply(self.bundle, hashlib.sha256(self.manifest_path.read_bytes()).hexdigest(), self.operation,
                      1000, hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(json.loads(self.manifest_path.read_text())["revision"], "a" * 40)


    def session_command(self, requests, mode="update", uid=1000, raw=None):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        return subprocess.run([str(self.helper), "session", mode, self.operation, generation, "b" * 40],
                              input=raw if raw is not None else "".join(json.dumps(item) + "\n" for item in requests),
                              capture_output=True, text=True, timeout=10,
                              env={**os.environ, "PKEXEC_UID": str(uid)})

    def test_one_session_installs_and_completes_with_protocol_output_only(self):
        self.archive()
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        result = self.session_command([["begin", generation, self.operation],
                                      ["apply", str(self.bundle), generation, self.operation,
                                       hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40],
                                      ["complete", self.operation]])
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(replies, [{"ok": True, "ready": True}, *[{"ok": True}] * 3])
        self.assertIn("System files installed and verified", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"updated")
        journal = json.loads((Path("/var/lib/dwm-titus/desktop-updates") / self.operation / "journal.json").read_text())
        self.assertEqual(journal["state"], "complete")

    def test_session_rejects_other_operations_generations_and_revisions(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        for request in (["begin", generation, "e" * 32], ["begin", "0" * 64, self.operation],
                        ["dependencies", "0" * 64], ["complete", self.operation],
                        ["session", "recover", self.operation], ["/usr/bin/sh", "-c", "true"]):
            with self.subTest(request=request):
                result = self.session_command([request])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("outside the authorized", result.stderr)
        result = self.session_command([["begin", generation, self.operation],
                                      ["apply", str(self.bundle), generation, self.operation, "0" * 64, "c" * 40]])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the authorized", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_session_eof_keeps_recovery_and_recovery_cannot_start_an_update(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        result = self.session_command([["begin", generation, self.operation]])
        self.assertEqual(result.returncode, 0, result.stderr)
        journal_path = Path("/var/lib/dwm-titus/desktop-updates") / self.operation / "journal.json"
        self.assertEqual(json.loads(journal_path.read_text())["state"], "preparing")
        rejected = self.session_command([["begin", generation, self.operation]], mode="recover")
        self.assertNotEqual(rejected.returncode, 0)
        result = self.session_command([["rollback", self.operation], ["complete", self.operation]], mode="recover")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([json.loads(line)["ok"] for line in result.stdout.splitlines()], [True, True, True])
        self.assertEqual(json.loads(journal_path.read_text())["state"], "rolled-back")

    def test_recovery_session_cannot_reuse_another_users_operation(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        self.assertEqual(self.session_command([["begin", generation, self.operation]]).returncode, 0)
        result = self.session_command([["rollback", self.operation], ["complete", self.operation]], mode="recover", uid=1001)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([item["ok"] for item in replies], [True, False, False])
        journal = json.loads((Path("/var/lib/dwm-titus/desktop-updates") / self.operation / "journal.json").read_text())
        self.assertEqual((journal["uid"], journal["state"]), (1000, "preparing"))

    def test_session_rejects_unbounded_and_malformed_requests(self):
        for raw in ("x" * 8193, "{broken}\n", "[1]\n", "[]\n", "{}\n", '["complete"]'):
            with self.subTest(raw=raw[:20]):
                result = self.session_command([], raw=raw)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.binary.read_bytes(), b"original")

    def test_session_has_a_deadline_even_when_client_keeps_pipe_open(self):
        self.helper.write_text(self.helper.read_text().replace("SESSION_SECONDS = 3600", "SESSION_SECONDS = 0.1"))
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        process = subprocess.Popen([str(self.helper), "session", "update", self.operation, generation, "b" * 40],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={**os.environ, "PKEXEC_UID": "1000"})
        try:
            self.assertEqual(process.wait(timeout=5), 1)
            self.assertIn(b"session expired", process.stderr.read())
        finally:
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main()
