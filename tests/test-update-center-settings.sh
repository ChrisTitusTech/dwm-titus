#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
python3 - "$repo" <<'PY'
import hashlib
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
helper = repo / "scripts/dwm-update-center-settings"
assert helper.is_file(), "FAIL: scripts/dwm-update-center-settings does not exist"

def tree():
    paths = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=repo).split(b"\0")
    return {p: (hashlib.sha256((repo / os.fsdecode(p)).read_bytes()).hexdigest(), (repo / os.fsdecode(p)).stat().st_mode)
            for p in paths if p and (repo / os.fsdecode(p)).is_file()}

before = tree()
with tempfile.TemporaryDirectory(prefix="update-center-settings-", dir=os.environ.get("TMPDIR") or str(Path.home() / "tmp")) as work:
    root = Path(work)
    home, config, runtime = [root / name for name in ("home", "config", "runtime")]
    for path in (home, config, runtime):
        path.mkdir(mode=0o700)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_RUNTIME_DIR=str(runtime))
    state = config / "dwm-titus/update-center.conf"

    def run(*args, error=None, environment=None):
        result = subprocess.run([str(helper), *args], env=environment or env, text=True, capture_output=True)
        if error is None:
            assert result.returncode == 0, (args, result.stderr)
            assert not result.stderr, result.stderr
        else:
            assert result.returncode == 1, (args, result.returncode)
            assert result.stderr == "dwm-update-center-settings: " + error + "\n", result.stderr
            assert not result.stdout, result.stdout
        return result.stdout

    def status(kind="defaults", seconds="3600", show="enabled", environment=None):
        output = run("status", environment=environment)
        lines = output.splitlines()
        assert lines[0] == "update-center-settings-protocol\t1\t0", output
        assert any(line.startswith("state\t" + kind + "\t") for line in lines), output
        assert "preference\trefreshSeconds\t" + seconds in lines, output
        assert "preference\talwaysShow\t" + show in lines, output
        assert lines[-1] == "complete\tstatus", output
        token = [line.split("\t")[1] for line in lines if line.startswith("baseline\t")]
        assert len(token) == 1 and token[0], output
        return token[0]

    baseline = status()
    assert not state.exists()
    for value in ("299", "21601", "abc", "1.5", "", "-300", "0300", "300\n"):
        run("set", value, "enabled", baseline, error="refreshSeconds must be an integer from 300 to 21600")
        assert not state.exists()
    run("set", "300", "true", baseline, error="alwaysShow must be enabled or disabled")
    run("set", "300", "enabled", error="usage: status | set REFRESH_SECONDS ALWAYS_SHOW BASELINE | reset BASELINE")
    run("set", "300", "enabled", baseline, "extra", error="usage: status | set REFRESH_SECONDS ALWAYS_SHOW BASELINE | reset BASELINE")
    for seconds in ("300", "21600"):
        output = run("set", seconds, "disabled", status("defaults" if not state.exists() else "available", "3600" if not state.exists() else "300", "enabled" if not state.exists() else "disabled"))
        assert output.startswith("update-center-settings-action-protocol\t1\t0\n")
        assert output.endswith("complete\tset\n")
        status("available", seconds, "disabled")
        assert state.stat().st_mode & 0o777 == 0o600
    saved = state.read_bytes()
    run("reset", baseline, error="preferences changed; refresh status before saving")
    assert state.read_bytes() == saved
    run("reset", status("available", "21600", "disabled"))
    status()
    assert not state.exists()

    header = "update-center-settings-protocol\t1\t0\n"
    malformed = [header + "refreshSeconds\t300\nalwaysShow\tenabled\nrefreshSeconds\t400\n",
                 header + "refreshSeconds\t300\nunknown\tenabled\n",
                 header + "refreshSeconds\t299\nalwaysShow\tenabled\n",
                 header + "refreshSeconds\t300\nalwaysShow\tenabled\textra\n",
                 header + "refreshSeconds\t300\n", "", header.replace("1\t0", "2\t0")]
    for content in malformed:
        state.write_text(content)
        state.chmod(0o600)
        token = status("partial")
        run("set", "300", "enabled", token, error="malformed persistent state; preserving file")
        run("reset", token, error="malformed persistent state; preserving file")
        assert state.read_text() == content
        state.unlink()

    for mode in (0o620, 0o602):
        state.write_text(header + "refreshSeconds\t300\nalwaysShow\tdisabled\n")
        state.chmod(mode)
        status("unavailable")
        run("reset", "absent", error="unsafe persistent state; preserving file")
        assert state.stat().st_mode & 0o777 == mode
        state.unlink()
    state.write_bytes(b"x" * 4097)
    state.chmod(0o600)
    status("unavailable")
    run("set", "300", "enabled", "absent", error="unsafe persistent state; preserving file")
    state.unlink()
    target = root / "external"
    target.write_text("external\n")
    state.symlink_to(target)
    status("unavailable")
    run("reset", "absent", error="unsafe persistent state; preserving file")
    assert target.read_text() == "external\n"
    state.unlink()
    os.link(target, state)
    status("unavailable")
    run("reset", "absent", error="unsafe persistent state; preserving file")
    state.unlink()
    config.chmod(0o777)
    status("unavailable")
    run("set", "300", "enabled", "absent", error="unsafe configuration directory")
    config.chmod(0o700)
    runtime.chmod(0o777)
    run("set", "300", "enabled", "absent", error="unsafe runtime directory")
    runtime.chmod(0o700)
    lock_path = runtime / "dwm-update-center-settings.lock"
    if lock_path.exists():
        lock_path.unlink()
    lock_path.symlink_to(target)
    run("set", "300", "enabled", "absent", error="unsafe runtime directory")
    assert target.read_text() == "external\n"
    lock_path.unlink()
    with lock_path.open("w") as held:
        lock_path.chmod(0o600)
        fcntl.flock(held, fcntl.LOCK_EX)
        run("set", "300", "enabled", "absent", error="another preferences operation is still running")
        assert not state.exists()
    managed = state.parent
    moved = config / "saved-dwm-titus"
    managed.rename(moved)
    managed.symlink_to(moved, target_is_directory=True)
    status("unavailable")
    run("set", "300", "enabled", "absent", error="unsafe configuration directory")
    managed.unlink()
    moved.rename(managed)

    # Inject failures at real stdlib boundaries without test hooks in production.
    injection = '''import os, runpy, sys
helper, mode, state = sys.argv[1:]
original = os.fsync
def fsync(fd):
    original(fd)
    if mode == "concurrent":
        with open(state, "w") as stream: stream.write("external edit\\n")
        os.chmod(state, 0o600)
    elif mode == "interrupt":
        raise KeyboardInterrupt
    elif mode == "io":
        raise OSError("injected stage sync failure")
os.fsync = fsync
sys.argv = [helper, "set", "300", "disabled", "absent"]
runpy.run_path(helper, run_name="__main__")
'''
    for mode in ("concurrent", "interrupt", "io"):
        result = subprocess.run([sys.executable, "-c", injection, str(helper), mode, str(state)], env=env, text=True, capture_output=True)
        assert result.returncode != 0, result.stdout
        stages = list(state.parent.glob(".update-center.*"))
        assert len(stages) == 1 and stages[0].stat().st_mode & 0o777 == 0o600, stages
        if mode == "concurrent":
            assert result.stderr == "dwm-update-center-settings: preferences changed during the transaction; staged preferences retained\n", result.stderr
            assert state.read_text() == "external edit\n"
            state.unlink()
        else:
            detail = "operation interrupted; staged preferences retained" if mode == "interrupt" else "I/O failure before preferences committed; staged preferences retained"
            assert result.stderr == "dwm-update-center-settings: " + detail + "\n", result.stderr
            assert not state.exists()
        stages[0].unlink()

    # A committed transaction cannot advertise a nonexistent recovery stage.
    committed_injection = '''import os, runpy, sys
helper, action, failure, baseline = sys.argv[1:]
original = os.fsync
calls = 0
def fsync(fd):
    global calls
    original(fd)
    calls += 1
    if calls == 2:
        if failure == "interrupt": raise KeyboardInterrupt
        raise OSError("injected directory sync failure")
os.fsync = fsync
sys.argv = [helper, "set", "300", "disabled", baseline] if action == "set" else [helper, "reset", baseline]
runpy.run_path(helper, run_name="__main__")
'''
    failures = []
    for action in ("set", "reset"):
        for failure in ("interrupt", "io"):
            if action == "reset":
                run("set", "300", "disabled", status())
                token = status("available", "300", "disabled")
            else:
                token = status()
            result = subprocess.run([sys.executable, "-c", committed_injection, str(helper), action, failure, token], env=env, text=True, capture_output=True)
            detail = "operation interrupted after preferences committed; refresh status" if failure == "interrupt" else "I/O failure after preferences committed; durability uncertain; refresh status"
            expected = "dwm-update-center-settings: " + detail + "\n"
            if result.returncode != 1 or result.stderr != expected or result.stdout:
                failures.append((action, failure, result.returncode, result.stderr, result.stdout))
            assert not list(state.parent.glob(".update-center.*")), "committed operation retained an unexpected stage"
            if action == "set":
                status("available", "300", "disabled")
                state.unlink()
            else:
                assert not state.exists()
                status()
    assert not failures, ("incorrect post-commit diagnostics", failures)

    # Wrong-owner metadata fixture: fake only fstat's owner, keep all I/O real.
    state.write_text(header + "refreshSeconds\t300\nalwaysShow\tdisabled\n")
    state.chmod(0o600)
    owner_fixture = '''import os, runpy, stat, sys
helper, action = sys.argv[1:]
original = os.fstat
def fstat(fd):
    info = original(fd)
    if stat.S_ISREG(info.st_mode) and info.st_size > 0:
        values = list(info); values[4] = info.st_uid + 1
        return os.stat_result(values)
    return info
os.fstat = fstat
sys.argv = [helper, "status"] if action == "status" else [helper, "reset", "absent"]
runpy.run_path(helper, run_name="__main__")
'''
    result = subprocess.run([sys.executable, "-c", owner_fixture, str(helper), "status"], env=env, text=True, capture_output=True)
    assert result.returncode == 0 and "state\tunavailable\t" in result.stdout, result
    result = subprocess.run([sys.executable, "-c", owner_fixture, str(helper), "reset"], env=env, text=True, capture_output=True)
    assert result.returncode == 1 and result.stderr == "dwm-update-center-settings: unsafe persistent state; preserving file\n", result
    assert state.read_text() == header + "refreshSeconds\t300\nalwaysShow\tdisabled\n"
    state.unlink()
    run("set", "300", "disabled", status())
    status("available", "300", "disabled")
    clean = root / "clean"
    clean.mkdir(mode=0o700)
    status(environment=dict(env, XDG_CONFIG_HOME=str(clean)))
    assert not (clean / "dwm-titus").exists()
assert tree() == before, "test suite mutated repository files"
print("PASS: update center preferences defaults, boundaries, path guards, transactions, isolation and repository immutability")
PY
