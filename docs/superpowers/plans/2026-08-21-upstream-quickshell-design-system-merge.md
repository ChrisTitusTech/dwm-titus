# Current Upstream Quickshell Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge current `upstream/main` into published `qs-integ` without rewriting history, preserving the accepted focused bar while adopting upstream's X11 design system, restyled menus, command menu, and hardened contracts.

**Architecture:** Create one normal two-parent merge commit. Keep the focused `qs-integ` implementations of `DwmPanel.qml`, `RunningAppItem.qml`, and `WorkspaceButton.qml`; combine upstream semantic tokens with fixed bar-only tokens in `Theme.qml`; and combine all build/test wiring in `Makefile`. Accept upstream's panel primitives, menu implementations, command-menu stack, DWM monitor tracking, package/CI/docs changes, then revise only upstream test assertions that contradict the intentionally reduced bar.

**Tech Stack:** Git, GNU Make, POSIX shell, ShellCheck, shfmt, C99/dwm, Qt 6 QML, Quickshell 0.2.x, X11/Xvfb, Fedora package profiles.

**Spec:** `docs/superpowers/specs/2026-08-21-omarchy-quickshell-bar-integration-design.md`

## Planning Baseline

- `origin/qs-integ`: `6ac680763fdcf477afd257538c6cee6921a35cc3`
- `upstream/main`: `a20ee6f82f54404bc954293268c67fe4ad85030f`
- Merge base: `2e1c042e9636155d26d6983643192ab3129cde96`
- Divergence: upstream-only `6`, `qs-integ`-only `18`.
- Since the previous `fd30ec7` plan, upstream added five commits and changed 52 files: panel/menu restyle, X11 command menu, Phase 4 plan, CodeQL update, and Phase 3 prerequisite hardening.
- Current conflicts: `Makefile`, `Theme.qml`, `DwmPanel.qml`, `RunningAppItem.qml`, `WorkspaceButton.qml`.
- `shell.qml`, `DwmState.qml`, and `tests/test-quickshell-controlcenter.sh` auto-merge but require behavioral review.

## Global Constraints

- Merge; do not rebase, squash, cherry-pick, force-push, or rewrite published `qs-integ` commits.
- Re-fetch both remotes before integration. If upstream moves beyond `a20ee6f`, regenerate the conflict map.
- If conflicts occur outside the five listed paths, stop and revise this plan again.
- Preserve X11-only operation; reject Wayland, Hyprland, WlrLayershell, `hyprctl`, `uwsm-app`, `wl-copy`, and `wl-paste` dependencies.
- Preserve bar colors exactly: background `#1a1b26`, foreground/inactive `#a9b1d6`, active/accent `#7aa2f7`, urgent `#f7768e`; retain the accepted workspace use of `Theme.accent`.
- Rename the integration-owned bar token namespace from `omarchyBar*` to `dwmBar*` across production QML, tests, and implementation documentation. Keep Omarchy only in provenance/design-origin prose.
- Preserve `dwmBarFontSize: 11`, 30 px panel/exclusive zone, three-zone layout, primary 1-9 workspaces, secondary monitor-local workspaces, `RunningAppsArea`, dynamic Network/Volume icons, volume wheel, and no tooltips.
- Do not restore tray, active title, status segments, battery, power widget, language indicator, or alternate clock behavior.
- Keep upstream semantic menu/control roles theme-derived and bar-specific `dwmBar*` roles fixed.
- Adopt upstream Bluetooth, Network, Volume, Control Center, Power, and command-menu work unless an integration test proves conflict with the focused bar.
- Do not start additional Phase 2 design work. Reassess remaining Phase 2 only after the merge passes.
- Do not push until full testing, independent review, and explicit approval.

---

### Task 1: Revalidate Inputs and Conflict Scope

**Files:**
- Inspect: `Makefile`
- Inspect: `config/quickshell/core/Theme.qml`
- Inspect: `config/quickshell/panel/DwmPanel.qml`
- Inspect: `config/quickshell/panel/RunningAppItem.qml`
- Inspect: `config/quickshell/panel/WorkspaceButton.qml`
- Inspect: `config/quickshell/shell.qml`
- Inspect: `config/quickshell/state/DwmState.qml`
- Inspect upstream: `tests/test-quickshell-panel-menus.sh`
- Inspect upstream: `tests/test-quickshell-command-menu.sh`

**Interfaces:**
- Consumes: clean local/fork `qs-integ` and freshly fetched `upstream/main`.
- Produces: exact input SHAs and a confirmed five-path conflict set.

- [ ] **Step 1: Verify branch, cleanliness, and fork equality**

