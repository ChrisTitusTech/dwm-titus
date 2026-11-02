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
    ClipboardWindow { id: surface; clipboardModel: model }
    Component.onCompleted: if (Quickshell.env("CLIPBOARD_TEST_EARLY_CLEAR") === "1") model.clearAll()
    IpcHandler {
        target: "clipboardtest"
        function state(): string { return JSON.stringify({ready:model.historyReady && model.settingsReady,
            capture:model.captureEnabled, backend:model.backendReady, backendFailed:model.backendFailed,
            storage:model.storageReady, preparing:model.storagePreparing,
            confirmed:model.confirmedPersistence, enabled:model.persistenceEnabled,
            writing:model.settingsWriting, failed:model.settingsSaveFailed,
            wipe:model.wipePending, historyFailed:model.saveFailed, discardFailed:model.consentFailed, count:model.entries.length}); }
        function capture(enabled: bool): void { model.setCapture(enabled); }
        function persist(enabled: bool): void { model.setPersistence(enabled); }
        function retry(): void { model.retrySave(); }
        function open(): void { model.open(); }
        function close(): void { model.close(); }
        function storageRetryEnabled(): bool {
            const stack = [surface.contentItem];
            while (stack.length) {
                const item = stack.pop();
                if (item.label === "Retry storage") return item.enabled;
                for (const child of item.children || []) stack.push(child);
            }
            return false;
        }
        function retryStorageFromUi(): void {
            const stack = [surface.contentItem];
            while (stack.length) {
                const item = stack.pop();
                if (item.label === "Retry storage" && item.enabled) { item.requestActivation(); return; }
                for (const child of item.children || []) stack.push(child);
            }
            throw new Error("Storage Retry is unavailable");
        }
        function clear(): void { model.clearAll(); }
        function clearTwice(): void { model.clearAll(); model.clearAll(); }
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
    if os.environ.get('DWM_TEST_CLIPBOARD_MODEL'):
        shutil.copy2(os.environ['DWM_TEST_CLIPBOARD_MODEL'], shell / 'clipboard/ClipboardModel.qml')
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
    # Pause an actual FileView atomic writer at fsync, not a mocked model flag.
    # Clear must wait for this older write before committing its empty file.
    preload_source = work / 'delay-history-write.c'
    preload_source.write_text(r"""
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static void delay_write(int fd) {
    const char *entered = getenv("CLIPBOARD_WRITE_ENTERED");
    const char *release = getenv("CLIPBOARD_WRITE_RELEASE");
    char proc[64], path[4096], data[2048];
    if (!entered || !release) return;
    snprintf(proc, sizeof proc, "/proc/self/fd/%d", fd);
    ssize_t n = readlink(proc, path, sizeof path - 1);
    if (n <= 0) return;
    path[n] = 0;
    if (!strstr(path, "/.cache/dwm-titus/")) return;
    int input = open(proc, O_RDONLY);
    if (input < 0) return;
    n = pread(input, data, sizeof data - 1, 0);
    close(input);
    if (n <= 0) return;
    data[n] = 0;
    if (!strstr(data, "DELAYED-")) return;
    int marker = open(entered, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (marker < 0) return;
    close(marker);
    struct timespec pause = {0, 5000000};
    for (int i = 0; i < 1000 && access(release, F_OK); i++) nanosleep(&pause, NULL);
}
int fsync(int fd) {
    static int (*next)(int);
    if (!next) next = dlsym(RTLD_NEXT, "fsync");
    delay_write(fd);
    return next(fd);
}
int fdatasync(int fd) {
    static int (*next)(int);
    if (!next) next = dlsym(RTLD_NEXT, "fdatasync");
    delay_write(fd);
    return next(fd);
}
""")
    preload = work / 'delay-history-write.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
                    preload_source, '-ldl', '-o', preload], check=True)
    entered = work / 'write-entered'
    release = work / 'write-release'
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
               'QT_QPA_PLATFORMTHEME': '', 'LD_PRELOAD': str(preload),
               'CLIPBOARD_WRITE_ENTERED': str(entered), 'CLIPBOARD_WRITE_RELEASE': str(release)}
        def launch():
            return subprocess.Popen(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                                    env=env, stdout=log, stderr=subprocess.STDOUT)
        saved_cache = work / 'saved-cache'
        if os.geteuid() != 0:
            cache.rename(saved_cache)
            cache.parent.chmod(0o500)
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
        if os.geteuid() != 0:
            wait(lambda s: s['failed'] and not s['preparing'])
            state = json.loads(ipc('state'))
            assert not state['storage'] and not state['capture'] and state['count'] == 0
            time.sleep(.15)
            assert not json.loads(ipc('state'))['preparing'], 'Storage setup retried without user action'
            ipc('open')
            assert ipc('storageRetryEnabled').strip() == 'true', 'Storage Retry button is disabled before settings readiness'
            cache.parent.chmod(0o700)
            saved_cache.rename(cache)
            ipc('retryStorageFromUi')
        wait(lambda s: s['ready'] and s['storage'])
        assert process.poll() is None, 'Storage retry required a shell restart'
        ipc('close')
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
        for operation in ('clear', 'disable'):
            entered.unlink(missing_ok=True)
            release.unlink(missing_ok=True)
            emit({'event': 'text', 'text': 'DELAYED-' + operation})
            for _ in range(100):
                if entered.exists(): break
                time.sleep(.02)
            assert entered.exists(), 'Actual history writer did not reach controlled fsync barrier'
            if operation == 'clear': ipc('clear')
            else: ipc('capture', 'false')
            # Give the former external-helper race time to commit its empty
            # file while the pre-clear FileView writer remains blocked.
            time.sleep(.3)
            release.touch()
            time.sleep(.15)
            wait(lambda s: s['count'] == 0 and not s['wipe'] and not s['writing'])
            for _ in range(100):
                if not json.loads(history.read_text())['entries']: break
                time.sleep(.05)
            assert not json.loads(history.read_text())['entries'], operation
            if operation == 'disable':
                assert not json.loads(ipc('state'))['capture']
                ipc('capture', 'true')
            wait(lambda s: s['capture'] and s['backend'] and s['count'] == 0)
            # The next delayed transaction needs persistence enabled again.
            if operation == 'clear':
                assert json.loads(ipc('state'))['confirmed']
            else:
                ipc('persist', 'true')
                wait(lambda s: s['confirmed'] and not s['writing'])
        entered.unlink(missing_ok=True)
        release.unlink(missing_ok=True)
        ipc('persist', 'false')
        wait(lambda s: not s['confirmed'] and not s['writing'] and not s['wipe'])
        emit({'event': 'text', 'text': 'memory capture after persistence off'})
        wait(lambda s: s['capture'] and s['backend'] and s['count'] == 1)
        assert not json.loads(history.read_text())['entries']
        ipc('persist', 'true')
        wait(lambda s: s['confirmed'] and not s['writing'])
        ipc('clearTwice')
        wait(lambda s: s['backend'] and s['capture'] and s['count'] == 0)
        assert not json.loads(history.read_text())['entries']
        emit({'event': 'text', 'text': 'post-clear'})
        wait(lambda s: s['count'] == 1)
        if os.geteuid() != 0: cache.chmod(0o500)
        ipc('capture', 'false')
        if os.geteuid() != 0:
            wait(lambda s: not s['capture'] and s['count'] == 0 and s['discardFailed'])
            cache.chmod(0o700)
            ipc('retry')
        wait(lambda s: not s['capture'] and s['count'] == 0 and not s['wipe'] and not s['historyFailed'])
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
            # A readable settings opt-in plus temporary history read failure
            # must recover without losing the live filtered source.
            process.terminate()
            process.wait(timeout=10)
            settings.write_text(json.dumps({'privacyVersion': 2, 'captureEnabled': True, 'persistenceEnabled': True}))
            history.write_text(json.dumps({'privacyVersion': 2, 'entries': [{'text': 'stored filtered text', 'timestamp': 1}]}))
            history.chmod(0o000)
            process = launch()
            wait(lambda s: s['ready'] and s['historyFailed'] and s['backend'])
            history.chmod(0o600)
            ipc('retry')
            wait(lambda s: s['ready'] and not s['historyFailed'] and s['capture'] and s['backend'])
            emit({'event': 'text', 'text': 'filtered after history recovery'})
            wait(lambda s: s['count'] == 2)

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
        # Clear requested before storage preparation must not remain deferred.
        process.terminate()
        process.wait(timeout=10)
        legacy.write_text('{"entries":[{"text":"early clear legacy"}]}')
        env['CLIPBOARD_TEST_EARLY_CLEAR'] = '1'
        process = launch()
        wait(lambda s: s['ready'])
        for _ in range(100):
            if not legacy.exists() and not json.loads(history.read_text())['entries']: break
            time.sleep(.05)
        assert not legacy.exists() and not json.loads(history.read_text())['entries']
        print('Actual QML privacy consent, filtered events, separate persistence, clear/disable, denial retry and backend failures: PASS')
    finally:
        config.chmod(0o700)
        cache.parent.chmod(0o700)
        if saved_cache.exists() and not cache.exists(): saved_cache.rename(cache)
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
