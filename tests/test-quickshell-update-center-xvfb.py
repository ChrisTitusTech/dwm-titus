#!/usr/bin/python3
"""Exercise Update Center popup geometry and interaction in isolated X11."""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


def run(env, *args, check=False):
    result = subprocess.run(args, env=env, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise AssertionError(f"{' '.join(args)} failed: {result.stderr}")
    return result


def wait_for(predicate, message, attempts=160):
    for _ in range(attempts):
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def visible_windows(env, pid):
    return run(env, "xdotool", "search", "--onlyvisible", "--pid", str(pid)).stdout.split()


def geometry(env, window):
    output = run(env, "xdotool", "getwindowgeometry", "--shell", window, check=True).stdout
    return {line.split("=", 1)[0]: line.split("=", 1)[1] for line in output.splitlines() if "=" in line}


providers = """[
 { id: "fedora", name: "Fedora", status: "available", pending: 40, managed: 1200,
   freshness: "fresh", lastSuccess: 30, updateAvailable: true, errorCode: "", detail: "",
   items: Array.from({length: 40}, function(_, index) { return {
     providerId: "fedora", action: "update", name: "Package with a deliberately long name " + index,
     current: "1." + index, available: "2." + index, packageId: "package-" + index,
     scope: "system", url: "https://example.test/package/" + index }; }) },
 { id: "dwm-titus", name: "DWM-Titus", status: "available", pending: 0, managed: 1,
   freshness: "fresh", lastSuccess: 90, updateAvailable: false, errorCode: "", detail: "", items: [] },
 { id: "flatpak", name: "Flatpak", status: "partial", pending: 1, managed: 12,
   freshness: "stale", lastSuccess: 4000, updateAvailable: true, errorCode: "network", detail: "Using cached results",
   items: [{ providerId: "flatpak", action: "update", name: "Application", current: "1", available: "2",
     packageId: "org.example.Application", scope: "user", url: "https://example.test/application" }] }
]"""


shell_qml = f'''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.updatecenter

ShellRoot {{
    QtObject {{
        id: model
        property var providers: {providers}
        property int totalUpdates: 41
        property bool visible: false
        property bool settingsMode: false
        property int draftRefreshSeconds: 3600
        property bool draftAlwaysShow: true
        property var activeOperation: null
        property string message: ""
        property string settingsError: ""
        property bool scanning: false
        property bool settingsLoading: false
        property bool online: true
        readonly property bool busy: activeOperation !== null
        function open() {{ visible = true; }}
        function close() {{ visible = false; settingsMode = false; discardSettings(); }}
        function refresh(force) {{ message = force ? "Manual refresh requested" : ""; return true; }}
        function launch(providerId) {{ message = "launch:" + providerId; visible = false; return true; }}
        function recover(providerId) {{ message = "recover:" + providerId; visible = false; return true; }}
        function showSettings() {{ settingsMode = true; discardSettings(); }}
        function discardSettings() {{ draftRefreshSeconds = 3600; draftAlwaysShow = true; settingsError = ""; }}
        function saveSettings() {{ message = "saved"; return true; }}
    }}

    PanelWindow {{
        id: panel
        implicitHeight: 30
        anchors {{ top: true; left: true; right: true }}
        exclusiveZone: 30
        color: Theme.barBackground
    }}

    ClickAwayPopup {{
        id: otherPopup
        targetWindow: panel
        visible: false
        popupX: 4
        popupY: 30
        popupWidth: 180
        popupHeight: 120
        onDismissed: visible = false
        Rectangle {{ anchors.fill: parent; color: "#aa3333" }}
    }}

    UpdateCenterWindow {{
        id: updateWindow
        updateCenterModel: model
        panelWindow: panel
        anchorX: panel.width / 2
        onExclusiveOpenRequested: otherPopup.visible = false
    }}

    IpcHandler {{
        target: "update-center-test"
        function open(): void {{ model.open(); }}
        function close(): void {{ model.close(); }}
        function openOther(): void {{ model.close(); otherPopup.visible = true; }}
        function settings(): void {{ model.showSettings(); }}
        function light(): void {{ Theme.dark = false; Theme.bg = "#f4f4f4"; Theme.surface = "#ffffff"; Theme.text = "#202020"; }}
        function dark(): void {{ Theme.dark = true; Theme.bg = "#202630"; Theme.surface = "#303846"; Theme.text = "#f0f0f0"; }}
        function reducedMotion(): void {{ Theme.applyAccessibility(false, true); }}
        function normalMotion(): void {{ Theme.applyAccessibility(false, false); }}
    }}
}}'''


required = ("quickshell", "xdotool")
missing = [command for command in required if shutil.which(command) is None]
if missing:
    print("SKIP: unavailable commands: " + ", ".join(missing))
    raise SystemExit(77)


tmp_root = os.environ.get("DWM_TEST_WORKSPACE", os.environ.get("DWM_TEST_TMP_ROOT", os.environ.get("TMPDIR", "/tmp")))
with tempfile.TemporaryDirectory(prefix="update-center-xvfb-", dir=tmp_root) as temp, \
        tempfile.TemporaryDirectory(prefix="uc-runtime-", dir="/tmp") as runtime_temp:
    base = Path(temp)
    home = base / "home"
    config_home = home / ".config"
    qml = config_home / "quickshell"
    # Quickshell's IPC endpoint is an AF_UNIX socket. Keep its runtime path
    # below sun_path limits even when the managed test workspace is deeply nested.
    runtime = Path(runtime_temp)
    qml.mkdir(parents=True)
    runtime.chmod(0o700)
    shutil.copytree(REPO / "config/quickshell/core", qml / "core")
    shutil.copytree(REPO / "config/quickshell/updatecenter", qml / "updatecenter")
    shutil.copytree(REPO / "config/quickshell/assets", qml / "assets")
    (qml / "shell.qml").write_text(shell_qml)

    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config_home),
        "XDG_DATA_HOME": str(base / "data"),
        "XDG_STATE_HOME": str(base / "state"),
        "XDG_RUNTIME_DIR": str(runtime),
        "QT_QPA_PLATFORM": "xcb",
        "QT_QPA_PLATFORMTHEME": "",
    }
    log = (base / "quickshell.log").open("w+")
    shell = subprocess.Popen(["quickshell", "--no-duplicate"], env=env, stdout=log, stderr=log)
    ipc = ("quickshell", "ipc", "--path", str(qml / "shell.qml"), "call", "update-center-test")

    try:
        wait_for(lambda: run(env, *ipc, "open").returncode == 0, "Update Center IPC unavailable")
        windows = wait_for(lambda: len(visible_windows(env, shell.pid)) >= 2 and visible_windows(env, shell.pid),
                           "Update Center popup did not open")
        geometries = {window: geometry(env, window) for window in windows}
        panel_id = next(window for window, data in geometries.items() if int(data["HEIGHT"]) == 30)
        popup_id = next(window for window, data in geometries.items() if int(data["HEIGHT"]) > 30)
        panel_geometry = geometries[panel_id]
        popup_geometry = geometries[popup_id]
        assert int(popup_geometry["Y"]) == int(panel_geometry["Y"]) + int(panel_geometry["HEIGHT"])
        assert int(popup_geometry["WIDTH"]) == 640, "Popup did not remain bounded to narrow monitor"
        assert int(popup_geometry["HEIGHT"]) <= 450, "Popup overflowed below the panel"

        run(env, *ipc, "openOther", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 2, "Comparison popup did not replace Update Center")
        run(env, *ipc, "open", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 2, "Popup exclusivity did not close the other popup")
        popup_id = next(window for window in visible_windows(env, shell.pid) if window != panel_id)

        run(env, "xdotool", "mousemove", "320", "210", "click", "5", "click", "5", check=True)
        assert shell.poll() is None, "Large provider list scrolling terminated the shell"

        run(env, "xdotool", "windowfocus", popup_id, check=True)
        run(env, "xdotool", "key", "Tab", "Tab", "Tab", check=True)
        assert run(env, "xdotool", "getwindowfocus").stdout.strip() == popup_id

        for fixture in ("light", "dark", "reducedMotion", "normalMotion"):
            run(env, *ipc, fixture, check=True)
            assert shell.poll() is None, f"{fixture} fixture terminated the shell"

        run(env, *ipc, "settings", check=True)
        run(env, "xdotool", "windowfocus", popup_id, check=True)
        run(env, "xdotool", "key", "Escape", check=True)
        wait_for(lambda: popup_id not in visible_windows(env, shell.pid), "Escape did not close the popup")

        run(env, *ipc, "open", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 2, "Popup did not reopen")
        run(env, "xdotool", "mousemove", "10", "300", "click", "1", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 1, "Click-away did not dismiss the popup")
        assert shell.poll() is None
        print("Quickshell Update Center Xvfb geometry, focus, overflow, theme, and dismissal: PASS")
    finally:
        shell.terminate()
        try:
            shell.wait(timeout=5)
        except subprocess.TimeoutExpired:
            shell.kill()
            shell.wait(timeout=5)
        log.seek(0)
        output = log.read()
        log.close()
        if output:
            print(output)