```sh
git status --short --branch
test "$(git branch --show-current)" = qs-integ
git fetch --prune origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/qs-integ)"
git rev-list --left-right --count HEAD...origin/qs-integ
```

Expected: clean `qs-integ`, exact local/fork equality, divergence `0 0`.

- [ ] **Step 2: Fetch and record upstream**

```sh
git fetch --prune upstream
git rev-parse HEAD origin/qs-integ upstream/main
git rev-list --left-right --count upstream/main...HEAD
git log --oneline HEAD..upstream/main
```

Expected baseline: upstream `a20ee6f`; divergence `6 18`. If it moved, proceed only after Step 3 confirms the same conflict set.

- [ ] **Step 3: Regenerate the conflict map**

```sh
merge_output=$(mktemp "${TMPDIR:-/tmp}/qs-integ-merge-tree.XXXXXX")
if git merge-tree --write-tree HEAD upstream/main >"$merge_output" 2>&1; then
  printf '%s\n' 'Unexpected conflict-free merge; inspect before continuing.' >&2
  exit 1
fi
sed -n '/^CONFLICT (content):/p' "$merge_output"
```

Expected conflicts only in the five files listed in the planning baseline. Any additional conflict triggers another plan revision.

- [ ] **Step 4: Run the pre-merge baseline**

```sh
make check-quickshell-bar
make check-quickshell-controls check-quickshell-network check-quickshell-controlcenter
git diff --check
```

Expected: all current focused checks pass.

---

### Task 2: Merge and Resolve Build/Theme Contracts

**Files:**
- Resolve: `Makefile`
- Resolve: `config/quickshell/core/Theme.qml`
- Accept upstream: CI workflows, `scripts/dwm-packages.sh`, `scripts/dwm-quickshell-pointer`, design/command-menu tests.

**Interfaces:**
- Consumes: upstream install/test targets and semantic theme roles plus Phase 1 bar targets/tokens.
- Produces: additive build graph and one `Theme` exposing both token families.

- [ ] **Step 1: Start the merge without committing**

```sh
git merge --no-ff --no-commit upstream/main
git diff --name-only --diff-filter=U
```

Expected: exactly five planned conflicts.

- [ ] **Step 2: Resolve `Makefile` additively**

Retain upstream's installed `dwm-quickshell-pointer` and its ShellCheck/shfmt coverage. Retain these targets and their calls in `check` and `.PHONY` exactly once:

```text
check-quickshell-bar
check-quickshell-bar-xvfb
check-quickshell-design-system
check-quickshell-panel-menus
check-quickshell-command-menu
check-quickshell-qml
```

Do not select either complete side or drop existing health, settings, network, LightDM, or Xvfb gates.

- [ ] **Step 3: Resolve `Theme.qml` by combining token families**

Keep fixed bar tokens:

```qml
readonly property string dwmBarBackground: "#1a1b26"
readonly property string dwmBarForeground: "#a9b1d6"
readonly property string dwmBarInactive: "#a9b1d6"
readonly property string dwmBarActive: "#7aa2f7"
readonly property string dwmBarUrgent: "#f7768e"
```

Retain every upstream semantic surface/menu/control role, spacing/type/control dimension, and new panel token (`panelHeroIconSize`, `panelMetaLetterSpacing`, slider and toggle dimensions). Use upstream compatibility aliases but preserve:

```qml
readonly property int titleFontSize: fontTitleSize
readonly property int bodyFontSize: fontSubtitleSize
readonly property int panelFontSize: fontBodySize
readonly property int dwmBarFontSize: 11
readonly property int smallFontSize: fontBodySmallSize
readonly property int tinyFontSize: fontCaptionSize
```

Do not retain `omarchyBar*` compatibility aliases. Do not derive `dwmBar*` values from `themes.toml`.

- [ ] **Step 4: Verify and stage both resolutions**

```sh
grep -RFnE '^(<<<<<<<|=======|>>>>>>>)' Makefile config/quickshell/core/Theme.qml || true
git diff --check
git add -- Makefile config/quickshell/core/Theme.qml
git diff --name-only --diff-filter=U
```

Expected: only the three bar components remain unmerged.

---

### Task 3: Preserve Focused Bar and Reconcile Upstream Test

**Files:**
- Resolve: `config/quickshell/panel/DwmPanel.qml`
- Resolve: `config/quickshell/panel/RunningAppItem.qml`
- Resolve: `config/quickshell/panel/WorkspaceButton.qml`
- Modify: `tests/test-quickshell-panel-menus.sh`
- Test: `tests/test-quickshell-bar.sh`
- Test: `tests/test-quickshell-panel-menus.sh`

