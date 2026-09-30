#!/usr/bin/python3
"""Durable Update Center terminal lifecycle and fixed provider adapters."""
import contextlib
import io
import json
import os
import runpy
import subprocess
import sys
import tempfile
import termios
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
            self.assertEqual(calls[0][0], ["/usr/bin/dwm-terminal", "--update-center", "/usr/bin/dwm-update-center-terminal",
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

    def test_terminal_closed_does_not_rescan_when_terminal_is_alive_and_phase_unchanged(self):
        op = self.api["reserve_operation"]("mise", "update", now=10)
        self.api["record_terminal"](op["operation"], 123, "123:7", now=11)
        rescanned = []
        with patch.dict(self.api["terminal_closed"].__globals__,
                        process_identity=lambda pid: "123:7",
                        rescan_provider=lambda provider: rescanned.append(provider)):
            result = self.api["terminal_closed"](op["operation"], now=12)
        self.assertEqual(rescanned, [])
        self.assertEqual(result["phase"], "launched")

    def test_matching_interrupted_owner_can_reserve_recovery_but_other_provider_cannot(self):
        previous = self.api["reserve_operation"]("flatpak", "update", now=10)
        self.api["update_operation"](previous["operation"], phase="interrupted", outcome="unknown")
        with self.assertRaisesRegex(ValueError, "no matching recoverable"):
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
        self.assertEqual((value["terminal_pid"], value["terminal_identity"]), (457, ""))
        with patch.dict(globals_, process_identity=lambda pid: "457:still-live",
                        rescan_provider=lambda provider: None,
                        validate_provider_action=lambda provider, action: None):
            retained = self.api["terminal_closed"](value["operation"], now=11)
            self.assertEqual((retained["phase"], retained["terminal_pid"]), ("completed", 457))
            self.assertEqual(self.api["active_operation"]()["operation"], value["operation"])
            with self.assertRaisesRegex(BlockingIOError, "active"):
                self.api["launch_operation"]("mise", now=12)

    def test_live_spawn_with_unavailable_identity_retains_pid_and_blocks_recovery(self):
        class Child:
            pid = 458
        globals_ = self.api["launch_operation"].__globals__
        with patch.dict(globals_, subprocess_popen=lambda argv, **options: Child(),
                        process_identity=lambda pid: None,
                        validate_provider_action=lambda provider, action: None), self.assertRaises(OSError):
            self.api["launch_operation"]("mise", now=10)
        ambiguous = self.api["read_operation"]()
        self.assertEqual((ambiguous["phase"], ambiguous["terminal_pid"], ambiguous["terminal_identity"]),
                         ("interrupted", 458, ""))
        with patch.dict(globals_, process_identity=lambda pid: "458:3"), self.assertRaises(BlockingIOError):
            self.api["reserve_operation"]("mise", "recover", now=11)

    def test_cli_recover_requires_and_consumes_matching_interrupted_state(self):
        previous = self.api["reserve_operation"]("flatpak", "update", now=10)
        self.api["update_operation"](previous["operation"], phase="interrupted", outcome="unknown")
        class Child:
            pid = 789
        globals_ = self.api["main"].__globals__
        with patch.dict(globals_, require_fedora=lambda: None,
                        validate_provider_action=lambda provider, action: None,
                        subprocess_popen=lambda argv, **options: Child(), process_identity=lambda pid: "789:2"), \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(self.api["main"](["recover", "flatpak"]), 0)
        self.assertIn("\tflatpak\trecover\tlaunched\tpending", output.getvalue())
        saved = self.api["read_operation"]()
        self.assertEqual((saved["action"], saved["recovery_of"], saved["recovery_phase"]),
                         ("recover", previous["operation"], "interrupted"))

    def test_recovery_rejects_absent_completed_failed_wrong_and_healthy_state(self):
        with self.assertRaisesRegex(ValueError, "no matching recoverable"):
            self.api["reserve_operation"]("flatpak", "recover")
        operation = self.api["reserve_operation"]("flatpak", "update", now=10)
        for phase in ("completed", "failed"):
            self.api["update_operation"](operation["operation"], phase=phase,
                                         outcome="succeeded" if phase == "completed" else "failed")
            with self.subTest(phase=phase), self.assertRaisesRegex(ValueError, "no matching recoverable"):
                self.api["reserve_operation"]("flatpak", "recover")
        self.api["update_operation"](operation["operation"], phase="interrupted", outcome="unknown")
        with self.assertRaisesRegex(ValueError, "no matching recoverable"):
            self.api["reserve_operation"]("mise", "recover")

    def test_runner_revalidation_requires_authoritative_recovery_basis(self):
        function = self.api["validate_provider_action"]
        healthy = self.api["ProviderResult"]("flatpak", update_available=True)
        with patch.dict(function.__globals__, scan_flatpak=lambda: healthy):
            with self.assertRaisesRegex(ValueError, "authoritative recovery"):
                function("flatpak", "recover")
            previous = self.api["reserve_operation"]("flatpak", "update", now=10)
            self.api["update_operation"](previous["operation"], phase="interrupted", outcome="unknown")
            self.assertEqual(function("flatpak", "recover"), healthy)
            recovery = self.api["reserve_operation"]("flatpak", "recover", now=11)
            self.assertEqual(function("flatpak", "recover"), healthy)
            self.assertEqual(recovery["recovery_phase"], "interrupted")

    def test_phase_outcome_coherence_rejects_impossible_durable_states(self):
        operation = self.api["reserve_operation"]("fedora", "update", now=10)
        for phase, outcome in (("completed", "pending"), ("failed", "succeeded"),
                               ("interrupted", "failed"), ("running", "succeeded"),
                               ("closed", "pending"), ("flatpak-user", "pending")):
            with self.subTest(phase=phase, outcome=outcome), self.assertRaisesRegex(ValueError, "invalid operation"):
                self.api["update_operation"](operation["operation"], phase=phase, outcome=outcome)

    def test_recovery_provenance_rejects_cross_provider_phases(self):
        operation = self.api["reserve_operation"]("flatpak", "update", now=10)
        self.api["update_operation"](operation["operation"], phase="system-complete/user-failed",
                                     provider_phase="flatpak-user", outcome="failed")
        recovery = self.api["reserve_operation"]("flatpak", "recover", now=11)
        malformed = (
            {**recovery, "provider": "fedora", "recovery_provider_phase": "fedora-executing"},
            {**recovery, "provider": "dwm-titus", "recovery_provider_phase": "desktop-starting"},
            {**recovery, "provider": "fedora", "recovery_phase": "interrupted",
             "recovery_provider_phase": "flatpak-user"},
            {**recovery, "provider": "mise", "recovery_phase": "interrupted",
             "recovery_provider_phase": "fedora-executing"},
        )
        for value in malformed:
            with self.subTest(provider=value["provider"], phase=value["recovery_phase"],
                              provider_phase=value["recovery_provider_phase"]), \
                    self.assertRaisesRegex(ValueError, "invalid operation"):
                self.api["validate_operation"](value)

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

    def test_desktop_authorization_is_owned_only_by_worker(self):
        self.assertNotIn("getpass", self.api)
        self.assertNotIn("validate_sudo_password", self.api)
        self.assertNotIn("prompt_sudo_password", self.api)

    def run_adapter(self, provider, action, responses=None, recovery_basis=("interrupted", "flatpak-system")):
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
                        checkpoint=lambda operation, phase, detail, **k: phases.append(phase),
                        validate_provider_action=lambda provider, action: None,
                        flatpak_recovery_basis=lambda operation: recovery_basis,
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

    def test_terminal_protocol_output_wraps_at_fields_without_splitting_words(self):
        output = io.StringIO()
        self.api["print_terminal_line"](
            "provider\tsecurity\tpartial read-only\tdwm-system-management\t"
            "Bounded read-only observations; inspect individual state details\n",
            output=output,
            width=52,
        )
        lines = output.getvalue().splitlines()
        self.assertGreater(len(lines), 1)
        self.assertTrue(all(len(line) <= 52 for line in lines))
        self.assertIn("dwm-system-management", output.getvalue())
        self.assertNotIn("dwm-system-\nmanagement", output.getvalue())
        self.assertNotIn("\t", output.getvalue())

    def test_terminal_formats_operation_and_package_progress_cleanly(self):
        output = io.StringIO()
        self.api["print_terminal_line"](
            "operation\top-123\tupdates-install-all\tupdate\trunning\t50\tyes\tInstalling updates\n",
            output=output,
        )
        self.assertEqual(output.getvalue().strip(), "\033[32m[ 50%]\033[0m Installing updates")

        output = io.StringIO()
        self.api["print_terminal_line"](
            "package\tinstalling\tfirefox;128.0;x86_64;updates\tWeb browser\n",
            output=output,
        )
        self.assertEqual(output.getvalue().strip(), "\033[1;34m->\033[0m \033[1mInstalling:\033[0m firefox - Web browser")

        output = io.StringIO()
        self.api["print_terminal_line"](
            "audit\top-123\tupdates-install-all\tupdate\tsucceeded\t2026-09-05T01:00:00Z\t2026-09-05T01:01:00Z\tAll packages updated\n",
            output=output,
        )
        self.assertEqual(output.getvalue().strip(), "\033[32m[OK]\033[0m All packages updated")

        output = io.StringIO()
        self.api["print_terminal_line"](
            "error\tupdates\tfailure\tPackageKit transaction failed\n",
            output=output,
        )
        self.assertEqual(output.getvalue().strip(), "\033[1;31m[ERROR]\033[0m PackageKit transaction failed")

        output = io.StringIO()
        self.api["print_terminal_line"](
            "system-management-protocol\t1\t0\n",
            output=output,
        )
        self.assertEqual(output.getvalue(), "")

    def test_terminal_formats_package_progress_and_suppresses_observed_signals(self):
        output = io.StringIO()
        self.api["print_terminal_line"](
            "package-progress\top-1\thunspell\tupdating\tunknown\n",
            output=output,
        )
        self.api["print_terminal_line"](
            "operation\top-1\tupdates-install-all\tupdate\trunning\t20\tyes\tObserved signals: install=0 update=2 remove=0 obsolete=0 unknown=0; sha256=abcdef; different=unknown; mismatch-samples=0\n",
            output=output,
        )
        self.assertEqual(
            output.getvalue().strip(),
            "\033[1;34m->\033[0m \033[1mUpdating:\033[0m hunspell \033[32m[ 20%]\033[0m",
        )
        self.assertNotIn("Observed signals", output.getvalue())
        self.assertNotIn("package-progress", output.getvalue())

    def test_terminal_formats_sequential_package_progress_stream_cleanly(self):
        output = io.StringIO()
        stream = (
            "package-progress\top-1\thunspell\tupdating\tunknown\n"
            "operation\top-1\tupdates-install-all\tupdate\trunning\t20\tyes\tObserved signals: install=0 update=2;\n"
            "operation\top-1\tupdates-install-all\tupdate\trunning\t24\tyes\tObserved signals: install=0 update=2;\n"
            "package-progress\top-1\tperl-LWP-MediaTypes\tupdating\tunknown\n"
            "operation\top-1\tupdates-install-all\tupdate\trunning\t28\tyes\tObserved signals: install=0 update=3;\n"
            "package-progress\top-1\thunspell\tcleaning\tunknown\n"
            "package-progress\top-1\thunspell-filesystem\tcleaning\tunknown\n"
            "operation\top-1\tupdates-install-all\tupdate\trunning\t87\tyes\tObserved signals: install=0 update=4;\n"
            "audit\top-1\tupdates-install-all\tupdate\tsucceeded\t2026-09-05T01:00:00Z\t2026-09-05T01:01:00Z\tAll packages updated\n"
        )
        for line in stream.splitlines(keepends=True):
            self.api["print_terminal_line"](line, output=output)

        expected = [
            "\033[1;34m->\033[0m \033[1mUpdating:\033[0m hunspell \033[32m[ 20%]\033[0m",
            "\033[1;34m->\033[0m \033[1mUpdating:\033[0m perl-LWP-MediaTypes \033[32m[ 28%]\033[0m",
            "\033[1;34m->\033[0m \033[1mCleaning:\033[0m hunspell \033[32m[ 28%]\033[0m",
            "\033[1;34m->\033[0m \033[1mCleaning:\033[0m hunspell-filesystem \033[32m[ 87%]\033[0m",
            "\033[32m[OK]\033[0m All packages updated",
        ]
        self.assertEqual(output.getvalue().strip().splitlines(), expected)
        self.assertNotIn("Observed signals", output.getvalue())
        self.assertNotIn("package-progress", output.getvalue())

    def test_provider_header_and_step_ansi_formatting(self):
        headers = {
            ("fedora", "update"): "\033[32m\nUpdate system packages\033[0m\n",
            ("flatpak", "update"): "\033[32m\nUpdate Flatpak packages\033[0m\n",
            ("dwm-titus", "update"): "\033[32m\nUpdate DWM-Titus\033[0m\n",
            ("mise", "update"): "\033[32m\nUpdate mise tools\033[0m\n",
            ("fedora", "recover"): "\033[32m\nRecover system packages\033[0m\n",
            ("flatpak", "recover"): "\033[32m\nRecover Flatpak packages\033[0m\n",
            ("dwm-titus", "recover"): "\033[32m\nRecover DWM-Titus\033[0m\n",
            ("mise", "recover"): "\033[32m\nRecover mise tools\033[0m\n",
        }
        for (provider, action), expected in headers.items():
            with self.subTest(provider=provider, action=action):
                output = io.StringIO()
                self.api["print_provider_header"](provider, action, output=output)
                self.assertEqual(output.getvalue(), expected)

        step_output = io.StringIO()
        self.api["print_step"]("Updating system Flatpaks", output=step_output)
        self.assertEqual(step_output.getvalue(), "\033[1;34m::\033[0m Updating system Flatpaks...\n")

        complete_output = io.StringIO()
        self.api["print_step"]("System Flatpak update completed", output=complete_output)
        self.assertEqual(complete_output.getvalue(), "\033[1;34m::\033[0m System Flatpak update completed\n")

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

    def test_fedora_update_without_operation_records_reports_failure(self):
        snapshot = self.fedora_snapshot(restart="none")
        no_operation_stream = (
            "system-management-protocol\t1\t0\n"
            "error\tupdates\tauthorization\tAuthentication was dismissed\n"
            "complete\toperation\n"
        )
        result, calls, phases = self.run_adapter("fedora", "update", [snapshot, no_operation_stream, snapshot])
        self.assertEqual(result["outcome"], "failed")
        self.assertEqual(result["phase"], "failed")
        self.assertIn("did not start", result["detail"])

    def test_interrupted_fedora_recovery_acknowledges_without_claiming_success(self):
        handoff = "terminal-handoff\top-" + "c" * 32 + "\tupdates-install-all\tupdate\n"
        snapshot = self.fedora_snapshot(active=handoff)
        result, calls, _ = self.run_adapter("fedora", "recover", [snapshot,
            self.operation_stream("interrupted"), snapshot, "", self.fedora_snapshot()])
        self.assertEqual([call[0][1] for call in calls],
                         ["snapshot", "watch-operation", "snapshot", "ack-operation", "snapshot"])
        self.assertEqual(calls[3][0][2], "op-" + "c" * 32)
        self.assertEqual((result["outcome"], result["phase"]), ("unknown", "failed"))
        self.assertIn("outcome remains unknown", result["detail"])
        banner = self.api["format_completion_banner"](result)
        self.assertIn("OUTCOME UNKNOWN", banner)
        self.assertNotIn("ERROR", banner)

    def test_interrupted_fedora_recovery_does_not_ack_active_or_changed_work(self):
        handoff = "terminal-handoff\top-" + "c" * 32 + "\tupdates-install-all\tupdate\n"
        active = "active-operation\top-" + "d" * 32 + "\tupdates-install-all\tupdate\trunning\tunknown\tno\tStarted\tWorking\n"
        for retained in (active, handoff.replace("c" * 32, "d" * 32)):
            with self.subTest(retained=retained):
                result, calls, _ = self.run_adapter("fedora", "recover", [self.fedora_snapshot(active=handoff),
                    self.operation_stream("interrupted"), self.fedora_snapshot(active=retained)])
                self.assertEqual((result["outcome"], result["phase"]), ("unknown", "interrupted"))
                self.assertNotIn("ack-operation", [call[0][1] for call in calls])

    def test_interrupted_fedora_recovery_requires_confirmed_acknowledgment(self):
        handoff = "terminal-handoff\top-" + "c" * 32 + "\tupdates-install-all\tupdate\n"
        snapshot = self.fedora_snapshot(active=handoff)
        result, _, _ = self.run_adapter("fedora", "recover", [snapshot,
            self.operation_stream("interrupted"), snapshot, "", snapshot])
        self.assertEqual((result["outcome"], result["phase"]), ("unknown", "interrupted"))

    def test_backend_canceled_replay_and_authorizing_cancel_are_accepted(self):
        backend = runpy.run_path(str(ROOT / "scripts/dwm-system-management"))
        operation = backend["JournalOperation"]("op-" + "c" * 32, "updates-install-all",
            "2026-09-05T01:00:00Z", "2026-09-05T01:01:00Z", "update", "canceled", None,
            "Canceled before dispatch", "a" * 64, "/18_adcbcaed", "none", "none", False,
            "01234567-89ab-cdef-0123-456789abcdef", 123, 0)
        for authorizing in (False, True):
            with self.subTest(authorizing=authorizing):
                output = []
                if authorizing:
                    stream = backend["OperationStream"](operation.operation_id, operation.action_id,
                        operation.started_at, "Starting", output.append)
                    stream.transition("authorizing", "Waiting for authorization")
                    stream.finish(operation)
                else:
                    backend["replay_terminal_operation"](operation, output.append)
                payload = "".join(output)
                self.assertEqual(self.api["parse_operation_stream"](payload, "updates-install-all")["state"], "canceled")
                handoff = "terminal-handoff\t" + operation.operation_id + "\tupdates-install-all\tupdate\n"
                result, calls, _ = self.run_adapter("fedora", "recover",
                    [self.fedora_snapshot(active=handoff), payload, self.fedora_snapshot(active=handoff), ""])
                self.assertEqual((result["outcome"], result["phase"]), ("failed", "failed"))
                self.assertEqual(calls[-1][0][1:], ["ack-operation", operation.operation_id])

    def test_run_command_isolates_stderr_from_machine_output(self):
        code = 'import sys; sys.stderr.write("warning: unmanaged\\n"); sys.stdout.write("{\\"ok\\": true}\\n")'
        devnull = os.open(os.devnull, os.O_WRONLY)
        old_stderr = os.dup(2)
        try:
            os.dup2(devnull, 2)
            with contextlib.redirect_stdout(io.StringIO()):
                output = self.api["run_command"]([sys.executable, "-c", code])
        finally:
            os.dup2(old_stderr, 2)
            os.close(old_stderr)
            os.close(devnull)
        self.assertEqual(output.strip(), '{"ok": true}')

    def test_run_command_enforces_read_deadline_and_reaps_child(self):
        code = 'import time; time.sleep(10)'
        with self.assertRaises(TimeoutError):
            self.api["run_command"]([sys.executable, "-c", code], timeout=0.1)

    def test_run_command_enforces_max_bytes_on_unbounded_line(self):
        code = 'import sys; [sys.stdout.write("x" * 1024) or sys.stdout.flush() for _ in range(10000)]'
        with patch.dict(self.api["CENTER"], MAX_BYTES=2048):
            with self.assertRaisesRegex(ValueError, "byte limit"):
                self.api["run_command"]([sys.executable, "-c", code], timeout=2)

    def test_run_protocol_command_enforces_deadline_and_max_bytes(self):
        code_hang = 'import time; time.sleep(10)'
        with self.assertRaises(TimeoutError):
            self.api["run_protocol_command"]([sys.executable, "-c", code_hang], timeout=0.1)

        code_unbounded = 'import sys; [sys.stdout.write("x" * 1024) or sys.stdout.flush() for _ in range(10000)]'
        with patch.dict(self.api["CENTER"], MAX_BYTES=2048):
            with self.assertRaisesRegex(ValueError, "byte limit"):
                self.api["run_protocol_command"]([sys.executable, "-c", code_unbounded], timeout=2)

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
        recovered_state = json.dumps({
            "schema": 1, "state": "failed", "installed": "a" * 40, "available": "b" * 40,
            "canUpdate": False, "detail": "Previous desktop files restored. Log out and back in, then check again.",
            "restart": "session"
        })
        recovered_res, calls, _ = self.run_adapter("dwm-titus", "recover", [interrupted, recovered_state])
        self.assertEqual((recovered_res["outcome"], recovered_res["phase"]), ("succeeded", "completed"))
        already_ready = json.dumps({
            "schema": 1, "state": "available", "installed": "a" * 40, "available": "b" * 40,
            "canUpdate": True, "detail": "A desktop update is available", "restart": "none"
        })
        already_res, calls, _ = self.run_adapter("dwm-titus", "recover", [already_ready])
        self.assertEqual([call[0][1] for call in calls], ["status"])
        self.assertEqual((already_res["outcome"], already_res["phase"]), ("succeeded", "completed"))
        self.assertIn("already recovered", already_res["detail"])

    def test_desktop_recovery_waits_for_independent_active_worker(self):
        for final_state, outcome, phase in (("current", "succeeded", "completed"),
                                          ("failed", "failed", "failed"),
                                          ("interrupted", "unknown", "interrupted")):
            with self.subTest(final_state=final_state), patch("time.sleep") as sleep, \
                    contextlib.redirect_stdout(io.StringIO()):
                responses = [json.dumps({"state": state, "detail": state, "restart": "none"})
                             for state in ("building", "installing", final_state)]
                result, calls, phases = self.run_adapter("dwm-titus", "recover", responses)
                self.assertEqual([call[0][1] for call in calls], ["status", "status", "status"])
                self.assertEqual(phases, ["recovering"])
                self.assertEqual(sleep.call_count, 2)
                self.assertEqual((result["outcome"], result["phase"]), (outcome, phase))

    def test_flatpak_system_first_partial_and_recovery_rechecks_both_scopes(self):
        result, calls, phases = self.run_adapter("flatpak", "update")
        self.assertEqual([call[0][1:] for call in calls], [["update", "--system", "--noninteractive"],
            ["update", "--user", "--noninteractive"]])
        self.assertEqual(result["outcome"], "succeeded")
        self.assertEqual(phases, ["flatpak-system", "flatpak-system-complete", "flatpak-user",
                                  "flatpak-user-complete"])
        result, calls, phases = self.run_adapter("flatpak", "update", ["", subprocess.CalledProcessError(1, ["flatpak"])])
        self.assertEqual(result["phase"], "system-complete/user-failed")
        self.assertNotIn("rollback", result["detail"].lower())
        recovered, recovery_calls, recovery_phases = self.run_adapter("flatpak", "recover")
        updates = [call[0][1:3] for call in recovery_calls if len(call[0]) > 1 and call[0][1] == "update"]
        self.assertEqual(updates, [["update", "--system"], ["update", "--user"]])
        self.assertEqual(recovered["outcome"], "succeeded")
        self.assertEqual(recovery_phases[:4], ["recovering", "flatpak-system",
                                               "flatpak-system-complete", "flatpak-user"])

    def test_flatpak_system_failure_never_starts_user_mutation(self):
        result, calls, phases = self.run_adapter("flatpak", "update",
            [subprocess.CalledProcessError(1, ["flatpak", "update", "--system"])])
        self.assertEqual([call[0][1] for call in calls], ["update"])
        self.assertEqual((result["outcome"], result["phase"]), ("failed", "system-failed"))
        self.assertEqual(phases, ["flatpak-system"])

    def test_flatpak_recovery_preserves_completed_system_and_retries_by_checkpoint(self):
        cases = (("system-failed", "flatpak-system", ["--system", "--user"]),
                 ("system-complete/user-failed", "flatpak-user", ["--user"]),
                 ("interrupted", "flatpak-system", ["--system", "--user"]),
                 ("interrupted", "flatpak-system-complete", ["--user"]),
                 ("interrupted", "flatpak-user", ["--user"]),
                 ("interrupted", "flatpak-user-complete", []),
                 ("interrupted", "recovering", ["--system", "--user"]))
        for recovery_phase, provider_phase, expected in cases:
            with self.subTest(recovery_phase=recovery_phase, provider_phase=provider_phase):
                result, calls, phases = self.run_adapter("flatpak", "recover",
                    recovery_basis=(recovery_phase, provider_phase))
                updates = [call[0][2] for call in calls if len(call[0]) > 2 and call[0][1] == "update"]
                self.assertEqual(updates, expected)
                self.assertEqual(result["outcome"], "succeeded")
                self.assertNotIn("rollback", result["detail"].lower())

    def test_mise_uses_managed_inventory_and_preserves_cooldown(self):
        inventory = json.dumps({"node": [{"version": "20.0.0", "installed": True, "requested_version": "20"},
                                          {"version": "22.0.0", "installed": True, "requested_version": "22"}]})
        result, calls, phases = self.run_adapter("mise", "update", [inventory, "", inventory])
        self.assertEqual(calls[0][0][1:], ["ls", "--current", "--installed", "--json"])
        self.assertEqual(calls[1][0][1:], ["upgrade", "--", "node"])
        self.assertNotIn("MISE_MINIMUM_RELEASE_AGE", calls[1][0])
        self.assertEqual(result["outcome"], "succeeded")
        self.assertEqual(phases, ["mise-inventory", "mise-update", "mise-recheck"])
        result, calls, phases = self.run_adapter("mise", "recover", [inventory, "", inventory])
        self.assertEqual(phases, ["mise-inventory", "recovering", "mise-update", "mise-recheck"])

    def test_completion_prompt_for_success_and_failure_and_test_stream(self):
        output_ok = io.StringIO()
        self.api["completion_hold"]({"outcome": "succeeded", "detail": "All packages updated"},
                                    input_stream=io.StringIO("x"), output=output_ok)
        self.assertIn("\033[1;32m==>\033[0m All packages updated", output_ok.getvalue())
        self.assertIn("\033[32m● \033[0mDone! Press any key to close...", output_ok.getvalue())

        output_fail = io.StringIO()
        self.api["completion_hold"]({"outcome": "failed", "detail": "Transaction failed"},
                                    input_stream=io.StringIO("x"), output=output_fail)
        self.assertIn("\033[1;31m==> ERROR:\033[0m Transaction failed", output_fail.getvalue())
        self.assertIn("\033[32m● \033[0mDone! Press any key to close...", output_fail.getvalue())

    def test_completion_hold_uses_cbreak_on_tty(self):
        calls = []
        class MockTTYStream(io.StringIO):
            def isatty(self):
                return True
            def fileno(self):
                return 42

        stream = MockTTYStream("q")
        output = io.StringIO()
        with patch.object(sys, "stdin", stream), \
             patch("tty.setcbreak", lambda fd: calls.append(("setcbreak", fd))), \
             patch("termios.tcgetattr", lambda fd: ["mock_settings"]), \
             patch("termios.tcsetattr", lambda fd, when, settings: calls.append(("tcsetattr", fd, when, settings))):
            self.api["completion_hold"]({"detail": "All good"}, output=output)
        self.assertEqual(calls, [("setcbreak", 42), ("tcsetattr", 42, termios.TCSADRAIN, ["mock_settings"])])

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
                completion_hold=hold, set_terminal_identity=lambda: True), \
                patch.dict(self.api["CENTER"], rescan_provider=lambda provider: None), \
                patch("sys.stdout", new_callable=io.StringIO) as stdout_capture:
            self.assertEqual(self.api["main"]([operation["operation"], "mise", "update"]), 0)
        self.assertIn("\033[32m\nUpdate mise tools\033[0m\n", stdout_capture.getvalue())
        saved = self.api["CENTER"]["read_operation"]()
        self.assertEqual((saved["phase"], saved["outcome"]), ("completed", "succeeded"))
        self.assertIn("\033[32m● \033[0mDone! Press any key to close...", held[0])

    def test_terminal_outcome_keeps_active_slot_through_success_and_failure_hold(self):
        for outcome, phase, code in (("succeeded", "completed", 0), ("failed", "failed", 1), ("unknown", "failed", 1)):
            with self.subTest(outcome=outcome):
                operation = self.api["CENTER"]["reserve_operation"]("fedora", "update", now=10)
                observed = []
                def hold(_value):
                    active = self.api["CENTER"]["active_operation"]()
                    observed.append((active["phase"], active["outcome"]))
                    with self.assertRaises(BlockingIOError):
                        self.api["CENTER"]["reserve_operation"]("mise", "update", now=11)
                    output = io.StringIO()
                    center_main = self.api["CENTER"]["main"]
                    with patch.dict(center_main.__globals__, require_fedora=lambda: None), \
                            patch("sys.stdout", output):
                        self.assertEqual(center_main(["active"]), 0)
                    self.assertIn("\t" + phase + "\t" + outcome, output.getvalue())
                globals_ = self.api["main"].__globals__
                with patch.dict(globals_, execute_provider=lambda *args: {
                        "outcome": outcome, "phase": phase, "detail": "Terminal result", "restart": "none"},
                        completion_hold=hold, set_terminal_identity=lambda: True), \
                        patch.dict(self.api["CENTER"], rescan_provider=lambda provider: None), \
                        patch("sys.stdout", new_callable=io.StringIO):
                    self.assertEqual(self.api["main"]([operation["operation"], "fedora", "update"]), code)
                self.assertEqual(observed, [(phase, outcome)])
                with patch.dict(self.api["CENTER"]["terminal_closed"].__globals__,
                                process_identity=lambda pid: None, rescan_provider=lambda provider: None):
                    closed = self.api["CENTER"]["terminal_closed"](operation["operation"], now=12)
                self.assertEqual(closed["phase"], "closed")

    def test_runner_interruption_retains_last_durable_provider_phase(self):
        operation = self.api["CENTER"]["reserve_operation"]("mise", "update", now=10)
        def fail(operation_id, provider, action):
            self.api["checkpoint"](operation_id, "mise-update", "Mutation dispatched")
            raise OSError("connection lost")
        globals_ = self.api["main"].__globals__
        with patch.dict(globals_, execute_provider=fail, completion_hold=lambda value: None,
                        set_terminal_identity=lambda: True), \
                patch.dict(self.api["CENTER"], rescan_provider=lambda provider: None), \
                patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(self.api["main"]([operation["operation"], "mise", "update"]), 1)
        saved = self.api["CENTER"]["read_operation"]()
        self.assertEqual((saved["phase"], saved["provider_phase"], saved["outcome"]),
                         ("interrupted", "mise-update", "unknown"))

    def test_fixed_terminal_identity_is_token_free_and_rejects_unusable_window(self):
        output = io.StringIO()
        self.assertFalse(self.api["set_terminal_identity"](
            {"DISPLAY": ":1", "WINDOWID": "$(touch injected)"}, output))
        self.assertEqual(self.api["TERMINAL_TITLE"], "dwm update center")
        self.assertEqual(self.api["TERMINAL_INSTANCE"], b"dwm-update-center")
        self.assertEqual(self.api["TERMINAL_CLASS"], b"DwmUpdateCenter")
        self.assertNotIn(self.operation, output.getvalue())

    def test_terminal_wrapper_identity_is_accepted_without_windowid(self):
        output = io.StringIO()
        self.assertTrue(self.api["set_terminal_identity"](
            {"DWM_UPDATE_CENTER_TERMINAL_IDENTITY": "1"}, output))
        self.assertIn("dwm update center", output.getvalue())

    def test_fixed_x11_title_and_class_are_applied_without_provider_input(self):
        calls = []
        class Function:
            def __init__(self, name, result):
                self.name, self.result = name, result
            def __call__(self, *args):
                calls.append((self.name, args))
                return self.result
        class Library:
            XOpenDisplay = Function("open", 1)
            XStoreName = Function("title", 1)
            XSetClassHint = Function("class", 1)
            XSync = Function("sync", 0)
            XCloseDisplay = Function("close", 0)
        output = io.StringIO()
        with patch.object(self.api["ctypes"], "CDLL", return_value=Library()):
            self.assertTrue(self.api["set_terminal_identity"](
                {"DISPLAY": ":9", "WINDOWID": "42", "PROVIDER": "$(bad)"}, output))
        self.assertEqual([name for name, _ in calls], ["open", "title", "class", "sync", "close"])
        self.assertEqual(calls[1][1][2], b"dwm update center")
        hint = calls[2][1][2]._obj
        self.assertEqual((hint.res_name, hint.res_class), (b"dwm-update-center", b"DwmUpdateCenter"))
        self.assertNotIn("bad", output.getvalue())

    def test_completion_hold_custom_status_banners(self):
        cases = [
            (
                {"outcome": "succeeded", "detail": "Desktop update installed, verified, and active."},
                "\033[1;32mUpdate Installed Successfully!\033[0m",
            ),
            (
                {"outcome": "succeeded", "detail": "Installed and verified. Log out and back in to activate the updated desktop."},
                "\033[1;32mUpdate Installed Successfully! \033[1;33mRestart required, or Log out and back in for update to take effect.\033[0m",
            ),
            (
                {"outcome": "succeeded", "detail": "Files installed and verified, but Quickshell did not respond. Log out and back in."},
                "\033[1;33mUpdate Files Installed, but Quickshell restart timed out, \033[1;31mPlease Log out and back in.\033[0m",
            ),
            (
                {"outcome": "succeeded", "detail": "Previous desktop files restored. Log out and back in, then check again."},
                "\033[1;32mRecovery completed, \033[1;31mPlease Log out and back in for recovery to take effect.\033[0m",
            ),
        ]
        for val, expected_text in cases:
            output = io.StringIO()
            self.api["completion_hold"](val, input_stream=io.StringIO("q"), output=output)
            self.assertIn(expected_text, output.getvalue())
            self.assertIn("\033[32m● \033[0mDone! Press any key to close...", output.getvalue())

    def test_desktop_status_dots_and_percentage_formatting(self):
        output = io.StringIO()
        formatter = self.api["DesktopStatusFormatter"](output=output)

        # Indeterminate step with cycling dots (1 to 5 dots, then reset to 1)
        formatter.update("Creating backup.....", percent=-1)
        self.assertEqual(output.getvalue(), "\r\033[KCreating backup.")

        formatter.update("Creating backup.....", percent=-1)
        self.assertEqual(output.getvalue(), "\r\033[KCreating backup.\r\033[KCreating backup. .")

        formatter.update("Creating backup.....", percent=-1)
        formatter.update("Creating backup.....", percent=-1)
        formatter.update("Creating backup.....", percent=-1)
        # 5th update should have 5 dots
        self.assertEqual(
            output.getvalue().split("\r\033[K")[-1],
            "Creating backup. . . . .",
        )

        formatter.update("Creating backup.....", percent=-1)
        # 6th update resets to 1 dot
        self.assertEqual(
            output.getvalue().split("\r\033[K")[-1],
            "Creating backup.",
        )

        # Transition to new step emits newline first
        formatter.update("Fetching Upstream.....", percent=-1)
        self.assertIn("Creating backup.\n\r\033[KFetching Upstream.", output.getvalue())

        # Percentage step formats in-place with green badge
        formatter.update("Building", percent=20)
        self.assertIn("\n\r\033[KBuilding \033[32m[ 20%]\033[0m", output.getvalue())

        formatter.close()
        self.assertTrue(output.getvalue().endswith("\n"))


class RootHelperAuthTests(unittest.TestCase):
    def setUp(self):
        self.root_api = runpy.run_path(str(ROOT / "scripts/dwm-desktop-update-root"))

    def test_caller_uid_supports_pkexec_and_sudo(self):
        self.assertIn("caller_uid", self.root_api)
        caller_uid = self.root_api["caller_uid"]
        with patch.dict(os.environ, {"PKEXEC_UID": "1000"}, clear=True):
            self.assertEqual(caller_uid(), 1000)
        with patch.dict(os.environ, {"SUDO_UID": "1001"}, clear=True):
            self.assertEqual(caller_uid(), 1001)
        with patch.dict(os.environ, {"PKEXEC_UID": "1000", "SUDO_UID": "1001"}, clear=True):
            self.assertEqual(caller_uid(), 1000)
        with patch.dict(os.environ, {"PKEXEC_UID": "", "SUDO_UID": ""}, clear=True):
            self.assertIsNone(caller_uid())
        with patch.dict(os.environ, {"SUDO_UID": "abc"}, clear=True):
            self.assertIsNone(caller_uid())
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(caller_uid())


class DesktopUpdateAuthorizeWordingTests(unittest.TestCase):
    def setUp(self):
        self.update_api = runpy.run_path(str(ROOT / "scripts/dwm-desktop-update"))

    def test_authorize_detail_omits_legacy_settings_dialog_message(self):
        state = Path("/tmp")
        value = {}
        saved_details = []

        def fake_save_status(s, v, **kwargs):
            if "detail" in kwargs:
                saved_details.append(kwargs["detail"])
            v.update(kwargs)
            return v

        class FakePrivileged:
            started = False
            def start(self):
                self.started = True
            def request(self, action, *args, **kwargs):
                return "ok"

        with patch.dict(self.update_api["authorize"].__globals__, {"save_status": fake_save_status}):
            self.update_api["authorize"](state, value, FakePrivileged(), "begin")

        self.assertTrue(len(saved_details) >= 1)
        first_detail = saved_details[0]
        self.assertNotIn("Settings closes to reveal the password dialog", first_detail)
        self.assertEqual(first_detail, "Administrator authorization: prepare the desktop update.")


if __name__ == "__main__":
    unittest.main()
