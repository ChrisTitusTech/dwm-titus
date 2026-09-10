#!/usr/bin/env python3
"""Automatic display profiles: isolated filesystem and mocked RandR evidence."""
import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch


sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader(
    "profiles", str(Path(__file__).resolve().parents[1] / "scripts/dwm-settings-display-profiles"))
spec = importlib.util.spec_from_loader(loader.name, loader)
profiles = importlib.util.module_from_spec(spec)
loader.exec_module(profiles)


class ProfilesTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name) / "autorandr"
        self.addCleanup(patch.stopall)
        patch.object(profiles, "ROOT", self.root).start()
        patch.object(profiles.shutil, "which", return_value="/usr/bin/autorandr").start()
        self.commands = []
        patch.object(profiles, "run", side_effect=self.fake_run).start()
        self.docked = ["eDP-1|0|||0|0|normal|0", "DVI-I-2-2|1|2560x1440|60.00|2560|0|normal|1",
                       "DVI-I-1-1|1|2560x1440|60.00|0|0|normal|0"]
        self.mobile = ["eDP-1|1|2560x1600|90.00|0|0|normal|1",
                       "DVI-I-2-2|0|||0|0|normal|0", "DVI-I-1-1|0|||0|0|normal|0"]

    def fake_run(self, *args):
        self.commands.append(args)
        if args[-1] == "--fingerprint":
            return "eDP-1 abcdef\nDVI-I-2-2 123abc\nDVI-I-1-1 345abc\n"
        if args[-1] == "discover":
            return ("display-protocol\t1\n"
                    "output\teDP-1\t0\t0\t\t0\t0\tnormal\tunsupported\n"
                    "output\tDVI-I-2-2\t1\t1\t2560x1440\t2560\t0\tnormal\tunsupported\n"
                    "output\tDVI-I-1-1\t1\t0\t2560x1440\t0\t0\tnormal\tunsupported\n"
                    "mode\teDP-1\t2560x1600\t90.00\t0\t1\n"
                    "mode-size\teDP-1\t2560x1600\t90.00\t2560\t1600\n"
                    "mode\tDVI-I-2-2\t2560x1440\t60.00\t1\t1\n"
                    "mode\tDVI-I-1-1\t2560x1440\t60.00\t1\t1\n")
        if args[-1] == "--detected":
            return "docked\n"
        if args[-1] == "--current":
            return ""
        raise AssertionError(f"Unexpected command / mutation: {args}")

    def test_docked_save_and_status(self):
        result = profiles.save("docked", self.docked)
        config = (self.root / "docked/config").read_text()
        self.assertNotIn("crtc", config)
        self.assertNotIn("x-prop", config)
        self.assertIn("skip-options = set,crtc", (self.root / "settings.ini").read_text())
        state = profiles.status()
        self.assertEqual(state["detected"], ["docked"])
        self.assertEqual(state["current"], [])
        self.assertTrue(state["profiles"][1]["saved"])
        self.assertEqual(Path(result["backup"]).parent.name, "display-profile-backups")

    def test_legacy_root_precedes_xdg(self):
        home = Path(self.work.name) / "home"
        home.mkdir()
        with patch.object(profiles.Path, "home", return_value=home), patch.dict(profiles.os.environ, {"XDG_CONFIG_HOME": str(self.root.parent)}):
            self.assertEqual(profiles.profile_root(), self.root)
            (home / ".autorandr").mkdir()
            self.assertEqual(profiles.profile_root(), home / ".autorandr")

    def test_settings_merge_preserves_choices_and_backup(self):
        self.root.mkdir()
        before = "[config]\nskip-options=gamma,--crtc\nmatch-edid=true\n[other]\nvalue=kept\n"
        (self.root / "settings.ini").write_text(before)
        result = profiles.save("docked", self.docked)
        parser = profiles.configparser.ConfigParser()
        parser.read(self.root / "settings.ini")
        self.assertEqual(parser.get("config", "skip-options"), "gamma,--crtc,set")
        self.assertEqual(parser.get("config", "match-edid"), "true")
        self.assertEqual(parser.get("other", "value"), "kept")
        self.assertEqual((Path(result["backup"]) / "settings.ini").read_text(), before)

    def test_settings_failure_rolls_back_profile(self):
        profiles.save("docked", self.docked)
        before = (self.root / "docked/config").read_text()
        (self.root / "settings.ini").write_text("[config]\nskip-options=gamma\n")
        replace = profiles.os.replace
        def fail_settings(source, destination):
            if Path(destination).name == "settings.ini":
                raise OSError("simulated settings failure")
            return replace(source, destination)
        with patch.object(profiles.os, "replace", side_effect=fail_settings), self.assertRaises(ValueError):
            profiles.save("docked", self.docked)
        self.assertEqual((self.root / "docked/config").read_text(), before)
        self.assertEqual((self.root / "settings.ini").read_text(), "[config]\nskip-options=gamma\n")

    def test_undocked_fingerprint_and_default(self):
        profiles.save("undocked", self.mobile)
        self.assertEqual((self.root / "mobile/setup").read_text(), "eDP-1 abcdef\n")
        self.assertNotIn("DVI", (self.root / "mobile/config").read_text())
        self.assertEqual((self.root / "default").readlink(), Path("mobile"))
        self.assertEqual(profiles.profile(self.root / "mobile/config")[0]["pixelWidth"], 2560)

    def test_overwrite_has_recoverable_backup(self):
        profiles.save("docked", self.docked)
        before = (self.root / "docked/config").read_text()
        (self.root / "docked/postswitch").write_text("custom hook")
        result = profiles.save("docked", self.docked)
        self.assertEqual((Path(result["backup"]) / "profile/config").read_text(), before)
        self.assertEqual((self.root / "docked/postswitch").read_text(), "custom hook")

    def test_profile_without_config_preserves_hook(self):
        destination = self.root / "docked"
        destination.mkdir(parents=True)
        (destination / "postswitch").write_text("custom hook")
        profiles.save("docked", self.docked)
        self.assertEqual((destination / "postswitch").read_text(), "custom hook")
        self.assertTrue(profiles.status()["profiles"][1]["saved"])

    def test_reject_invalid_and_unsafe_layouts(self):
        for role, specs in [("other", self.docked), ("undocked", self.docked),
                            ("docked", self.mobile), ("docked", self.docked[1:]),
                            ("docked", self.docked + self.docked[:1]),
                            ("docked", [s.replace("60.00", "42.00") for s in self.docked]),
                            ("docked", [s.replace("2560|0", "-1|0") for s in self.docked]),
                            ("docked", [s.replace("normal|1", "normal|0") for s in self.docked])]:
            with self.subTest(role=role, specs=specs), self.assertRaises(ValueError):
                profiles.save(role, specs)
        self.assertFalse(self.root.exists())

    def test_symlink_directory_is_not_overwritten(self):
        self.root.mkdir()
        target = Path(self.work.name) / "outside"
        target.mkdir()
        (self.root / "docked").symlink_to(target)
        with self.assertRaises(ValueError):
            profiles.save("docked", self.docked)
        self.assertEqual(list(target.iterdir()), [])

    def test_existing_unsupported_options_are_not_lost(self):
        profiles.save("docked", self.docked)
        path = self.root / "docked/config"
        path.write_text(path.read_text() + "transform 1,0,0,0,1,0,0,0,1\n")
        before = path.read_text()
        with self.assertRaises(ValueError):
            profiles.save("docked", self.docked)
        self.assertEqual(path.read_text(), before)
        self.assertIn("Unsupported", profiles.status()["profiles"][1]["error"])

    def test_missing_autorandr_is_isolated(self):
        with patch.object(profiles.shutil, "which", return_value=None):
            self.assertFalse(profiles.status()["available"])
            with self.assertRaises(ValueError):
                profiles.save("docked", self.docked)

    def test_publish_failure_restores_previous_profile(self):
        profiles.save("docked", self.docked)
        before = (self.root / "docked/config").read_text()
        replace = profiles.os.replace
        def fail_publish(source, destination):
            if Path(source).name == "staged":
                raise OSError("simulated publish failure")
            return replace(source, destination)
        with patch.object(profiles.os, "replace", side_effect=fail_publish), self.assertRaises(ValueError):
            profiles.save("docked", self.docked)
        self.assertEqual((self.root / "docked/config").read_text(), before)

    def test_default_failure_restores_previous_profile(self):
        profiles.save("undocked", self.mobile)
        (self.root / "settings.ini").unlink()
        before = (self.root / "mobile/config").read_text()
        replace = profiles.os.replace
        def fail_default(source, destination):
            if Path(destination).name == "default":
                raise OSError("simulated default failure")
            return replace(source, destination)
        with patch.object(profiles.os, "replace", side_effect=fail_default), self.assertRaises(ValueError):
            profiles.save("undocked", self.mobile)
        self.assertEqual((self.root / "mobile/config").read_text(), before)
        self.assertEqual((self.root / "default").readlink(), Path("mobile"))
        self.assertFalse((self.root / "settings.ini").exists())


if __name__ == "__main__":
    unittest.main()
