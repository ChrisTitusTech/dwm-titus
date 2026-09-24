#!/usr/bin/python3
"""Exercise the installed helper with real DNF in an expendable Fedora container."""
import os
from pathlib import Path
import pty
import subprocess
import tempfile

assert os.geteuid() == 0 and Path("/.dockerenv").exists()
assert os.environ.get("DWM_DISPOSABLE_DNF_TEST") == "1"
repo = Path(__file__).resolve().parents[1]
helper = Path("/usr/local/libexec/dwm-titus/dwm-initial-update-root")
helper.parent.mkdir(parents=True, exist_ok=True)
helper.write_text((repo / "scripts/dwm-initial-update-root").read_text().replace("@PREFIX@", "/usr/local"))
helper.chmod(0o755)
state = Path("/var/lib/dwm-titus/initial-update")
state.mkdir(parents=True, exist_ok=True)
marker = state / "complete.json"
marker.unlink(missing_ok=True)
(state / "pending.json").write_text('{}\n')


def run(path=helper):
    master, slave = pty.openpty()
    try:
        result = subprocess.run([str(path), "run"], stdin=slave, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=240, text=True)
        print(result.stdout, flush=True)
        return result.returncode
    finally:
        os.close(master)
        os.close(slave)


with tempfile.TemporaryDirectory() as name:
    work = Path(name)
    packages = work / "packages"
    packages.mkdir()
    subprocess.run(["createrepo_c", str(packages)], check=True)
    repos = work / "repos"
    repos.mkdir()
    config = Path("/etc/dnf/dnf.conf")
    original = config.read_bytes()
    try:
        config.write_text("[main]\nreposdir=" + str(repos) + "\n")
        assert run(repo / "scripts/dwm-initial-update-root") != 0
        assert run() != 0 and not marker.exists(), "Disabled repositories cannot complete the update"
        fixture = repos / "fixture.repo"
        fixture.write_text("[fixture]\nname=Fixture\nenabled=1\npkg_gpgcheck=1\nbaseurl=" +
                           (work / "missing").as_uri() + "\n")
        assert run() != 0 and not marker.exists(), "Unavailable repository cannot complete the update"
        fixture.write_text(fixture.read_text().replace((work / "missing").as_uri(), packages.as_uri()))
        assert run() == 0 and marker.exists(), "Retry must complete an up-to-date transaction"
        before = marker.read_bytes()
        fixture.write_text(fixture.read_text().replace(packages.as_uri(), (work / "missing").as_uri()))
        assert run() == 0 and marker.read_bytes() == before, "Subsequent login must skip the transaction"
    finally:
        config.write_bytes(original)
print("PASS: installed root helper rejects repository copy, fails without completion, retries successfully, and skips later runs")
