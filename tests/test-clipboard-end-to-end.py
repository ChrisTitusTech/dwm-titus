#!/usr/bin/env python3
"""Run the production X11 observer through the actual QML model and storage."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
tmp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT', str(Path.home() / 'tmp')))
tmp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='clipboard-e2e-', dir=tmp_root) as directory:
    work = Path(directory)
    home = work / 'home'
    home.mkdir()
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700)
    tools = work / 'prefix $literal `literal`' / 'bin'
    tools.mkdir(parents=True)
    shutil.copy2(repo / 'dwm-clipboard-observer', tools / 'dwm-clipboard-observer')
    owner = tools / 'firefox'
    subprocess.run(['cc', '-D_POSIX_C_SOURCE=200809L', '-std=c99', '-Wall', '-Wextra', '-Werror',
                    repo / 'tests/clipboard-owner.c', '-lxcb', '-o', owner], check=True)
    for name in ('alacritty', 'bitwarden'):
        shutil.copy2(owner, tools / name)
    shell = work / 'shell'
    shutil.copytree(repo / 'config/quickshell', shell)
    (shell / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.clipboard
ShellRoot {
    ClipboardModel { id: model }
    LazyLoader { active: model.visible; ClipboardWindow { clipboardModel: model } }
    IpcHandler {
        target: "clipboardtest"
        function state(): string { return JSON.stringify({ready:model.settingsReady && model.historyReady,
            capture:model.captureEnabled, backend:model.backendReady, writing:model.settingsWriting,
            count:model.entries.length, texts:model.entries.map(e => e.text), wipe:model.wipePending,
            persist:model.confirmedPersistence}); }
        function capture(value: bool): void { model.setCapture(value); }
        function persist(value: bool): void { model.setPersistence(value); }
        function clear(): void { model.clearAll(); }
        function open(): void { model.open(); }
        function close(): void { model.close(); }
    }
}
''')
    display_file = (work / 'display').open('w+')
    log = (work / 'runtime.log').open('w+')
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(display_file.fileno()), '-screen', '0',
                             '800x600x24', '-nolisten', 'tcp'], pass_fds=[display_file.fileno()],
                            stdout=log, stderr=subprocess.STDOUT)
    processes = []
    try:
        for _ in range(100):
            display_file.seek(0)
            display = display_file.read().strip()
            if display: break
            time.sleep(.05)
        assert display, 'Xvfb unavailable'
        env = {**os.environ, 'HOME': str(home), 'DISPLAY': ':' + display,
               'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(home / '.config'),
               'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_DATA_HOME': str(home / '.local/share'),
               'PATH': str(tools) + ':' + os.environ['PATH'], 'QT_QPA_PLATFORMTHEME': ''}
        process = subprocess.Popen(['quickshell', '--no-duplicate', '--path', shell / 'shell.qml'],
                                   env=env, stdout=log, stderr=subprocess.STDOUT)
        processes.append(process)
        def ipc(*arguments):
            response = subprocess.run(['quickshell', 'ipc', '--path', shell / 'shell.qml', 'call',
                                       'clipboardtest', *arguments], env=env, capture_output=True,
                                      text=True, timeout=5)
            assert response.returncode == 0, response.stderr
            return response.stdout
        def wait(predicate):
            last = None
            for _ in range(100):
                try:
                    last = json.loads(ipc('state'))
                    if predicate(last): return last
                except (AssertionError, json.JSONDecodeError): pass
                time.sleep(.05)
            raise AssertionError(last)
        history = home / '.cache/dwm-titus/clipboard-history-v2.json'
        def stored():
            return json.loads(history.read_text())['entries']
        def copy(application, mode, text):
            requests = work / ('requests-' + str(len(processes)))
            client = subprocess.Popen([tools / application, mode, text, requests], env=env,
                                      stdout=subprocess.PIPE, stderr=log, text=True)
            processes.append(client)
            with selectors.DefaultSelector() as selector:
                selector.register(client.stdout, selectors.EVENT_READ)
                assert selector.select(3), 'Selection fixture failed to start'
                assert client.stdout.readline().strip() == 'ready'
            return requests
        wait(lambda s: s['ready'])
        ipc('open')
        for _ in range(100):
            windows = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^dwm clipboard$'],
                                     env=env, capture_output=True, text=True)
            if windows.returncode == 0: break
            time.sleep(.05)
        assert windows.returncode == 0, 'Clipboard surface did not open'
        time.sleep(.2)
        identity = subprocess.check_output(['xprop', '-id', windows.stdout.splitlines()[0], 'WM_CLASS'],
                                           env=env, text=True).strip()
        print('Clipboard window identity: ' + identity, flush=True)
        assert 'not found.' in identity, 'Update migration identity selectors for the new runtime WM_CLASS'
        evidence = os.environ.get('DWM_CLIPBOARD_EVIDENCE_DIR')
        if evidence:
            destination = Path(evidence)
            destination.mkdir(parents=True, exist_ok=True)
            subprocess.run(['maim', '-i', windows.stdout.splitlines()[0], destination / 'clipboard-opt-in.png'],
                           env=env, check=True, timeout=10)
            (destination / 'clipboard-opt-in.xprop').write_text(identity + '\n')

        ipc('close')
        time.sleep(.1)
        assert not json.loads(ipc('state'))['capture'] and not history.exists()
        requests = copy('firefox', 'plain', 'PRE-ENABLE NEVER IMPORT')
        time.sleep(.15)
        assert not requests.exists() and not history.exists()
        ipc('capture', 'true')
        wait(lambda s: s['capture'] and s['backend'])
        time.sleep(.1)
        assert json.loads(ipc('state'))['count'] == 0, 'Imported already-owned clipboard'
        ipc('persist', 'true')
        wait(lambda s: s['persist'] and not s['writing'])
        for application, text in [('firefox', 'normal browser \u03bb \U0001f600'), ('alacritty', 'normal terminal text')]:
            before = json.loads(ipc('state'))['count']
            copy(application, 'plain', text)
            state = wait(lambda s: s['count'] == before + 1)
            assert text in state['texts']
            for _ in range(100):
                if any(e['text'] == text for e in stored()): break
                time.sleep(.05)
            assert any(e['text'] == text for e in stored())
        for application, mode in [('firefox', 'secret'), ('bitwarden', 'plain')]:
            secret = 'NEVER-RETAIN-' + application
            before = json.loads(ipc('state'))['texts']
            requests = copy(application, mode, secret)
            time.sleep(.25)
            assert json.loads(ipc('state'))['texts'] == before
            assert secret not in history.read_text()
            actions = requests.read_text().splitlines() if requests.exists() else []
            assert 'TEXT' not in actions
            assert ('TARGETS' in actions) == (mode == 'secret')
        ipc('clear')
        wait(lambda s: s['capture'] and s['backend'] and s['count'] == 0)
        assert stored() == []
        copy('firefox', 'plain', 'after clear')
        wait(lambda s: s['count'] == 1)
        ipc('capture', 'false')
        wait(lambda s: not s['capture'] and s['count'] == 0 and not s['wipe'] and not s['writing'])
        assert stored() == []
        requests = copy('alacritty', 'plain', 'DISABLED NEVER RETAIN')
        time.sleep(.2)
        assert not requests.exists() and json.loads(ipc('state'))['count'] == 0
        assert stored() == [] and history.stat().st_mode & 0o777 == 0o600
        print('Production observer -> actual QML -> private disk: browser/terminal retained; marked/manager rejected; opt-in, Clear and disable: PASS')
    finally:
        for child in reversed(processes):
            if child.poll() is None: child.terminate()
            child.wait(timeout=10)
            if child.stdout: child.stdout.close()
        xvfb.terminate()
        xvfb.wait(timeout=10)
        display_file.close()
        log.flush()
        log.seek(0)
        output = log.read()
        log.close()
        if any('Traceback' in line or 'Error:' in line for line in output.splitlines()):
            print(output)
