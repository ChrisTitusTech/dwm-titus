#!/usr/bin/env python3
"""Native X11 policy tests. Run via scripts/run-tests python3 this-file."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class Observer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="clipboard-observer-", dir=os.environ.get("DWM_TEST_TMP_ROOT"))
        cls.base = Path(cls.temp.name)
        cls.owner = cls.base / "eligible-owner"
        cls.other = cls.base / "bitwarden"
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", "-Wall", "-Wextra", "-Werror", str(REPO / "tests/clipboard-owner.c"), "-lxcb", "-o", str(cls.owner)], check=True)
        shutil.copy2(cls.owner, cls.other)
        cls.binary = cls.base / "observer"
        libs = subprocess.check_output(["pkg-config", "--libs", "xcb", "xcb-xfixes", "xcb-res"], text=True).split()
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", "-Wall", "-Wextra", "-Werror", str(REPO / "clipboard-observer.c"), *libs, "-o", str(cls.binary)], check=True)
        cls.xvfb = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "800x600x24", "-nolisten", "tcp"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        display = cls.xvfb.stdout.readline().strip()
        if not display:
            raise RuntimeError("Xvfb failed")
        cls.env = {**os.environ, "DISPLAY": ":" + display}

    @classmethod
    def tearDownClass(cls):
        cls.xvfb.terminate()
        cls.xvfb.wait(timeout=5)
        cls.xvfb.stdout.close()
        cls.temp.cleanup()

    def setUp(self):
        self.processes = []
        self.observer = self.start([self.binary])
        self.assertEqual(self.line(self.observer, 3), {"event": "ready", "protocol": 1})
        time.sleep(0.02)

    def tearDown(self):
        for process in reversed(self.processes):
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()

    def start(self, argv, environment=None):
        process = subprocess.Popen(argv, env=environment or self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(process)
        return process

    def line(self, process, timeout):
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout):
                return None
            value = process.stdout.readline()
            return json.loads(value) if value else None

    def capture(self, executable, mode, text, claimed_pid=None, child=None):
        log = self.base / (self._testMethodName + ".requests")
        log.unlink(missing_ok=True)
        environment = {**self.env}
        if claimed_pid is not None:
            environment["CLIPBOARD_FIXTURE_PID"] = str(claimed_pid)
        if child is not None:
            environment["CLIPBOARD_FIXTURE_CHILD"] = str(child)
        owner = self.start([executable, mode, text, log], environment)
        self.assertEqual(owner.stdout.readline().strip(), "ready")
        events = []
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            event = self.line(self.observer, max(0, deadline - time.monotonic()))
            if event is None:
                break
            events.append(event)
        requests = log.read_text().splitlines() if log.exists() else []
        return events, requests

    def test_policy_rejects_managers_and_preserves_browser_terminal(self):
        source = self.base / "policy-test.c"
        source.write_text('#define main observer_program_main\n#include "' +
                          str(REPO / "clipboard-observer.c") +
                          '"\n#undef main\nint main(void) {\n' +
                          'const char *denied[] = {"/usr/bin/bitwarden", "/usr/bin/keepassxc", '
                          '"/opt/Bitwarden/bitwarden", "/opt/KeePass/KeePass.exe", "/usr/bin/bw", '
                          '"/usr/bin/pass", "/usr/bin/gopass", "/usr/bin/1password"};\n'
                          'for (unsigned int i = 0; i < sizeof denied / sizeof denied[0]; i++) '
                          'if (eligible_path(denied[i])) return 1;\n'
                          'const char *allowed[] = {"/usr/bin/firefox", "/usr/bin/chromium", '
                          '"/usr/bin/alacritty", "/usr/bin/xclip", "/usr/bin/mono", "/usr/bin/python3"};\n'
                          'for (unsigned int i = 0; i < sizeof allowed / sizeof allowed[0]; i++) '
                          'if (!eligible_path(allowed[i])) return 2;\nif (!eligible_command(getpid(), "/usr/bin/bash")) return 3;\nreturn 0;\n}\n')
        binary = self.base / "policy-test"
        libs = subprocess.check_output(["pkg-config", "--libs", "xcb", "xcb-xfixes", "xcb-res"], text=True).split()
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", str(source), *libs, "-o", str(binary)], check=True)
        subprocess.run([binary, "/"], check=True, timeout=5)

    def test_notice_accepts_wrapped_and_long_running_timestamps(self):
        source = self.base / "timestamp-test.c"
        source.write_text('#define main observer_program_main\n#include "' +
                          str(REPO / "clipboard-observer.c") +
                          '"\n#undef main\nint main(void) {\n'
                          'xcb_xfixes_selection_notify_event_t event = {0};\n'
                          'uint32_t times[] = {1, UINT32_C(0x80000000), UINT32_MAX, 0, 2};\n'
                          'fixes_event=70; clipboard=42; event.response_type=70; '
                          'event.selection=42; event.owner=123;\n'
                          'for (unsigned i=0; i<sizeof times/sizeof times[0]; i++) {\n'
                          'event.selection_timestamp=times[i]; pending=0; '
                          'uint64_t before=generation; notice((void *)&event);\n'
                          'if (!pending || generation!=before+1 || latest.selection_timestamp!=times[i]) return 1; }\n'
                          'event.owner=0; notice((void *)&event); if (pending) return 2;\n'
                          'event.owner=123; event.response_type=70|128; uint64_t before=generation; '
                          'notice((void *)&event); if (pending || generation!=before) return 3;\n'
                          'return 0; }\n')
        binary = self.base / "timestamp-test"
        libs = subprocess.check_output(["pkg-config", "--libs", "xcb", "xcb-xfixes", "xcb-res"], text=True).split()
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", "-Wall", "-Wextra", "-Werror",
                        str(source), *libs, "-o", str(binary)], check=True)
        subprocess.run([binary], check=True, timeout=5)

    def test_missing_xres_is_unavailable(self):
        server = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "800x600x24",
                                   "-nolisten", "tcp", "-extension", "X-Resource"],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        try:
            display = server.stdout.readline().strip()
            self.assertTrue(display)
            result = subprocess.run([self.binary], env={**self.env, "DISPLAY": ":" + display},
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('"event":"ready"', result.stdout)
            self.assertNotIn('"event":"text"', result.stdout)
        finally:
            server.terminate()
            server.wait(timeout=5)
            server.stdout.close()

    def test_eligible_text(self):
        text = 'normal text "quoted"\nsecond line λ'
        events, requests = self.capture(self.owner, "plain", text)
        self.assertIn({"event": "text", "text": text}, events)
        self.assertIn("TEXT", requests)

    def test_browser_and_terminal_copies_remain_available(self):
        for name in ("firefox", "alacritty"):
            with self.subTest(application=name):
                executable = self.base / name
                shutil.copy2(self.owner, executable)
                events, requests = self.capture(executable, "plain", name + " normal copy")
                self.assertIn({"event": "text", "text": name + " normal copy"}, events)
                self.assertIn("TEXT", requests)
                events, requests = self.capture(executable, "secret", name + " marked secret")
                self.assertNotIn("TEXT", requests)
                self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_helper_spawned_by_manager_is_rejected(self):
        events, requests = self.capture(self.other, "spawn", "NEVER-EMIT-MANAGER-HELPER", child=self.owner)
        self.assertEqual(requests, [])
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_interpreter_hosted_keepass_is_rejected(self):
        mono = self.base / "mono"
        shutil.copy2(self.owner, mono)
        for index, application in enumerate(("KeePass.exe", "/home/test/vault dir/KeePass.exe")):
            with self.subTest(launch_path=application):
                log = self.base / (self._testMethodName + str(index) + ".requests")
                owner = self.start([mono, application, "plain", "NEVER-EMIT-MONO-SECRET", log])
                self.assertEqual(owner.stdout.readline().strip(), "ready")
                self.assertIsNone(self.line(self.observer, 1.5))
                self.assertFalse(log.exists(), "Interpreter-hosted manager was queried")

    def test_option_operand_and_perl_managers_are_rejected(self):
        for name, args in (("mono", ["--config", "/tmp/mono.config", "KeePass.exe"]),
                           ("perl", ["/usr/bin/kpcli"]),
                           ("bash", ["-e", "/usr/bin/pass"])):
            with self.subTest(interpreter=name):
                executable = self.base / name
                shutil.copy2(self.owner, executable)
                log = self.base / (name + "-options.requests")
                owner = self.start([executable, *args, "plain", "NEVER-EMIT-SECRET", log])
                self.assertEqual(owner.stdout.readline().strip(), "ready")
                self.assertIsNone(self.line(self.observer, 1.5))
                self.assertFalse(log.exists(), "Interpreter manager was queried")

    def test_invalid_utf8_is_not_retained(self):
        events, requests = self.capture(self.owner, "invalid-utf8", "unused")
        self.assertIn("TEXT", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_excess_targets_are_rejected_before_text(self):
        events, requests = self.capture(self.owner, "many-targets", "unused")
        self.assertIn("TARGETS", requests)
        self.assertNotIn("TEXT", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_startup_does_not_import_owned_clipboard(self):
        self.observer.terminate()
        self.observer.wait(timeout=5)
        log = self.base / (self._testMethodName + ".requests")
        owner = self.start([self.owner, "plain", "NEVER-IMPORT-STARTUP", log])
        self.assertEqual(owner.stdout.readline().strip(), "ready")
        self.observer = self.start([self.binary])
        self.assertEqual(self.line(self.observer, 3), {"event": "ready", "protocol": 1})
        self.assertIsNone(self.line(self.observer, 1.5))
        self.assertFalse(log.exists(), "Observer imported existing ownership on startup")

    def test_idle_does_not_poll_selection_or_consume_cpu(self):
        events, requests = self.capture(self.owner, "plain", "ordinary idle clipboard")
        self.assertIn({"event": "text", "text": "ordinary idle clipboard"}, events)
        log = self.base / (self._testMethodName + ".requests")
        before_requests = log.read_text()
        def ticks():
            fields = Path(f"/proc/{self.observer.pid}/stat").read_text().rsplit(")", 1)[1].split()
            return int(fields[11]) + int(fields[12])
        before = ticks()
        time.sleep(1)
        consumed = ticks() - before
        self.assertEqual(log.read_text(), before_requests)
        self.assertLessEqual(consumed, max(1, int(os.sysconf("SC_CLK_TCK") * .01)))
        print(f"Observer idle: {consumed} CPU ticks in 1s; selection requests unchanged", flush=True)

    def test_sensitive_marker_blocks_before_text(self):
        secret = "NEVER-EMIT-MARKED-SECRET"
        events, requests = self.capture(self.owner, "secret", secret)
        self.assertNotIn("TEXT", requests)
        self.assertIn("TARGETS", requests)
        self.assertNotIn(secret, json.dumps(events))
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_incremental_transfer_is_not_retained(self):
        events, requests = self.capture(self.owner, "incr", "NEVER-EMIT-INCR")
        self.assertIn("TEXT", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_oversize_is_not_retained(self):
        events, requests = self.capture(self.owner, "oversize", "unused")
        self.assertIn("TEXT", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_same_owner_recopied_secret_invalidates_read(self):
        events, requests = self.capture(self.owner, "race", "NEVER-EMIT-STALE-RACE")
        self.assertIn("TEXT", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))

    def test_unresponsive_owner_times_out_and_recovers(self):
        events, requests = self.capture(self.owner, "timeout", "unused")
        self.assertIn("TARGETS", requests)
        self.assertFalse(any(event.get("event") == "text" for event in events))
        events, requests = self.capture(self.owner, "plain", "recovered")
        self.assertIn({"event": "text", "text": "recovered"}, events)

    def test_manager_cannot_forge_class_and_pid(self):
        secret = "NEVER-EMIT-UNKNOWN-BROWSER"
        self.capture(self.owner, "secret", "marked preliminary owner")
        eligible_pid = self.processes[-1].pid
        events, requests = self.capture(self.other, "plain", secret, claimed_pid=eligible_pid)
        self.assertEqual(requests, [], "Unapproved source was queried before identity admission")
        self.assertNotIn(secret, json.dumps(events))
        self.assertFalse(any(event.get("event") == "text" for event in events))


if __name__ == "__main__":
    unittest.main()
