# Omarchy Quickshell Bar Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dwm-titus bar presentation with the approved Omarchy-inspired layout and Bluetooth, Network, and Volume panels while preserving the existing Fedora X11 shell architecture and every unrelated dwm-titus surface.

**Architecture:** Keep the existing managed `ShellRoot`, one Quickshell process, `DwmState`, X11 `PanelWindow` geometry, IPC handlers, and service-facing models. Implement focused bar modules and adapted panel components inside `config/quickshell/`; extend the existing bounded helpers for missing metrics and actions instead of importing Omarchy's plugin host, commands, or Wayland/Hyprland runtime.

**Tech Stack:** QML/QtQuick, Quickshell 0.3.0 or Fedora 44's supported snapshot, X11/dwm EWMH state, NetworkManager/nmcli, BlueZ/bluetoothctl, PipeWire/WirePlumber, POSIX shell/Bash helpers, Fedora RPM/Kickstart packaging, shell fixture tests, qmllint, and nested X11 runtime tests.

**Spec:** `docs/superpowers/specs/2026-08-21-omarchy-quickshell-bar-integration-design.md`

## Global Constraints

- Fedora 44 x86_64 and the Xorg dwm session remain the only supported release target.
- Use the existing managed `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` tree and exactly one Quickshell process.
- Do not depend on Omarchy, `/usr/share/omarchy`, Hyprland, Arch Linux, Wayland layer shell, `omarchy-*`, or `wl-copy`.
- Preserve the existing Control Center, launcher, Settings, notifications, power menu, IPC endpoints, `RunningAppsArea`, and user-owned dwm TOML files.
- Preserve one top bar per monitor, 30 px bar height, 30 px exclusive zone, and existing fullscreen behavior.
- Primary monitor shows workspaces 1 through 9; secondary monitors retain monitor-local workspaces.
- Bar order is CTT logo, workspaces / clock / running applications, Bluetooth, Network, Volume.
- Bar palette is background `#1a1b26`, foreground/inactive `#a9b1d6`, active/accent `#7aa2f7`, and urgent `#f7768e`.
- Every bar text label and glyph is exactly 11 px; no bar item exposes a tooltip.
- Bluetooth, Network, and Volume panels use a continuous 1 px `#7aa2f7` border and contain no decorative subtitle/status phrase or reserved phrase spacing.
- Network excludes QR/barcode, speed test, and DNS controls and implementation.
- Prefer event-driven updates. Only the minute clock and bounded network metrics may be sampled; sampled processes must never overlap.
- Follow test-driven development, make each phase independently reviewable, and stop at each phase gate for real-session acceptance.
- Attribute adapted Omarchy code and preserve applicable license notices.
- Do not install or activate this branch on Abs's current Omarchy session.

## Planned File Structure

### New focused QML units

- `config/quickshell/panel/BarIconButton.qml` — tooltip-free 11 px bar icon button contract.
- `config/quickshell/panel/NetworkBarModule.qml` — local network glyphs and click behavior.
- `config/quickshell/panel/VolumeBarModule.qml` — local volume glyphs, thresholds, click, and wheel behavior.
- `config/quickshell/core/OmarchyPanelSurface.qml` — shared 1 px panel border, background, padding, and content sizing boundary.
- `config/quickshell/network/NetworkMetrics.js` — pure parsers and derived metrics for fixture testing.
- `tests/test-quickshell-bar.sh` — static contracts for final bar composition and local glyph ownership.
- `tests/test-quickshell-bar-xvfb.sh` — real Quickshell/X11 geometry, IPC, popup, and idle checks.
- `tests/test-quickshell-panel-layout.sh` — static panel inclusion/exclusion, sizing, and border contracts.
- `tests/test-quickshell-network-metrics.sh` — helper fixture tests for connection metrics.
- `docs/OMARCHY-BAR-ATTRIBUTION.md` — upstream source inventory, commit, license, and adaptation notes.
- `docs/qs-integ-acceptance.md` — owner installation, three-phase testing, evidence, and rollback procedure.

### Existing files changed in place

- `config/quickshell/panel/DwmPanel.qml` — strict three-zone layout and final module ordering.
- `config/quickshell/panel/WorkspaceButton.qml` — exact 11 px active/inactive presentation.
- `config/quickshell/panel/LogoButton.qml` — exact 11 px/no-tooltip bar contract while preserving the existing asset and action.
- `config/quickshell/panel/RunningAppItem.qml` — exact 11 px/no-tooltip bar contract.
- `config/quickshell/state/DwmState.qml` — explicit primary/all-workspaces selector without changing secondary mapping.
- `config/quickshell/core/Theme.qml` — named Omarchy bar/panel tokens without changing unrelated surface themes.
- `config/quickshell/network/NetworkModel.qml` — event-driven icon state, grouped networks, bounded metrics, failures, and actions.
- `config/quickshell/network/NetworkWindow.qml` — approved Omarchy-style compact Network panel.
- `config/quickshell/network/NetworkWifiRow.qml` — known/other row presentation and actions.
- `config/quickshell/controls/BluetoothModel.qml` — richer device state, battery, trust, and action results.
- `config/quickshell/controls/BluetoothWindow.qml` — approved adaptive Bluetooth panel.
- `config/quickshell/controls/ControlsModel.qml` — volume icon state API and action failure reporting.
- `config/quickshell/controls/ControlsWindow.qml` — approved adaptive Volume panel.
- `config/quickshell/shell.qml` — retain model ownership and expose test-only read IPC without adding another shell host.
- `scripts/dwm-quickshell-network` — versioned machine-readable connection metrics and missing Network actions.
- `scripts/dwm-quickshell-controls` — richer Bluetooth rows and stable action failure output.
- `scripts/dwm-packages.sh`, `scripts/check-deps.sh`, `dwm-fedora.ks`, `dwm-fedora-nvidia.ks` — dependency alignment.
- `Makefile` — register focused tests in the managed suite.
- `SPEC.md`, `README.md`, `CHANGELOG.md` — durable behavior, dependencies, and user-visible change.

---

## Phase 1: Bar Integration and Geometry

### Task 1: Lock the bar theme and tooltip-free module primitives

