#!/usr/bin/python3
"""Exercise both dependency buttons without running desktop installation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class DependencyLaunchers(unittest.TestCase):
    def test_buttons_use_package_repair_with_stale_or_missing_source_installer(self):
        with tempfile.TemporaryDirectory(prefix="dependency repair ") as temporary:
            base = Path(temporary)
            scripts = base / "legacy/scripts"
            scripts.mkdir(parents=True)
            for name in ("dwm-quickshell-controlcenter", "dwm-system-health", "check-deps.sh", "dwm-utils.sh", "dwm-packages.sh"):
                shutil.copy2(REPO / "scripts" / name, scripts / name)
            marker = base / "desktop-reinstalled"
            installer = scripts.parent / "install.sh"
            installer.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\nexit 97\n")
            installer.chmod(0o755)
            files = [scripts.parent / "Makefile", base / "dwm", base / "desktop-install.json", base / "status.json"]
            for path in files:
                path.write_text("original " + path.name)
            before = {p: p.read_bytes() for p in files}
            tools = base / "bin"
            tools.mkdir()
            log = base / "calls.jsonl"
            log.touch()
            terminal = tools / "dwm-terminal"
            terminal.write_text("#!/bin/sh\n[ \"$1\" = --print-command ] && { echo mock-term; exit 0; }\n[ \"$1\" = -e ] || exit 91\nshift\nexec \"$@\"\n")
            terminal.chmod(0o755)
            pkg = tools / "pkg-config"
            pkg.write_text("#!/bin/sh\nexit 1\n")
            pkg.chmod(0o755)
            updater = tools / "dwm-desktop-update"
            updater.write_text("#!/usr/bin/python3\nimport json,os,sys\n"
                               "assert sys.argv[1:] == ['install-dependencies'], sys.argv\n"
                               "with open(os.environ['REPAIR_CALLS'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n")
            updater.chmod(0o755)
            environment = {**os.environ, "PATH": str(tools) + ":/usr/bin:/bin", "HOME": str(base),
                           "DWM_TEST_SYNC": "1", "REPAIR_CALLS": str(log)}
            for source_exists in (True, False):
                if not source_exists:
                    installer.unlink()
                for name, args in (("dwm-quickshell-controlcenter", ["action", "dependency-check"]),
                                   ("dwm-system-health", ["repair-user", "install-dependencies"])):
                    with self.subTest(button=name, source_exists=source_exists):
                        marker.unlink(missing_ok=True)
                        result = subprocess.run([scripts / name, *args], input="y\n", env=environment,
                                                 capture_output=True, text=True, timeout=15)
                        self.assertFalse(marker.exists(), "Dependency button ran the full desktop installer")
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual({p: p.read_bytes() for p in files}, before)
            self.assertEqual([json.loads(line) for line in log.read_text().splitlines()],
                             [["install-dependencies"]] * 4)

    def test_buttons_fail_when_no_backing_terminal_is_available(self):
        with tempfile.TemporaryDirectory(prefix="dependency repair no term ") as temporary:
            base = Path(temporary)
            scripts = base / "legacy/scripts"
            scripts.mkdir(parents=True)
            for name in ("dwm-quickshell-controlcenter", "dwm-system-health", "check-deps.sh", "dwm-utils.sh", "dwm-packages.sh"):
                shutil.copy2(REPO / "scripts" / name, scripts / name)
            tools = base / "bin"
            tools.mkdir()
            terminal = tools / "dwm-terminal"
            terminal.write_text("#!/bin/sh\n[ \"$1\" = --print-command ] && exit 127\nexit 127\n")
            terminal.chmod(0o755)
            pkg = tools / "pkg-config"
            pkg.write_text("#!/bin/sh\nexit 1\n")
            pkg.chmod(0o755)
            environment = {**os.environ, "PATH": str(tools) + ":/usr/bin:/bin", "HOME": str(base), "DWM_TEST_SYNC": "1"}
            for name, args in (("dwm-quickshell-controlcenter", ["action", "dependency-check"]),
                               ("dwm-system-health", ["repair-user", "install-dependencies"])):
                with self.subTest(button=name):
                    result = subprocess.run([scripts / name, *args], env=environment,
                                             capture_output=True, text=True, timeout=15)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("launched", result.stdout)

    def test_button_resolves_sibling_checker_in_custom_prefix(self):
        with tempfile.TemporaryDirectory(prefix="dependency repair prefix ") as temporary:
            base = Path(temporary)
            installed_bin = base / "opt/dwm/bin"
            installed_bin.mkdir(parents=True)
            for name in ("dwm-quickshell-controlcenter", "check-deps.sh", "dwm-utils.sh"):
                shutil.copy2(REPO / "scripts" / name, installed_bin / name)
            tools = base / "bin"
            tools.mkdir()
            log = base / "dispatch.log"
            terminal = tools / "dwm-terminal"
            terminal.write_text("#!/bin/sh\n"
                                "[ \"$1\" = --print-command ] && { echo mock-term; exit 0; }\n"
                                "[ \"$1\" = -e ] || exit 91\n"
                                "shift\n"
                                "echo \"$@\" >> '" + str(log) + "'\n")
            terminal.chmod(0o755)
            environment = {**os.environ, "PATH": str(tools) + ":/usr/bin:/bin", "HOME": str(base), "DWM_TEST_SYNC": "1"}
            result = subprocess.run([installed_bin / "dwm-quickshell-controlcenter", "action", "dependency-check"],
                                    env=environment, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            dispatched = log.read_text().strip()
            expected_checker = str(installed_bin / "check-deps.sh")
            self.assertIn(expected_checker, dispatched)

    def test_buttons_fail_when_checker_is_unavailable(self):
        with tempfile.TemporaryDirectory(prefix="dependency repair no checker ") as temporary:
            base = Path(temporary)
            scripts = base / "legacy/scripts"
            scripts.mkdir(parents=True)
            for name in ("dwm-quickshell-controlcenter", "dwm-system-health", "dwm-utils.sh"):
                shutil.copy2(REPO / "scripts" / name, scripts / name)
            tools = base / "bin"
            tools.mkdir()
            terminal = tools / "dwm-terminal"
            terminal.write_text("#!/bin/sh\n[ \"$1\" = --print-command ] && { echo mock-term; exit 0; }\n[ \"$1\" = -e ] || exit 91\nshift\nexec \"$@\"\n")
            terminal.chmod(0o755)
            environment = {**os.environ, "PATH": str(tools) + ":/usr/bin:/bin", "HOME": str(base),
                           "DWM_CHECK_DEPS_SCRIPT": str(base / "missing-check-deps.sh")}
            environment.pop("DWM_TEST_SYNC", None)
            for name, args in (("dwm-quickshell-controlcenter", ["action", "dependency-check"]),
                               ("dwm-system-health", ["repair-user", "install-dependencies"])):
                with self.subTest(button=name):
                    result = subprocess.run([scripts / name, *args], env=environment,
                                             capture_output=True, text=True, timeout=15)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("launched", result.stdout)
                    if name == "dwm-quickshell-controlcenter":
                        self.assertIn("unavailable", result.stderr)


if __name__ == "__main__":
    unittest.main()
