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
                self.assertEqual(result.stderr, "usage: snapshot [--force] | rescan PROVIDER\n")
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


if __name__ == "__main__":
    unittest.main()