**Files:**
- Create: `config/quickshell/panel/BarIconButton.qml`
- Modify: `config/quickshell/core/Theme.qml:10-147`
- Modify: `config/quickshell/panel/LogoButton.qml`
- Modify: `config/quickshell/panel/WorkspaceButton.qml`
- Modify: `config/quickshell/panel/RunningAppItem.qml`
- Create: `tests/test-quickshell-bar.sh`
- Modify: `Makefile:372-395,527-535,555`

**Interfaces:**
- Produces `Theme.omarchyBarBackground`, `Theme.omarchyBarForeground`, `Theme.omarchyBarInactive`, `Theme.omarchyBarActive`, `Theme.omarchyBarUrgent`, and `Theme.omarchyBarFontSize` without changing the existing theme-derived `Theme.barBackground` used by unrelated controls.
- Produces `BarIconButton { glyph: string; active: bool; activated(); wheelUp(); wheelDown() }` with no tooltip property or popup.
- Preserves `LogoButton.activated()`, `WorkspaceButton.clicked()`, and `RunningAppItem.focusRequested(string windowId)`.

- [ ] **Step 1: Write a failing static bar-contract test**

Create `tests/test-quickshell-bar.sh` with these initial assertions:

```sh
#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo/config/quickshell/core/Theme.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml

grep -F 'readonly property int omarchyBarFontSize: 11' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarBackground: "#1a1b26"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarForeground: "#a9b1d6"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarActive: "#7aa2f7"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarUrgent: "#f7768e"' "$theme" >/dev/null
if grep -F 'PanelTooltip {' "$panel" >/dev/null; then
    printf '%s\n' 'DwmPanel still creates tooltips' >&2
    exit 1
fi
printf '%s\n' 'Quickshell bar source contract: PASS'
```

Add executable mode and a `check-quickshell-bar` Make target that runs it; include that target in `check` and `.PHONY`.

- [ ] **Step 2: Run the test and verify the contract is absent**

Run:

```sh
tests/test-quickshell-bar.sh
```

Expected: non-zero exit at the first missing bar token.

- [ ] **Step 3: Add exact bar tokens and the focused button primitive**

Add these independent bar tokens to `Theme.qml`; do not replace the theme-derived values used by non-bar surfaces:

```qml
readonly property string omarchyBarBackground: "#1a1b26"
readonly property string omarchyBarForeground: "#a9b1d6"
readonly property string omarchyBarInactive: "#a9b1d6"
readonly property string omarchyBarActive: "#7aa2f7"
readonly property string omarchyBarUrgent: "#f7768e"
readonly property int omarchyBarFontSize: 11
```

Implement `BarIconButton.qml` as an `Item` containing one centered `IconText` at `Theme.omarchyBarFontSize` and one `MouseArea`. It may expose hover fill through `containsMouse`, but it must not construct `PanelTooltip`, `ToolTip`, or delayed hover timers.

Update `LogoButton.qml`, `WorkspaceButton.qml`, and `RunningAppItem.qml` so every glyph/text node inside the bar binds `font.pixelSize: Theme.omarchyBarFontSize`. Remove any tooltip creation or tooltip-facing hover property from those modules while preserving click/focus behavior.

- [ ] **Step 4: Run focused lint and tests**

Run:

```sh
tests/test-quickshell-bar.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit Task 1**

```bash
git add -- Makefile config/quickshell/core/Theme.qml \
  config/quickshell/panel/BarIconButton.qml \
  config/quickshell/panel/LogoButton.qml \
  config/quickshell/panel/WorkspaceButton.qml \
  config/quickshell/panel/RunningAppItem.qml \
  tests/test-quickshell-bar.sh
git commit -m "feat: add Omarchy bar presentation primitives"
```

### Task 2: Implement primary and secondary workspace contracts

**Files:**
- Modify: `config/quickshell/state/DwmState.qml:7-197`
- Modify: `config/quickshell/panel/DwmPanel.qml:32-119`
- Modify: `tests/test-quickshell-bar.sh`
- Test: `tests/test-dwm-status.sh`

**Interfaces:**
- Consumes `DwmPanel.primaryPanel` and existing `workspaceIndexes(screen)`.
- Produces `DwmState.barWorkspaceIndexes(screen, primaryPanel): int[]`.
- Preserves `switchWorkspaceForScreen(screen, index)` and monitor-local routing on secondary bars.

- [ ] **Step 1: Extend the failing source test**

Add assertions that `DwmPanel.qml` calls:

```qml
root.state.barWorkspaceIndexes(root.screen, root.primaryPanel)
```

and that `DwmState.qml` defines `function barWorkspaceIndexes(screen, primaryPanel)`.

- [ ] **Step 2: Run the source test and verify failure**

Run `tests/test-quickshell-bar.sh`.

Expected: non-zero exit because `barWorkspaceIndexes` does not exist.

- [ ] **Step 3: Implement the explicit selector**

Add to `DwmState.qml`:

```qml
function allWorkspaceIndexes() {
    const indexes = [];
    for (let index = 0; index < Math.min(9, root.workspaceNames.length); index++) {
        indexes.push(index);
    }
    return indexes;
}

function barWorkspaceIndexes(screen, primaryPanel) {
    return primaryPanel ? root.allWorkspaceIndexes() : root.workspaceIndexes(screen);
}
```

Change only the bar repeater model to call the new selector. Do not change
`workspaceIndexes(screen)` because other monitor-local consumers rely on it.

- [ ] **Step 4: Run workspace and state tests**

Run:

```sh
tests/test-quickshell-bar.sh
tests/test-dwm-status.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 2**

```bash
git add -- config/quickshell/state/DwmState.qml \
  config/quickshell/panel/DwmPanel.qml tests/test-quickshell-bar.sh
git commit -m "feat: show all workspaces on the primary bar"
```

### Task 3: Add dynamic Network and Volume bar modules

**Files:**
- Create: `config/quickshell/panel/NetworkBarModule.qml`
- Create: `config/quickshell/panel/VolumeBarModule.qml`
- Modify: `scripts/dwm-quickshell-network:1-248`
- Modify: `config/quickshell/network/NetworkModel.qml:8-372`
- Modify: `config/quickshell/controls/ControlsModel.qml:10-407`
- Modify: `tests/test-quickshell-bar.sh`
- Modify: `tests/test-quickshell-network.sh`
- Modify: `tests/test-quickshell-controls.sh`

