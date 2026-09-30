#!/usr/bin/python3
"""Exercise Update Center popup geometry and interaction in isolated X11."""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import ImageGrab


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
   freshness: "fresh", lastSuccess: 30, updateAvailable: true, errorCode: "", detail: "", restart: "none",
   items: Array.from({length: 40}, function(_, index) { return {
     providerId: "fedora", action: "update", name: "Package with a deliberately long name " + index,
     current: "1." + index, available: "2." + index, packageId: "package-" + index,
     scope: "system", url: "https://example.test/package/" + index }; }) },
 { id: "dwm-titus", name: "DWM-Titus", status: "available", pending: 0, managed: 1,
   freshness: "fresh", lastSuccess: 90, updateAvailable: false, errorCode: "", detail: "", restart: "none", items: [] },
 { id: "flatpak", name: "Flatpak", status: "partial", pending: 1, managed: 12,
   freshness: "stale", lastSuccess: 4000, updateAvailable: true, errorCode: "network", detail: "Using cached results",
   restart: "none",
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
        property int refreshCount: 0
        property int saveCount: 0
        property string probeAction: ""
        property string probeUrl: ""
        property int anchorX: 320
        readonly property bool busy: activeOperation !== null
        function open() {{ visible = true; }}
        function close() {{ visible = false; settingsMode = false; discardSettings(); }}
        function refresh(force) {{ refreshCount++; message = force ? "Manual refresh requested" : ""; return true; }}
        function launch(providerId) {{ message = "launch:" + providerId; visible = false; return true; }}
        function recover(providerId) {{ message = "recover:" + providerId; visible = false; return true; }}
        function showSettings() {{ settingsMode = true; discardSettings(); }}
        function discardSettings() {{ draftRefreshSeconds = 3600; draftAlwaysShow = true; settingsError = ""; }}
        function saveSettings() {{ saveCount++; message = "saved"; settingsLoading = true; saveTimer.start(); return true; }}
    }}

    QtObject {{
        id: highProvider
        property string id: "fedora"
        property string name: "High-cardinality Fedora"
        property string status: "available"
        property int pending: 4096
        property int managed: 4096
        property string freshness: "fresh"
        property int lastSuccess: 999941
        property bool updateAvailable: true
        property string errorCode: ""
        property string detail: ""
        property string restart: "none"
        property var items: Array.from({{length: 4096}}, function(_, index) {{ return {{
            providerId: "fedora", action: "update", name: "Package " + index,
            current: "1", available: "2", packageId: "package-" + index,
            scope: "system", url: "https://example.test/package/" + index }}; }})
    }}

    Timer {{
        id: saveTimer
        interval: 20
        repeat: false
        onTriggered: model.settingsLoading = false
    }}

    PanelWindow {{
        id: panel
        implicitHeight: 30
        anchors {{ top: true; left: true; right: true }}
        exclusiveZone: 30
        color: Theme.barBackground

        Rectangle {{ id: updateButton; x: 240; y: 2; width: 40; height: 26; color: "#ff00ff" }}

        ProviderRow {{
            id: probeRow
            visible: false
            provider: model.providers[0]
            onUpdateRequested: providerId => model.probeAction = "update:" + providerId
            onRecoverRequested: providerId => model.probeAction = "recover:" + providerId
            onOpenUrlRequested: url => model.probeUrl = url
        }}

        ProviderRow {{
            id: highRow
            width: 430
            opacity: 0
            provider: highProvider
        }}
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
        anchorX: model.anchorX
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
        function motionDuration(): string {{ return String(Theme.animationFast); }}
        function probeAge(lastSuccess: int, nowSeconds: int): string {{ return probeRow.formatCheckAge(lastSuccess, nowSeconds); }}
        function probeExpand(): string {{ probeRow.toggleExpanded(); return String(probeRow.expanded); }}
        function probeDetails(): string {{ return probeRow.itemDescription(model.providers[0].items[0]); }}
        function probeAction(mode: string): string {{
            model.probeAction = "";
            probeRow.globalBusy = mode === "busy";
            probeRow.providerRecoverable = mode === "recover";
            probeRow.requestAction();
            return model.probeAction;
        }}
        function probeOpen(url: string): string {{ model.probeUrl = ""; probeRow.requestOpen({{ url: url }}); return model.probeUrl; }}
        function accessibleName(): string {{ return probeRow.Accessible.name; }}
        function setProbeRestart(value: string): string {{
            probeRow.provider = {{
                id: "fedora", name: "Fedora", status: "available", pending: 0, managed: 1200,
                freshness: "fresh", lastSuccess: 30, updateAvailable: false, errorCode: "",
                detail: "", restart: value, items: []
            }};
            return probeRow.Accessible.name + "|" + probeRow.visibleDetail();
        }}
        function probeStatusLabel(): string {{ return probeRow.statusLabel(); }}
        function probeStatusLabelColor(): string {{ return String(probeRow.statusLabelColor()); }}
        function setProbeScanning(value: bool): void {{ probeRow.scanning = value; }}
        function mutedColor(): string {{ return String(Theme.menuMutedText); }}
        function probePackageSummary(): string {{ return probeRow.packageSummary(); }}
        function probeHasDetails(): string {{ return String(probeRow.hasDetails); }}
        function setProbeDetail(detail: string): void {{
            probeRow.provider = {{
                id: "fedora", name: "Fedora", status: "available", pending: 0, managed: 1200,
                freshness: "fresh", lastSuccess: 30, updateAvailable: false, errorCode: "",
                detail: detail, restart: "none", items: []
            }};
        }}
        function counts(): string {{ return model.refreshCount + ":" + model.saveCount; }}
        function editorFocused(): string {{ return String(updateWindow.editorFocused()); }}
        function saveStatus(): string {{ return updateWindow.saveStatus; }}
        function highDelegateCount(): string {{ return String(highRow.instantiatedItemDelegates); }}
        function highExpand(): void {{ highRow.expanded = true; }}
        function highCollapse(): void {{ highRow.expanded = false; }}
        function setProbeClock(lastSuccess: int, nowSeconds: int): string {{
            highProvider.lastSuccess = lastSuccess;
            highRow.nowSeconds = nowSeconds;
            return highRow.relativeCheckAge;
        }}
        function ageClockRunning(): string {{ return String(updateWindow.ageClockRunning); }}
        function setAnchor(value: int): void {{ model.anchorX = value; }}
        function anchorToButton(): void {{ model.anchorX = updateButton.x + updateButton.width / 2; }}
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

    def call(name, *arguments):
        return run(env, *ipc, name, *(str(argument) for argument in arguments), check=True).stdout.strip()

    def screenshot():
        return ImageGrab.grab(xdisplay=env.get("DISPLAY")).convert("RGB")

    def color_bounds(image, rgb):
        points = [(x, y) for y in range(image.height) for x in range(image.width) if image.getpixel((x, y)) == rgb]
        assert points, f"color {rgb} was not rendered"
        return min(x for x, _ in points), min(y for _, y in points), max(x for x, _ in points), max(y for _, y in points), len(points)

    def pixel_difference(first, second):
        first_pixels = first.get_flattened_data() if hasattr(first, "get_flattened_data") else first.getdata()
        second_pixels = second.get_flattened_data() if hasattr(second, "get_flattened_data") else second.getdata()
        return sum(1 for before, after in zip(first_pixels, second_pixels) if before != after)

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
        time.sleep(0.2)
        run(env, "xdotool", "mousemove", "10", "15", check=True)
        time.sleep(0.1)
        assert call("highDelegateCount") == "0", "Collapsed provider eagerly instantiated item delegates"
        call("highExpand")
        expanded_delegate_count = wait_for(
            lambda: int(call("highDelegateCount")) or None,
            "Expanding a provider did not render its bounded item list",
        )
        assert expanded_delegate_count < 32, f"Expanded provider constructed {expanded_delegate_count} of 4096 delegates"
        call("highCollapse")
        wait_for(lambda: call("highDelegateCount") == "0", "Collapsing one provider did not restore the independent row layout")

        expected_ages = (
            (0, 1_000_000, "Not checked"),
            (1_000_001, 1_000_000, "0s ago"),
            (1_000_000, 1_000_000, "0s ago"),
            (999_941, 1_000_000, "59s ago"),
            (999_940, 1_000_000, "1m ago"),
            (996_400, 1_000_000, "1h ago"),
            (913_600, 1_000_000, "1d ago"),
        )
        for last_success, now_seconds, expected in expected_ages:
            assert call("probeAge", last_success, now_seconds) == expected

        assert call("probeExpand") == "true"
        assert call("probeExpand") == "false", "Provider expansion was not independently reversible"
        assert call("probeDetails") == "Package with a deliberately long name 0 (system)\n1.0 -> 2.0"
        assert call("probeAction", "update") == "update:fedora"
        assert call("probeAction", "recover") == "recover:fedora"
        assert call("probeAction", "busy") == "", "Busy provider dispatched an action"
        assert call("probeOpen", "https://example.test/release") == "https://example.test/release"
        assert call("probeOpen", "file:///tmp/untrusted") == ""
        assert call("probeOpen", "javascript:alert(1)") == ""
        assert call("accessibleName") == "Fedora, 40 pending"
        assert call("setProbeRestart", "session") == "Fedora, Restart session|Sign out and back in to complete this update."
        assert call("setProbeRestart", "system") == "Fedora, Restart system|Restart the system to complete this update."
        assert call("setProbeRestart", "none") == "Fedora, Up to date|"
        assert call("probeStatusLabel") == "Up to date"
        call("setProbeScanning", "true")
        assert call("probeStatusLabel") == "Checking"
        assert call("probeStatusLabelColor") == call("mutedColor"), "Checking must use default muted text color"
        call("setProbeScanning", "false")
        assert call("probePackageSummary") == "1200 Packages"
        call("setProbeDetail", "System notice")
        assert call("probeHasDetails") == "true", "Provider with detail but no items must have details available"
        assert call("highDelegateCount") == "0", "Collapsed provider retained item delegates"
        assert call("setProbeClock", 999_941, 1_000_000) == "59s ago"
        assert call("setProbeClock", 999_941, 1_000_001) == "1m ago", "Relative age did not react without a rescan"
        assert call("ageClockRunning") == "true"

        run(env, *ipc, "openOther", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 2, "Comparison popup did not replace Update Center")
        assert call("ageClockRunning") == "false", "Age clock continued while Update Center was closed"
        run(env, *ipc, "open", check=True)
        wait_for(lambda: len(visible_windows(env, shell.pid)) == 2, "Popup exclusivity did not close the other popup")
        assert call("ageClockRunning") == "true"
        popup_id = next(window for window in visible_windows(env, shell.pid) if window != panel_id)

        run(env, "xdotool", "mousemove", "320", "210", "click", "5", "click", "5", check=True)
        assert shell.poll() is None, "Large provider list scrolling terminated the shell"

        run(env, "xdotool", "windowfocus", popup_id, check=True)
        run(env, "xdotool", "key", "Tab", "Tab", "Tab", check=True)
        assert run(env, "xdotool", "getwindowfocus").stdout.strip() == popup_id

        for fixture in ("light", "dark", "reducedMotion", "normalMotion"):
            run(env, *ipc, fixture, check=True)
            assert shell.poll() is None, f"{fixture} fixture terminated the shell"

        call("light")
        time.sleep(0.2)
        light_image = screenshot()
        assert color_bounds(light_image, (244, 244, 244))[4] > 1000
        call("dark")
        call("anchorToButton")
        time.sleep(0.2)
        dark_image = screenshot()
        card_bounds = color_bounds(dark_image, (32, 38, 48))
        assert card_bounds[:4] == (21, 31, 498, card_bounds[3]), \
            f"Rendered card did not center below the button at x=260: {card_bounds}"
        assert card_bounds[4] > 1000
        call("setAnchor", 620)
        time.sleep(0.2)
        clamped_image = screenshot()
        clamped_bounds = color_bounds(clamped_image, (32, 38, 48))
        assert clamped_bounds[0] == 161 and clamped_bounds[2] == 638, \
            f"Narrow-screen button anchoring did not clamp the card: {clamped_bounds}"
        call("setAnchor", 320)
        call("reducedMotion")
        assert call("motionDuration") == "0"
        call("normalMotion")

        run(env, *ipc, "settings", check=True)
        run(env, "xdotool", "windowfocus", popup_id, check=True)
        time.sleep(0.2)
        before_refresh, before_save = map(int, call("counts").split(":"))
        run(env, "xdotool", "mousemove", "525", "318", "click", "1", check=True)
        wait_for(lambda: call("saveStatus") == "Preferences saved", "Save did not report successful persistence")
        clicked_refresh, clicked_save = map(int, call("counts").split(":"))
        assert clicked_refresh == before_refresh and clicked_save == before_save + 1
        run(env, "xdotool", "key", "r", check=True)
        after_refresh, after_save = map(int, call("counts").split(":"))
        assert after_refresh == clicked_refresh + 1 and after_save == clicked_save
        run(env, "xdotool", "key", "s", check=True)
        shortcut_refresh, shortcut_save = map(int, call("counts").split(":"))
        assert shortcut_refresh == after_refresh and shortcut_save == after_save + 1
        for _ in range(16):
            run(env, "xdotool", "key", "Tab", check=True)
            if call("editorFocused") == "true":
                break
        else:
            raise AssertionError("Interval editor was not keyboard reachable")
        run(env, "xdotool", "key", "s", check=True)
        editor_refresh, editor_save = map(int, call("counts").split(":"))
        assert editor_refresh == shortcut_refresh and editor_save == shortcut_save, \
            f"S escaped the focused interval editor: before={shortcut_refresh, shortcut_save} after={editor_refresh, editor_save}"
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
