#!/usr/bin/python3
"""Snapshot boundaries: real parser/cache/scanner, external provider fixtures."""
import os
import json
import stat
import subprocess
import time
import sys
from dataclasses import replace
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/dwm-update-center"


def workspace():
    base = os.environ.get("DWM_TEST_WORKSPACE") or os.environ.get("DWM_TEST_TMP_ROOT") or str(Path.home() / "tmp")
    return tempfile.TemporaryDirectory(dir=base)


def source(rows=""):
    return ("system-management-protocol\t1\t0\n"
            "provider\tupdates\tavailable\tdelegated\tPackageKit\tReady\n"
            "state\tupdate-summary\tavailable\t1\tReady\n"
            "action\tupdates-install-all\tavailable\tdelegated\tupdates\tInstall\tReady\n"
            + rows + "complete\tsnapshot\n")


ROW = "update\tz;2;x86_64;repo\tnormal\tinstallable\tz\t2\tSummary\n"


class SnapshotProtocolTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(HELPER.exists(), "snapshot helper/parser interface is missing")
        self.api = runpy.run_path(str(HELPER))

    def test_fixed_order_and_preserved_item_fields(self):
        self.assertEqual([p.identifier for p in self.api["REGISTRY"]],
                         ["fedora", "dwm-titus", "flatpak", "mise"])
        result = self.api["parse_fedora_snapshot"](source(ROW))
        self.assertEqual(result.pending, 1)
        self.assertIs(type(result.pending), int)
        item = result.items[0]
        self.assertEqual((item.action, item.name, item.current, item.available, item.package_id),
                         ("update", "z", "unknown", "2", "z;2;x86_64;repo"))
        self.assertTrue(result.update_available)

    def test_deterministic_output_and_strict_escaping(self):
        result = self.api["parse_fedora_snapshot"](source(ROW))
        output = self.api["render_snapshot"]([result])
        self.assertTrue(output.startswith("update-center-protocol\t1\t0\nprovider\tfedora\t"))
        self.assertTrue(output.endswith("complete\tsnapshot\n"))
        self.assertEqual(output, self.api["render_snapshot"]([result]))
        self.assertEqual(self.api["unescape"](self.api["escape"]("a\tb\nc\\d")), "a\tb\nc\\d")
        with self.assertRaises(ValueError):
            self.api["unescape"]("\\q")
        for text in ("\x01", "\x1b", "\x7f", "\x85"):
            with self.subTest(text=repr(text)), self.assertRaises(ValueError):
                self.api["escape"](text)

    def test_rejects_unknown_fields_counts_duplicates_and_budgets(self):
        for payload in (source(ROW.replace("Summary\n", "Summary\textra\n")),
                        source(ROW.replace("Summary", "x" * 8193)),
                        source(ROW + ROW), source(ROW).replace("available\t1\tReady", "available\t-1\tReady"),
                        source(ROW.replace("Summary", "\x1bmalformed")),
                        source(ROW) + "unexpected\trow\n", source(ROW).replace("complete\tsnapshot\n", "")):
            with self.subTest(payload=payload[:100]), self.assertRaises(ValueError):
                self.api["parse_fedora_snapshot"](payload)

    def test_fedora_identity_fails_closed(self):
        with workspace() as folder:
            release = Path(folder) / "os-release"
            for identity in ("ID=arch\nID_LIKE=fedora\n", "ID=fedora\nID=arch\n", "ID=\"fedora\"\nBAD\n"):
                release.write_text(identity)
                with self.assertRaisesRegex(ValueError, "Fedora"):
                    self.api["require_fedora"](release)
            release.write_text('ID="fedora"\nVERSION_ID=44\n')
            self.api["require_fedora"](release)

    def test_plan_action_and_input_order_preserved_deterministically(self):
        a = "update\ta;3;x86_64;repo\tsecurity\tinstallable\ta\t3\tSummary\n"
        plan = "package-change\ta;3;x86_64;repo\tinstall\ta\t3\tSummary\n"
        one = source(ROW + a + plan).replace("available\t1\tReady", "available\t2\tReady")
        two = source(plan + a + ROW).replace("available\t1\tReady", "available\t2\tReady")
        self.assertEqual(self.api["render_snapshot"]([self.api["parse_fedora_snapshot"](one)]),
                         self.api["render_snapshot"]([self.api["parse_fedora_snapshot"](two)]))
        self.assertEqual(self.api["parse_fedora_snapshot"](one).items[0].action, "install")

    def test_existing_composed_machine_snapshot_is_accepted(self):
        with workspace() as directory:
            result = subprocess.run([sys.executable, str(ROOT / "tests/fixtures/system-native-discovery-provider.py"), "snapshot"],
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "DWM_NATIVE_DISCOVERY_FIXTURE": directory},
                text=True, capture_output=True, check=True, timeout=5)
            normalized = self.api["parse_fedora_snapshot"](result.stdout)
            self.assertEqual(normalized.identifier, "fedora")
            self.assertIs(type(normalized.pending), int)

    def test_existing_terminal_handoff_disables_advisory_update(self):
        payload = source(ROW).replace("complete\tsnapshot", "terminal-handoff\top-00000000000000000000000000000000\tupdates-install-all\tupdate\ncomplete\tsnapshot")
        result = self.api["parse_fedora_snapshot"](payload)
        self.assertEqual(result.pending, 1)
        self.assertFalse(result.update_available)

    def test_fedora_restart_guidance_is_normalized(self):
        payload = source(ROW).replace("complete\tsnapshot", "state\tupdate-restart\tavailable\tsystem\tRestart required\ncomplete\tsnapshot")
        result = self.api["parse_fedora_snapshot"](payload)
        self.assertEqual(result.restart, "system")
        self.assertIn("guidance\tfedora\trestart\tsystem\n", self.api["render_snapshot"]([result]))

    def test_fedora_restart_guidance_accepts_system_management_buckets(self):
        for backend, normalized in (("security-system", "system"), ("security-session", "session"),
                                    ("application", "session"), ("none", "none")):
            with self.subTest(backend=backend):
                payload = source(ROW).replace("complete\tsnapshot",
                    f"state\tupdate-restart\tavailable\t{backend}\tRestart required\ncomplete\tsnapshot")
                result = self.api["parse_fedora_snapshot"](payload)
                self.assertEqual(result.restart, normalized)
        partial = source(ROW).replace("complete\tsnapshot",
            "state\tupdate-restart\tpartial\tsecurity-session\tRestart guidance retained\ncomplete\tsnapshot")
        self.assertEqual(self.api["parse_fedora_snapshot"](partial).restart, "session")
        unknown = source(ROW).replace("complete\tsnapshot",
            "state\tupdate-restart\tpartial\tunknown\tRestart guidance incomplete\ncomplete\tsnapshot")
        self.assertEqual(self.api["parse_fedora_snapshot"](unknown).restart, "none")

    def test_source_uses_only_lf_records_and_rejects_raw_control_separators(self):
        valid = source().replace("available\t1\tReady", "available\t0\tReady")
        self.assertEqual(self.api["parse_fedora_snapshot"](valid).pending, 0)
        for separator in ("\x0b", "\x0c", "\x1c", "\x1d", "\x1e", "\x85", "\r", "\r\n", "\u2028", "\u2029"):
            with self.subTest(separator=repr(separator)), self.assertRaises(ValueError):
                self.api["parse_fedora_snapshot"](valid.replace("\n", separator))


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))
        self.temp = workspace()
        self.addCleanup(self.temp.cleanup)
        from unittest.mock import patch
        environment = patch.dict(os.environ, {"XDG_RUNTIME_DIR": "", "XDG_STATE_HOME": str(Path(self.temp.name) / "state")})
        environment.start()
        self.addCleanup(environment.stop)
        self.path = Path(self.temp.name) / "cache/dwm-titus/update-center.json"
        self.good = self.api["parse_fedora_snapshot"](source(ROW))
        self.assertTrue("snapshot" in self.api, "last-good cache interface is missing")

    def scan(self, scanners=None, **options):
        return self.api["snapshot"](self.path, scanners or {"fedora": lambda: self.good}, now=100, **options)

    def test_immediate_cache_and_force_replacement(self):
        self.scan(force=True)
        def forbidden():
            self.fail("valid cache must not start a provider")
        self.assertEqual(self.scan({"fedora": forbidden})[0].pending, 1)
        fresh = replace(self.good, pending=0, items=())
        self.assertEqual(self.scan({"fedora": lambda: fresh}, force=True)[0].pending, 0)
        self.assertEqual(json.loads(self.path.read_text())["schema"], 1)

    def test_schema_one_cache_without_restart_defaults_to_none(self):
        self.scan(force=True)
        cached = json.loads(self.path.read_text())
        del cached["providers"][0]["restart"]
        self.path.write_text(json.dumps(cached))
        result = self.api["read_cache"](self.path)[0]
        self.assertEqual(result.restart, "none")
        def forbidden():
            self.fail("compatible schema-one cache must not force a live scan")
        self.assertEqual(self.scan({"fedora": forbidden})[0].pending, 1)

    def test_failure_retains_last_good_independently_and_recovers(self):
        desktop = self.api["ProviderResult"]("dwm-titus", pending=0)
        self.scan({"fedora": lambda: self.good, "dwm-titus": lambda: desktop}, force=True)
        def fail():
            raise ValueError("bad data")
        results = self.scan({"fedora": fail, "dwm-titus": lambda: desktop}, force=True)
        self.assertEqual((results[0].pending, results[0].freshness, results[0].last_success), (1, "stale", 100))
        self.assertEqual(results[0].items, self.good.items)
        self.assertFalse(results[0].update_available)
        self.assertEqual(results[1].freshness, "fresh")
        recovered = self.scan(force=True)[0]
        self.assertEqual((recovered.freshness, recovered.error_code), ("fresh", ""))

    def test_provider_network_failure_preserves_failure_classification(self):
        self.scan(force=True)
        failed = source().replace("state\tupdate-summary\tavailable\t1\tReady",
                                  "state\tupdate-summary\tunavailable\tunknown\tOffline")
        failed = failed.replace("complete\tsnapshot", "error\tupdates\tnetwork\tNetwork unavailable\ncomplete\tsnapshot")
        result = self.scan({"fedora": lambda: self.api["parse_fedora_snapshot"](failed)}, force=True)[0]
        self.assertEqual((result.pending, result.freshness, result.error_code), (1, "stale", "network"))
        self.assertIn("Network unavailable", result.detail)

    def test_invalid_cache_is_ignored_and_preserved_when_unsafe(self):
        self.scan(force=True)
        for content in ('{"schema":2}', '{broken', '{"schema":1,"providers":[]}'):
            self.path.write_text(content)
            self.assertIsNone(self.api["read_cache"](self.path))
        self.path.write_text("unsafe")
        self.path.chmod(0o666)
        self.assertEqual(self.scan(force=True)[0].pending, 1)
        self.assertEqual(self.path.read_text(), "unsafe")
        self.assertIsNone(self.api["read_cache"](self.path))

    def test_cache_schema_types_unknown_fields_oversize_and_unsafe_parent(self):
        self.scan(force=True)
        valid = json.loads(self.path.read_text())
        for field, value in (("pending", True), ("pending", -1), ("managed", "123"),
                             ("last_success", "100"), ("status", "invented"), ("detail", "x" * 8193),
                             ("invented", "unexpected")):
            changed = json.loads(json.dumps(valid))
            changed["providers"][0][field] = value
            self.path.write_text(json.dumps(changed))
            self.assertIsNone(self.api["read_cache"](self.path), field)
        self.path.write_text('{"schema":1,"schema":1,"providers":[]}')
        self.assertIsNone(self.api["read_cache"](self.path))
        self.path.write_text("x" * (8 * 1024 * 1024 + 1))
        self.assertIsNone(self.api["read_cache"](self.path))
        self.path.parent.chmod(0o777)
        self.assertIsNone(self.api["read_cache"](self.path))
        self.path.parent.chmod(0o700)

    def test_wrong_owner_and_nonregular_cache_are_ignored_without_mutation(self):
        from unittest.mock import patch
        self.scan(force=True)
        before = self.path.read_bytes()
        original = os.fstat
        def wrong_owner(fd):
            info = original(fd)
            if stat.S_ISREG(info.st_mode):
                fields = list(info)
                fields[4] = os.getuid() + 1
                return os.stat_result(fields)
            return info
        with patch("os.fstat", side_effect=wrong_owner):
            self.assertIsNone(self.api["read_cache"](self.path))
        self.assertEqual(self.path.read_bytes(), before)
        self.path.unlink()
        os.mkfifo(self.path)
        started = time.monotonic()
        self.assertIsNone(self.api["read_cache"](self.path))
        self.assertLess(time.monotonic() - started, 1)
        self.assertTrue(stat.S_ISFIFO(self.path.lstat().st_mode))

    def test_failed_atomic_replace_retains_old_cache_and_cleans_staging(self):
        from unittest.mock import patch
        self.scan(force=True)
        before = self.path.read_bytes()
        with patch("os.replace", side_effect=OSError("injected failure")):
            fresh = replace(self.good, pending=0, items=())
            self.assertEqual(self.scan({"fedora": lambda: fresh}, force=True)[0].pending, 0)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertFalse(any(p.name.startswith(".update-center-") for p in self.path.parent.iterdir()))

    def test_atomic_replacement_and_symlink_hardlink_rejection(self):
        self.scan(force=True)
        inode = self.path.stat().st_ino
        self.scan(force=True)
        self.assertNotEqual(self.path.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual({p.name for p in self.path.parent.iterdir()}, {"update-center.json", ".cache-write"})
        linked = self.path.with_name("linked")
        os.link(self.path, linked)
        self.assertIsNone(self.api["read_cache"](self.path))
        linked.unlink()
        target = self.path.with_name("target")
        self.path.rename(target)
        self.path.symlink_to(target)
        before = target.read_bytes()
        self.scan(force=True)
        self.assertEqual(target.read_bytes(), before)
        self.assertTrue(self.path.is_symlink())

    def test_unsafe_cache_parent_does_not_prevent_live_scan(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text("unsafe cache preserved")
        self.path.parent.chmod(0o777)
        result = self.scan(force=True)[0]
        self.assertEqual((result.pending, result.freshness, result.status), (1, "fresh", "available"))
        self.assertEqual(self.path.read_text(), "unsafe cache preserved")
        self.assertEqual({p.name for p in self.path.parent.iterdir()}, {"update-center.json"})

    def test_cache_write_denial_does_not_prevent_live_scan(self):
        from unittest.mock import patch
        original = self.api["snapshot"].__globals__["cache_directory"]
        import contextlib
        @contextlib.contextmanager
        def denied(path, create=False):
            if Path(path) == self.path.parent:
                raise PermissionError("cache denied")
            with original(path, create=create) as fd:
                yield fd
        with patch.dict(self.api["snapshot"].__globals__, {"cache_directory": denied}):
            result = self.scan(force=True)[0]
        self.assertEqual((result.pending, result.freshness), (1, "fresh"))
        self.assertFalse(self.path.exists())

    def test_invalid_relative_cache_path_does_not_block_live_cli_snapshot(self):
        from unittest.mock import patch
        import contextlib
        import io
        output = io.StringIO()
        globals_ = self.api["main"].__globals__
        with patch.dict(os.environ, {"XDG_CACHE_HOME": "relative-cache-must-not-exist"}), \
                patch.dict(globals_, {"require_fedora": lambda: None, "scan_fedora": lambda: self.good}), \
                contextlib.redirect_stdout(output):
            self.assertEqual(self.api["main"](["snapshot", "--force"]), 0)
        self.assertIn("provider\tfedora\tFedora\tavailable\t1", output.getvalue())
        self.assertFalse((ROOT / "relative-cache-must-not-exist").exists())

    def test_optional_only_cache_cannot_suppress_fedora_acquisition(self):
        reserved = self.api["ProviderResult"]("mise", last_success=100)
        self.api["write_cache"](self.path, [reserved])
        result = self.scan()
        self.assertEqual([p.identifier for p in result], ["fedora"])
        self.assertEqual((result[0].pending, result[0].freshness), (1, "fresh"))

    def test_retired_provider_cache_is_never_returned_or_merged(self):
        reserved = self.api["ProviderResult"]("mise", last_success=100)
        fedora = replace(self.good, last_success=100)
        self.api["write_cache"](self.path, [fedora, reserved])
        def forbidden():
            self.fail("active Fedora cache should render immediately")
        self.assertEqual([p.identifier for p in self.scan({"fedora": forbidden})], ["fedora"])
        self.assertEqual([p.identifier for p in self.scan(force=True)], ["fedora"])
        self.assertEqual([p.identifier for p in self.api["read_cache"](self.path)], ["fedora"])

    def test_targeted_rescan_preserves_other_active_provider_and_fills_missing_core(self):
        desktop = self.api["ProviderResult"]("dwm-titus", last_success=100)
        self.api["write_cache"](self.path, [desktop])
        results = self.scan({"fedora": lambda: self.good, "dwm-titus": lambda: desktop}, provider="dwm-titus")
        self.assertEqual([p.identifier for p in results], ["fedora", "dwm-titus"])
        self.assertEqual(results[0].pending, 1)
        def forbidden():
            self.fail("targeted rescan must retain cached active Fedora")
        results = self.scan({"fedora": forbidden, "dwm-titus": lambda: desktop}, provider="dwm-titus")
        self.assertEqual([p.identifier for p in results], ["fedora", "dwm-titus"])
        self.assertEqual(results[0].pending, 1)


class ScanIsolationTests(CacheTests):
    def setUp(self):
        super().setUp()
        self.assertTrue("run_bounded" in self.api, "bounded concurrent scanner is missing")

    def test_deadline_retains_fedora_while_independent_provider_finishes(self):
        self.scan(force=True)
        marker = Path(self.temp.name) / "independent"
        def hung():
            try:
                payload = self.api["run_bounded"]([sys.executable, "-c", "import time;time.sleep(20)"], timeout=0.2)
            finally:
                self.assertTrue(marker.exists(), "independent scan must finish before Fedora deadline")
            return self.api["parse_fedora_snapshot"](payload)
        def desktop():
            marker.write_text("completed")
            return self.api["ProviderResult"]("dwm-titus")
        started = time.monotonic()
        results = self.scan({"fedora": hung, "dwm-titus": desktop}, force=True)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(marker.read_text(), "completed")
        self.assertEqual((results[0].pending, results[0].freshness, results[0].error_code), (1, "stale", "timeout"))
        self.assertEqual(results[1].freshness, "fresh")

    def test_failed_malformed_and_oversized_child_output(self):
        for script, error in (("import sys;sys.exit(1)", OSError),
                              ("print('invalid')", ValueError),
                              ("import sys;sys.stdout.write('x'*9000000)", ValueError)):
            with self.subTest(script=script):
                def scan():
                    return self.api["parse_fedora_snapshot"](self.api["run_bounded"]([sys.executable, "-c", script], timeout=2))
                result = self.scan({"fedora": scan}, force=True)[0]
                self.assertEqual((result.status, result.freshness, result.pending), ("unavailable", "error", 0))

    def test_malformed_adapter_types_degrade_only_affected_provider(self):
        for bad in (replace(self.good, status={}), replace(self.good, identifier=[]),
                    replace(self.good, items=None), replace(self.good, error_code=[])):
            with self.subTest(bad=bad):
                desktop = self.api["ProviderResult"]("dwm-titus")
                results = self.scan({"fedora": lambda: bad, "dwm-titus": lambda: desktop}, force=True)
                self.assertEqual(results[0].error_code, "malformed")
                self.assertEqual(results[1].freshness, "fresh")

    def test_consecutive_processes_environment_and_repository_immutability(self):
        def repository_state():
            return (subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT),
                    subprocess.check_output(["git", "diff", "--binary"], cwd=ROOT),
                    HELPER.read_bytes(), Path(__file__).read_bytes(), (ROOT / "Makefile").read_bytes())
        before = repository_state()
        command = [sys.executable, "-c", "import os;print(os.environ.get('DWM_CENTER_CUSTOM', 'default'))"]
        custom = {**os.environ, "DWM_CENTER_CUSTOM": "custom"}
        default = {key: value for key, value in os.environ.items() if key != "DWM_CENTER_CUSTOM"}
        self.assertEqual(self.api["run_bounded"](command, env=custom), "custom\n")
        self.assertEqual(self.api["run_bounded"](command, env=default), "default\n")
        self.scan(force=True)
        self.assertEqual(repository_state(), before)
        self.assertFalse((ROOT / "scripts/__pycache__").exists())

    def test_cli_rejects_invalid_arguments_before_identity_and_cache_writes(self):
        for args in ([], ["snapshot", "--force=yes"], ["rescan"], ["rescan", "arbitrary"], ["snapshot", "--force", "extra"]):
            with self.subTest(args=args):
                result = subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True,
                                        env={**os.environ, "XDG_CACHE_HOME": self.temp.name})
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stderr, "usage: snapshot [--force] | rescan PROVIDER | launch PROVIDER | "
                                 "active | terminal-closed OPERATION_ID | recover PROVIDER\n")
                self.assertEqual(result.stdout, "")
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_same_provider_lock_prevents_overlap(self):
        import threading
        entered = threading.Event()
        release = threading.Event()
        def slow():
            entered.set()
            release.wait(2)
            return self.good
        first = threading.Thread(target=lambda: self.scan({"fedora": slow}, force=True))
        first.start()
        self.assertTrue(entered.wait(1))
        try:
            def forbidden():
                self.fail("same provider scans must not overlap")
            second = self.scan({"fedora": forbidden}, force=True)[0]
            self.assertEqual(second.error_code, "busy")
        finally:
            release.set()
            first.join(3)
        self.assertFalse(first.is_alive())

    def test_cross_process_provider_exclusion_is_independent_of_cache_path(self):
        import select
        child = subprocess.Popen([sys.executable, "-B", "-c",
            "import runpy,sys;api=runpy.run_path(sys.argv[1]);\nwith api['scan_lock']('fedora'):\n print('locked',flush=True);sys.stdin.read(1)", str(HELPER)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=dict(os.environ))
        try:
            self.assertTrue(select.select([child.stdout], [], [], 3)[0], "child lock acquisition timed out")
            self.assertEqual(child.stdout.readline(), "locked\n")
            self.path.parent.mkdir(parents=True)
            self.path.parent.chmod(0o777)
            def forbidden():
                self.fail("cross-process lock must exclude the same provider")
            result = self.scan({"fedora": forbidden}, force=True)[0]
            self.assertEqual(result.error_code, "busy")
        finally:
            child.communicate("x", timeout=3)
        self.assertEqual(child.returncode, 0)
        self.assertEqual(self.scan(force=True)[0].freshness, "fresh")
        self.assertEqual(list(self.path.parent.iterdir()), [])

    def test_runtime_environment_does_not_change_state_coordination(self):
        from unittest.mock import patch
        runtime = Path(self.temp.name) / "runtime"
        runtime.mkdir(mode=0o700)
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
            self.scan(force=True)
            self.assertEqual(list(runtime.iterdir()), [])
            runtime.chmod(0o777)
            self.assertEqual(self.scan(force=True)[0].freshness, "fresh")
        self.assertTrue((Path(os.environ["XDG_STATE_HOME"]) / "dwm-titus/update-center/.scan-fedora").exists())

    def test_cross_process_runtime_variation_never_splits_scanner_or_cache_ownership(self):
        import select
        from unittest.mock import patch
        runtime = Path(self.temp.name) / "runtime"
        alternate = Path(self.temp.name) / "alternate-runtime"
        runtime.mkdir(mode=0o700)
        alternate.mkdir(mode=0o700)
        code = ("import runpy,sys;from dataclasses import replace;api=runpy.run_path(sys.argv[1]);\n"
                "def scan():\n print('scanning',flush=True);sys.stdin.read(1);return replace(api['parse_fedora_snapshot'](sys.argv[3]),pending=0,items=())\n"
                "api['snapshot'](sys.argv[2],{'fedora':scan},force=True,now=200)")
        for changed in (None, str(alternate)):
            with self.subTest(runtime=changed):
                self.scan(force=True)
                before = self.path.read_bytes()
                before_metadata = (self.path.stat().st_ino, self.path.stat().st_mtime_ns)
                child = subprocess.Popen([sys.executable, "-B", "-c", code, str(HELPER), str(self.path), source(ROW)],
                    env={**os.environ, "XDG_RUNTIME_DIR": str(runtime)}, stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    self.assertTrue(select.select([child.stdout], [], [], 3)[0], "child scan did not start")
                    self.assertEqual(child.stdout.readline(), "scanning\n")
                    environment = {key: value for key, value in os.environ.items() if key != "XDG_RUNTIME_DIR"}
                    if changed is not None:
                        environment["XDG_RUNTIME_DIR"] = changed
                    calls = []
                    def second():
                        calls.append("scanned")
                        return self.good
                    with patch.dict(os.environ, environment, clear=True):
                        result = self.scan({"fedora": second}, force=True)[0]
                    self.assertEqual(result.error_code, "busy")
                    self.assertEqual(calls, [])
                    self.assertEqual(self.path.read_bytes(), before)
                    self.assertEqual((self.path.stat().st_ino, self.path.stat().st_mtime_ns), before_metadata)
                finally:
                    try:
                        _, stderr = child.communicate("x", timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.communicate()
                        raise
                self.assertEqual(child.returncode, 0, stderr)
                self.assertEqual(self.api["read_cache"](self.path)[0].pending, 0)

    def test_unsafe_state_coordination_is_rejected_without_following_symlinks(self):
        state = Path(os.environ["XDG_STATE_HOME"])
        target = Path(self.temp.name) / "target"
        target.mkdir()
        state.symlink_to(target)
        def forbidden():
            self.fail("unsafe coordination cannot allow an unprotected scan")
        result = self.scan({"fedora": forbidden}, force=True)[0]
        self.assertEqual(result.error_code, "scan-failed")
        self.assertEqual(list(target.iterdir()), [])

    def test_concurrent_different_provider_rescans_preserve_both_results(self):
        import threading
        desktop = self.api["ProviderResult"]("dwm-titus")
        self.scan({"fedora": lambda: self.good, "dwm-titus": lambda: desktop}, force=True)
        entered, release = threading.Event(), threading.Event()
        def slow():
            entered.set()
            release.wait(2)
            return self.good
        def forbidden():
            self.fail("targeted rescan must not scan the other cached provider")
        first = threading.Thread(target=lambda: self.scan({"fedora": slow, "dwm-titus": forbidden}, provider="fedora"))
        first.start()
        self.assertTrue(entered.wait(1))
        try:
            self.scan({"fedora": forbidden, "dwm-titus": lambda: desktop}, provider="dwm-titus")
        finally:
            release.set()
            first.join(3)
        self.assertEqual([p.identifier for p in self.api["read_cache"](self.path)], ["fedora", "dwm-titus"])


class OptionalFailureTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))

    def test_operational_failure_first_run_and_last_good_exact_codes(self):
        from unittest.mock import patch
        for identifier in ("flatpak", "mise"):
            for failure, code in ((TimeoutError("expired"), "timeout"),
                                  (OSError("exit nonzero"), "scan-failed"),
                                  (PermissionError("denied"), "permission-denied")):
                with self.subTest(provider=identifier, code=code), workspace() as folder:
                    function = self.api["scan_" + identifier]
                    def run(argv, **options):
                        raise failure
                    with patch.dict(function.__globals__, optional_executable=lambda name: "/usr/bin/" + name,
                                    run_bounded=run), patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
                        path = Path(folder) / "cache/update-center.json"
                        first = self.api["snapshot"](path, {identifier: function}, force=True, now=100)
                        self.assertEqual([(r.identifier, r.freshness, r.error_code) for r in first],
                                         [(identifier, "error", code)])
                        good = self.api["ProviderResult"](identifier, pending=1, managed=1, items=(
                            self.api["ItemResult"]("update", "item", "1", "2", "item"),))
                        self.api["snapshot"](path, {identifier: lambda: good}, force=True, now=101)
                        retained = self.api["snapshot"](path, {identifier: function}, force=True, now=102)[0]
                        self.assertEqual((retained.pending, retained.managed, retained.freshness,
                                          retained.error_code, retained.last_success), (1, 1, "stale", code, 101))

    def test_flatpak_system_success_then_user_failure_keeps_error_visible(self):
        from unittest.mock import patch
        ref = "org.example.App/x86_64/stable"
        for fail_index in range(8):
            with self.subTest(call=fail_index), workspace() as folder:
                function = self.api["scan_flatpak"]
                calls = []
                def run(argv, **options):
                    calls.append(argv)
                    if len(calls) - 1 == fail_index:
                        raise TimeoutError("scope timeout")
                    return ref + "\t1\n"
                with patch.dict(function.__globals__, optional_executable=lambda name: "/usr/bin/flatpak", run_bounded=run), \
                        patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
                    path = Path(folder) / "cache/result.json"
                    result = self.api["snapshot"](path, {"flatpak": function}, force=True, now=100)[0]
                    good = self.api["ProviderResult"]("flatpak", pending=2, managed=2, items=tuple(
                        self.api["ItemResult"]("update", "App", "1", "2", ref, scope)
                        for scope in ("system", "user")))
                    self.api["snapshot"](path, {"flatpak": lambda: good}, force=True, now=101)
                    calls.clear()
                    retained = self.api["snapshot"](path, {"flatpak": function}, force=True, now=102)[0]
                    self.assertEqual((retained.items, retained.pending, retained.freshness,
                                      retained.error_code, retained.last_success), (good.items, 2, "stale", "timeout", 101))
                self.assertEqual((result.identifier, result.freshness, result.error_code), ("flatpak", "error", "timeout"))
                self.assertEqual(len(calls), fail_index + 1)

    def test_actual_nonzero_child_exit_is_operational_error_for_optional_adapter(self):
        from unittest.mock import patch
        for identifier in ("flatpak", "mise"):
            with self.subTest(provider=identifier), workspace() as folder, \
                    patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
                function = self.api["scan_" + identifier]
                bounded = self.api["run_bounded"]
                def run(argv, **options):
                    return bounded([sys.executable, "-c", "raise SystemExit(3)"], timeout=2)
                with patch.dict(function.__globals__, optional_executable=lambda name: "/usr/bin/" + name, run_bounded=run):
                    result = self.api["snapshot"](Path(folder) / "cache/result.json", {identifier: function}, force=True)[0]
                self.assertEqual((result.identifier, result.freshness, result.error_code), (identifier, "error", "scan-failed"))

    def test_consecutive_disappearance_retains_exceptional_evidence_without_commands(self):
        from unittest.mock import patch
        for identifier in ("flatpak", "mise"):
            for code, freshness, successful in (("network", "stale", True),
                                                 ("interrupted", "stale", True),
                                                 ("timeout", "error", False)):
                with self.subTest(provider=identifier, code=code), workspace() as folder, \
                        patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
                    path = Path(folder) / "cache/snapshot.json"
                    function = self.api["discover_scanners"]
                    globals_ = function.__globals__
                    cores = {"fedora": lambda: self.api["ProviderResult"]("fedora"),
                             "dwm-titus": lambda: self.api["ProviderResult"]("dwm-titus")}
                    good = self.api["ProviderResult"](identifier, managed=1, pending=1, items=(
                        self.api["ItemResult"]("update", "item", "1", "2", "item"),))
                    if successful:
                        self.api["snapshot"](path, {**cores, identifier: lambda: good}, force=True, now=100)
                    def fail():
                        raise self.api["ScanFailure"](code, "Retain recovery evidence")
                    self.api["snapshot"](path, {**cores, identifier: fail}, force=True, now=101)
                    with patch.dict(globals_, optional_executable=lambda name: None):
                        scanners = function()
                    self.assertEqual(list(scanners), ["fedora", "dwm-titus"])
                    def forbidden():
                        self.fail("ordinary cache read must not execute commands")
                    cached = self.api["snapshot"](path, {key: forbidden for key in scanners}, now=102)
                    retained = cached[-1]
                    self.assertEqual((retained.identifier, retained.error_code, retained.freshness),
                                     (identifier, code, freshness))
                    self.assertIn("Retain recovery evidence", retained.detail)
                    self.assertIn("missing-provider", retained.detail)
                    self.assertFalse(retained.update_available)
                    forced = self.api["snapshot"](path, cores, force=True, now=103)
                    self.assertEqual(forced[-1], retained)
                    persisted = self.api["read_cache"](path)[-1]
                    self.assertEqual(persisted, retained)
                    if successful:
                        self.assertEqual((persisted.pending, persisted.last_success), (1, 100))

    def test_incompatible_capability_preserves_interrupted_evidence(self):
        from unittest.mock import patch
        with workspace() as folder, patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
            path = Path(folder) / "cache/snapshot.json"
            record = self.api["ProviderResult"]("mise", "restricted", error_code="interrupted", detail="Recheck before retry")
            self.api["snapshot"](path, {"mise": lambda: record}, force=True, now=100)
            result = self.api["snapshot"](path, {"mise": lambda: None}, force=True, now=101)[0]
            self.assertEqual((result.error_code, result.freshness, result.last_success, result.update_available),
                             ("interrupted", "stale", 100, False))
            self.assertIn("Recheck before retry", result.detail)
            self.assertIn("unsupported", result.detail)

    def test_recovery_restricted_record_retained_but_healthy_unavailable_hidden(self):
        from unittest.mock import patch
        with workspace() as folder, patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
            path = Path(folder) / "cache/snapshot.json"
            self.api["write_cache"](path, [self.api["ProviderResult"]("fedora", last_success=100),
                self.api["ProviderResult"]("flatpak", "unavailable", last_success=100),
                self.api["ProviderResult"]("mise", "restricted", last_success=100, detail="Native recovery required")])
            def forbidden():
                self.fail("missing provider must not execute")
            result = self.api["snapshot"](path, {"fedora": forbidden}, now=101)
            self.assertEqual([r.identifier for r in result], ["fedora", "mise"])
            self.assertEqual((result[-1].error_code, result[-1].freshness), ("missing-provider", "stale"))
            self.assertIn("Native recovery required", result[-1].detail)

    def test_disappearance_guidance_respects_protocol_record_limit(self):
        from unittest.mock import patch
        with workspace() as folder, patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
            path = Path(folder) / "cache/snapshot.json"
            self.api["write_cache"](path, [self.api["ProviderResult"]("fedora", last_success=100),
                self.api["ProviderResult"]("mise", "restricted", last_success=100, detail="Recover: " + "x" * 8080)])
            result = self.api["snapshot"](path, {"fedora": lambda: self.api["ProviderResult"]("fedora")})
            output = self.api["render_snapshot"](result)
            self.assertIn("Recover:", output)
            self.assertIn("missing-provider", output)


class RegistryDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))

    def test_all_providers_declare_safe_discovery_and_operation_capabilities(self):
        self.assertEqual([p.identifier for p in self.api["REGISTRY"]], ["fedora", "dwm-titus", "flatpak", "mise"])
        for provider in self.api["REGISTRY"]:
            self.assertRegex(provider.identifier, r"^[a-z][a-z0-9-]*$")
            self.assertRegex(provider.icon, r"^[a-z][a-z0-9-]*$")
            self.assertTrue(callable(getattr(provider, "discover", None)), "provider discover function missing")
            self.assertIs(type(provider.can_update), bool)
            self.assertIs(type(provider.can_recover), bool)
            self.assertTrue(not provider.can_update or provider.can_recover,
                            "mutable provider must declare safe recovery eligibility")
            self.assertFalse(hasattr(provider, "command"))
        self.assertTrue(self.api["REGISTRY"][1].can_recover)

    def test_activation_rejects_mutable_provider_without_recovery_eligibility(self):
        from unittest.mock import patch
        function = self.api["discover_scanners"]
        for provider in self.api["REGISTRY"]:
            broken = tuple(replace(entry, can_recover=False) if entry.identifier == provider.identifier else entry
                           for entry in self.api["REGISTRY"])
            with self.subTest(provider=provider.identifier), \
                    patch.dict(function.__globals__, REGISTRY=broken, optional_executable=lambda name: None), \
                    self.assertRaisesRegex(ValueError, "mutable provider requires recovery eligibility"):
                function()

    def test_optional_incompatible_result_hides_and_retains_last_good_if_present(self):
        from unittest.mock import patch
        with workspace() as folder:
            path = Path(folder) / "cache/update-center.json"
            with patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
                results = self.api["snapshot"](path, {"fedora": lambda: self.api["ProviderResult"]("fedora"),
                             "dwm-titus": lambda: self.api["ProviderResult"]("dwm-titus"),
                             "flatpak": lambda: None, "mise": lambda: None}, force=True, now=100)
                self.assertEqual([r.identifier for r in results], ["fedora", "dwm-titus"])
                self.api["snapshot"](path, {"mise": lambda: self.api["ProviderResult"]("mise")}, force=True, now=101)
                result = self.api["snapshot"](path, {"mise": lambda: None}, force=True, now=102)[0]
                self.assertEqual((result.identifier, result.freshness, result.error_code), ("mise", "stale", "unsupported"))

    def test_discovery_registers_both_core_rows_and_hides_missing_optional_tools(self):
        self.assertTrue("discover_scanners" in self.api, "registry activation missing")
        from unittest.mock import patch
        function = self.api["discover_scanners"]
        with patch.dict(function.__globals__, optional_executable=lambda name: None):
            self.assertEqual(list(function()), ["fedora", "dwm-titus"])

    def test_count_and_item_bounds_fail_closed(self):
        constructor = self.api["ProviderResult"]
        for provider in self.api["REGISTRY"]:
            for count in (-1, 4097, True):
                with self.subTest(provider=provider.identifier, count=count), self.assertRaises(ValueError):
                    self.api["validate_result"](constructor(provider.identifier, pending=count))

    def test_machine_json_rejects_duplicate_keys_and_excessive_nesting(self):
        self.assertTrue("machine_json" in self.api, "bounded machine JSON decoder missing")
        for payload in ('{"schema":1,"schema":2}', "[" * 2000 + "]" * 2000):
            with self.subTest(payload=payload[:50]), self.assertRaises(ValueError):
                self.api["machine_json"](payload)

    def test_bounded_subprocess_uses_neutral_cwd_and_preserves_environment(self):
        environment = {**os.environ, "MISE_MINIMUM_RELEASE_AGE": "9d"}
        output = self.api["run_bounded"]([sys.executable, "-c",
            "import os,json; print(json.dumps([os.getcwd(),os.environ.get('MISE_MINIMUM_RELEASE_AGE')]))"],
            cwd="/", env=environment, timeout=2)
        self.assertEqual(json.loads(output), ["/", "9d"])

    def test_unavailable_desktop_scan_preserves_cached_revision(self):
        from unittest.mock import patch
        with workspace() as folder, patch.dict(os.environ, XDG_STATE_HOME=str(Path(folder) / "state")):
            path = Path(folder) / "cache/update-center.json"
            good = self.api["ProviderResult"]("dwm-titus", pending=1, items=(
                self.api["ItemResult"]("update", "DWM-Titus", "a" * 40, "b" * 40, "b" * 40),))
            self.api["snapshot"](path, {"dwm-titus": lambda: good}, force=True, now=100)
            failed = self.api["ProviderResult"]("dwm-titus", "unavailable", error_code="missing-provider", detail="Missing helper")
            result = self.api["snapshot"](path, {"dwm-titus": lambda: failed}, force=True, now=101)[0]
            self.assertEqual((result.pending, result.freshness, result.error_code, result.last_success),
                             (1, "stale", "missing-provider", 100))


class MiseDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))

    def scan(self, outputs, executable="/usr/bin/mise"):
        from unittest.mock import patch
        self.assertTrue("scan_mise" in self.api, "Mise discovery is missing")
        function = self.api["scan_mise"]
        calls = []
        def run(argv, **options):
            calls.append(argv)
            self.assertEqual(options["cwd"], "/")
            self.assertLessEqual(options["timeout"], 120)
            self.assertEqual(options["env"].get("MISE_MINIMUM_RELEASE_AGE"), os.environ.get("MISE_MINIMUM_RELEASE_AGE"))
            return json.dumps(outputs[len(calls) - 1])
        with patch.dict(function.__globals__, optional_executable=lambda name: executable, run_bounded=run):
            result = function()
        return result, calls

    def test_installed_inventory_including_inactive_versions_defines_count(self):
        inventory = {"node": [{"version": "20.0.0", "installed": True, "active": False},
                              {"version": "22.0.0", "installed": True, "active": True}],
                     "python": [{"version": "3.13.0", "installed": True}]}
        result, calls = self.scan([inventory, {"node": {"current": "20.0.0", "latest": "20.1.0"}},
                                  {}, {"python": {"current": "3.13.0", "latest": "3.13.1"}}])
        self.assertEqual(calls, [["/usr/bin/mise", "ls", "--installed", "--json"],
                                 ["/usr/bin/mise", "outdated", "--json", "--", "node@20.0.0"],
                                 ["/usr/bin/mise", "outdated", "--json", "--", "node@22.0.0"],
                                 ["/usr/bin/mise", "outdated", "--json", "--", "python@3.13.0"]])
        self.assertEqual((result.managed, result.pending), (3, 2))
        self.assertEqual([(i.name, i.current, i.available) for i in result.items],
                         [("node", "20.0.0", "20.1.0"), ("python", "3.13.0", "3.13.1")])

    def test_cooldown_is_preserved_and_absent_is_not_forced(self):
        from unittest.mock import patch
        for configured in (None, "7d"):
            environment = dict(os.environ)
            environment.pop("MISE_MINIMUM_RELEASE_AGE", None)
            if configured is not None:
                environment["MISE_MINIMUM_RELEASE_AGE"] = configured
            with patch.dict(os.environ, environment, clear=True):
                self.assertEqual(self.scan([{}])[0].managed, 0)

    def test_absent_incompatible_and_foreign_outdated_tools_hide(self):
        self.assertEqual(self.scan([], executable=None), (None, []))
        for inventory in ([], {"node": "20"}, {"../bad": [{"version": "1", "installed": True}]}):
            with self.subTest(inventory=inventory):
                self.assertIsNone(self.scan([inventory])[0])
        self.assertIsNone(self.scan([{"node": [{"version": "20", "installed": True}]},
                                    {"python": {"current": "3", "latest": "4"}}])[0])


class FlatpakDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))

    def scan(self, outputs, executable="/usr/bin/flatpak"):
        from unittest.mock import patch
        self.assertTrue("scan_flatpak" in self.api, "Flatpak discovery is missing")
        function = self.api["scan_flatpak"]
        calls = []
        def run(argv, **options):
            calls.append(argv)
            self.assertLessEqual(options["timeout"], 180)
            return outputs[len(calls) - 1]
        with patch.dict(function.__globals__, optional_executable=lambda name: executable, run_bounded=run):
            result = function()
        return result, calls

    def test_scoped_inventory_and_updates_keep_duplicate_refs(self):
        ref = "org.example.App/x86_64/stable"
        result, calls = self.scan([
            ref + "\t1\n", ref + "\t2\n",
            "", "",
            ref + "\t1\n", ref + "\t3\n",
            "", "",
        ])
        self.assertEqual(calls, [
            ["/usr/bin/flatpak", "list", "--system", "--app", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "remote-ls", "--system", "--updates", "--app", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "list", "--system", "--runtime", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "remote-ls", "--system", "--updates", "--runtime", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "list", "--user", "--app", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "remote-ls", "--user", "--updates", "--app", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "list", "--user", "--runtime", "--columns=ref:full,version"],
            ["/usr/bin/flatpak", "remote-ls", "--user", "--updates", "--runtime", "--columns=ref:full,version"],
        ])
        self.assertEqual((result.pending, result.managed), (2, 2))
        self.assertEqual([(item.scope, item.current, item.available) for item in result.items],
                         [("system", "1", "2"), ("user", "1", "3")])
        self.assertEqual(result.items[0].url, "https://flathub.org/apps/org.example.App")

    def test_absent_and_incompatible_flatpak_hide_without_human_fallback(self):
        self.assertEqual(self.scan([], executable=None), (None, []))
        for text in ("Application ID Version Branch\n", "bad/x86_64/stable\t2\n", "a\tb\tc\n"):
            with self.subTest(text=text):
                result, calls = self.scan([text])
                self.assertIsNone(result)
                self.assertEqual(len(calls), 1)

    def test_runtime_has_no_fabricated_flathub_link_and_empty_versions_unknown(self):
        ref = "org.example.Platform/x86_64/stable"
        result, _ = self.scan([
            "", "",
            ref + "\t\n", ref + "\t\n",
            "", "",
            "", "",
        ])
        self.assertEqual((result.items[0].current, result.items[0].available, result.items[0].url),
                         ("unknown", "unknown", ""))


class DesktopDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.api = runpy.run_path(str(HELPER))

    def status(self, **changes):
        return dict(schema=1, state="available", installed="a" * 40,
                    available="b" * 40, canUpdate=True, detail="Update ready",
                    restart="none", **changes)

    def scan(self, records, helper="/usr/bin/dwm-desktop-update"):
        from unittest.mock import patch
        self.assertIn("scan_desktop", self.api, "desktop discovery is missing")
        function = self.api["scan_desktop"]
        calls = []
        def run(argv, **options):
            calls.append(argv)
            self.assertEqual(argv[0], helper)
            self.assertLessEqual(options["timeout"], 180)
            value = records[len(calls) - 1]
            if isinstance(value, Exception):
                raise value
            return json.dumps(value)
        with patch.dict(function.__globals__, trusted_desktop_helper=lambda: helper, run_bounded=run):
            result = function()
        return result, calls

    def test_desktop_revision_item_and_status_before_check(self):
        result, calls = self.scan([self.status(), self.status()])
        self.assertEqual(calls, [["/usr/bin/dwm-desktop-update", "status"],
                                 ["/usr/bin/dwm-desktop-update", "check"]])
        self.assertEqual((result.identifier, result.pending, result.managed, result.update_available),
                         ("dwm-titus", 1, 1, True))
        self.assertEqual((result.items[0].current, result.items[0].available), ("a" * 40, "b" * 40))

    def test_interrupted_and_restart_preserve_guidance_without_check(self):
        record = self.status()
        record.update(state="interrupted", canUpdate=False, detail="Restore retained backup", restart="session")
        result, calls = self.scan([record])
        self.assertEqual(len(calls), 1)
        self.assertFalse(result.update_available)
        self.assertEqual(result.error_code, "interrupted")
        self.assertIn("Restore retained backup", result.detail)
        self.assertIn("session", result.detail)
        self.assertEqual(result.restart, "session")
        self.assertIn("guidance\tdwm-titus\trestart\tsession\n", self.api["render_snapshot"]([result]))

    def test_malformed_revision_timeout_and_missing_helper(self):
        record = self.status()
        record["available"] = "bad revision"
        with self.assertRaises(ValueError):
            self.scan([record])
        with self.assertRaises(TimeoutError):
            self.scan([TimeoutError("expired")])
        result, calls = self.scan([], helper=None)
        self.assertEqual((result.status, result.error_code, calls), ("unavailable", "missing-provider", []))

    def test_malformed_status_types_cannot_crash_other_providers(self):
        for field, value in (("state", []), ("restart", {}), ("statusInvalid", "false")):
            record = self.status()
            record[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.scan([record])

    def test_active_updater_and_drift_keep_check_disabled_or_repair_available(self):
        record = self.status()
        record.update(state="building", canUpdate=True)
        result, calls = self.scan([record])
        self.assertEqual((result.error_code, result.update_available, len(calls)), ("busy", False, 1))
        record.update(state="drift", available="a" * 40)
        result, _ = self.scan([record, record])
        self.assertEqual((result.pending, result.update_available), (0, True))

    def test_rejects_user_owned_or_writable_installed_helper(self):
        self.assertTrue("trusted_desktop_helper" in self.api)
        from unittest.mock import patch
        from types import SimpleNamespace
        for uid, mode in ((1000, 0o100755), (0, 0o100777), (0, 0o120755)):
            with self.subTest(uid=uid, mode=mode), patch.object(Path, "lstat", return_value=SimpleNamespace(st_uid=uid, st_mode=mode)):
                self.assertIsNone(self.api["trusted_desktop_helper"]())

    def test_trusted_installed_absolute_path_only(self):
        self.assertIn("trusted_desktop_helper", self.api, "trusted installed helper resolution is missing")
        from unittest.mock import patch
        function = self.api["trusted_desktop_helper"]
        with workspace() as folder:
            checkout = Path(folder) / "dwm-desktop-update"
            checkout.write_text("#!/bin/sh\nexit 0\n")
            checkout.chmod(0o755)
            with patch.dict(os.environ, PATH=folder):
                chosen = function()
            self.assertNotEqual(chosen, str(checkout))
            if chosen:
                self.assertIn(chosen, ("/usr/bin/dwm-desktop-update", "/usr/local/bin/dwm-desktop-update"))
                self.assertEqual(Path(chosen).stat().st_uid, 0)


if __name__ == "__main__":
    unittest.main()