**Interfaces:**
- Produces `NetworkModel.connectionKind: "ethernet" | "wifi" | "disconnected"`, `wifiSignal: int`, and `barIconState: string`; the model exposes semantic state, not glyphs.
- Produces `ControlsModel.volumeIconState: "mute" | "low" | "medium" | "high"` with the approved thresholds; the model exposes semantic state, not glyphs.
- `NetworkBarModule` consumes `networkModel` and emits the existing popup request before `networkModel.toggle()`.
- `VolumeBarModule` consumes `controlsModel`, emits the existing popup request, and calls `volumeUp()`/`volumeDown()` on wheel events.

- [ ] **Step 1: Add failing parser and source assertions**

Extend `tests/test-quickshell-network.sh` with fixture cases for a new helper status row:

```text
ethernet\tenp2s0\tWired connection 1\t-1
wifi\twlan0\tHUAWEI-BY10D8_Wi-Fi5\t74
disconnected\t\t\t-1
```

Assert `NetworkModel.qml` exposes `connectionKind`, `wifiSignal`, and `barIconState`.

Extend `tests/test-quickshell-controls.sh` or add source assertions to
`tests/test-quickshell-bar.sh` for these exact Volume outcomes:

```text
muted=true percent=50 -> mute
muted=false percent=0 -> mute
percent=1 -> low
percent=33 -> low
percent=34 -> medium
percent=66 -> medium
percent=67 -> high
percent=100 -> high
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-controls.sh
tests/test-quickshell-bar.sh
```

Expected: non-zero because the new state fields, modules, and threshold function are absent.

- [ ] **Step 3: Implement local glyph ownership and state derivation**

Define Network glyphs only inside `NetworkBarModule.qml`:

```qml
readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
readonly property string ethernetIcon: "󰈀"
readonly property string disconnectedIcon: "󰤮"
```

Define Volume glyphs only inside `VolumeBarModule.qml`:

```qml
readonly property string muteIcon: "󰝟"
readonly property string lowIcon: "󰕿"
readonly property string mediumIcon: "󰖀"
readonly property string highIcon: "󰕾"
```

Use one pure `ControlsModel.volumeIconStateFor(percent, muted)` function:

```qml
function volumeIconStateFor(percent, muted) {
    if (muted || percent <= 0) return "mute";
    if (percent <= 33) return "low";
    if (percent <= 66) return "medium";
    return "high";
}
```

The model returns the semantic state; `VolumeBarModule` maps the state to its
locally owned glyph. Keep PipeWire signal connections as the immediate update
source. Extend `dwm-quickshell-network status` to emit the four-field row from
Step 1. Extend the Network model parser so wired wins over Wi-Fi and the monitor
process refreshes state without a timer.

- [ ] **Step 4: Run focused tests and QML lint**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-controls.sh
tests/test-quickshell-bar.sh
shellcheck scripts/dwm-quickshell-network tests/test-quickshell-network.sh
shfmt -d scripts/dwm-quickshell-network tests/test-quickshell-network.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 3**

```bash
git add -- config/quickshell/panel/NetworkBarModule.qml \
  config/quickshell/panel/VolumeBarModule.qml \
  scripts/dwm-quickshell-network \
  config/quickshell/network/NetworkModel.qml \
  config/quickshell/controls/ControlsModel.qml \
  tests/test-quickshell-bar.sh tests/test-quickshell-network.sh \
  tests/test-quickshell-controls.sh
git commit -m "feat: add dynamic network and volume bar modules"
```

### Task 4: Replace DwmPanel with the final three-zone composition

**Files:**
- Modify: `config/quickshell/panel/DwmPanel.qml:1-421`
- Modify: `config/quickshell/shell.qml` at the `DwmPanel` instantiation and IPC section
- Modify: `tests/test-quickshell-bar.sh`
- Create: `tests/test-quickshell-bar-xvfb.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes Task 1 theme/module primitives, Task 2 workspace selector, Task 3 dynamic modules, and existing model `toggle()` methods.
- Produces test-only `IpcHandler target: "bar"` methods `height(): int`, `layout(): string`, `workspaceCount(): int`, `networkIconState(): string`, and `volumeIconState(): string`.
- Preserves `popupRequested(panelWindow, popupId)` and current popup mutual exclusion.

- [ ] **Step 1: Extend the failing static test for exact layout**

Assert that `DwmPanel.qml` contains, in source order:

```text
LogoButton
WorkspaceButton
clockLabel
RunningAppsArea
Bluetooth
NetworkBarModule
VolumeBarModule
```

Assert the file does not contain `TrayArea`, `statusSegments`, `batteryPill`,
`activeWindowTitle`, `showPowerWidget`, `PanelTooltip`, or the clock's old
`ddd dd MMM - HH:mm` format. Assert it contains:

```qml
Qt.formatDateTime(root.clock.date, "ddd, d MMM | hh:mm")
```

- [ ] **Step 2: Run the test and verify failure**

Run `tests/test-quickshell-bar.sh`.

Expected: non-zero because the old panel composition is still present.

- [ ] **Step 3: Implement the strict layout**

Rewrite only the contents of the bar window; retain these window properties:

```qml
implicitHeight: 30
exclusiveZone: 30
anchors.top: true
anchors.left: true
anchors.right: true
aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(
    root.state.screenIndex(root.screen)) === -1
