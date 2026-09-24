#!/usr/bin/env python3
"""Exercise DNF ownership across installation, modification, and removal."""

from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / "scripts/dwm-dnf-defaults"
SOURCE = REPO / "config/dnf/40-dwm-titus.conf"


class DefaultsTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="dnf-defaults-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name) / "staged root"
        self.target = self.root / "usr/share/dnf5/libdnf.conf.d/40-dwm-titus.conf"
        self.record = self.root / "var/lib/dwm-titus/dnf-defaults/sha256"
        self.target.parent.mkdir(parents=True)

    def run_helper(self, action):
        subprocess.run(["/usr/bin/python3", "-I", str(HELPER), action,
                        "--destdir", str(self.root), "--source", str(SOURCE)],
                       check=True, capture_output=True, text=True)

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
