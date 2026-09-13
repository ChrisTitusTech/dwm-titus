#!/usr/bin/python3
"""Offline update discovery, staging, generation, and recovery regressions."""
import copy
import importlib.machinery
import importlib.util
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]


def module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    value = importlib.util.module_from_spec(spec)
    loader.exec_module(value)
    return value


update = module("desktop_update", REPO / "scripts/dwm-desktop-update")
privileged = module("desktop_root", REPO / "scripts/dwm-desktop-update-root")
REAL_RUN = update.run
REAL_ROOT_OWNED = update.root_owned


class DesktopUpdate(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.config, self.data, self.state = (self.base / name for name in ("config", "data", "state"))
        for path in (self.config / "quickshell", self.data / "config", self.data / "scripts", self.state):
            path.mkdir(parents=True)
            (path / "file").write_text("original")
        self.binary = self.base / "bin/dwm"
        self.binary.parent.mkdir()
        self.binary.write_text("binary")
        self.binary.chmod(0o755)
        self.manifest = {"schema": 1, "source": update.SOURCE, "revision": "a" * 40,
                         "layout": {"prefix": str(self.base)}, "packages": [],
                         "files": {str(self.binary): update.fingerprint(self.binary)}}
        self.manifest_path = self.base / "manifest.json"
        update.write_json(self.manifest_path, self.manifest)
        update.write_json(self.state / "installed.json", {"schema": 1, "revision": "a" * 40, "checkout": str(self.data),
            "trees": {str(self.config / "quickshell"): update.tree_manifest(self.config / "quickshell"),
                      str(self.data / "config"): update.tree_manifest(self.data / "config"),
                      str(self.data / "scripts"): update.tree_manifest(self.data / "scripts")}})
        self.addCleanup(patch.stopall)
        patch.object(update, "paths", return_value=(self.config, self.data, self.state)).start()
        patch.object(update, "installation", return_value=(self.manifest_path, self.manifest)).start()
        patch.object(update, "missing_packages", return_value=[]).start()
        patch.object(update, "service_active", return_value=False).start()
        patch.object(update, "root_owned", return_value=True).start()
        patch.object(update, "trusted_directory", return_value=None).start()
        patch.object(update, "installed_worker", return_value=self.base / "bin/dwm-desktop-update").start()
        self.command = patch.object(update, "run", return_value="a" * 40 + "\trefs/heads/main").start()

    def test_current_and_content_drift_are_distinct(self):
        self.assertEqual(update.check(True)["state"], "current")
        (self.config / "quickshell/file").write_text("stale shell")
        value = update.check(True)
        self.assertEqual(value["state"], "drift")
        self.assertTrue(value["canUpdate"])
        self.assertIn(str(self.config / "quickshell"), value["changes"])

    def test_upstream_revision_and_missing_binary(self):
        self.command.return_value = "b" * 40 + "\trefs/heads/main"
        self.binary.unlink()
        value = update.check(True)
        self.assertEqual(value["state"], "available")
        self.assertEqual(value["available"], "b" * 40)
        self.assertIn(str(self.binary), value["changes"])

    def test_offline_never_reports_current(self):
        self.command.side_effect = update.CommandFailure("offline", 128)
        value = update.check(True)
        self.assertEqual(value["state"], "failed")
        self.assertFalse(value["canUpdate"])
        self.assertEqual(value["installed"], "a" * 40)

    def test_cached_check_does_not_contact_network(self):
        update.check(True)
        self.command.reset_mock()
        update.check(False)
        self.command.assert_not_called()

    def test_overall_check_deadline_bounds_slow_package_queries(self):
        with patch.object(update, "CHECK_SECONDS", 0.05), \
                patch.object(update, "missing_packages", side_effect=lambda _: time.sleep(1)):
            started = time.monotonic()
            value = update.check(True)
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(value["state"], "failed")
        self.assertIn("exceeded its time limit", value["detail"])

    def test_missing_user_receipt_requires_repair(self):
        (self.state / "installed.json").unlink()
        self.assertEqual(update.check(True)["state"], "drift")

    def test_incomplete_receipts_never_verify_or_report_current(self):
        original = update.read_json(self.state / "installed.json")
        without_checkout = copy.deepcopy(original)
        without_checkout["checkout"] = ""
        update.write_json(self.state / "installed.json", without_checkout)
        self.assertEqual(update.check(True)["state"], "current")
        variants = []
        for root in original["trees"]:
            value = copy.deepcopy(original)
            del value["trees"][root]
            variants.append(value)
        for key, value in (("schema", 99), ("trees", {}), ("trees", [])):
            variant = copy.deepcopy(original)
            variant[key] = value
            variants.append(variant)
        for receipt in variants:
            with self.subTest(receipt=receipt):
                update.write_json(self.state / "installed.json", receipt)
                self.assertNotEqual(update.check(True)["state"], "current")
                with patch.object(update, "source_revision", return_value="a" * 40):
                    with self.assertRaises(RuntimeError):
                        update.verify_receipts(self.data, self.manifest_path)

    def test_unknown_source_revision_remains_bootstrappable(self):
        receipt = update.read_json(self.state / "installed.json")
        receipt["revision"] = "unknown"
        self.manifest["revision"] = "unknown"
        update.write_json(self.state / "installed.json", receipt)
        update.write_json(self.manifest_path, self.manifest)
        value = update.check(True)
        self.assertEqual(value["state"], "available")
        self.assertTrue(value["canUpdate"])
        with patch.object(update, "source_revision", return_value="unknown"):
            update.verify_receipts(self.data, self.manifest_path)

    def test_overlapping_targets_rejected_before_launch_or_staging(self):
        for config, data, state in ((self.data, self.data, self.state),
                                    (self.config, self.config / "quickshell/data", self.state),
                                    (self.config, self.data, self.data / "state")):
            with self.subTest(config=config, data=data, state=state), \
                    patch.object(update, "paths", return_value=(config, data, state)):
                self.command.reset_mock()
                with self.assertRaisesRegex(RuntimeError, "must not overlap"):
                    update.launch("a" * 40)
                with self.assertRaisesRegex(RuntimeError, "must not overlap"):
                    update.prepare_user(self.base, "e" * 32)
                self.command.assert_not_called()
        with patch.object(update, "paths", return_value=(self.data, self.data, self.state)):
            self.assertEqual(update.check(True)["state"], "failed")

    def test_missing_system_directory_blocks_automatic_repair(self):
        self.binary.unlink()
        self.binary.parent.rmdir()
        value = update.check(True)
        self.assertEqual(value["state"], "blocked")
        self.assertFalse(value["canUpdate"])
        self.assertIn("source installer", value["detail"])

    def test_ownership_only_drift_is_repairable(self):
        if os.geteuid() == 0:
            os.chown(self.binary, 65534, 65534)
        with patch.object(update, "root_owned", REAL_ROOT_OWNED):
            value = update.check(True)
        self.assertEqual(value["state"], "drift")
        self.assertTrue(value["canUpdate"])
        self.assertIn(str(self.binary), value["changes"])

    def test_untrusted_system_parent_blocks_before_network(self):
        with patch.object(update, "trusted_directory", side_effect=RuntimeError("untrusted parent")):
            value = update.check(True)
        self.assertEqual(value["state"], "blocked")
        self.assertFalse(value["canUpdate"])
        self.assertIn("source installer", value["detail"])
        self.command.assert_not_called()

    def test_untrusted_installed_worker_blocks_before_offering_repair(self):
        worker = self.base / "bin/dwm-desktop-update"
        worker.write_text("worker")
        worker.chmod(0o755)
        self.manifest["files"][str(worker)] = update.fingerprint(worker)
        if os.geteuid() == 0:
            os.chown(worker, 65534, 65534)
        value = update.check(True)
        self.assertEqual(value["state"], "blocked")
        self.assertFalse(value["canUpdate"])
        self.assertIn("updater requires the source installer", value["detail"])
        self.command.assert_not_called()

    def test_unsafe_system_drift_blocks_before_network_or_authorization(self):
        for mode in (0o4755, 0o2755, 0o775):
            self.binary.chmod(mode)
            value = update.check(True)
            self.assertEqual(value["state"], "blocked")
            self.assertFalse(value["canUpdate"])
            self.assertIn("source installer", value["detail"])
        self.binary.chmod(0o755)
        self.binary.write_text("modified by its user owner")
        with patch.object(update, "root_owned", return_value=False):
            self.assertEqual(update.check(True)["state"], "blocked")
        self.command.assert_not_called()

    def test_manifest_directory_uses_trusted_mode_under_group_umask(self):
        stage = self.base / "stage"
        args = SimpleNamespace(source_dir=str(self.base), destdir=str(stage), prefix="/usr",
                               manprefix="/usr/share/man", xsessions="/usr/share/xsessions", datadir="/usr/share",
                               commands=[], helpers=[], packages=[])
        previous = os.umask(0o002)
        try:
            with patch.object(update, "fingerprint", return_value={"mode": 0o755, "sha256": "a" * 64}):
                update.record_system(args)
        finally:
            os.umask(previous)
        self.assertEqual((stage / "usr/share/dwm-titus").stat().st_mode & 0o777, 0o755)

    def test_service_forwards_build_overrides_without_shell_splitting(self):
        overrides = {"CC": "clang", "CFLAGS": "-O1 -g", "CPPFLAGS": "-DTEST=1", "LDFLAGS": "-Wl,--as-needed"}
        with patch.dict(os.environ, overrides):
            command = update.service_command("test.service", ["worker"])
        for key, value in overrides.items():
            self.assertIn("--setenv=" + key + "=" + value, command)

    def test_permission_or_corrupt_receipt_not_current(self):
        (self.state / "installed.json").write_text("{")
        self.assertEqual(update.check(True)["state"], "failed")

    def test_restart_guidance_survives_rechecking(self):
        update.write_json(self.state / "status.json", {**update.status_default(), "restart": "session"})
        with patch.object(update, "running_dwm_matches", return_value=False):
            value = update.check(True)
        self.assertEqual(value["state"], "restart-required")
        self.assertFalse(value["canUpdate"])

    def test_restart_guidance_survives_unresponsive_shell(self):
        update.write_json(self.state / "status.json", {**update.status_default(), "restart": "session"})
        self.command.side_effect = ["a" * 40 + "\trefs/heads/main", update.CommandFailure("IPC failed", 1)]
        with patch.object(update, "running_dwm_matches", return_value=True), \
                patch.object(update, "quickshell_processes", return_value={("2", "new")}):
            value = update.check(True)
        self.assertEqual(value["state"], "restart-required")
        self.assertEqual(value["restart"], "session")

    def test_restart_recheck_requires_replacement_shell(self):
        update.write_json(self.state / "status.json", {**update.status_default(), "restart": "session",
                          "activationShells": [["1", "old"]]})
        with patch.object(update, "running_dwm_matches", return_value=True), \
                patch.object(update, "quickshell_processes", return_value={("1", "old")}):
            value = update.check(True)
        self.assertEqual(value["state"], "restart-required")
        self.assertEqual(value["restart"], "session")
        self.command.assert_called_once()  # No old-shell IPC probe.
        with patch.object(update, "running_dwm_matches", return_value=True), \
                patch.object(update, "quickshell_processes", return_value={("2", "new")}):
            value = update.check(True)
        self.assertEqual(value["state"], "current")
        self.assertEqual(value["restart"], "none")

    def test_interrupted_operation_cannot_be_overwritten_by_check(self):
        update.write_json(self.state / "status.json", {**update.status_default(), "state": "installing", "operation": "c" * 32})
        self.assertEqual(update.check(True)["state"], "interrupted")
        self.command.assert_not_called()

    def test_dead_checker_recovers(self):
        update.write_json(self.state / "status.json", {**update.status_default(), "state": "checking"})
        self.assertEqual(update.check(True)["state"], "current")

    def test_recovery_tracks_the_shell_running_before_rollback(self):
        operation = "c" * 32
        directory = self.state / "operations" / operation
        update.write_json(directory / "preview.json", {"manifest": str(self.manifest_path)})
        update.write_json(self.state / "status.json", {**update.status_default(), "operation": operation,
                          "state": "interrupted", "activationShells": [["1", "before-update"]]})
        with patch.object(update, "trusted_installation"), \
                patch.object(update, "quickshell_processes", return_value={("2", "before-rollback")}):
            value = update.recover(operation)
        self.assertEqual(value["activationShells"], [("2", "before-rollback")])
        self.assertEqual(value["restart"], "session")
        with patch.object(update, "running_dwm_matches", return_value=True), \
                patch.object(update, "quickshell_processes", return_value={("2", "before-rollback")}):
            self.assertEqual(update.check(True)["state"], "restart-required")
        with patch.object(update, "running_dwm_matches", return_value=True), \
                patch.object(update, "quickshell_processes", return_value={("3", "after-rollback")}):
            self.assertEqual(update.check(True)["state"], "current")

    def test_recovery_restores_receipt_absence_only_after_backup_completion(self):
        original = (self.state / "installed.json").read_bytes()
        for completed in (False, True):
            operation = ("d" if completed else "c") * 32
            directory = self.state / "operations" / operation
            update.write_json(directory / "preview.json", {"manifest": str(self.manifest_path)})
            update.write_json(self.state / "status.json", {**update.status_default(), "operation": operation,
                              "state": "interrupted"})
            if completed:
                update.write_json(directory / "receipt-backup.json", {"installed.json": False, "build-config.h": False})
                (self.state / "build-config.h").write_text("created by failed update")
            with patch.object(update, "trusted_installation"), patch.object(update, "quickshell_processes", return_value=set()):
                update.recover(operation)
            if completed:
                self.assertFalse((self.state / "installed.json").exists())
                self.assertFalse((self.state / "build-config.h").exists())
            else:
                self.assertEqual((self.state / "installed.json").read_bytes(), original)

    def test_missing_recorded_receipt_backup_stops_recovery(self):
        operation = "c" * 32
        directory = self.state / "operations" / operation
        update.write_json(directory / "receipt-backup.json", {"installed.json": True})
        update.write_json(self.state / "status.json", {**update.status_default(), "operation": operation,
                          "state": "interrupted"})
        with self.assertRaisesRegex(RuntimeError, "recovery copy is missing"):
            update.recover(operation)
        self.command.assert_not_called()

    def test_verified_completion_recovery_finishes_without_rollback(self):
        operation = "d" * 32
        directory = self.state / "operations" / operation
        update.write_json(directory / "completion.json", {"verified": True})
        update.write_json(directory / "preview.json", {"manifest": str(self.manifest_path)})
        update.write_json(self.state / "status.json", {**update.status_default(), "operation": operation, "state": "interrupted"})
        with patch.object(update, "trusted_installation"):
            value = update.recover(operation)
        self.assertEqual(value["state"], "restart-required")
        self.assertEqual(self.command.call_args.args[0][-2:], ["complete", operation])
        self.assertEqual((self.config / "quickshell/file").read_text(), "original")
        update.write_json(directory / "completion.json", {"recovered": True})
        update.write_json(self.state / "status.json", {**value, "state": "interrupted"})
        with patch.object(update, "trusted_installation"):
            value = update.recover(operation)
        self.assertEqual(value["state"], "failed")
        self.assertIn("Previous desktop files restored", value["detail"])
        self.assertFalse(value["canUpdate"])

    def test_changed_confirmation_does_not_launch(self):
        self.command.return_value = "b" * 40 + "\trefs/heads/main"
        update.check(True)
        self.command.reset_mock()
        with self.assertRaisesRegex(RuntimeError, "preview changed"):
            update.launch("c" * 40)
        self.command.assert_not_called()

    def test_failed_worker_launch_is_retryable(self):
        self.command.return_value = "b" * 40 + "\trefs/heads/main"
        update.check(True)
        self.command.side_effect = RuntimeError("service unavailable")
        with self.assertRaisesRegex(RuntimeError, "service unavailable"):
            update.launch("b" * 40)
        self.assertEqual(update.status_read(self.state)["state"], "failed")

    def test_service_executes_installed_worker_without_user_owned_copy(self):
        self.command.return_value = "b" * 40 + "\trefs/heads/main"
        update.check(True)
        self.command.reset_mock()
        value = update.launch("b" * 40)
        command = self.command.call_args.args[0]
        self.assertEqual(command[-5:], ["/usr/bin/python3", "-I", self.base / "bin/dwm-desktop-update", "worker", value["operation"]])
        self.assertFalse((self.state / "operations" / value["operation"] / "worker.py").exists())

    def test_update_lock_prevents_overlap(self):
        with update.locked(self.state):
            with self.assertRaises(BlockingIOError):
                update.check(True)

    def test_directory_swap_and_preserved_personal_settings(self):
        source = self.base / "source"
        (source / "config/quickshell").mkdir(parents=True)
        (source / "config/quickshell/file").write_text("updated")
        (source / "scripts").mkdir()
        (source / "scripts/helper").write_text("helper")
        personal = self.config / "dwm-titus/themes.toml"
        personal.parent.mkdir()
        personal.write_text("personal settings")
        entries = update.prepare_user(source, "d" * 32)
        for entry in entries:
            update.exchange(Path(entry["target"]), Path(entry["backup"]))
        self.assertEqual((self.config / "quickshell/file").read_text(), "updated")
        self.assertEqual(personal.read_text(), "personal settings")
        for entry in reversed(entries):
            update.exchange(Path(entry["target"]), Path(entry["backup"]))
        self.assertEqual((self.config / "quickshell/file").read_text(), "original")

    def test_local_branch_and_dirty_source_block_updates(self):
        (self.data / ".git").mkdir()
        self.command.return_value = "topic"
        self.assertIn("development branch", update.checkout_reason(self.data))
        self.command.side_effect = ["main", " M scripts/helper"]
        self.assertIn("has changes", update.checkout_reason(self.data))

    def test_git_checkout_is_staged_as_a_clean_fast_forward(self):
        def git(path, *args):
            return subprocess.check_output(["git", "-C", path, "-c", "user.name=Desktop Test",
                                            "-c", "user.email=desktop-test@example.invalid", *args],
                                           stderr=subprocess.PIPE, text=True).strip()

        git(self.data, "init", "-b", "main")
        git(self.data, "add", ".")
        git(self.data, "commit", "-m", "baseline")
        original = git(self.data, "rev-parse", "HEAD")
        source = self.base / "upstream"
        subprocess.run(["git", "clone", "--quiet", self.data, source], check=True)
        (source / "config/quickshell").mkdir()
        (source / "config/quickshell/new.qml").write_text("new shell")
        git(source, "add", ".")
        git(source, "commit", "-m", "new shell")
        with patch.object(update, "run", REAL_RUN):
            entries = update.prepare_user(source, "e" * 32)
        self.assertEqual(git(self.data, "rev-parse", "HEAD"), original)
        self.assertEqual(git(Path(entries[0]["backup"]), "rev-parse", "HEAD"), git(source, "rev-parse", "HEAD"))
        self.assertEqual(git(Path(entries[0]["backup"]), "status", "--porcelain"), "")
        for name in ("config/local-work", "scripts/local-work"):
            local = self.data / name
            local.write_text("untracked work")
            with patch.object(update, "run", REAL_RUN), self.assertRaisesRegex(RuntimeError, "has changes"):
                update.prepare_user(source, "f" * 32)
            self.assertEqual(local.read_text(), "untracked work")
            local.unlink()
        (self.data / ".git/info/exclude").write_text("config/ignored-work\n")
        ignored = self.data / "config/ignored-work"
        ignored.write_text("ignored personal work")
        with patch.object(update, "run", REAL_RUN), self.assertRaisesRegex(RuntimeError, "has changes"):
            update.prepare_user(source, "f" * 32)
        self.assertEqual(ignored.read_text(), "ignored personal work")
        ignored.unlink()
        (self.data / "local-file").write_text("local")
        git(self.data, "add", ".")
        git(self.data, "commit", "-m", "divergent local work")
        with patch.object(update, "run", REAL_RUN), self.assertRaises(RuntimeError):
            update.prepare_user(source, "f" * 32)
        self.assertFalse((self.data.parent / (".dwm-update-" + "f" * 32 + "-0")).exists())
        with patch.object(update, "run", REAL_RUN), patch.object(update, "SOURCE", str(source)):
            self.assertIn("divergent", update.checkout_ancestry_reason(self.data, git(source, "rev-parse", "HEAD")))
            self.assertEqual(update.checkout_ancestry_reason(source, git(source, "rev-parse", "HEAD")), "")

    def test_external_checkout_ancestry_blocks_preview(self):
        external = self.base / "external"
        external.mkdir()
        receipt = update.read_json(self.state / "installed.json")
        receipt["checkout"] = str(external)
        update.write_json(self.state / "installed.json", receipt)
        with patch.object(update, "checkout_ancestry_reason", side_effect=["", "Local source has divergent history."]) as ancestry:
            value = update.check(True)
        self.assertEqual(value["state"], "blocked")
        self.assertFalse(value["canUpdate"])
        ancestry.assert_any_call(external, "a" * 40)

    def test_root_candidate_rejects_changed_destinations_modes_and_links(self):
        privileged.validate_candidate(self.manifest, self.manifest)
        for mutation in ("destination", "mode", "hash", "revision", "packages"):
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(self.manifest)
                if mutation == "destination":
                    candidate["files"]["/etc/shadow"] = candidate["files"].pop(str(self.binary))
                elif mutation == "mode":
                    candidate["files"][str(self.binary)]["mode"] = 0o4755
                elif mutation == "hash":
                    candidate["files"][str(self.binary)]["sha256"] = "bad"
                elif mutation == "revision":
                    candidate["revision"] = "main;echo unsafe"
                else:
                    candidate["packages"] = ["extra-package"]
                with self.assertRaises(RuntimeError):
                    privileged.validate_candidate(candidate, self.manifest)

    def test_user_owned_manifest_cannot_select_a_privileged_helper(self):
        if os.geteuid() == 0:
            os.chown(self.manifest_path, 65534, 65534)
        with self.assertRaisesRegex(RuntimeError, "root-owned"):
            update.trusted_installation(self.manifest_path)

    def test_archive_contains_only_numbered_regular_files(self):
        stage = self.base / "stage"
        blob = stage / str(self.binary).lstrip("/")
        blob.parent.mkdir(parents=True)
        blob.write_bytes(self.binary.read_bytes())
        bundle = self.base / "bundle.tar"
        update.make_bundle(stage, self.manifest, bundle)
        with tarfile.open(bundle) as archive:
            self.assertEqual(archive.getnames(), ["manifest.json", "0"])
            self.assertTrue(all(member.isfile() for member in archive))

    def test_worker_waits_for_launcher_lock(self):
        directory = self.base / "lock-wait"
        process = None
        try:
            with update.locked(directory / "state"):
                process = subprocess.Popen([sys.executable, REPO / "tests/fixtures/desktop-worker-scenario.py",
                                            REPO, directory, "success"])
                log = directory / "state/operations" / ("c" * 32) / "update.log"
                for _ in range(100):
                    if log.exists():
                        break
                    time.sleep(0.02)
                self.assertTrue(log.exists())
                time.sleep(0.1)
                self.assertIsNone(process.poll(), "Worker exited while its launcher held the lock")
            self.assertEqual(process.wait(timeout=10), 0)
            self.assertEqual(update.read_json(directory / "state/status.json")["state"], "restart-required")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()

    def test_activation_waits_for_helper_exit_and_rejects_failure(self):
        waiting = "ExecMainCode=0\nExecMainStatus=0\nExecMainExitTimestampMonotonic=0\nActiveState=active"
        success = "ExecMainCode=1\nExecMainStatus=0\nExecMainExitTimestampMonotonic=123\nActiveState=active"
        self.command.side_effect = ["", waiting, success]
        with patch.object(update.time, "sleep"):
            update.start_activation(self.base, "a" * 32)
        self.assertEqual(self.command.call_count, 3)
        self.command.side_effect = ["", waiting, success.replace("ExecMainStatus=0", "ExecMainStatus=1")]
        with patch.object(update.time, "sleep"), self.assertRaisesRegex(RuntimeError, "restart failed"):
            update.start_activation(self.base, "a" * 32)

    def test_worker_success_failure_denial_and_interruption(self):
        for scenario, expected, code in (("success", "restart-required", 0), ("build-failure", "failed", 1),
                                         ("denied", "failed", 1), ("apply-failure", "interrupted", 1),
                                         ("killed", "installing", 9), ("activation-success", "current", 0),
                                         ("activation-stale", "restart-required", 0),
                                         ("activation-failure", "restart-required", 0)):
            with self.subTest(scenario=scenario):
                directory = self.base / scenario
                result = subprocess.run([sys.executable, REPO / "tests/fixtures/desktop-worker-scenario.py",
                                         REPO, directory, scenario], capture_output=True, text=True,
                                        env={**os.environ, "CC": "test-cc", "CFLAGS": "-O1 -g",
                                             "CPPFLAGS": "-DTEST=1", "LDFLAGS": "-Wl,--as-needed"})
                self.assertEqual(result.returncode, code, result.stderr)
                value = update.read_json(directory / "state/status.json")
                self.assertEqual(value["state"], expected, value)
                self.assertEqual((directory / "config/dwm-titus/themes.toml").read_text(), "personal theme")
                if scenario == "success" or scenario.startswith("activation-"):
                    self.assertEqual((directory / "config/quickshell/file").read_text(), "new shell")
                    self.assertEqual((directory / "prefix/bin/dwm").read_text(), "new binary")
                    entries = update.read_json(directory / "state/operations" / ("c" * 32) / "user-backup.json")
                    for entry in entries:
                        self.assertEqual(Path(entry["backup"]).stat().st_mode & 0o777, 0o700)
                        self.assertEqual(Path(entry["target"]).stat().st_mode & 0o777, entry["originalMode"])
                    self.assertFalse((directory / "state/operations" / ("c" * 32) / "source").exists())
                    if scenario.startswith("activation-"):
                        self.assertEqual(value["activationShells"], [["1", "old"]])
                elif scenario != "killed":
                    self.assertEqual((directory / "config/quickshell/file").read_text(), "old")
                    self.assertEqual((directory / "prefix/bin/dwm").read_text(), "old binary")

    def test_directory_sync_failure_keeps_transaction_unfinished(self):
        directory = self.base / "durability-failure"
        result = subprocess.run([sys.executable, REPO / "tests/fixtures/desktop-worker-scenario.py",
                                 REPO, directory, "durability-failure"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        value = update.read_json(directory / "state/status.json")
        self.assertEqual(value["state"], "interrupted")
        self.assertIn("directory sync failure", value["detail"])
        self.assertFalse((directory / "state/complete-called").exists())
        self.assertFalse((directory / "state/operations" / ("c" * 32) / "completion.json").exists())

    def test_abrupt_private_copy_never_exposes_staging_root(self):
        source, destination = self.base / "private", self.base / "staging"
        source.mkdir(mode=0o700)
        (source / "readable-secret").write_text("private data")
        (source / "readable-secret").chmod(0o644)
        copy = shutil.copy2
        def interrupted(*args, **kwargs):
            copy(*args, **kwargs)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            raise RuntimeError("abrupt copy interruption")
        previous = os.umask(0o022)
        try:
            with patch.object(update.shutil, "copy2", side_effect=interrupted), self.assertRaisesRegex(RuntimeError, "abrupt copy"):
                update.copy_private_tree(source, destination)
        finally:
            os.umask(previous)
        self.assertEqual(destination.stat().st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
