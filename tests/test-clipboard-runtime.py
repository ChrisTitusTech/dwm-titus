#!/usr/bin/env python3
"""Test actual clipboard model persistence, denial, and deferred opt-out in Xvfb."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.clipboard
ShellRoot {
    ClipboardModel { id: model }
    IpcHandler {
        target: "clipboardtest"
        function state(): string { return JSON.stringify({ready:model.historyReady && model.settingsReady,
            confirmed:model.confirmedPersistence, enabled:model.persistenceEnabled,
            writing:model.settingsWriting, failed:model.settingsSaveFailed,
            wipe:model.wipePending, historyFailed:model.saveFailed, count:model.entries.length}); }
        function capture(text: string): void { model.capture(text); }
        function persist(enabled: bool): void { model.setPersistence(enabled); }
        function retry(): void { model.retrySave(); }
        function clear(): void { model.clearAll(); }
        function deferHistory(): void { model.historyReady = false; }
        function finishHistory(): void { model.loadHistory(); }
    }
}
'''
tmp_root = Path(os.environ.get("DWM_TEST_TMP_ROOT", str(Path.home() / "tmp")))
tmp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="clipboard-runtime-") as directory, \
        tempfile.TemporaryDirectory(prefix="cb.", dir=tmp_root) as runtime_directory:
    work = Path(directory)
    home = work / 'home'
    home.mkdir()
    runtime = Path(runtime_directory)
    shell = work / 'shell'
    shutil.copytree(root / 'config/quickshell', shell)
    (shell / 'shell.qml').write_text(qml)
    display_file = (work / 'display').open('w+')
    xvfb_log = (work / 'xvfb.log').open('w+')
    shell_log = (work / 'quickshell.log').open('w+')
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(display_file.fileno()), '-screen', '0',
                             '1024x768x24', '-nolisten', 'tcp'], pass_fds=[display_file.fileno()],
                            stdout=xvfb_log, stderr=subprocess.STDOUT)
    process = None
    config = home / '.config/dwm-titus'
    try:
        for _ in range(100):
            display_file.seek(0)
            number = display_file.read().strip()
            if number:
                break
            time.sleep(.05)
        assert number, 'Xvfb did not start'
        env = dict(os.environ, HOME=str(home), DISPLAY=':' + number, XDG_RUNTIME_DIR=str(runtime),
                   XDG_CONFIG_HOME=str(home / '.config'), XDG_CACHE_HOME=str(home / '.cache'),
                   XDG_DATA_HOME=str(home / '.local/share'), QT_QPA_PLATFORMTHEME='')
        # Exercise the actual Xlib modifier-map path on this private X server.
        probe = subprocess.run([sys.executable, '-c',
            'import json,runpy,sys; print(json.dumps(runpy.run_path(sys.argv[1])["numlock_masks"]()))',
            str(root / 'scripts/dwm-migrate-clipboard-surface')], env=env, capture_output=True,
            text=True, timeout=5, check=True)
        masks = json.loads(probe.stdout)
        assert len(masks) == 1 and 0 <= masks[0] <= 255, masks
        process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                   env=env, stdout=shell_log, stderr=subprocess.STDOUT)
        def ipc(*args):
            return subprocess.run(['quickshell', 'ipc', '--path', str(shell / 'shell.qml'),
                                   'call', 'clipboardtest', *args], env=env, capture_output=True,
                                  text=True, timeout=5)
        def wait_state(predicate):
            last = None
            for _ in range(100):
                response = ipc('state')
                if response.returncode == 0:
                    last = json.loads(response.stdout)
                    if predicate(last):
                        return last
                time.sleep(.05)
            raise AssertionError(last)
        def action(*args):
            result = ipc(*args)
            assert result.returncode == 0, result.stderr
        wait_state(lambda state: state['ready'])
        history = home / '.cache/dwm-titus/clipboard-history.json'
        settings = config / 'clipboard-settings.json'
        action('capture', 'session only')
        assert not history.exists(), 'persisted without opt-in'
        # Missing settings in a read-only directory must not reload/write forever.
        if os.geteuid() != 0:
            config.chmod(0o500)
            action('persist', 'true')
            wait_state(lambda state: state['ready'] and state['failed'] and not state['writing'])
            assert not settings.exists() and not history.exists()
            before = Path(f'/proc/{process.pid}/stat').read_text().split()
            time.sleep(.4)
            after = Path(f'/proc/{process.pid}/stat').read_text().split()
            assert int(after[13]) + int(after[14]) - int(before[13]) - int(before[14]) < 10
            config.chmod(0o700)
        else:
            print('Unwritable-directory case requires an unprivileged user; skipped as root')
        action('persist', 'true')
        wait_state(lambda state: state['confirmed'] and not state['writing'])
        for _ in range(100):
            if history.exists() and history.stat().st_mode & 0o777 == 0o600:
                break
            time.sleep(.05)
        assert history.stat().st_mode & 0o777 == 0o600
        assert history.parent.stat().st_mode & 0o777 == 0o700
        assert json.loads(history.read_text())['entries'][0]['text'] == 'session only'
        if os.geteuid() != 0:
            history.parent.chmod(0o500)
            action('capture', 'retry retained entry')
            wait_state(lambda state: state['historyFailed'])
            history.parent.chmod(0o700)
            action('retry')
            wait_state(lambda state: not state['historyFailed'])
            assert json.loads(history.read_text())['entries'][0]['text'] == 'retry retained entry'
            history.parent.chmod(0o500)
            action('persist', 'false')
            wait_state(lambda state: not state['confirmed'] and state['historyFailed'] and state['wipe'])
            history.parent.chmod(0o700)
            action('retry')
            wait_state(lambda state: not state['historyFailed'] and not state['wipe'])
            assert not json.loads(history.read_text())['entries']
            action('persist', 'true')
            wait_state(lambda state: state['confirmed'] and not state['writing'])
        action('deferHistory')
        action('persist', 'false')
        wait_state(lambda state: not state['confirmed'] and not state['writing'] and state['wipe'])
        action('finishHistory')
        wait_state(lambda state: state['ready'] and not state['wipe'])
        for _ in range(100):
            if not json.loads(history.read_text())['entries']:
                break
            time.sleep(.05)
        assert not json.loads(history.read_text())['entries'], 'deferred wipe was lost'
        assert json.loads(settings.read_text())['persistenceEnabled'] is False
        process.terminate()
        process.wait(timeout=5)
        history.write_text(json.dumps({'entries': [{'text': 'leftover private text', 'timestamp': 1}]}))
        process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                   env=env, stdout=shell_log, stderr=subprocess.STDOUT)
        wait_state(lambda state: state['ready'] and not state['wipe'])
        for _ in range(100):
            if not json.loads(history.read_text())['entries']:
                break
            time.sleep(.05)
        assert not json.loads(history.read_text())['entries'], 'restart retained opted-out history'
        if os.geteuid() != 0:
            process.terminate()
            process.wait(timeout=5)
            settings.write_text(json.dumps({'persistenceEnabled': True}))
            history.write_text(json.dumps({'entries': [{'text': 'retained on disk', 'timestamp': 1}]}))
            settings.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['failed'])
            action('capture', 'memory despite unreadable settings')
            wait_state(lambda state: state['count'] == 1)
            assert json.loads(history.read_text())['entries'][0]['text'] == 'retained on disk'
            settings.chmod(0o600)
            action('retry')
            wait_state(lambda state: state['confirmed'] and not state['failed'] and state['count'] == 2)
            process.terminate()
            process.wait(timeout=5)
            settings.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['failed'])
            action('capture', 'session retained after removing damaged settings')
            settings.unlink()
            action('retry')
            wait_state(lambda state: state['ready'] and not state['failed'] and state['count'] == 1)
            action('persist', 'true')
            wait_state(lambda state: state['confirmed'])
            process.terminate()
            process.wait(timeout=5)
            history.write_text(json.dumps({'entries': [{'text': 'unreadable stored history', 'timestamp': 1}]}))
            history.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['historyFailed'])
            action('capture', 'memory while history unreadable')
            wait_state(lambda state: state['count'] == 1)
            assert history.stat().st_mode & 0o777 == 0, 'unreadable history was replaced'
            history.chmod(0o600)
            assert json.loads(history.read_text())['entries'][0]['text'] == 'unreadable stored history'
            action('retry')
            wait_state(lambda state: not state['historyFailed'] and state['count'] == 2)
            process.terminate()
            process.wait(timeout=5)
            history.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['historyFailed'])
            action('clear')
            history.chmod(0o600)
            action('retry')
            wait_state(lambda state: not state['historyFailed'] and state['count'] == 0)
            for _ in range(100):
                if not json.loads(history.read_text())['entries']:
                    break
                time.sleep(.05)
            assert not json.loads(history.read_text())['entries'], 'Clear intent lost after history reload'
            process.terminate()
            process.wait(timeout=5)
            history.write_text(json.dumps({'entries': [{'text': 'old settings-gated history', 'timestamp': 1}]}))
            settings.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['failed'])
            action('capture', 'session before clear with unreadable settings')
            action('clear')
            settings.chmod(0o600)
            action('retry')
            wait_state(lambda state: not state['failed'] and state['count'] == 0)
            for _ in range(100):
                if not json.loads(history.read_text())['entries']:
                    break
                time.sleep(.05)
            assert not json.loads(history.read_text())['entries'], 'Clear intent lost after settings reload'
            process.terminate()
            process.wait(timeout=5)
            settings.write_text(json.dumps({'persistenceEnabled': True}))
            history.write_text(json.dumps({'entries': [{'text': 'both files unreadable', 'timestamp': 1}]}))
            settings.chmod(0)
            history.chmod(0)
            process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                       env=env, stdout=shell_log, stderr=subprocess.STDOUT)
            wait_state(lambda state: state['ready'] and state['historyFailed'] and state['failed'])
            history.chmod(0o600)
            action('retry')
            time.sleep(.2)
            assert json.loads(history.read_text())['entries'][0]['text'] == 'both files unreadable'
            settings.chmod(0o600)
            action('retry')
            wait_state(lambda state: not state['historyFailed'] and not state['failed'] and state['count'] == 1)
            assert json.loads(history.read_text())['entries'][0]['text'] == 'both files unreadable'
        action('deferHistory')
        action('capture', 'queued before Clear')
        action('clear')
        action('finishHistory')
        wait_state(lambda state: state['ready'] and state['count'] == 0)
        print('Clipboard opt-in, private storage, failure recovery, idle and restarted opt-out: PASS')
    except BaseException:
        shell_log.flush()
        print((work / 'quickshell.log').read_text())
        raise
    finally:
        if config.exists():
            config.chmod(0o700)
        for child in [process, xvfb]:
            if child:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        for file in [display_file, xvfb_log, shell_log]:
            file.close()