```

Use two `Item { Layout.fillWidth: true }` side zones and a naturally sized
center clock so the clock remains geometrically centered regardless of left
and right content widths. Do not add mouse handlers to the clock. Keep
`RunningAppsArea` before the three system modules.

Add the read-only bar IPC methods to `shell.qml`; they are test observability,
not mutation APIs.

- [ ] **Step 4: Create the nested-X11 Phase 1 test**

Base `tests/test-quickshell-bar-xvfb.sh` on
`tests/test-quickshell-settings-xvfb.sh`. It must:

1. Require `Xvfb`, `dbus-run-session`, `quickshell`, `xdotool`, `xprop`, `pgrep`, and `getconf` or exit 77.
2. Copy the managed Quickshell tree and dwm helpers into a temporary XDG home.
3. Start Xvfb at 1280x800, start the built dwm, and start one `quickshell --no-duplicate`.
4. Wait for `quickshell ipc ... call bar height` to return `30`.
5. Assert `bar layout` returns `logo,workspaces|clock|running-apps,bluetooth,network,volume`.
6. Assert `pgrep -xc quickshell` returns `1`.
7. Launch a normal X client, maximize/tile it, and use `xdotool getwindowgeometry --shell` to assert its Y coordinate is at least 30 and its height does not overlap the bar.
8. Exercise the existing fullscreen client path and assert the bar's `aboveWindows` exception remains effective.
9. Sample closed-shell CPU for two seconds with the existing `/proc/$pid/stat` calculation and require less than 10 percent.

- [ ] **Step 5: Run Phase 1 automated verification**

Run:

```sh
scripts/run-tests make clean all
tests/test-quickshell-bar.sh
tests/test-quickshell-network.sh
tests/test-quickshell-controls.sh
tests/test-quickshell-controlcenter.sh
tests/test-quickshell-bar-xvfb.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all available tests exit 0; environment-missing nested X11 returns 77 and is recorded rather than reported as a pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add -- Makefile config/quickshell/panel/DwmPanel.qml \
  config/quickshell/shell.qml tests/test-quickshell-bar.sh \
  tests/test-quickshell-bar-xvfb.sh
git commit -m "feat: integrate the focused Omarchy-style bar"
```

### Phase 1 Review Gate

- [ ] Review the cumulative Phase 1 diff against the specification.
- [ ] Run the Phase 1 automated verification command from Task 4.
- [ ] On the disposable Fedora/dwm-titus X11 system, verify exact colors, 11 px glyph/text size, logo action, primary 1-9 workspaces, secondary local workspaces, centered clock, running application icons, Network and Volume state changes, wheel volume, no tooltips, 30 px reserved area, and fullscreen behavior.
- [ ] Record screenshots and command output in the Phase 1 section of `docs/qs-integ-acceptance.md` when that document is created in Phase 3.
- [ ] Do not start Phase 2 until Phase 1 is accepted.

---

## Phase 2: Omarchy-Style Bluetooth, Network, and Volume Panels

### Task 5: Add the shared adaptive panel surface

**Files:**
- Create: `config/quickshell/core/OmarchyPanelSurface.qml`
- Modify: `config/quickshell/core/Theme.qml`
- Create: `tests/test-quickshell-panel-layout.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces `OmarchyPanelSurface { contentImplicitWidth; contentImplicitHeight; maximumHeight; borderColor; default property contentData }`.
- Produces `availablePanelHeight(screen, panelHeight, edgeMargin): int` logic local to the component.
- Provides a single 1 px `Theme.omarchyBarActive` border and `Theme.omarchyBarBackground` surface; child windows must not add a second outer border.

- [ ] **Step 1: Write a failing panel-layout contract test**

Create `tests/test-quickshell-panel-layout.sh` asserting:

```sh
grep -F 'border.width: 1' config/quickshell/core/OmarchyPanelSurface.qml
grep -F 'border.color: Theme.omarchyBarActive' config/quickshell/core/OmarchyPanelSurface.qml
grep -F 'Math.min(contentImplicitHeight, maximumHeight)' config/quickshell/core/OmarchyPanelSurface.qml
```

Also reject `ROUTING CRUMBS`, `DNS PROVIDER`, `SpeedTest`, `wifiqr`, and
`PanelTooltip` from the three final panel files.

- [ ] **Step 2: Run the test and verify failure**

Run `tests/test-quickshell-panel-layout.sh`.

Expected: non-zero because the shared component does not exist.

- [ ] **Step 3: Implement one outer panel contract**

Create a `Rectangle`-based component with:

```qml
property int contentImplicitWidth: contentItem.implicitWidth
property int contentImplicitHeight: contentItem.implicitHeight
property int maximumHeight: 600
implicitWidth: contentImplicitWidth + leftPadding + rightPadding
implicitHeight: Math.min(contentImplicitHeight, maximumHeight)
color: Theme.omarchyBarBackground
border.color: Theme.omarchyBarActive
border.width: 1
```

Expose padding aliases or named padding properties, and one default content
property. Keep scrolling outside this component so each panel can fix its
header and scroll only its dynamic list.

- [ ] **Step 4: Run focused tests and lint**

Run:

```sh
tests/test-quickshell-panel-layout.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: both exit 0. At this task, the test checks only the shared surface.
Tasks 7, 9, and 10 each add their panel-specific rejection checks in the same
commit that makes those checks pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add -- Makefile config/quickshell/core/OmarchyPanelSurface.qml \
  config/quickshell/core/Theme.qml tests/test-quickshell-panel-layout.sh
git commit -m "feat: add adaptive Omarchy panel surface"
```

### Task 6: Extend Bluetooth data and actions before replacing its UI

**Files:**
- Modify: `scripts/dwm-quickshell-controls:430-496,565-586`
- Modify: `config/quickshell/controls/BluetoothModel.qml:8-77`
- Modify: `tests/test-quickshell-controls.sh`

**Interfaces:**
- `bluetooth-devices` produces one tab-separated row per device:
  `address, name, paired, trusted, connected, batteryPercent`.
- Adds `bluetooth-trust ADDRESS` and preserves power, scan, pair, connect, and disconnect commands.
- `BluetoothModel.devices` objects contain `address`, `name`, `paired`, `trusted`, `connected`, and `batteryPercent` where unavailable battery is `-1`.
- `BluetoothModel.message` receives non-empty bounded stderr/action failure text and clears on successful refresh.

- [ ] **Step 1: Add failing Bluetooth helper fixtures**

In `tests/test-quickshell-controls.sh`, mock `bluetoothctl info` with paired,
trusted, connected, and `Battery Percentage: 0x55 (85)` output. Assert:

```text
AA:BB:CC:DD:EE:FF\tHeadphones\tyes\tyes\tyes\t85
```

