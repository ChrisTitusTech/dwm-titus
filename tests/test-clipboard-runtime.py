#!/usr/bin/env python3
"""Exercise actual QML privacy gating, filtered process events, and disk consent."""
import json
import os
from pathlib import Path
import shutil
import subprocess
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
            capture:model.captureEnabled, backend:model.backendReady, backendFailed:model.backendFailed,
            confirmed:model.confirmedPersistence, enabled:model.persistenceEnabled,
            writing:model.settingsWriting, failed:model.settingsSaveFailed,
            wipe:model.wipePending, historyFailed:model.saveFailed, count:model.entries.length}); }
        function capture(enabled: bool): void { model.setCapture(enabled); }
        function persist(enabled: bool): void { model.setPersistence(enabled); }
        function retry(): void { model.retrySave(); }
        function clear(): void { model.clearAll(); }
    }
}
'''
tmp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT', str(Path.home() / 'tmp')))
tmp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='clipboard-privacy-', dir=tmp_root) as directory:
    work = Path(directory)
    home = work / 'home'
    home.mkdir()
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700)
    shell = work / 'shell'
    shutil.copytree(root / 'config/quickshell', shell)
    (shell / 'shell.qml').write_text(qml)
    tools = work / 'custom prefix $literal `literal`' / 'bin'
    tools.mkdir(parents=True)
    fifo = work / 'events'
    os.mkfifo(fifo)
    pipe = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
    mock = tools / 'dwm-clipboard-observer'
    mock.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                    'print(json.dumps({"event":"ready","protocol":1}),flush=True)\n'
                    'with open(os.environ["CLIPBOARD_TEST_EVENTS"]) as f:\n'
                    ' for line in f:\n'
                    '  if line.strip()=="CRASH": sys.exit(1)\n'
                    '  if line.strip()=="OVERSIZE": print("x"*393301,flush=True); continue\n'
                    '  print(line.rstrip("\\n"),flush=True)\n')
    mock.chmod(0o755)
    config = home / '.config/dwm-titus'
    cache = home / '.cache/dwm-titus'
    config.mkdir(parents=True)
    cache.mkdir(parents=True)
    settings = config / 'clipboard-settings.json'
    history = cache / 'clipboard-history-v2.json'
    legacy = cache / 'clipboard-history.json'
    settings.write_text(json.dumps({'persistenceEnabled': True}))
    legacy.write_text('{"entries":[{"text":"LEGACY SECRET NEVER IMPORT"}]}')
    legacy.chmod(0o000)
    display_file = (work / 'display').open('w+')
    log = (work / 'shell.log').open('w+')
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(display_file.fileno()), '-screen', '0',
                             '1024x768x24', '-nolisten', 'tcp'], pass_fds=[display_file.fileno()],
                            stdout=log, stderr=subprocess.STDOUT)
    process = None
    try:
        for _ in range(100):
            display_file.seek(0)
            number = display_file.read().strip()
            if number:
                break
            time.sleep(.05)
        assert number, 'Xvfb unavailable'
        env = {**os.environ, 'HOME': str(home), 'DISPLAY': ':' + number,
               'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(home / '.config'),
               'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_DATA_HOME': str(home / '.local/share'),
               'PATH': str(tools) + ':' + os.environ['PATH'], 'CLIPBOARD_TEST_EVENTS': str(fifo),
               'QT_QPA_PLATFORMTHEME': ''}
        def launch():
            return subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                    env=env, stdout=log, stderr=subprocess.STDOUT)
        process = launch()
        def ipc(*args):
            result = subprocess.run(['quickshell', 'ipc', '--path', str(shell / 'shell.qml'),
                                     'call', 'clipboardtest', *args], env=env,
                                    capture_output=True, text=True, timeout=5)
            assert result.returncode == 0, result.stderr
            return result.stdout
        def wait(predicate):
            last = None
            for _ in range(100):
                try:
                    last = json.loads(ipc('state'))
                    if predicate(last): return last
                except (AssertionError, json.JSONDecodeError):
                    pass
                time.sleep(.05)
            raise AssertionError(last)
        def emit(value):
            os.write(pipe, (json.dumps(value, ensure_ascii=True) + '\n').encode())
        wait(lambda s: s['ready'])
        assert not json.loads(ipc('state'))['capture']
        assert json.loads(ipc('state'))['count'] == 0 and legacy.exists()
        assert not history.exists(), 'legacy history read or rewritten before consent'
        if os.geteuid() != 0:
            config.chmod(0o500)
            ipc('capture', 'true')
            wait(lambda s: s['failed'] and not s['writing'])
            assert not json.loads(ipc('state'))['capture'], 'enabled before settings write confirmed'
            config.chmod(0o700)
        ipc('capture', 'true')
        wait(lambda s: s['capture'] and s['backend'])
        assert not legacy.exists(), 'consent did not discard older history'
        assert json.loads(settings.read_text()) == {'privacyVersion': 2, 'captureEnabled': True, 'persistenceEnabled': False}, settings.read_text()
        emit({'event': 'text', 'text': 'filtered editor text λ\nsecond'})
        wait(lambda s: s['count'] == 1)
        assert not json.loads(history.read_text())['entries'], 'persisted before separate opt-in'
        ipc('persist', 'true')
        wait(lambda s: s['confirmed'] and not s['writing'])
        for _ in range(100):
            if json.loads(history.read_text())['entries']: break
            time.sleep(.05)
        assert json.loads(history.read_text())['privacyVersion'] == 2
        assert json.loads(history.read_text())['entries'][0]['text'].startswith('filtered editor')
        assert history.stat().st_mode & 0o777 == 0o600
        if os.geteuid() != 0:
            cache.chmod(0o500)
            emit({'event': 'text', 'text': 'retry filtered entry'})
            wait(lambda s: s['historyFailed'])
            cache.chmod(0o700)
            ipc('retry')
            wait(lambda s: not s['historyFailed'])
        ipc('clear')
        wait(lambda s: s['backend'] and s['capture'] and s['count'] == 0)
        assert not json.loads(history.read_text())['entries']
        emit({'event': 'text', 'text': 'post-clear'})
        wait(lambda s: s['count'] == 1)
        ipc('capture', 'false')
        wait(lambda s: not s['capture'] and s['count'] == 0 and not s['wipe'])
        assert not json.loads(history.read_text())['entries']
        ipc('capture', 'true')
        wait(lambda s: s['backend'] and s['capture'])
        emit({'event': 'text', 'text': 'bad schema', 'extra': True})
        wait(lambda s: s['backendFailed'] and not s['capture'])
        assert json.loads(ipc('state'))['count'] == 0
        ipc('capture', 'true')
        wait(lambda s: s['backend'] and s['capture'])
        os.write(pipe, b'CRASH\n')
        wait(lambda s: s['backendFailed'] and not s['capture'])
        time.sleep(.2)
        assert not json.loads(ipc('state'))['capture'], 'backend crash retried automatically'
        ipc('capture', 'true')
        wait(lambda s: s['backend'] and s['capture'])
        os.write(pipe, b'OVERSIZE\n')
        wait(lambda s: s['backendFailed'] and not s['capture'])
        if os.geteuid() != 0:
            # Both unreadable files must fail closed; explicit Clear still wins.
            process.terminate()
            process.wait(timeout=10)
            settings.chmod(0o000)
            history.chmod(0o000)
            legacy.write_text('{"entries":[{"text":"old secret"}]}')
            process = launch()
            wait(lambda s: s['ready'] and s['failed'])
            assert not json.loads(ipc('state'))['capture']
            assert json.loads(ipc('state'))['count'] == 0
            ipc('clear')
            for _ in range(100):
                if not legacy.exists() and history.stat().st_mode & 0o777 == 0o600: break
                time.sleep(.05)
            assert not legacy.exists()
            assert not json.loads(history.read_text())['entries']
            settings.chmod(0o600)
            ipc('retry')
            wait(lambda s: s['ready'] and not s['failed'])
            assert not json.loads(ipc('state'))['capture'], 'retry silently bypassed explicit capture action'
        print('Actual QML privacy consent, filtered events, separate persistence, clear/disable, denial retry and backend failures: PASS')
    finally:
        config.chmod(0o700)
        cache.chmod(0o700)
        if process:
            process.terminate()
            process.wait(timeout=10)
        xvfb.terminate()
        xvfb.wait(timeout=10)
        os.close(pipe)
        display_file.close()
        log.flush()
        if process and process.returncode not in (0, -15):
            log.seek(0)
            print(log.read())
        log.close()
