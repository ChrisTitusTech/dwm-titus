#!/usr/bin/env python3

import os
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
MIGRATOR = REPO / "scripts" / "dwm-migrate-update-center-window-rule"


class UpdateCenterWindowRuleMigrationTests(unittest.TestCase):
    def run_migration(self, contents):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "window-rules.toml"
            config.write_text(contents)
            result = subprocess.run(
                [sys.executable, str(MIGRATOR), str(config)],
                check=False,
                capture_output=True,
                text=True,
            )
            return result, config.read_text()

    def test_adds_only_the_required_rule_and_is_idempotent(self):
        original = '''# custom marker
rules = [
  { class="Alacritty", isterminal=1 },
]
'''
        result, migrated = self.run_migration(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("# custom marker", migrated)
        rules = tomllib.loads(migrated)["rules"]
        expected = {
            "title": "dwm update center",
            "class": "DwmUpdateCenter",
            "instance": "dwm-update-center",
            "isfloating": 1,
            "noswallow": 1,
        }
        self.assertEqual(sum(rule == expected for rule in rules), 1)

        result, repeated = self.run_migration(migrated)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(repeated, migrated)

    def test_direct_migration_keeps_original_recovery_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "window-rules.toml"
            original = '# personal rules\nrules = [{class="Editor", isfloating=1}]\n'
            config.write_text(original)
            config.chmod(0o640)
            subprocess.run([sys.executable, str(MIGRATOR), str(config)], check=True, capture_output=True)
            backups = list(config.parent.glob("window-rules.toml.before-update-center.*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o640)
            subprocess.run([sys.executable, str(MIGRATOR), str(config)], check=True, capture_output=True)
            self.assertEqual(list(config.parent.glob("window-rules.toml.before-update-center.*")), backups)

    def test_relative_xdg_config_uses_home_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".config/dwm-titus/window-rules.toml"
            config.parent.mkdir(parents=True)
            config.write_text("rules = []\n")
            subprocess.run([sys.executable, str(MIGRATOR)], check=True, capture_output=True,
                           env={**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": "relative"})
            self.assertIn('class="DwmUpdateCenter"', config.read_text())

    def test_fifo_is_rejected_without_blocking(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "window-rules.toml"
            os.mkfifo(config)
            original = config.lstat()
            result = subprocess.run([sys.executable, str(MIGRATOR), str(config)],
                                    capture_output=True, text=True, timeout=3)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("regular file", result.stderr)
            self.assertEqual(config.lstat().st_ino, original.st_ino)
            self.assertEqual(config.lstat().st_mode, original.st_mode)

    def test_existing_matching_identity_is_not_duplicated(self):
        original = '''rules = [
  { title="dwm update center", class="DwmUpdateCenter", instance="dwm-update-center", isfloating=1, noswallow=1 },
]
'''
        result, migrated = self.run_migration(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        rules = tomllib.loads(migrated)["rules"]
        self.assertEqual(len(rules), 4)
        self.assertEqual(sum(rule.get("class") == "DwmUpdateCenter" for rule in rules), 2)
        self.assertEqual(rules[-1]["title"], "dwm update center tiled")
        self.assertEqual(rules[-1]["isfloating"], 0)

    def test_invalid_config_is_preserved_and_rejected(self):
        original = "rules = [\n  { broken = },\n]\n"
        result, migrated = self.run_migration(original)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid TOML", result.stderr)
        self.assertEqual(migrated, original)

    def test_adds_rule_when_last_rule_lacks_trailing_comma(self):
        original = '''rules = [
  { class="Alacritty", isterminal=1 }
]
'''
        result, migrated = self.run_migration(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        rules = tomllib.loads(migrated)["rules"]
        self.assertEqual(len(rules), 5)



if __name__ == "__main__":
    unittest.main()