Add a test that `bluetooth-trust AA:BB:CC:DD:EE:FF` executes exactly
`bluetoothctl trust AA:BB:CC:DD:EE:FF` and rejects malformed addresses.

- [ ] **Step 2: Run the helper test and verify failure**

Run `tests/test-quickshell-controls.sh`.

Expected: non-zero because the helper emits four fields and lacks the trust action.

- [ ] **Step 3: Implement stable rows and bounded validation**

Validate addresses with:

```bash
[[ $address =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || {
    printf '%s\n' 'invalid Bluetooth address' >&2
    return 2
}
```

Parse battery percentage from `bluetoothctl info` and emit `-1` when absent.
Update `BluetoothModel.parseDevices()` for six fields. Capture action exit
status and stderr through the existing process boundary; clear `busy` on every
completion path.

- [ ] **Step 4: Run helper, QML, and shell validation**

Run:

```sh
tests/test-quickshell-controls.sh
shellcheck scripts/dwm-quickshell-controls tests/test-quickshell-controls.sh
shfmt -d scripts/dwm-quickshell-controls tests/test-quickshell-controls.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 6**

```bash
git add -- scripts/dwm-quickshell-controls \
  config/quickshell/controls/BluetoothModel.qml \
  tests/test-quickshell-controls.sh
git commit -m "feat: expose complete Bluetooth device state"
```

### Task 7: Adapt the Bluetooth panel

**Files:**
- Modify: `config/quickshell/controls/BluetoothWindow.qml:1-91`
- Modify: `tests/test-quickshell-panel-layout.sh`
- Modify: `tests/test-quickshell-controls.sh`

**Interfaces:**
- Consumes Task 5 `OmarchyPanelSurface` and Task 6 six-field device objects/actions.
- Preserves `BluetoothModel.open()`, `close()`, `toggle()`, `refresh(scan)`, and `action(name,args)`.
- Popup width derives from content with a screen-bounded maximum; list height is `Math.min(contentHeight, availableListHeight)`.

- [ ] **Step 1: Enable failing Bluetooth layout assertions**

Assert the window uses `OmarchyPanelSurface`, contains one fixed header/control
area and one clipped/flickable device list, and does not contain a decorative
subtitle phrase. Add source assertions for power, scan, pair, trust, connect,
disconnect, and battery display.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-controls.sh
```

Expected: non-zero because the old fixed 360x420 panel lacks the adapted contract.

- [ ] **Step 3: Replace fixed dimensions with content-derived geometry**

Use a fixed header row containing Bluetooth state and power/scan controls, then
one dynamic device list. Set popup width from the larger of header and row
implicit widths, clamped to the target screen width minus two edge margins.
Set popup height from header plus list content, capped to the usable screen
height below the 30 px bar. Display battery only for `batteryPercent >= 0`.
Do not add any subtitle phrase or tooltip.

- [ ] **Step 4: Run Bluetooth and layout validation**

Run:

```sh
tests/test-quickshell-controls.sh
tests/test-quickshell-panel-layout.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 7**

```bash
git add -- config/quickshell/controls/BluetoothWindow.qml \
  tests/test-quickshell-controls.sh tests/test-quickshell-panel-layout.sh
git commit -m "feat: adapt the Omarchy-style Bluetooth panel"
```

### Task 8: Add bounded Network metrics and approved actions

**Files:**
- Create: `config/quickshell/network/NetworkMetrics.js`
- Modify: `scripts/dwm-quickshell-network:1-248`
- Modify: `config/quickshell/network/NetworkModel.qml:8-372`
- Create: `tests/test-quickshell-network-metrics.sh`
- Modify: `tests/test-quickshell-network.sh`

**Interfaces:**
- `dwm-quickshell-network metrics` emits one versioned tab-separated row:
  `v1, kind, interface, label, signal, ip, gateway, rxBytes, txBytes, gatewayPingMs, internetPingMs, packetLossPercent`.
- `dwm-quickshell-network wifi-enabled` emits `yes`, `no`, or `unavailable`.
- `dwm-quickshell-network wifi-set on|off` validates the single enum and delegates to `nmcli radio wifi`.
- `dwm-quickshell-network forget UUID` validates a UUID-shaped non-empty identifier and delegates to `nmcli connection delete uuid`.
- `NetworkModel.metrics` is a plain object with the same named fields plus derived `receiveRate` and `sendRate`.
- `NetworkMetrics.throughput(previous,next,elapsedMs)` is pure and never returns a negative rate after counter reset or interface change.

- [ ] **Step 1: Write failing helper and pure-JS fixtures**

Mock `nmcli`, `ip`, `ping`, and `/sys/class/net` reads. Cover:

- Ethernet takes priority over simultaneous Wi-Fi.
- Wi-Fi signal and SSID are preserved when Ethernet is absent.
- Disconnected emits empty interface/address fields and numeric zero counters.
- IPv4 address and default gateway are parsed without human-oriented labels.
- Ping timeout produces `-1` latency without blocking beyond the helper's limit.
- Packet loss is clamped from 0 through 100.
- Counter reset and interface switch produce zero current throughput, not a negative value.
- A second metrics request is not launched while the first is running.

- [ ] **Step 2: Run Network tests and verify failure**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-network-metrics.sh
```

Expected: non-zero because the commands, format, and parser do not exist.

- [ ] **Step 3: Implement a bounded machine interface**

Use `nmcli --terse`, `ip -j` where its JSON shape is stable, and numeric
`/sys/class/net/$iface/statistics/{rx_bytes,tx_bytes}` counters. Run ping with
fixed count and deadline, for example `ping -n -q -c 2 -W 1 -w 3`. Never pass
network-derived values through `sh -c`. Emit the v1 row with tabs and no
localized prose.

In QML, add one metrics `Process`, one non-overlapping `Timer` active only while
the Network panel is visible, and a slower/inactive state path driven by the
existing `nmcli monitor`. Stop the metrics timer immediately when the panel
closes.

- [ ] **Step 4: Run Network, shell, and QML validation**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-network-metrics.sh
shellcheck scripts/dwm-quickshell-network tests/test-quickshell-network.sh \
  tests/test-quickshell-network-metrics.sh
shfmt -d scripts/dwm-quickshell-network tests/test-quickshell-network.sh \
  tests/test-quickshell-network-metrics.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 8**

