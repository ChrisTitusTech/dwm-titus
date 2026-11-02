#!/usr/bin/env python3
"""Exercise hidden-network form recovery in the actual QML model."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tmp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT', str(Path.home() / 'tmp')))
tmp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='hidden-network-model-') as directory, \
        tempfile.TemporaryDirectory(prefix='nw.', dir=tmp_root) as runtime_directory:
    work = Path(directory)
    shell = work / 'shell'
    shutil.copytree(root / 'config/quickshell', shell)
    runtime = Path(runtime_directory)
    (shell / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.network
ShellRoot {
    NetworkModel { id: model }
    Timer {
        interval: 1000; running: true
        onTriggered: {
            function check(value, message) { if (!value) throw new Error(message); }
            try {
                model.providerState = "available";
                model.operationState = "delegated";
                model.devices = [{device:"wlan0", type:"wifi", state:"disconnected"},
                                 {device:"wlan1", type:"wifi", state:"disconnected"}];
                model.openHiddenPrompt("panel");
                model.hiddenSsid = "Saved form";
                model.hiddenSecurity = "open";
                model.hiddenDevice = "wlan0";
                model.devices = [{device:"wlan1", type:"wifi", state:"disconnected"}];
                check(model.hiddenDevice === "wlan1", "stale adapter retained");
                check(model.hiddenSsid === "Saved form", "form lost during replug");
                check(model.hiddenFormValid, "remaining adapter cannot connect");
                model.devices = [];
                check(!model.hiddenFormValid, "missing adapter accepted");
                model.resetHiddenPrompt();
                model.providerState = "unavailable";
                model.openHiddenPrompt("settings");
                check(model.hiddenPromptPendingOrigin === "settings", "request lost after snapshot failure");
                model.devices = [{device:"wlan1", type:"wifi", state:"disconnected"}];
                model.providerState = "available";
                model.openPendingHiddenPrompt();
                check(model.hiddenPromptVisible && model.hiddenPromptOrigin === "settings", "queued request not recovered");
                console.warn("Hidden-network adapter and failed-provider recovery: PASS");
                Qt.quit();
            } catch (error) {
                console.error(error);
                Qt.exit(1);
            }
        }
    }
}
''')
    env = dict(os.environ, HOME=str(work), XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(work / 'config'), XDG_DATA_HOME=str(work / 'data'),
               QT_QPA_PLATFORM='offscreen', PATH='/usr/bin:/bin')
    result = subprocess.run(['quickshell', '--no-duplicate', '--path', str(shell / 'shell.qml')],
                            env=env, text=True, capture_output=True, timeout=15)
    print(result.stdout + result.stderr)
    assert result.returncode == 0 and 'recovery: PASS' in result.stdout + result.stderr
