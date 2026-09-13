#!/usr/bin/python3
"""Run as root only in a disposable Fedora container."""
import copy
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
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
                         "files": {str(self.binary): {"mode": 0o755, "sha256": hashlib.sha256(b"original").hexdigest()}}}
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

    def command(self, *args, helper=None):
        return subprocess.run([str(helper or self.helper), *args], capture_output=True, text=True,
                              env={**os.environ, "PKEXEC_UID": "1000", "PYTHONPATH": str(self.prefix)})

    def apply(self):
        generation = hashlib.sha256(self.manifest_path.read_bytes()).hexdigest()
        return self.command("apply", str(self.bundle), generation, self.operation,
                            hashlib.sha256(self.bundle.read_bytes()).hexdigest(), "b" * 40)

    def test_apply_and_rollback_restore_verified_original(self):
        self.archive()
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"updated")
        self.assertEqual(self.binary.stat().st_uid, 0)
        result = self.command("rollback", self.operation)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"original")
        self.assertEqual(self.command("rollback", self.operation).returncode, 0)

    def test_matching_user_owned_system_file_is_reinstalled_as_root(self):
        os.chown(self.binary, 1000, 1000)
        self.archive(payload=b"original")
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
        self.assertIn("Privileged helpers changed", result.stderr)
        self.assertEqual(target.read_bytes(), original)

    def test_self_replacement_with_matching_payload_hash_is_rejected(self):
        self.assert_helper_payload_rejected(self.helper)

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

    def test_hash_tampering_is_rejected(self):
        self.archive(lambda value: value["files"][str(self.binary)].update(sha256="0" * 64))
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
            if path == backup / "journal.json" and value["state"] == "rolled-back":
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
        self.assertEqual(json.loads((backup / "journal.json").read_text())["state"], "rolled-back")

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
        self.assertEqual(journal["state"], "rolled-back")


if __name__ == "__main__":
    unittest.main()