```bash
git add -- scripts/dwm-quickshell-network \
  config/quickshell/network/NetworkMetrics.js \
  config/quickshell/network/NetworkModel.qml \
  tests/test-quickshell-network.sh tests/test-quickshell-network-metrics.sh
git commit -m "feat: add bounded Network panel metrics"
```

### Task 9: Adapt the Network panel with the approved exclusions

**Files:**
- Modify: `config/quickshell/network/NetworkWindow.qml:1-380`
- Modify: `config/quickshell/network/NetworkWifiRow.qml`
- Modify: `config/quickshell/network/NetworkProfileRow.qml`
- Modify: `tests/test-quickshell-panel-layout.sh`
- Modify: `tests/test-quickshell-network.sh`
- Modify: `tests/test-quickshell-bar-xvfb.sh`

**Interfaces:**
- Consumes Task 5 surface and Task 8 `NetworkModel.metrics`, known/saved profiles, visible Wi-Fi networks, actions, and errors.
- Produces fixed header/metrics area plus one bounded scrolling network-list area.
- Preserves the existing password prompt boundary and extends it only for enterprise identity when the selected security type requires it.

- [ ] **Step 1: Add failing inclusion and exclusion tests**

Assert the panel contains labels/bindings for Ping, Packet Loss, Receiving,
Sending, Downloaded, Uploaded, IP Address, Gateway, Known Networks, and Other
Networks. Assert the source and helper do not contain QR/barcode, speed-test,
DNS-provider, or decorative subtitle implementation.

Add geometry assertions through test-only IPC:

- Empty/short fixture: panel height equals header plus empty-state content and is less than the legacy 680 px.
- Long fixture: panel height is no greater than screen height minus bar and edge margins, and the list reports `contentHeight > height`.
- Popup right edge remains within the selected monitor.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-bar-xvfb.sh
```

Expected: non-zero because the old panel has Active/Wi-Fi/Saved sections and fixed dimensions rather than the approved design.

- [ ] **Step 3: Implement the approved layout without dead regions**

Build the panel in this order:

1. Connection icon, elided connection name, and Wi-Fi toggle.
2. Two-column metrics grid containing only the eight approved metrics.
3. One separator.
4. `KNOWN NETWORKS` header and rows.
5. `OTHER NETWORKS` header and rows.

Do not create components, loaders, zero-height placeholders, imports, commands,
or actions for decorative subtitle phrases, QR, speed test, or DNS. Derive known
rows from saved profiles and connected networks; deduplicate by stable SSID or
connection UUID. Put known and other sections in one bounded `Flickable` or
`ListView` so the metrics remain fixed. Preserve selection, connect,
disconnect, forget, password, and enterprise credential paths.

- [ ] **Step 4: Run Network layout and runtime validation**

Run:

```sh
tests/test-quickshell-network.sh
tests/test-quickshell-network-metrics.sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-bar-xvfb.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all available tests exit 0; an unavailable Xvfb environment returns 77.

- [ ] **Step 5: Commit Task 9**

```bash
git add -- config/quickshell/network/NetworkWindow.qml \
  config/quickshell/network/NetworkWifiRow.qml \
  config/quickshell/network/NetworkProfileRow.qml \
  tests/test-quickshell-network.sh tests/test-quickshell-panel-layout.sh \
  tests/test-quickshell-bar-xvfb.sh
git commit -m "feat: adapt the focused Omarchy Network panel"
```

### Task 10: Adapt the Volume panel and synchronize every input path

**Files:**
- Modify: `config/quickshell/controls/ControlsWindow.qml:1-360`
- Modify: `config/quickshell/controls/ControlsModel.qml:10-407`
- Modify: `tests/test-quickshell-controls.sh`
- Modify: `tests/test-quickshell-panel-layout.sh`
- Modify: `tests/test-quickshell-bar-xvfb.sh`

**Interfaces:**
- Consumes Task 5 surface and Task 3 semantic volume icon state.
- Preserves `volumeUp()`, `volumeDown()`, `volumeSet(percent)`, `volumeToggleMute()`, `outputSetDefault(name)`, media methods, output devices, and microphone state.
- Produces one fixed volume/output header and bounded optional device/media content without a decorative subtitle row.

- [ ] **Step 1: Add failing synchronization and layout tests**

Cover these sequences with mocked helper/PipeWire state:

1. Wheel up calls `volume-up 5%`; subsequent `83%` state makes icon state `high`.
2. Slider to zero makes icon state `mute` while mute flag is false.
3. External volume transitions 20 → 50 → 80 produce low → medium → high.
4. External mute produces mute and unmute at 80 returns high.
5. Action failure clears `busy`, retains the previous valid value, and sets a bounded message.

Assert the panel uses `OmarchyPanelSurface`, has one 1 px outer border, and
contains no subtitle phrase or fixed 560 px height.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```sh
tests/test-quickshell-controls.sh
tests/test-quickshell-panel-layout.sh
```

Expected: non-zero because the old fixed-size panel and error behavior do not meet the contract.

- [ ] **Step 3: Implement the adapted Volume layout**

Retain the current PipeWire signal connections as authoritative. Structure the
panel with the volume icon/value/slider and output selector fixed above any
bounded output/media lists. Remove the decorative subtitle item from the
component tree. Bind the slider display to live state when not pressed and its
pending value while pressed; commit through `volumeSet()` on release.

- [ ] **Step 4: Run Volume and runtime validation**

Run:

```sh
tests/test-quickshell-controls.sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-bar-xvfb.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all available tests exit 0; unavailable Xvfb returns 77.

- [ ] **Step 5: Commit Task 10**

```bash
git add -- config/quickshell/controls/ControlsWindow.qml \
  config/quickshell/controls/ControlsModel.qml \
  tests/test-quickshell-controls.sh tests/test-quickshell-panel-layout.sh \
  tests/test-quickshell-bar-xvfb.sh
