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
        cls.other = cls.base / "browser-owner"
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", "-Wall", "-Wextra", str(REPO / "tests/clipboard-owner.c"), "-lxcb", "-o", str(cls.owner)], check=True)
        shutil.copy2(cls.owner, cls.other)
        cls.binary = cls.base / "observer"
        libs = subprocess.check_output(["pkg-config", "--libs", "xcb", "xcb-xfixes", "xcb-res"], text=True).split()
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", "-Wall", "-Wextra", '-DCLIPBOARD_TEST_EXECUTABLE="' + str(cls.owner) + '"', str(REPO / "clipboard-observer.c"), *libs, "-o", str(cls.binary)], check=True)
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

    def capture(self, executable, mode, text, claimed_pid=None):
        log = self.base / (self._testMethodName + ".requests")
        log.unlink(missing_ok=True)
        environment = {**self.env}
        if claimed_pid is not None:
            environment["CLIPBOARD_FIXTURE_PID"] = str(claimed_pid)
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

    def test_policy_rejects_sensitive_and_generic_executables(self):
        source = self.base / "policy-test.c"
        source.write_text('#define main observer_program_main\n#include "' +
                          str(REPO / "clipboard-observer.c") +
                          '"\n#undef main\nint main(void) {\n' +
                          'const char *denied[] = {"/usr/bin/firefox", "/usr/bin/chromium", '
                          '"/usr/bin/google-chrome", "/usr/bin/bitwarden", "/usr/bin/keepassxc", '
                          '"/usr/bin/mono", "/usr/bin/xclip", "/usr/bin/xsel", "/usr/bin/alacritty", '
                          '"/usr/bin/kitty", "/usr/bin/python3", "/usr/bin/electron"};\n'
                          'for (unsigned int i = 0; i < sizeof denied / sizeof denied[0]; i++) '
                          'if (eligible_path(denied[i])) return 1;\nreturn 0;\n}\n')
        binary = self.base / "policy-test"
        libs = subprocess.check_output(["pkg-config", "--libs", "xcb", "xcb-xfixes", "xcb-res"], text=True).split()
        subprocess.run(["cc", "-D_POSIX_C_SOURCE=200809L", "-std=c99", str(source), *libs, "-o", str(binary)], check=True)
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

    def test_unknown_owner_cannot_forge_class(self):
        secret = "NEVER-EMIT-UNKNOWN-BROWSER"
        self.capture(self.owner, "secret", "marked preliminary owner")
        eligible_pid = self.processes[-1].pid
        events, requests = self.capture(self.other, "plain", secret, claimed_pid=eligible_pid)
        self.assertEqual(requests, [], "Unapproved source was queried before identity admission")
        self.assertNotIn(secret, json.dumps(events))
        self.assertFalse(any(event.get("event") == "text" for event in events))


if __name__ == "__main__":
    unittest.main()
