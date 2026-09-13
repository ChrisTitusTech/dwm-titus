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

    def command(self, *args, helper=None, uid=1000):
        return subprocess.run([str(helper or self.helper), *args], capture_output=True, text=True,
                              env={**os.environ, "PKEXEC_UID": str(uid), "PYTHONPATH": str(self.prefix)})

    def apply(self, uid=1000):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        return self.command("apply", str(self.bundle), generation, self.operation,
                            hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40, uid=uid)

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
        self.assertIn("layout changed", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def assert_helper_payload_rejected(self, target):
        original = target.read_bytes()
        self.binary = target
        self.manifest["files"] = {str(target): {"mode": 0o755, "sha256": hashlib.sha256(original).hexdigest()}}
        self.manifest_path.write_text(json.dumps(self.manifest))
        self.archive(payload=b"arbitrary privileged code")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("System file contents changed", result.stderr)
        self.assertEqual(target.read_bytes(), original)

    def test_self_replacement_with_matching_payload_hash_is_rejected(self):
        self.assert_helper_payload_rejected(self.helper)

    def test_session_binary_with_matching_payload_hash_is_rejected(self):
        self.archive(payload=b"malicious session binary")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("System file contents changed", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")

    def test_later_administrator_edit_blocks_rollback(self):
        self.archive()
        self.assertEqual(self.apply().returncode, 0)
        self.binary.write_bytes(b"administrator edit after update")
        result = self.command("rollback", self.operation)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after this update", result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"administrator edit after update")

    def test_other_privileged_helper_payload_is_rejected(self):
        target = self.helper.parent / "dwm-settings-display-root"
        target.write_bytes(b"original display helper")
        target.chmod(0o755)
        self.assert_helper_payload_rejected(target)

    def test_root_executed_display_setup_payload_is_rejected(self):
        target = self.prefix / "bin/dwm-display-setup"
        target.write_bytes(b"original root-executed display setup")
        target.chmod(0o755)
        self.assert_helper_payload_rejected(target)

    def test_root_executed_system_health_payload_is_rejected(self):
        target = self.prefix / "bin/dwm-system-health"
        target.write_bytes(b"original root-executed system health")
        target.chmod(0o755)
        self.assert_helper_payload_rejected(target)

    def test_root_executed_power_management_payload_is_rejected(self):
        target = self.prefix / "bin/power-management.sh"
        target.write_bytes(b"original root-executed power management")
        target.chmod(0o755)
        self.assert_helper_payload_rejected(target)

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


if __name__ == "__main__":
    unittest.main()