git commit -m "feat: adapt the Omarchy-style Volume panel"
```

### Task 11: Complete Phase 2 popup integration and regression coverage

**Files:**
- Modify: `config/quickshell/shell.qml`
- Modify: `tests/test-quickshell-bar-xvfb.sh`
- Modify: `tests/test-quickshell-controlcenter.sh`
- Modify: `tests/test-quickshell-network.sh`
- Modify: `tests/test-quickshell-controls.sh`

**Interfaces:**
- Preserves `selectPanelPopup(panel,popupId)` as the one-popup-at-a-time coordinator.
- Adds read-only test IPC status for `activePopup`, panel width/height, list viewport/content height, and model busy state.
- Does not expose secrets, passphrases, SSIDs beyond what the visible UI already renders, or any mutation-only test shortcut.

- [ ] **Step 1: Add failing popup lifecycle tests**

Extend the Xvfb test to open Bluetooth, then Network, then Volume through their
normal IPC/model routes and assert exactly one is visible after every action.
For each panel, verify Escape closes it. For one panel, synthesize an outside
click and verify closure. Reopen each panel after closure to prove its model
and loader remain usable.

- [ ] **Step 2: Run the runtime test and verify failure**

Run `tests/test-quickshell-bar-xvfb.sh`.

Expected: non-zero until the read-only observability and adapted popup lifecycle are complete.

- [ ] **Step 3: Complete coordinator and observability wiring**

Keep the existing coordinator's close-before-open ordering. Add only read-only
IPC methods needed by the test. Ensure every panel's `onVisibleChanged` and
`onDismissed` paths converge on its model `close()` without recursive reopen or
stale busy state.

- [ ] **Step 4: Run the complete Phase 2 automated set**

Run:

```sh
tests/test-quickshell-bar.sh
tests/test-quickshell-controls.sh
tests/test-quickshell-network.sh
tests/test-quickshell-network-metrics.sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-controlcenter.sh
tests/test-quickshell-bar-xvfb.sh
scripts/quickshell-qmllint --root config/quickshell
```

Expected: all available tests exit 0; unavailable Xvfb returns 77.

- [ ] **Step 5: Commit Task 11**

```bash
git add -- config/quickshell/shell.qml tests/test-quickshell-bar-xvfb.sh \
  tests/test-quickshell-controlcenter.sh tests/test-quickshell-network.sh \
  tests/test-quickshell-controls.sh
git commit -m "test: cover Omarchy panel popup lifecycle"
```

### Phase 2 Review Gate

- [ ] Review the cumulative Phase 2 diff and attribution candidates against the specification.
- [ ] Run the complete Phase 2 automated set from Task 11.
- [ ] On the disposable Fedora/dwm-titus X11 system, compare Bluetooth, Network, and Volume visually with Abs's approved Omarchy reference.
- [ ] Verify all three subtitle phrases are absent and their space collapses.
- [ ] Verify every outer border is continuous, 1 px, and `#7aa2f7`.
- [ ] Verify short lists shrink, long lists scroll internally, fixed controls remain visible, and no panel crosses a monitor edge or bottom boundary.
- [ ] Verify Network's LAN/Wi-Fi icons, all approved metrics/actions, and the complete absence of QR, speed test, and DNS behavior.
- [ ] Verify Volume bar-wheel, panel-slider, external PipeWire, and zero-percent icon behavior.
- [ ] Verify Bluetooth power, scan, pair, trust, connect, disconnect, and battery state where hardware exposes it.
- [ ] Do not start Phase 3 until Phase 2 is accepted.

---

## Phase 3: Hardening and Owner Handoff

### Task 12: Align runtime and test dependencies

**Files:**
- Modify: `scripts/dwm-packages.sh:12-67`
- Modify: `scripts/check-deps.sh:110-170`
- Modify: `dwm-fedora.ks:55-130`
- Modify: `dwm-fedora-nvidia.ks:56-131`
- Modify: `tests/test-fedora-packages.sh`
- Modify: `tests/test-kickstart-variants.sh`

**Interfaces:**
- `fedora:desktop` or a dedicated required runtime capability includes `NetworkManager`, `iproute`, and `iputils` because the shipped bar requires them.
- `fedora:qml-development` includes `qt6-qtdeclarative-devel`, `xorg-x11-server-Xvfb`, `ShellCheck`, and `shfmt` only if the project intentionally exposes a complete developer-test profile; otherwise document them without installing them for end users.
- Both Kickstarts contain every required runtime package and remain semantically aligned.

- [ ] **Step 1: Add failing package-map tests**

Assert required runtime resolution includes exactly one occurrence of
`NetworkManager`, `iproute`, and `iputils`, and both Kickstarts contain all
three. Assert development/test packages do not leak into the recommended
desktop runtime transaction unless selected through the development profile.

- [ ] **Step 2: Run dependency tests and verify failure**

Run:

```sh
tests/test-fedora-packages.sh
tests/test-kickstart-variants.sh
```

Expected: non-zero because `iproute` and `iputils` are not declared in the shared map/Kickstarts.

- [ ] **Step 3: Update the single capability map and generated consumers**

Move `NetworkManager` from optional desktop status to the required desktop
capability if no other required profile already supplies it. Add `iproute` and
`iputils` beside it. Update both Kickstarts explicitly because they predeclare
their package payload. Extend `check-deps.sh` to report `ip` and `ping` with
actionable package names.

- [ ] **Step 4: Run package and shell validation**

Run:

```sh
tests/test-fedora-packages.sh
tests/test-kickstart-variants.sh
shellcheck scripts/dwm-packages.sh scripts/check-deps.sh \
  tests/test-fedora-packages.sh tests/test-kickstart-variants.sh
shfmt -d scripts/dwm-packages.sh scripts/check-deps.sh \
  tests/test-fedora-packages.sh tests/test-kickstart-variants.sh
make check-kickstart
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 12**

```bash
git add -- scripts/dwm-packages.sh scripts/check-deps.sh dwm-fedora.ks \
  dwm-fedora-nvidia.ks tests/test-fedora-packages.sh \
  tests/test-kickstart-variants.sh
