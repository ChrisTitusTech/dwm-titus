#!/usr/bin/env python3
"""Configuration preservation, transaction, GPU-policy and session isolation tests."""

import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

loader = importlib.machinery.SourceFileLoader(
    "picom_settings",
    str(Path(__file__).resolve().parents[1] / "scripts/dwm-settings-picom"),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
picom = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
loader.exec_module(picom)


class PicomTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.config = self.home / "config"
        self.config.mkdir(mode=0o700)
        self.path = self.config / "picom.conf"
        self.env = patch.dict(
            os.environ,
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config),
                "XDG_CONFIG_DIRS": str(self.home / "vendor"),
                "XDG_STATE_HOME": str(self.home / "state"),
                "DISPLAY": "",
                "DWM_PICOM_CONFIG": "",
                "PICOM_BACKEND": "",
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        self.running = patch.object(picom, "processes", return_value=[])
        self.running.start()
        self.addCleanup(self.running.stop)
        self.which = patch.object(picom.shutil, "which", return_value="/usr/bin/picom")
        self.which.start()
        self.addCleanup(self.which.stop)

    def write(self, text):
        self.path.write_text(text)
        return picom.Configuration()

    def apply(self, config, active=90, inactive=75):
        return picom.mutate("set-opacity", [active, inactive], config.revision())

    def test_display_screen_identity(self):
        self.assertEqual(picom.display_name(":0.0"), picom.display_name("unix:0"))
        self.assertNotEqual(picom.display_name(":0.1"), picom.display_name(":0"))
        self.assertEqual(picom.display_name("host:2.1"), "host:2.1")

    def test_backup_history_is_bounded(self):
        self.write("active-opacity=.8;")
        for value in range(70, 84):
            self.apply(picom.Configuration(), value)
        backups = list(picom.private_dir().glob("backup-*"))
        self.assertEqual(len(backups), 10)
        self.assertTrue(all((p / "manifest.json").exists() for p in backups))

    def test_rollback_continues_after_concurrent_removal(self):
        child = self.config / "inactive.conf"
        child.write_text("inactive-opacity=.6;")
        original = '@include "inactive.conf"\nactive-opacity=.8;'
        config = self.write(original)
        process = {"pid": 123, "identity": "1", "args": ["picom"]}

        def fail_launch(*args, **kwargs):
            child.unlink()
            raise picom.Error("failed")

        with (
            patch.object(picom, "processes", return_value=[process]),
            patch.object(picom, "stop"),
            patch.object(picom, "launch", side_effect=fail_launch),
            self.assertRaisesRegex(picom.Error, "newer edits preserved"),
        ):
            self.apply(config)
        self.assertFalse(child.exists())
        self.assertEqual(self.path.read_text(), original)

    def test_failed_backend_retry_preserves_both_logs(self):
        child = Mock()
        child.poll.return_value = 1

        def launch(command, **kwargs):
            kwargs["stdout"].write(command[-1] + " failed\n")
            return child

        with (
            patch.object(picom, "owner", return_value=0),
            patch.object(picom, "renderer", return_value="intel"),
            patch.object(picom.subprocess, "Popen", side_effect=launch),
            self.assertRaises(picom.Error),
        ):
            picom.launch(picom.Configuration())
        self.assertEqual(
            (picom.private_dir() / "session.log").read_text(),
            "glx failed\nxrender failed\n",
        )

    def test_missing_creates_only_on_edit(self):
        state = picom.status(False)
        self.assertFalse(self.path.exists())
        self.assertTrue(state["editable"])
        self.assertEqual(state["active"], 100)
        self.apply(picom.Configuration())
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_preserves_comments_nested_keys_and_format(self):
        text = '# active-opacity = .1;\nactive-opacity=.98; // active\ninactive-opacity = 0.8\nbackend="glx";\nwintypes: { tooltip = { opacity = 0.5; }; };\n'
        config = self.write(text)
        self.apply(config)
        expected = text.replace("active-opacity=.98", "active-opacity=0.9").replace(
            "inactive-opacity = 0.8", "inactive-opacity = 0.75"
        )
        self.assertEqual(self.path.read_text(), expected)
        self.assertTrue(list((self.home / "state/dwm-titus/picom").glob("backup-*")))

    def test_includes_preserved_and_changed_at_source(self):
        child = self.config / "opacity.conf"
        child.write_text("active-opacity = .7; inactive-opacity = .6;\n")
        config = self.write('@include "opacity.conf"\nbackend = "glx";\n')
        self.apply(config)
        self.assertEqual(
            self.path.read_text(), '@include "opacity.conf"\nbackend = "glx";\n'
        )
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))

    def test_nested_includes_use_root_directory(self):
        sub = self.config / "sub"
        sub.mkdir()
        (sub / "child.conf").write_text('@include "values.conf"')
        values = self.config / "values.conf"
        values.write_text("active-opacity=.7; inactive-opacity=.6;")
        decoy = sub / "values.conf"
        decoy.write_text("active-opacity=.1;")
        config = self.write('@include "sub/child.conf"')
        self.assertEqual(config.opacity(), (0.7, 0.6))
        self.apply(config)
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))
        self.assertEqual(decoy.read_text(), "active-opacity=.1;")

    def test_include_cycle_and_duplicates(self):
        self.path.write_text('@include "picom.conf"')
        with self.assertRaises(picom.Error):
            picom.Configuration()
        with self.assertRaises(picom.Error):
            self.write("active-opacity=1; active-opacity=.5;")

    def test_session_delegates_unsupported_editor_syntax(self):
        self.path.write_text('backend="xrender"; wintypes={\n@include "types.conf"\n};')
        config = picom.session_configuration()
        self.assertIsInstance(config, picom.NativeConfiguration)
        self.assertEqual(config.path, self.path)
        self.assertFalse(picom.status(False)["editable"])
        with self.assertRaises(picom.Error):
            picom.Configuration()

    def test_modern_rules_preserve_custom_exceptions(self):
        custom = "{ match=\"class_g = 'Alacritty'\"; opacity=.8; shadow=false; }"
        config = self.write("rules = (" + custom + ');\nbackend="glx";\n')
        self.apply(config)
        self.assertIn(custom, self.path.read_text())
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))
        self.assertLess(
            self.path.read_text().index(picom.END), self.path.read_text().index(custom)
        )
        self.apply(picom.Configuration(), 88, 66)
        self.assertEqual(self.path.read_text().count(picom.BEGIN), 1)
        self.assertEqual(picom.Configuration().opacity(), (0.88, 0.66))

    def test_empty_modern_rules(self):
        self.apply(self.write("rules=();"))
        self.apply(picom.Configuration(), 100, 100)
        self.assertEqual(picom.Configuration().opacity(), (1, 1))

    def test_stale_revision_no_overwrite(self):
        config = self.write("active-opacity=.8;")
        self.path.write_text("active-opacity=.6;")
        with self.assertRaisesRegex(picom.Error, "changed"):
            self.apply(config)
        self.assertEqual(self.path.read_text(), "active-opacity=.6;")

    def test_invalid_range_and_syntax(self):
        config = self.write("active-opacity=.8;")
        for value in (-1, 101, float("nan"), float("inf")):
            with self.assertRaises(picom.Error):
                self.apply(config, value)
        for text in (
            "active-opacity=oops;",
            "rules=({foo=1;",
            'active-opacity="oops";',
        ):
            with self.assertRaises(picom.Error):
                self.write(text).opacity()

    def test_owned_symlink_preserved(self):
        target = self.home / "dotfiles.conf"
        target.write_text("active-opacity=.8;")
        self.path.symlink_to(target)
        self.apply(picom.Configuration())
        self.assertTrue(self.path.is_symlink())
        self.assertIn("0.9", target.read_text())

    def test_readonly_or_shared_path_rejected(self):
        self.write("active-opacity=.8;")
        self.path.chmod(0o444)
        self.assertFalse(picom.status(False)["editable"])
        with self.assertRaises(picom.Error):
            self.apply(picom.Configuration())
        self.path.chmod(0o666)
        with self.assertRaises(picom.Error):
            self.apply(picom.Configuration())

    def test_failed_activation_restores_bytes(self):
        original = "active-opacity=.8; # my choice\n"
        config = self.write(original)
        process = {"pid": 123, "identity": "1", "args": ["picom"]}
        with (
            patch.object(picom, "processes", return_value=[process]),
            patch.object(picom, "stop"),
            patch.object(picom, "launch", side_effect=picom.Error("failed")),
            self.assertRaisesRegex(picom.Error, "restored"),
        ):
            self.apply(config)
        self.assertEqual(self.path.read_text(), original)

    def test_candidate_validation_precedes_publication(self):
        config = self.write("active-opacity=.8;")
        with (
            patch.object(
                picom, "validate_candidate", side_effect=picom.Error("bad syntax")
            ),
            self.assertRaises(picom.Error),
        ):
            self.apply(config)
        self.assertEqual(self.path.read_text(), "active-opacity=.8;")

    def test_validation_stages_relative_includes(self):
        child = self.config / "child.conf"
        child.write_text("active-opacity=.8;")
        config = self.write('@include "child.conf"')

        def validate(path):
            staged = picom.Configuration(path)
            self.assertEqual(staged.opacity(), (0.9, 0.75))
            return ""

        with (
            patch.dict(os.environ, DISPLAY=":99"),
            patch.object(picom, "diagnostics", side_effect=validate),
        ):
            picom.validate_candidate(
                config, config.opacity_changes(0.9, 0.75), self.path
            )
        self.assertEqual(child.read_text(), "active-opacity=.8;")

    def test_backend_precedence_and_auto(self):
        config = self.write('backend="glx"; # preserve\n')
        with patch.object(picom, "renderer", return_value="nvidia"):
            self.assertEqual(picom.backend(config)[1], "glx")
        picom.mutate("set-backend", ["auto"], config.revision())
        self.assertIn("# preserve", self.path.read_text())
        self.assertNotIn("backend=", self.path.read_text())
        for gpu, expected in [
            ("intel", "glx"),
            ("amd", "glx"),
            ("nvidia", "xrender"),
            ("unknown", "xrender"),
            ("software", "xrender"),
        ]:
            with patch.object(picom, "renderer", return_value=gpu):
                self.assertEqual(picom.backend(picom.Configuration())[1], expected)
        with patch.dict(os.environ, PICOM_BACKEND="egl"):
            self.assertEqual(picom.backend(picom.Configuration())[1:3], ("egl", "egl"))
            with self.assertRaises(picom.Error):
                picom.mutate("set-backend", ["glx"], picom.Configuration().revision())

    def test_active_renderer_not_pci_inventory(self):
        for vendor, gl, accelerated, expected in [
            ("Intel", "Mesa Intel Graphics", 1, "intel"),
            ("NVIDIA Corporation", "RTX", 1, "nvidia"),
            ("Mesa", "llvmpipe", 0, "software"),
        ]:
            text = (
                f"* GL: {vendor}\n* GL renderer: {gl}\n* Accelerated: {accelerated}\n"
            )
            with patch.object(picom, "diagnostics", return_value=text):
                self.assertEqual(picom.renderer(picom.Configuration()), expected)

    def test_reload_does_not_start_stopped_compositor(self):
        with patch.object(picom, "launch") as launch:
            self.assertIn("stopped", picom.activate(picom.Configuration(), "reload"))
            launch.assert_not_called()

    def test_missing_picom_status(self):
        with patch.object(picom.shutil, "which", return_value=None):
            result = picom.status(False)
            self.assertFalse(result["editable"])
            self.assertIn("not installed", result["detail"])

    def test_command_line_config_selection(self):
        explicit = self.home / "other.conf"
        explicit.write_text("active-opacity=.7;")
        with patch.object(
            picom,
            "processes",
            return_value=[{"args": ["picom", "--config", str(explicit)]}],
        ):
            self.assertEqual(picom.source_path(), explicit)

    def test_copy_vendor_config_does_not_overwrite(self):
        vendor = self.home / "vendor"
        vendor.mkdir()
        source = vendor / "picom.conf"
        source.write_text('backend="glx";')
        config = picom.Configuration()
        picom.mutate("copy-config", [], config.revision())
        self.assertEqual(self.path.read_text(), source.read_text())
        with self.assertRaises(picom.Error):
            picom.mutate("copy-config", [], picom.Configuration().revision())

    def test_copy_vendor_shader_references(self):
        vendor = self.home / "vendor"
        vendor.mkdir()
        (vendor / "custom.frag").write_text("shader")
        source = vendor / "picom.conf"
        source.write_text(
            'window-shader-fg="custom.frag"; root-pixmap-shader="custom.frag";'
            "window-shader-fg-rule=[\"custom.frag:name = 'x'\", \"default:name = 'y'\"];"
            'rules=({shader="custom.frag";}, {shader={path="custom.frag"; defines={COLOR="red";};};});'
        )
        picom.mutate("copy-config", [], picom.Configuration().revision())
        copied = self.path.read_text()
        self.assertEqual(copied.count(str(vendor / "custom.frag")), 5)
        self.assertIn('COLOR="red"', copied)
        self.assertIn("default:name = 'y'", copied)
        self.assertIn('window-shader-fg="custom.frag"', source.read_text())

    def test_copy_vendor_include_graph_is_editable(self):
        vendor = self.home / "vendor"
        vendor.mkdir()
        source = vendor / "picom.conf"
        included = vendor / "opacity.conf"
        included.write_text("active-opacity=.7; inactive-opacity=.6;")
        included.chmod(0o444)
        source.write_text('@include "opacity.conf"\nbackend="glx";')
        source.chmod(0o444)
        config = picom.Configuration()
        picom.mutate("copy-config", [], config.revision())
        self.assertTrue(picom.status(False)["editable"])
        self.apply(picom.Configuration())
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))
        self.assertEqual(
            included.read_text(), "active-opacity=.7; inactive-opacity=.6;"
        )

    def test_launch_implicit_discovery_and_daemon_readiness(self):
        child = Mock()
        child.poll.return_value = 0
        with (
            patch.object(picom, "owner", side_effect=[0, *([1] * 50)]),
            patch.object(picom, "processes", return_value=[{"pid": 123}]),
            patch.object(picom.subprocess, "Popen", return_value=child) as popen,
        ):
            picom.launch(
                picom.Configuration(self.path),
                previous=["picom", "--daemon", "--vsync"],
            )
        command = popen.call_args.args[0]
        self.assertNotIn("--config", command)
        self.assertNotIn("/dev/null", command)
        self.assertIn("--daemon", command)
        self.assertIn("--vsync", command)

    def test_marker_outside_rules_is_rejected(self):
        config = self.write(
            "# dwm-titus opacity defaults begin\n# opacity = .1; opacity = .2;\n# dwm-titus opacity defaults end\nrules=();"
        )
        with self.assertRaises(picom.Error):
            self.apply(config)

    def test_crlf_is_preserved(self):
        self.path.write_bytes(b"active-opacity=.8;\r\n# comment\r\n")
        self.apply(picom.Configuration())
        self.assertIn(b"# comment\r\n", self.path.read_bytes())

    def test_system_xdg_include_search_order(self):
        vendor = self.home / "vendor/picom/include"
        vendor.mkdir(parents=True)
        (vendor / "opacity.conf").write_text("active-opacity=.7; inactive-opacity=.6;")
        config = self.write('@include "opacity.conf"')
        self.assertEqual(config.opacity(), (0.7, 0.6))
        self.apply(config)
        self.assertEqual(picom.Configuration().opacity(), (0.9, 0.75))
        (self.config / "opacity.conf").write_text("active-opacity=.4;")
        self.assertEqual(picom.Configuration().opacity(), (0.4, 1.0))

    def test_attached_short_opacity_override(self):
        config = self.write('backend="xrender";')
        for arguments in (
            ["-i0.4"],
            ["-i=.4"],
            ["-bi0.4"],
            ["-bi", "0.4"],
            ["-bcfi", "0.4"],
            ["-i", "0.4"],
        ):
            with patch.object(
                picom, "processes", return_value=[{"args": ["picom", *arguments]}]
            ):
                self.assertFalse(picom.status(False)["editable"])
                with self.assertRaisesRegex(picom.Error, "command-line opacity"):
                    self.apply(config)


if __name__ == "__main__":
    unittest.main()
