#!/usr/bin/python3
"""Durable Update Center terminal lifecycle and fixed provider adapters."""
import io
import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CENTER = ROOT / "scripts/dwm-update-center"
RUNNER = ROOT / "scripts/dwm-update-center-terminal"


class Environment(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("DWM_TEST_WORKSPACE") or None)
        self.addCleanup(self.temp.cleanup)
        self.environment = patch.dict(os.environ, {
            "XDG_STATE_HOME": str(Path(self.temp.name) / "state"),
            "XDG_CACHE_HOME": str(Path(self.temp.name) / "cache"),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)


class ReservationTests(Environment):
    def setUp(self):
        super().setUp()
        self.api = runpy.run_path(str(CENTER))

    def test_launch_is_fixed_argv_and_one_active_operation(self):
        calls = []
        class Child:
            pid = 321
        def launch(argv, **options):
            calls.append((argv, options))
            return Child()
        with patch.dict(self.api["launch_operation"].__globals__, subprocess_popen=launch,
                        process_identity=lambda pid: "321:99"):
            first = self.api["launch_operation"]("flatpak", "update", terminal="/usr/bin/dwm-terminal",
                                                  runner="/usr/bin/dwm-update-center-terminal", now=10)
            self.assertRegex(first["operation"], r"^op-[0-9a-f]{32}$")
            self.assertEqual(calls[0][0], ["/usr/bin/dwm-terminal", "/usr/bin/dwm-update-center-terminal",
                                          first["operation"], "flatpak", "update"])
            self.assertFalse(calls[0][1].get("shell", False))
            with self.assertRaisesRegex(BlockingIOError, "active"):
                self.api["launch_operation"]("mise", "update", terminal="/usr/bin/dwm-terminal",
                                              runner="/usr/bin/dwm-update-center-terminal")

    def test_provider_and_action_injection_are_rejected_before_launch(self):
        with patch.dict(self.api["launch_operation"].__globals__, subprocess_popen=lambda *a, **k: self.fail("spawned")):
            for provider in ("fedora;sh", "../mise", "unknown"):
                with self.subTest(provider=provider), self.assertRaises(ValueError):
                    self.api["launch_operation"](provider, "update")
            with self.assertRaises(ValueError):
                self.api["launch_operation"]("fedora", "update;sh")

    def test_malformed_durable_owner_fails_closed_without_replacement(self):
        path = self.api["operation_path"]()
        path.parent.mkdir(parents=True)
        path.write_text("{broken")
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "unsafe or malformed"):
            self.api["reserve_operation"]("fedora", "update")
        self.assertEqual(path.read_bytes(), before)

    def test_terminal_closed_never_claims_success_and_ambiguity_is_retained(self):
        op = self.api["reserve_operation"]("mise", "update", now=10)
        self.api["record_terminal"](op["operation"], 123, "123:7", now=11)
        with patch.dict(self.api["terminal_closed"].__globals__, process_identity=lambda pid: "123:8",
                        rescan_provider=lambda provider: None):
            result = self.api["terminal_closed"](op["operation"], now=12)
        self.assertEqual((result["phase"], result["outcome"]), ("interrupted", "unknown"))
        self.assertEqual(self.api["active_operation"]()["operation"], op["operation"])


class RunnerTests(Environment):
    def setUp(self):
        super().setUp()
        self.api = runpy.run_path(str(RUNNER))
        self.operation = "op-" + "a" * 32

    def run_adapter(self, provider, action, responses=None):
        calls = []
        responses = list(responses or [])
        def command(argv, **options):
            calls.append((argv, options))
            value = responses.pop(0) if responses else ""
            if isinstance(value, Exception):
                raise value
            return value
        with patch.dict(self.api["execute_provider"].__globals__, run_command=command,
                        executable=lambda name: "/usr/bin/" + name,
                        trusted_desktop_helper=lambda: "/usr/bin/dwm-desktop-update"):
            result = self.api["execute_provider"](self.operation, provider, action)
        return result, calls

    def test_fedora_uses_packagekit_snapshot_update_watch_and_reconciliation(self):
        snapshot = "snapshot-generation\t" + "b" * 64 + "\n"
        handoff = "terminal-handoff\top-" + "c" * 32 + "\tupdates-install-all\tupdate\n"
        result, calls = self.run_adapter("fedora", "update", [snapshot, handoff, "terminal\tsucceeded\n", snapshot])
        self.assertEqual([call[0][1] for call in calls], ["snapshot", "updates-install-all", "watch-operation", "snapshot"])
        self.assertEqual(calls[1][0][2], "b" * 64)
        self.assertEqual(result["outcome"], "succeeded")

    def test_desktop_uses_trusted_status_check_start_and_recover(self):
        ready = json.dumps({"schema": 1, "state": "available", "installed": "a" * 40,
                            "available": "b" * 40, "canUpdate": True, "detail": "Ready", "restart": "none"})
        done = json.dumps({"schema": 1, "state": "current", "installed": "b" * 40,
                           "available": "b" * 40, "canUpdate": False, "detail": "Done", "restart": "session"})
        result, calls = self.run_adapter("dwm-titus", "update", [ready, ready, done, done])
        self.assertEqual([call[0][1] for call in calls], ["status", "check", "start", "status"])
        self.assertEqual(calls[2][0][2], "b" * 40)
        self.assertEqual((result["outcome"], result["restart"]), ("succeeded", "session"))
        interrupted = json.dumps({**json.loads(ready), "state": "interrupted", "operation": "d" * 32})
        _, calls = self.run_adapter("dwm-titus", "recover", [interrupted, done])
        self.assertEqual([call[0][1] for call in calls], ["status", "recover"])
        self.assertEqual(calls[1][0][2], "d" * 32)

    def test_flatpak_system_first_partial_and_recovery_rechecks_both_scopes(self):
        result, calls = self.run_adapter("flatpak", "update")
        self.assertEqual([call[0][1:] for call in calls], [["update", "--system", "--noninteractive"],
            ["update", "--user", "--noninteractive"]])
        self.assertEqual(result["outcome"], "succeeded")
        result, calls = self.run_adapter("flatpak", "update", ["", subprocess.CalledProcessError(1, ["flatpak"])])
        self.assertEqual(result["phase"], "system-complete/user-failed")
        self.assertNotIn("rollback", result["detail"].lower())
        with patch.dict(self.api["execute_provider"].__globals__, executable=lambda name: "/usr/bin/flatpak",
                        scan_flatpak_scope=lambda executable, scope: calls.append((scope, {}))):
            self.api["execute_provider"](self.operation, "flatpak", "recover")
        self.assertEqual([entry[0] for entry in calls[-2:]], ["system", "user"])

    def test_mise_uses_managed_inventory_and_preserves_cooldown(self):
        inventory = json.dumps({"node": [{"version": "20", "installed": True}]})
        result, calls = self.run_adapter("mise", "update", [inventory, "", inventory])
        self.assertEqual(calls[0][0][1:], ["ls", "--installed", "--json"])
        self.assertEqual(calls[1][0][1:], ["upgrade", "--", "node@20"])
        self.assertNotIn("MISE_MINIMUM_RELEASE_AGE", calls[1][0])
        self.assertEqual(result["outcome"], "succeeded")

    def test_completion_prompt_for_success_and_failure_and_test_stream(self):
        for outcome in ("succeeded", "failed"):
            output = io.StringIO()
            self.api["completion_hold"]({"outcome": outcome}, input_stream=io.StringIO("x"), output=output)
            self.assertIn("Done. Press any key to close", output.getvalue())


if __name__ == "__main__":
    unittest.main()