git commit -m "build: declare Quickshell bar dependencies"
```

### Task 13: Add attribution, durable requirements, and owner acceptance documentation

**Files:**
- Create: `docs/OMARCHY-BAR-ATTRIBUTION.md`
- Create: `docs/qs-integ-acceptance.md`
- Modify: `SPEC.md:98-128,348-379`
- Modify: `README.md:24-35` and dependency/testing sections
- Modify: `CHANGELOG.md`

**Interfaces:**
- Attribution records the exact Omarchy repository URL, source branch/commit, source paths, original license, copied/adapted files, and material changes.
- Acceptance document records commands, exit codes, screenshots/evidence paths, dependency installation, phase gates, limitations, and rollback.
- SPEC records the final bar geometry, layout, dynamic icon states, panel exclusions, and required Fedora capabilities.

- [ ] **Step 1: Write documentation assertions before prose**

Extend `tests/test-quickshell-bar.sh` or add a documentation test that requires:

- Both new documents exist.
- Attribution contains `https://github.com/basecamp/omarchy`, the pinned source commit, and every adapted source path.
- Acceptance contains Phase 1, Phase 2, Phase 3, dependency install, real X11, evidence, and rollback sections.
- README and SPEC mention `iproute` and `iputils`.

- [ ] **Step 2: Run the documentation contract and verify failure**

Run `tests/test-quickshell-bar.sh`.

Expected: non-zero because the handoff documents do not exist.

- [ ] **Step 3: Write exact attribution and acceptance procedures**

Determine the Omarchy source commit used during implementation with:

```sh
git ls-remote https://github.com/basecamp/omarchy.git refs/heads/quattro
```

Record that immutable SHA and the specific `shell/Commons`, `shell/Ui`,
`shell/plugins/bar`, `shell/plugins/panels/audio`,
`shell/plugins/panels/bluetooth`, and `shell/plugins/panels/network` files from
which code or design was adapted. Include the upstream license text or required
notice exactly as its license requires.

In `docs/qs-integ-acceptance.md`, provide this dependency command:

```sh
sudo dnf install iproute iputils qt6-qtdeclarative-devel \
  xorg-x11-server-Xvfb ShellCheck shfmt
```

Separate runtime packages from development/test packages in the surrounding
text. Document rollback as checking out the pre-integration commit or branch,
running the repository's supported install/dev-sync path, and restarting the
managed shell only with explicit session authorization.

- [ ] **Step 4: Run documentation and diff validation**

Run:

```sh
tests/test-quickshell-bar.sh
git diff --check
```

Expected: both exit 0.

- [ ] **Step 5: Commit Task 13**

```bash
git add -- docs/OMARCHY-BAR-ATTRIBUTION.md docs/qs-integ-acceptance.md \
  SPEC.md README.md CHANGELOG.md tests/test-quickshell-bar.sh
git commit -m "docs: document Omarchy bar integration handoff"
```

### Task 14: Run full validation and prepare the fork-only handoff

**Files:**
- Modify only if validation exposes a scoped defect: files already listed in Tasks 1-13
- Update: `docs/qs-integ-acceptance.md` with observed results and evidence

**Interfaces:**
- Produces a clean `qs-integ` branch with a complete automated and real-X11 evidence record.
- Does not merge to `main`, install on the current Omarchy system, or push any branch other than `qs-integ`.

- [ ] **Step 1: Run fast static and focused verification**

Run:

```sh
git diff --check main...HEAD
scripts/quickshell-qmllint --root config/quickshell
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
tests/test-quickshell-bar.sh
tests/test-quickshell-panel-layout.sh
tests/test-quickshell-network.sh
tests/test-quickshell-network-metrics.sh
tests/test-quickshell-controls.sh
tests/test-quickshell-controlcenter.sh
```

Expected: all exit 0.

- [ ] **Step 2: Run build, complete managed suite, and staged install**

Run:

```sh
scripts/run-tests make clean all
scripts/run-tests
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
make DESTDIR="$stage" install
test -f "$stage/usr/local/bin/dwm"
test -f "$stage/usr/local/share/dwm-titus/config/quickshell/shell.qml" || \
  find "$stage" -path '*/dwm-titus/config/quickshell/shell.qml' -print -quit | grep .
```

Expected: build, suite, and staged install exit 0. Record any environment-owned skip separately; a skip is not a pass.

- [ ] **Step 3: Run nested and real X11 acceptance**

Run `tests/test-quickshell-bar-xvfb.sh`, then follow every manual item in
`docs/qs-integ-acceptance.md` on the disposable Fedora/dwm-titus X11 system.
Capture:

- Actual Fedora, Quickshell, Qt, NetworkManager, BlueZ, PipeWire, and dwm-titus revisions.
- Commands and exit codes.
- Phase 1 and Phase 2 screenshots.
- Bar geometry and app-reservation evidence.
- Short/long panel geometry and scrolling evidence.
- Dynamic Network/Volume state transitions.
- Quickshell process count and closed-idle CPU sample.

- [ ] **Step 4: Re-run final-state verification after any fixes**

After the last fix, repeat Steps 1-3 from the current `HEAD`. Do not reuse
earlier output. Confirm:

```sh
git status --short
git rev-list --left-right --count main...HEAD
```

Expected: worktree is clean; `qs-integ` is ahead of `main` with no unexpected
working-tree changes.

- [ ] **Step 5: Commit the completed evidence record**

```bash
git add -- docs/qs-integ-acceptance.md
git commit -m "test: record Quickshell bar acceptance"
```

- [ ] **Step 6: Push only the integration branch after Abs approves the final diff**

Preview:

```sh
git log --oneline main..qs-integ
git diff --stat main...qs-integ
git status --short --branch
```

After explicit approval:

```sh
git push -u origin qs-integ
git fetch --prune origin
git rev-list --left-right --count HEAD...origin/qs-integ
```

Expected final divergence: `0 0`.

### Phase 3 Review Gate

- [ ] Confirm every specification requirement maps to an implemented and tested task.
- [ ] Confirm the complete dependency appendix distinguishes existing runtime, new runtime, and development/test packages.
- [ ] Confirm attribution is complete and license-compatible.
- [ ] Confirm real-X11 evidence exists; do not describe nested-X11-only results as complete acceptance.
- [ ] Confirm no Omarchy, Hyprland, Wayland, QR, speed-test, DNS-management, or second-shell dependency entered the branch.
- [ ] Confirm the branch is clean and only `qs-integ` is proposed for fork publication.
