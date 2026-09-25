#!/usr/bin/env python3
"""Initial-update ordering, failure, mirror trust, and completion regressions."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


worker = load("initial_worker", ROOT / "scripts/dwm-initial-update-root")
client = load("initial_client", ROOT / "scripts/dwm-initial-update")


class InitialUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.state = self.work / "state"
        self.state.mkdir()

    def transaction(self, codes, arguments=()):
        commands = []

        def run(command, **_kwargs):
            commands.append(command)
            self.assertFalse((self.state / "complete.json").exists())
            value = codes[len(commands) - 1]
            if isinstance(value, Exception):
                raise value
            return subprocess.CompletedProcess(command, value)

        with patch.object(worker, "optimize", return_value=(list(arguments), [])):
            worker.update([{"id": "fixture"}], self.work, self.state, run)
        return commands

    def test_success_requires_repository_validation_then_confirmed_upgrade(self):
        commands = self.transaction([0, 0])
        self.assertEqual(commands[0][-2:], ["--refresh", "makecache"])
        self.assertEqual(commands[1][-1], "upgrade")
        self.assertIn("--setopt=assumeyes=False", commands[1])
        self.assertNotIn("--setopt=defaultyes=True", commands[1])
        self.assertIn("--setopt=*.skip_if_unavailable=False", commands[1])
        self.assertIn("--setopt=exit_on_lock=True", commands[1])
        self.assertGreater(json.loads((self.state / "complete.json").read_text())["completed_at"], 0)

    def test_unavailable_repositories_never_record_success(self):
        with self.assertRaises(RuntimeError):
            self.transaction([1])
        self.assertFalse((self.state / "complete.json").exists())

    def test_cancelled_or_failed_upgrade_is_retryable(self):
        with self.assertRaises(RuntimeError):
            self.transaction([0, 1])
        self.assertFalse((self.state / "complete.json").exists())
        self.transaction([0, 0])
        self.assertTrue((self.state / "complete.json").exists())

    def test_interrupted_preflight_is_not_completion(self):
        with self.assertRaises(RuntimeError):
            self.transaction([subprocess.TimeoutExpired("dnf", 180)])
        self.assertFalse((self.state / "complete.json").exists())

    def test_optimized_mirrors_fail_back_to_repository_defaults(self):
        selection = "--setopt=fedora.metalink=file:///run/private/mirrors"
        commands = self.transaction([1, 0, 0], [selection])
        self.assertIn(selection, commands[0])
        self.assertNotIn(selection, commands[1])
        self.assertNotIn(selection, commands[2])

    def test_optimized_mirror_timeout_also_falls_back(self):
        selection = "--setopt=fedora.metalink=file:///run/private/mirrors"
        commands = self.transaction([subprocess.TimeoutExpired("dnf", 180), 0, 0], [selection])
        self.assertIn(selection, commands[0])
        self.assertNotIn(selection, commands[1])
        self.assertNotIn(selection, commands[2])

    def test_offline_or_completed_images_do_not_offer(self):
        image = self.work / "image"
        complete = self.work / "complete"
        with patch.object(client, "PENDING", image), patch.object(client, "COMPLETE", complete):
            self.assertFalse(client.pending())
            image.touch()
            self.assertTrue(client.pending())
            complete.touch()
            self.assertFalse(client.pending())

    def test_writable_helper_cannot_be_elevated(self):
        helper = self.work / "writable-helper"
        helper.write_text("untrusted fixture")
        helper.chmod(0o666)
        with self.assertRaises(RuntimeError):
            client.trusted(helper)

    def test_authorization_denial_keeps_update_pending(self):
        with patch.object(client, "pending", return_value=True), patch.object(client, "trusted"), \
                patch.object(client.subprocess, "run", return_value=subprocess.CompletedProcess([], 126)) as run, \
                patch("builtins.input", return_value=""):
            self.assertEqual(client.terminal(), 126)
        self.assertEqual(run.call_args.args[0], ["/usr/bin/pkexec", str(client.HELPER), "run"])
        self.assertFalse((self.state / "complete.json").exists())

    def test_non_https_or_credential_urls_are_not_measured(self):
        for url in ["http://example.org/a", "https://user:secret@example.org/a", "file:///etc/passwd",
                    "https://example.org/a\nb", "https:///a"]:
            with self.subTest(url=url), patch.object(worker.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    worker.fetch(url, self.work, 10)
                run.assert_not_called()

    def test_budget_prevents_more_downloads(self):
        with patch.object(worker.time, "monotonic", return_value=100), patch.object(worker, "fetch") as fetch:
            arguments, reports = worker.optimize([{"id": "fedora"}], self.work, budget=0)
            self.assertEqual((arguments, reports), ([], []))
            fetch.assert_not_called()

    def test_checksum_mismatch_rejects_mirror(self):
        with patch.object(worker, "fetch", return_value=(b"different", {})):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                worker.measure_mirror("https://mirror.test/repodata/repomd.xml",
                                      {"sha256": "0" * 64}, self.work, 100)

    def test_primary_location_cannot_escape_repository(self):
        data = b'<repomd><data type="primary"><location href="https://evil.test/a"/></data></repomd>'
        with patch.object(worker, "fetch", return_value=(data, {})):
            with self.assertRaisesRegex(ValueError, "location"):
                worker.measure_mirror("https://mirror.test/repodata/repomd.xml", {}, self.work, 100)

    def test_throughput_order_preserves_metalink_verification_and_fallbacks(self):
        first, second = ["https://" + host + "/repodata/repomd.xml" for host in ("one.test", "two.test")]
        original = ET.fromstring('<metalink><files><file name="repomd.xml"><verification>'
                                 '<hash type="sha256">abcd</hash></verification><resources>'
                                 f'<url preference="100">{first}</url><url preference="99">{second}</url>'
                                 '</resources></file></files></metalink>')
        values = [{"url": first, "bytes_per_second": 1000, "transfer_bytes_per_second": 1000, "connect_seconds": .01, "bytes": 65536},
                  {"url": second, "bytes_per_second": 5000, "transfer_bytes_per_second": 5000, "connect_seconds": .2, "bytes": 65536}]
        with patch.object(worker, "mirror_document", return_value=("metalink", original, [first, second], {})), \
                patch.object(worker, "measure_mirror", side_effect=values):
            arguments, reports = worker.optimize([{"id": "fedora"}], self.work)
        self.assertIn("--setopt=fedora.fastestmirror=False", arguments)
        tree = ET.parse(self.work / "mirrors-0")
        self.assertEqual(tree.find(".//hash").text, "abcd")
        urls = {node.text: node.get("preference") for node in tree.findall(".//url")}
        self.assertEqual(urls, {first: "99", second: "100"})
        self.assertEqual(reports[0]["selected_bytes_per_second"], 5000)
        self.assertNotIn("two.test", json.dumps(reports))

    def test_mirror_ranking_includes_latency_and_noise_band(self):
        urls = ["https://" + host + "/repodata/repomd.xml" for host in ("one.test", "two.test")]
        # A faster payload rate alone cannot promote a slow-to-connect mirror.
        # Conversely, enough latency or throughput improvement can win.
        cases = [(1.0, 1.2, .01, .8, False),
                 (1.0, .95, .8, .01, True),
                 (1.0, 4.0, .01, .2, True),
                 (1.0, 1.05, .01, .01, False)]
        for first_rate, second_rate, first_connect, second_connect, selected in cases:
            values = [{"url": url, "bytes_per_second": rate * worker.LIMIT,
                       "transfer_bytes_per_second": rate * worker.LIMIT,
                       "connect_seconds": connect, "bytes": worker.LIMIT}
                      for url, rate, connect in zip(urls, (first_rate, second_rate),
                                                   (first_connect, second_connect))]
            with self.subTest(case=values), \
                    patch.object(worker, "mirror_document", return_value=("mirrorlist", "original", urls, {})), \
                    patch.object(worker, "measure_mirror", side_effect=values):
                arguments, _ = worker.optimize([{"id": "fixture"}], self.work)
            self.assertEqual(bool(arguments), selected)

    def test_measurement_separates_payload_duration_from_connection_time(self):
        metadata = b'<repomd><data type="primary"><location href="repodata/primary.xml"/></data></repomd>'
        metrics = {"size_download": 65536, "speed_download": 16384,
                   "time_connect": 1, "time_total": 4, "time_starttransfer": 2}
        with patch.object(worker, "fetch", side_effect=[(metadata, {}), (b"payload", metrics)]):
            result = worker.measure_mirror("https://one.test/repodata/repomd.xml", {}, self.work, 100)
        self.assertEqual(result["transfer_bytes_per_second"], 32768)
        self.assertEqual(worker.mirror_cost(result), 33)

    def test_failed_discovery_keeps_defaults(self):
        with patch.object(worker, "mirror_document", side_effect=ValueError("unavailable")):
            self.assertEqual(worker.optimize([{"id": "fedora"}], self.work), ([], []))

    def test_probe_tries_bounded_fallbacks_after_unavailable_first_mirror(self):
        urls = ["https://" + host + "/repodata/repomd.xml"
                for host in ("one.test", "two.test", "three.test", "four.test")]
        for kind in ("baseurl", "metalink"):
            repo = {"id": "fixture", "custom": False,
                    "baseurl": [url.removesuffix("/repodata/repomd.xml") for url in urls]}
            document = ("metalink", None, urls, {}) if kind == "metalink" else None
            with self.subTest(kind=kind), patch.object(worker, "repositories", return_value=[repo]), \
                    patch.object(worker, "mirror_document", return_value=document), \
                    patch.object(worker, "fetch", side_effect=[OSError("unreachable"),
                                                               (b"<repomd/>", {})]) as fetch:
                self.assertEqual(worker.probe(), 0)
                self.assertEqual([call.args[0] for call in fetch.call_args_list], urls[:2])
            with patch.object(worker, "repositories", return_value=[repo]), \
                    patch.object(worker, "mirror_document", return_value=document), \
                    patch.object(worker, "fetch", side_effect=OSError("unreachable")) as fetch, \
                    patch.object(worker, "native_probe", return_value=False):
                self.assertEqual(worker.probe(), 1)
                self.assertEqual(fetch.call_count, 3)

    def test_probe_deadline_stops_fallback_downloads(self):
        repo = {"id": "fixture", "custom": False, "baseurl": ["https://one.test"]}
        with patch.object(worker, "repositories", return_value=[repo]), \
                patch.object(worker, "mirror_document", return_value=None), \
                patch.object(worker.time, "monotonic", side_effect=[0, 46]), \
                patch.object(worker, "fetch") as fetch:
            self.assertEqual(worker.probe(), 1)
        fetch.assert_not_called()

    def test_failed_https_mirrors_or_discovery_try_native_fallback(self):
        repo = {"id": "fixture", "custom": False, "mirrorlist": "https://intranet.test/list"}
        document = ("mirrorlist", "https://down.test\nhttp://working.test\n",
                    ["https://down.test/repodata/repomd.xml"], {})
        for discovery in (document, OSError("discovery failed")):
            with self.subTest(discovery=discovery), patch.object(worker, "repositories", return_value=[repo]), \
                    patch.object(worker, "mirror_document") as mirrors, \
                    patch.object(worker, "fetch", side_effect=OSError("unreachable")), \
                    patch.object(worker, "native_probe", return_value=True) as native:
                if isinstance(discovery, Exception):
                    mirrors.side_effect = discovery
                else:
                    mirrors.return_value = discovery
                self.assertEqual(worker.probe(), 0)
                native.assert_called_once()

    def test_stalled_repository_reserves_time_for_next_repository(self):
        repos = [{"id": name, "custom": True} for name in ("offline", "reachable")]
        clock = [0]
        deadlines = []

        def native(repo, _directory, deadline):
            deadlines.append(deadline)
            if repo["id"] == "offline":
                clock[0] = deadline
                raise subprocess.TimeoutExpired("dnf", deadline)
            return True

        with patch.object(worker, "repositories", return_value=repos), \
                patch.object(worker.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(worker, "native_probe", side_effect=native):
            self.assertEqual(worker.probe(), 0)
        self.assertEqual(deadlines, [22.5, 45])

    def test_non_https_repositories_use_native_connectivity_without_measurement(self):
        repos = [{"id": "fixture", "custom": False, "baseurl": ["http://intranet.test/repo"]},
                 {"id": "fixture", "custom": False, "baseurl": ["file:///srv/repo"]},
                 {"id": "fixture", "custom": False, "mirrorlist": "http://intranet.test/list"}]
        for repo in repos:
            with self.subTest(repo=repo), patch.object(worker, "repositories", return_value=[repo]), \
                    patch.object(worker, "native_probe", return_value=True) as native, \
                    patch.object(worker, "mirror_document") as mirrors:
                self.assertEqual(worker.probe(), 0)
                self.assertEqual(native.call_args.args[0], repo)
                mirrors.assert_not_called()

    def test_https_list_with_only_ineligible_mirrors_uses_native_probe(self):
        repo = {"id": "fixture", "custom": False, "mirrorlist": "https://intranet.test/list"}
        with patch.object(worker, "repositories", return_value=[repo]), \
                patch.object(worker, "mirror_document", return_value=("mirrorlist", "http://mirror.test", [], {})), \
                patch.object(worker, "native_probe", return_value=True) as native:
            self.assertEqual(worker.probe(), 0)
        native.assert_called_once()

    def test_proxy_metalink_connectivity_uses_dnf_transport(self):
        repo = {"id": "fedora", "custom": True, "metalink": "https://repository.test/metalink",
                "mirrorlist": "", "baseurl": []}
        with patch.object(worker, "repositories", return_value=[repo]), \
                patch.object(worker, "native_probe", return_value=True) as native, \
                patch.object(worker, "mirror_document") as mirrors:
            self.assertEqual(worker.probe(), 0)
        self.assertEqual(native.call_args.args[0], repo)
        mirrors.assert_not_called()

    def test_proxy_probe_failure_and_timeout_remain_offline(self):
        repo = {"id": "fedora", "custom": True}
        for result in [False, subprocess.TimeoutExpired("dnf", 45)]:
            with self.subTest(result=result), patch.object(worker, "repositories", return_value=[repo]), \
                    patch.object(worker, "native_probe") as native:
                if isinstance(result, Exception):
                    native.side_effect = result
                else:
                    native.return_value = result
                self.assertEqual(worker.probe(), 1)

    def test_no_repositories_cannot_complete_initial_update(self):
        with patch.object(worker, "optimize") as optimize, self.assertRaises(RuntimeError):
            worker.update([], self.work, self.state)
        optimize.assert_not_called()
        self.assertFalse((self.state / "complete.json").exists())

    def test_supported_metalink_parser_ignores_untrusted_transports(self):
        data = ('<metalink xmlns="http://www.metalinker.org/"><files><file name="repomd.xml">'
                '<verification><hash type="sha256">abcd</hash></verification><resources>'
                '<url>http://plain.test/repodata/repomd.xml</url>'
                '<url>https://secure.test/repodata/repomd.xml</url></resources>'
                '</file></files></metalink>').encode()
        repo = {"metalink": "https://source.test/", "mirrorlist": "", "custom": False}
        with patch.object(worker, "fetch", return_value=(data, {})):
            kind, _, urls, hashes = worker.mirror_document(repo, self.work, 100)
        self.assertEqual(kind, "metalink")
        self.assertEqual(urls, ["https://secure.test/repodata/repomd.xml"])
        self.assertEqual(hashes, {"sha256": "abcd"})
        # librepo rejects generated ns0 prefixes even though they are valid XML.
        self.assertNotIn(b"ns0:", ET.tostring(_))


if __name__ == "__main__":
    unittest.main()
