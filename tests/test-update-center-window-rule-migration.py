#!/usr/bin/env python3

import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
MIGRATOR = REPO / "scripts" / "migrate-update-center-window-rule"


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

    def test_existing_matching_identity_is_not_duplicated(self):
        original = '''rules = [
  { title="dwm update center", class="DwmUpdateCenter", instance="dwm-update-center", isfloating=1, noswallow=1 },
]
'''
        result, migrated = self.run_migration(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(migrated, original)

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
        self.assertEqual(len(rules), 2)



if __name__ == "__main__":
    unittest.main()