**Interfaces:**
- Consumes: accepted Phase 1 bar and upstream panel primitives/menus.
- Produces: unchanged focused bar plus full menu coverage without contradictory old-bar assertions.

- [ ] **Step 1: Resolve `DwmPanel.qml` to our focused panel**

```sh
git checkout --ours -- config/quickshell/panel/DwmPanel.qml
```

Verify literal 30 px height/zone, fixed background, `barWorkspaceIndexes`, `RunningAppsArea`, Bluetooth, Network, and Volume. Reject `TrayArea`, active title, status segments, battery, power, and old clock. Upstream `outlined` changes target removed pills and must not be recreated.

- [ ] **Step 2: Resolve `RunningAppItem.qml` to fixed bar styling**

```sh
git checkout --ours -- config/quickshell/panel/RunningAppItem.qml
```

Retain image-only rendering, fixed background/active/hover colors, click focus, and no tooltip/timer. Do not adopt theme-derived `controlSelected*` or `controlHover*` colors here.

- [ ] **Step 3: Resolve `WorkspaceButton.qml` to fixed 11 px styling**

```sh
git checkout --ours -- config/quickshell/panel/WorkspaceButton.qml
```

Retain fixed background/foreground/inactive colors, `dwmBarFontSize`, selected/occupied behavior, and no tooltip/timer. Do not adopt `panelFontSize` or semantic control colors.

- [ ] **Step 4: Adapt only contradictory old-bar assertions in `test-quickshell-panel-menus.sh`**

Preserve all checks for `PanelHero`, separator, slider, toggle, Controls, Bluetooth, Network, credentials, Control Center, Power, keyboard actions, X11 safety, and process-free primitives.

Replace old broad-bar assertions with:

```sh
grep -Fq 'exclusiveZone: 30' "$panel/DwmPanel.qml"
grep -Fq 'model: root.state.barWorkspaceIndexes(root.screen, root.primaryPanel)' "$panel/DwmPanel.qml"
grep -Fq 'RunningAppsArea {' "$panel/DwmPanel.qml"
grep -Fq 'border.color: selected ? Theme.accent' "$panel/WorkspaceButton.qml"
grep -Fq 'color: root.selected ? Theme.accent' "$panel/WorkspaceButton.qml"
grep -Fq 'Theme.dwmBarActive' "$panel/RunningAppItem.qml"
if grep -Fq 'TrayArea' "$panel/DwmPanel.qml"; then
	printf '%s\n' 'Focused bar unexpectedly restored the system tray.' >&2
	exit 1
fi
```

Remove only assertions requiring `workspaceIndexes(root.screen)`, `TrayArea`, `outlined: true` in `DwmPanel`, and `controlSelectedFill` in the two fixed bar primitives.

- [ ] **Step 5: Stage and verify manual resolutions**

```sh
git add -- config/quickshell/panel/DwmPanel.qml \
  config/quickshell/panel/RunningAppItem.qml \
  config/quickshell/panel/WorkspaceButton.qml \
  tests/test-quickshell-panel-menus.sh
git diff --name-only --diff-filter=U
git diff --cached --check
```

Expected: no unmerged files or whitespace errors.

---

### Task 4: Audit Automatic Merges and Commit

**Files:**
- Review: `config/quickshell/shell.qml`
- Review: `config/quickshell/state/DwmState.qml`
- Review: `tests/test-quickshell-controlcenter.sh`
- Review: `dwm.c`
- Review: `scripts/dwm-quickshell-state`
- Review: `scripts/dwm-quickshell-pointer`
- Review: `config/window-rules.toml`
- Review: command-menu model/window/catalog.

**Interfaces:**
- Consumes: upstream command menu/monitor tracking plus existing bar IPC and popup routing.
- Produces: mutually exclusive menus with intact bar/workspace behavior.

- [ ] **Step 1: Audit `shell.qml`**

Retain the six bar IPC methods: `height`, `layout`, `iconSizes`, `workspaceCount`, `networkIconState`, and `volumeIconState`. Verify upstream `menu` IPC, `panelForScreen`, and `openCommandMenu` coexist with `selectPanelPopup`: command menu closes all five panel models; any panel popup closes command menu.

- [ ] **Step 2: Audit state and DWM monitor behavior**

Ensure upstream `focusedMonitorIndex`/`focusedScreen()` do not replace `barWorkspaceIndexes`, both workspace-switch functions, or `fullscreenMonitorIndexes`. Primary remains 1-9; secondary remains monitor-local. Confirm DWM monitor updates and state helper output preserve reservation/fullscreen parsing.

