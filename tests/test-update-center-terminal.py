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
                        validate_provider_action=lambda provider, action: None,
                        process_identity=lambda pid: "321:99"):
            first = self.api["launch_operation"]("flatpak", "update", terminal="/usr/bin/dwm-terminal",
                                                  runner="/usr/bin/dwm-update-center-terminal", now=10)
            self.assertRegex(first["operation"], r"^op-[0-9a-f]{32}$")
            self.assertEqual(calls[0][0], ["/usr/bin/dwm-terminal", "-e", "/usr/bin/dwm-update-center-terminal",
                                          first["operation"], "flatpak", "update"])
            self.assertFalse(calls[0][1].get("shell", False))
            with self.assertRaisesRegex(BlockingIOError, "active"):
                self.api["launch_operation"]("mise", "update", terminal="/usr/bin/dwm-terminal",
                                              runner="/usr/bin/dwm-update-center-terminal")

    def test_provider_and_action_injection_are_rejected_before_launch(self):
        with patch.dict(self.api["launch_operation"].__globals__, subprocess_popen=lambda *a, **k: self.fail("spawned"),
                        validate_provider_action=lambda provider, action: (_ for _ in ()).throw(ValueError("invalid"))):
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
        with patch.dict(self.api["terminal_closed"].__globals__, process_identity=lambda pid: None,
                        rescan_provider=lambda provider: None):
            repeated = self.api["terminal_closed"](op["operation"], now=13)
        self.assertEqual((repeated["phase"], repeated["outcome"]), ("interrupted", "unknown"))

    def test_matching_interrupted_owner_can_reserve_recovery_but_other_provider_cannot(self):
        previous = self.api["reserve_operation"]("flatpak", "update", now=10)
        self.api["update_operation"](previous["operation"], phase="interrupted", outcome="unknown")
        with self.assertRaises(BlockingIOError):
            self.api["reserve_operation"]("mise", "recover", now=11)
        recovery = self.api["reserve_operation"]("flatpak", "recover", now=12)
        self.assertEqual((recovery["provider"], recovery["action"], recovery["phase"]),
                         ("flatpak", "recover", "reserved"))
        self.assertEqual(recovery["recovery_of"], previous["operation"])

    def test_recovery_waits_until_interrupted_terminal_is_really_gone(self):
        previous = self.api["reserve_operation"]("mise", "update", now=10)
        self.api["record_terminal"](previous["operation"], 555, "555:9", now=11)
        self.api["update_operation"](previous["operation"], phase="interrupted", outcome="unknown")
        globals_ = self.api["reserve_operation"].__globals__
        with patch.dict(globals_, process_identity=lambda pid: "555:9"), self.assertRaises(BlockingIOError):
            self.api["reserve_operation"]("mise", "recover", now=12)
        with patch.dict(globals_, process_identity=lambda pid: None):
            recovery = self.api["reserve_operation"]("mise", "recover", now=13)
        self.assertEqual(recovery["recovery_of"], previous["operation"])

    def test_close_preserves_flatpak_partial_completion_recovery_phase(self):
        operation = self.api["reserve_operation"]("flatpak", "update", now=10)
        self.api["update_operation"](operation["operation"], phase="system-complete/user-failed",
                                     provider_phase="flatpak-user", outcome="failed")
        with patch.dict(self.api["terminal_closed"].__globals__, process_identity=lambda pid: None,
                        rescan_provider=lambda provider: None):
            closed = self.api["terminal_closed"](operation["operation"], now=11)
        self.assertEqual((closed["phase"], closed["provider_phase"]),
                         ("system-complete/user-failed", "flatpak-user"))

    def test_child_completion_cannot_be_regressed_to_launched_by_parent(self):
        class Child:
            pid = 456
        globals_ = self.api["launch_operation"].__globals__
        def launch(argv, **options):
            active = self.api["active_operation"]()
            self.api["update_operation"](active["operation"], phase="completed", outcome="succeeded",
                                         detail="Child finished")
            return Child()
        with patch.dict(globals_, subprocess_popen=launch, process_identity=lambda pid: "456:1",
                        validate_provider_action=lambda provider, action: None):
            value = self.api["launch_operation"]("fedora", now=10)
        self.assertEqual((value["phase"], value["outcome"], value["detail"]),
                         ("completed", "succeeded", "Child finished"))
        self.assertEqual(value["terminal_identity"], "456:1")

    def test_child_completion_wins_even_when_parent_cannot_observe_process(self):
        class Child:
            pid = 457
        def launch(argv, **options):
            active = self.api["active_operation"]()
            self.api["update_operation"](active["operation"], phase="completed", outcome="succeeded",
                                         detail="Child finished before identity capture")
            return Child()
        globals_ = self.api["launch_operation"].__globals__
        with patch.dict(globals_, subprocess_popen=launch, process_identity=lambda pid: None,
                        validate_provider_action=lambda provider, action: None):
            value = self.api["launch_operation"]("fedora", now=10)
        self.assertEqual((value["phase"], value["outcome"]), ("completed", "succeeded"))

    def test_cli_recover_routes_only_valid_provider_to_recovery_launch(self):
        calls = []
        value = {"operation": "op-" + "f" * 32, "provider": "flatpak", "action": "recover",
                 "phase": "launched", "outcome": "pending"}
        globals_ = self.api["main"].__globals__
        with patch.dict(globals_, require_fedora=lambda: None,
                        launch_operation=lambda provider, action: calls.append((provider, action)) or value), \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(self.api["main"](["recover", "flatpak"]), 0)
        self.assertEqual(calls, [("flatpak", "recover")])
        self.assertIn("\tflatpak\trecover\tlaunched\tpending", output.getvalue())

    def test_missing_optional_provider_is_not_operation_eligible(self):
        function = self.api["validate_provider_action"]
        with patch.dict(function.__globals__, scan_flatpak=lambda: None):
            with self.assertRaisesRegex(ValueError, "unavailable or incompatible"):
                function("flatpak", "update")


