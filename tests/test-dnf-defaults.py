#!/usr/bin/env python3
"""Exercise DNF ownership across installation, modification, and removal."""

from pathlib import Path
import subprocess
import os
import importlib.machinery
import importlib.util
from unittest import mock
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True


REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / "scripts/dwm-dnf-defaults"
SOURCE = REPO / "config/dnf/40-dwm-titus.conf"
loader = importlib.machinery.SourceFileLoader("dnf_defaults", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class DefaultsTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="dnf-defaults-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name) / "staged root"
        self.target = self.root / "usr/share/dnf5/libdnf.conf.d/40-dwm-titus.conf"
        self.record = self.root / "var/lib/dwm-titus/dnf-defaults/sha256"
        self.target.parent.mkdir(parents=True)
        self.helper = self.root / "usr/local/libexec/dwm-titus/dwm-dnf-defaults"
        self.helper.parent.mkdir(parents=True)
        self.helper.write_text(HELPER.read_text().replace("@PREFIX@", "/usr/local"))
        self.helper.chmod(0o755)

    def run_helper(self, action, destdir=None):
        subprocess.run(["/usr/bin/python3", "-I", str(self.helper), action,
                        "--destdir", destdir or str(self.root), "--source", str(SOURCE)],
                       check=True, capture_output=True, text=True)

    def assert_no_partial_install(self):
        self.assertFalse(self.target.exists())
        self.assertFalse(self.record.exists())
        self.assertEqual(list(self.root.rglob(".dwm-dnf-*")), [])

    def test_flush_failure_does_not_publish_defaults(self):
        with mock.patch.object(module.os, "fsync", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                module.manage("install", str(self.root), SOURCE)
        self.assert_no_partial_install()

    def test_record_publish_failure_rolls_back_defaults(self):
        with mock.patch.object(module.os, "replace", side_effect=OSError("record failure")):
            with self.assertRaises(OSError):
                module.manage("install", str(self.root), SOURCE)
        self.assert_no_partial_install()

    def test_write_failure_does_not_publish_defaults(self):
        original = module.tempfile.NamedTemporaryFile

        def failing_file(**kwargs):
            output = original(**kwargs)
            output.write = mock.Mock(side_effect=OSError("write failure"))
            return output

        with mock.patch.object(module.tempfile, "NamedTemporaryFile", side_effect=failing_file):
            with self.assertRaises(OSError):
                module.manage("install", str(self.root), SOURCE)
        self.assert_no_partial_install()

    def test_close_failure_does_not_publish_defaults(self):
        original = module.tempfile.NamedTemporaryFile

        class FailingClose:
            def __enter__(self):
                self.file = original(dir=self_dir, prefix=".dwm-dnf-", delete=False)
                return self.file

            def __exit__(self, *_args):
                self.file.close()
                raise OSError("close failure")

        self_dir = self.target.parent
        with mock.patch.object(module.tempfile, "NamedTemporaryFile", return_value=FailingClose()):
            with self.assertRaises(OSError):
                module.manage("install", str(self.root), SOURCE)
        self.assert_no_partial_install()

    @unittest.skipUnless(os.geteuid() == 0, "Root-only installed helper boundary")
    def test_root_rejects_repository_copy(self):
        result = subprocess.run(
            ["/usr/bin/python3", "-I", str(HELPER), "install",
             "--destdir", str(self.root), "--source", str(SOURCE)],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Run the installed DNF defaults helper", result.stderr)
        self.assert_no_partial_install()

    def test_relative_staging_root(self):
        self.run_helper("install", os.path.relpath(self.root))
        self.run_helper("uninstall", os.path.relpath(self.root))
        self.assertFalse(self.target.exists())

    def test_created_defaults_removed_after_repeated_install(self):
        self.run_helper("install")
        self.assertEqual(self.target.read_bytes(), SOURCE.read_bytes())
        self.assertTrue(self.record.exists())
        self.run_helper("install")
        self.run_helper("uninstall")
        self.assertFalse(self.target.exists())
        self.assertFalse(self.record.exists())
        self.run_helper("uninstall")

    def test_make_uninstall_honors_destdir(self):
        self.run_helper("install")
        subprocess.run(["make", "uninstall", f"DESTDIR={self.root}"],
                       cwd=REPO, check=True, capture_output=True, text=True)
        self.assertFalse(self.target.exists())
        self.assertFalse(self.record.exists())

    def test_preexisting_identical_defaults_are_not_adopted(self):
        self.target.write_bytes(SOURCE.read_bytes())
        self.run_helper("install")
        self.assertFalse(self.record.exists())
        self.run_helper("uninstall")
        self.assertEqual(self.target.read_bytes(), SOURCE.read_bytes())

    def test_admin_modified_defaults_preserved_and_ownership_released(self):
        self.run_helper("install")
        self.target.write_text("[main]\ndefaultyes=False\n")
        self.run_helper("install")
        self.run_helper("uninstall")
        self.assertEqual(self.target.read_text(), "[main]\ndefaultyes=False\n")
        self.assertFalse(self.record.exists())

    def test_admin_symlink_replacement_preserved(self):
        self.run_helper("install")
        self.target.unlink()
        self.target.symlink_to(self.root / "absent-admin-config")
        self.run_helper("uninstall")
        self.assertTrue(self.target.is_symlink())
        self.assertFalse(self.record.exists())

    def test_preexisting_symlink_preserved(self):
        self.target.symlink_to(self.root / "absent-admin-config")
        self.run_helper("install")
        self.run_helper("uninstall")
        self.assertTrue(self.target.is_symlink())
        self.assertFalse(self.record.exists())

    def test_deleted_owned_defaults_do_not_break_uninstall(self):
        self.run_helper("install")
        self.target.unlink()
        self.run_helper("uninstall")
        self.assertFalse(self.record.exists())


if __name__ == "__main__":
    unittest.main()