- [ ] **Step 3: Audit the pointer helper**

Confirm 100-attempt bound, 0.05 s sleep, install/test wiring, X11-only commands, and no unbounded wait or Wayland dependency.

- [ ] **Step 4: Run focused integration tests**

```sh
make check-quickshell-bar check-quickshell-design-system \
  check-quickshell-panel-menus check-quickshell-command-menu \
  check-quickshell-controls check-quickshell-network \
  check-quickshell-controlcenter check-quickshell-qml \
  check-monitor-tags check-system-health check-settings \
  check-shell check-format
```

Expected: all targets exit 0. Record the command-menu test's explicit Qt runner skip if applicable.

- [ ] **Step 5: Inspect and create the merge commit**

```sh
git diff --cached --check
git diff --cached --stat
git status --short
git commit -m "merge: integrate upstream Quickshell updates"
git rev-list --parents -n 1 HEAD
```

Expected: exactly two parents: pre-merge `qs-integ` and fetched `upstream/main`.

---

### Task 5: Full Verification and Independent Review

**Files:**
- Verify: complete merge against both parents.

**Interfaces:**
- Consumes: two-parent merge commit.
- Produces: build, X11, packaging, ancestry, and review evidence for push approval.

- [ ] **Step 1: Run clean build and Xvfb gates**

```sh
scripts/run-tests make clean all
scripts/run-tests make check-quickshell-bar-xvfb
scripts/run-tests make check-quickshell-health-xvfb
```

Expected: passes; exit 77 is an environment skip, not real-X11 acceptance.

- [ ] **Step 2: Run packaging/install contracts**

```sh
make check-fedora-packages check-kickstart check-install \
  check-install-preservation check-lightdm-config
```

Expected: all exit 0.

- [ ] **Step 3: Run full managed suite**

```sh
scripts/run-tests
```

Expected: all runnable tests pass; record every environment skip.

- [ ] **Step 4: Verify ancestry and clean state**

```sh
git merge-base --is-ancestor upstream/main HEAD
git merge-base --is-ancestor 6ac680763fdcf477afd257538c6cee6921a35cc3 HEAD
git rev-list --left-right --count upstream/main...HEAD
git status --short --branch
```

Expected: both inputs are ancestors, upstream missing count is zero, worktree clean.

- [ ] **Step 5: Run independent scoped review**

Review both-parent diff for: complete upstream import; fixed bar palette/type/layout/geometry; complete semantic/panel tokens; narrowly revised panel-menu assertions; two-way menu exclusivity; workspace/fullscreen preservation; bounded X11 pointer helper; and no unrelated weakened tests.

Expected: no unresolved findings. Fix findings separately and rerun affected gates plus `scripts/run-tests`.

- [ ] **Step 6: Stop for explicit push approval**

Report SHAs, parents, tests, skips, findings, and divergence. Do not push automatically.

---

### Task 6: Publish and Re-Accept in Fedora VM After Approval

**Files:**
- No source changes expected unless VM testing reproduces a defect.

**Interfaces:**
- Consumes: explicit approval and reviewed commits.
- Produces: exact fork equality and real-X11 evidence before upstream PR or further Phase 2 work.

- [ ] **Step 1: Push without force and verify**

```sh
git push origin qs-integ
git fetch --prune origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/qs-integ)"
git rev-list --left-right --count HEAD...origin/qs-integ
```

Expected: fast-forward push, divergence `0 0`.

- [ ] **Step 2: Fast-forward and test the VM**

```sh
cd ~/dwm-titus
git switch qs-integ
git pull --ff-only origin qs-integ
git rev-parse HEAD
tests/test-quickshell-bar-xvfb.sh
```

Expected: exact published SHA and Xvfb PASS.

- [ ] **Step 3: Deploy and verify managed parity**

Run `scripts/dev-sync-install.sh`. If it requests a session restart, return to the dwm X11 session and run `scripts/dev-sync-install.sh --check`.

- [ ] **Step 4: Repeat real-X11 acceptance**

Verify the full Phase 1 checklist plus upstream command-menu targeting, keyboard actions, pointer placement, two-way popup exclusivity, panel rendering/actions, credential focus, and near-idle closed-state CPU.

- [ ] **Step 5: Reassess remaining Phase 2 scope**

Compare verified upstream behavior against Phase 2. Retain unresolved subtitle removal, exact Network exclusions, 1 px borders, adaptive sizing, and bounded scrolling when upstream did not already satisfy them. Do not open an upstream PR or begin further Phase 2 implementation before this reassessment and real-X11 acceptance.