class RunnerTests(Environment):
    def setUp(self):
        super().setUp()
        self.api = runpy.run_path(str(RUNNER))
        self.operation = "op-" + "a" * 32

    def run_adapter(self, provider, action, responses=None):
        calls = []
        phases = []
        responses = list(responses or [])
        def command(argv, **options):
            calls.append((argv, options))
            value = responses.pop(0) if responses else ""
            if isinstance(value, Exception):
                raise value
            return value
        with patch.dict(self.api["execute_provider"].__globals__, run_command=command, run_protocol_command=command,
                        checkpoint=lambda operation, phase, detail: phases.append(phase),
                        validate_provider_action=lambda provider, action: None,
                        executable=lambda name: "/usr/bin/" + name,
                        trusted_desktop_helper=lambda: "/usr/bin/dwm-desktop-update"):
            result = self.api["execute_provider"](self.operation, provider, action)
        return result, calls, phases

    def fedora_snapshot(self, generation="b" * 64, restart="none", active=""):
        return ("system-management-protocol\t1\t0\n"
                f"snapshot-generation\t{generation}\n"
                "provider\tupdates\tavailable\tdelegated\tPackageKit\tReady\n"
                "state\tupdate-summary\tavailable\t0\tCurrent\n"
                "state\tupdate-last-refresh\tavailable\t1\tRecent\n"
                f"state\tupdate-restart\tavailable\t{restart}\tRestart state\n"
                "action\tupdates-refresh\tavailable\tdelegated\tupdates\tRefresh\tReady\n"
                "action\tupdates-install-all\tavailable\tdelegated\tupdates\tInstall\tReady\n"
                "action\tupdates-cancel\tunavailable\tdelegated\tupdates\tCancel\tIdle\n"
                f"{active}complete\tsnapshot\n")

    def operation_stream(self, state="succeeded"):
        operation = "op-" + "c" * 32
        return ("system-management-protocol\t1\t0\n"
                f"operation\t{operation}\tupdates-install-all\tupdate\tpending\tunknown\tno\tStarting\n"
                f"operation\t{operation}\tupdates-install-all\tupdate\trunning\t50\tyes\tInstalling\n"
                f"operation\t{operation}\tupdates-install-all\tupdate\t{state}\tunknown\tno\tFinished\n"
                f"audit\t{operation}\tupdates-install-all\tupdate\t{state}\t2026-09-05T01:00:00Z\t2026-09-05T01:01:00Z\tAuthoritative result\n"
                "complete\toperation\n")

    def test_fedora_uses_packagekit_snapshot_update_watch_and_reconciliation(self):
        snapshot = self.fedora_snapshot(restart="system")
        result, calls, phases = self.run_adapter("fedora", "update", [snapshot, self.operation_stream(), snapshot, ""])
        self.assertEqual([call[0][1] for call in calls], ["snapshot", "updates-install-all", "snapshot", "ack-operation"])
        self.assertEqual(calls[1][0][2], "b" * 64)
        self.assertEqual(calls[3][0][2], "op-" + "c" * 32)
        self.assertEqual((result["outcome"], result["restart"]), ("succeeded", "system"))
        self.assertEqual(phases, ["preparing", "fedora-executing"])

    def test_fedora_rejects_malformed_authoritative_stream(self):
        with self.assertRaisesRegex(ValueError, "PackageKit operation"):
            self.run_adapter("fedora", "update", [self.fedora_snapshot(),
                self.operation_stream().replace("complete\toperation", "complete\tsnapshot")])

    def test_desktop_uses_trusted_status_check_start_and_recover(self):
        ready = json.dumps({"schema": 1, "state": "available", "installed": "a" * 40,
                            "available": "b" * 40, "canUpdate": True, "detail": "Ready", "restart": "none"})
        done = json.dumps({"schema": 1, "state": "current", "installed": "b" * 40,
                           "available": "b" * 40, "canUpdate": False, "detail": "Done", "restart": "session"})
        result, calls, phases = self.run_adapter("dwm-titus", "update", [ready, ready, done, done])
        self.assertEqual([call[0][1] for call in calls], ["status", "check", "start", "status"])
        self.assertEqual(calls[2][0][2], "b" * 40)
        self.assertEqual((result["outcome"], result["restart"]), ("succeeded", "session"))
        interrupted = json.dumps({**json.loads(ready), "state": "interrupted", "operation": "d" * 32})
        _, calls, _ = self.run_adapter("dwm-titus", "recover", [interrupted, done])
        self.assertEqual([call[0][1] for call in calls], ["status", "recover"])
        self.assertEqual(calls[1][0][2], "d" * 32)

    def test_flatpak_system_first_partial_and_recovery_rechecks_both_scopes(self):
        result, calls, phases = self.run_adapter("flatpak", "update")
        self.assertEqual([call[0][1:] for call in calls], [["update", "--system", "--noninteractive"],
            ["update", "--user", "--noninteractive"]])
        self.assertEqual(result["outcome"], "succeeded")
        self.assertEqual(phases, ["flatpak-system", "flatpak-system-complete", "flatpak-user"])
        result, calls, phases = self.run_adapter("flatpak", "update", ["", subprocess.CalledProcessError(1, ["flatpak"])])
        self.assertEqual(result["phase"], "system-complete/user-failed")
        self.assertNotIn("rollback", result["detail"].lower())
        with patch.dict(self.api["execute_provider"].__globals__, executable=lambda name: "/usr/bin/flatpak",
                        scan_flatpak_scope=lambda executable, scope: calls.append((scope, {}))):
            with patch.dict(self.api["execute_provider"].__globals__, validate_provider_action=lambda provider, action: None,
                            checkpoint=lambda *args: None):
                self.api["execute_provider"](self.operation, "flatpak", "recover")
        self.assertEqual([entry[0] for entry in calls[-2:]], ["system", "user"])

    def test_flatpak_system_failure_never_starts_user_mutation(self):
        result, calls, phases = self.run_adapter("flatpak", "update",
            [subprocess.CalledProcessError(1, ["flatpak", "update", "--system"])])
        self.assertEqual([call[0][1] for call in calls], ["update"])
        self.assertEqual((result["outcome"], result["phase"]), ("failed", "system-failed"))
        self.assertEqual(phases, ["flatpak-system"])

    def test_mise_uses_managed_inventory_and_preserves_cooldown(self):
        inventory = json.dumps({"node": [{"version": "20", "installed": True}]})
        result, calls, phases = self.run_adapter("mise", "update", [inventory, "", inventory])
        self.assertEqual(calls[0][0][1:], ["ls", "--installed", "--json"])
        self.assertEqual(calls[1][0][1:], ["upgrade", "--", "node@20"])
        self.assertNotIn("MISE_MINIMUM_RELEASE_AGE", calls[1][0])
        self.assertEqual(result["outcome"], "succeeded")
        self.assertEqual(phases, ["mise-inventory", "mise-update", "mise-recheck"])
        result, calls, phases = self.run_adapter("mise", "recover", [inventory, "", inventory])
        self.assertEqual(phases, ["mise-inventory", "recovering", "mise-update", "mise-recheck"])

    def test_completion_prompt_for_success_and_failure_and_test_stream(self):
        for outcome in ("succeeded", "failed"):
            output = io.StringIO()
            self.api["completion_hold"]({"outcome": outcome}, input_stream=io.StringIO("x"), output=output)
            self.assertIn("Done. Press any key to close", output.getvalue())

    def test_runner_main_commits_terminal_state_then_holds_for_injected_key(self):
        operation = self.api["CENTER"]["reserve_operation"]("mise", "update", now=10)
        held = []
        def hold(value):
            output = io.StringIO()
            self.api["completion_hold"](value, input_stream=io.StringIO("k"), output=output)
            held.append(output.getvalue())
        globals_ = self.api["main"].__globals__
        with patch.dict(globals_, execute_provider=lambda *args: {
                "outcome": "succeeded", "phase": "completed", "detail": "Verified", "restart": "none"},
                completion_hold=hold), patch.dict(self.api["CENTER"], rescan_provider=lambda provider: None):
            self.assertEqual(self.api["main"]([operation["operation"], "mise", "update"]), 0)
        saved = self.api["CENTER"]["read_operation"]()
        self.assertEqual((saved["phase"], saved["outcome"]), ("completed", "succeeded"))
        self.assertIn("Done. Press any key to close", held[0])

    def test_runner_interruption_retains_last_durable_provider_phase(self):
        operation = self.api["CENTER"]["reserve_operation"]("mise", "update", now=10)
        def fail(operation_id, provider, action):
            self.api["checkpoint"](operation_id, "mise-update", "Mutation dispatched")
            raise OSError("connection lost")
        globals_ = self.api["main"].__globals__
        with patch.dict(globals_, execute_provider=fail, completion_hold=lambda value: None), \
                patch.dict(self.api["CENTER"], rescan_provider=lambda provider: None):
            self.assertEqual(self.api["main"]([operation["operation"], "mise", "update"]), 1)
        saved = self.api["CENTER"]["read_operation"]()
        self.assertEqual((saved["phase"], saved["provider_phase"], saved["outcome"]),
                         ("interrupted", "mise-update", "unknown"))


if __name__ == "__main__":
    unittest.main()
