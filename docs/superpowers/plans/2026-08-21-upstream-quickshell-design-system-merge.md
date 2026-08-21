# Upstream Quickshell Design-System Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the current `upstream/main` into the published `qs-integ` branch without rewriting its history, preserving both upstream's general X11 Quickshell design system and the accepted Phase 1 bar contract.

**Architecture:** Use a normal merge commit so the 17 published `qs-integ` commits retain their SHAs. Accept upstream's semantic popup, menu, control, spacing, typography, CI, package-profile, documentation, and shared-core changes; manually combine the two known overlaps in `Makefile` and `config/quickshell/core/Theme.qml`. Treat the fixed Omarchy bar palette and 11 px bar size as a separate bar-specific contract, not as replacements for upstream's theme-derived semantic roles.

**Tech Stack:** Git, GNU Make, POSIX shell, ShellCheck, shfmt, Qt 6 QML, Quickshell 0.2.x, X11/Xvfb, Fedora package profiles.

**Spec:** `docs/superpowers/specs/2026-08-21-omarchy-quickshell-bar-integration-design.md`

## Global Constraints

- Merge `upstream/main`; do not rebase, squash, cherry-pick, or force-push the published `qs-integ` history.
- Re-fetch both remotes immediately before integration. The observed planning refs were `origin/qs-integ` at `2a1474000d3c71ab110faf296ce00347e89eb798` and `upstream/main` at `fd30ec77bf7e022baf1f44e73858c8eeb95f50a1`.
- If the fresh upstream tip introduces manual conflicts outside `Makefile` and `config/quickshell/core/Theme.qml`, stop and refresh this plan before resolving them.
- Preserve upstream's X11-only boundary: no Wayland, Hyprland, WlrLayershell, `hyprctl`, `uwsm-app`, `wl-copy`, or `wl-paste` dependencies.
- Preserve the Phase 1 bar's fixed colors: background `#1a1b26`, foreground/inactive `#a9b1d6`, active `#7aa2f7`, urgent `#f7768e`.
- Preserve `Theme.omarchyBarFontSize: 11`, the 30 px panel/exclusive zone, exact three-zone layout, primary workspaces 1-9, secondary monitor-local workspaces, existing `RunningAppsArea`, dynamic Network/Volume icons, volume wheel actions, and tooltip-free bar modules.
- Do not start Phase 2 panel redesign work as part of this merge.
- Do not push the merge until focused checks, the full managed suite, independent diff review, and explicit push approval are complete.

---

### Task 1: Freeze and Revalidate the Integration Inputs

**Files:**
- Inspect: `Makefile`
- Inspect: `config/quickshell/core/Theme.qml`
- Inspect: `tests/test-quickshell-bar.sh`
- Inspect from upstream: `tests/test-quickshell-design-system.sh`

**Interfaces:**
- Consumes: clean local `qs-integ`, `origin/qs-integ`, and `upstream/main` refs.
- Produces: exact input SHAs and a confirmed conflict set for the merge task.

- [ ] **Step 1: Verify the worktree and branch before fetching**

Run:

```sh
git status --short --branch
git branch --show-current
```

Expected: branch `qs-integ`; this plan has already been committed, and the worktree has no staged, modified, or untracked files.

- [ ] **Step 2: Fetch both remotes and verify the fork baseline**

Run:

```sh
git fetch --prune origin
git fetch --prune upstream
git rev-parse HEAD origin/qs-integ upstream/main
git rev-list --left-right --count HEAD...origin/qs-integ
```

Expected: local `HEAD` and `origin/qs-integ` have no unexplained divergence. If the plan document was committed locally after `2a14740`, only that named local commit may be ahead.

- [ ] **Step 3: Recompute the upstream divergence and conflict map**

Run:

```sh
git rev-list --left-right --count upstream/main...HEAD
base=$(git merge-base HEAD upstream/main)
git merge-tree "$base" HEAD upstream/main >"${TMPDIR:-/tmp}/qs-integ-upstream-merge-tree.txt"
grep -nE 'changed in both|^<<<<<<< |^=======|^>>>>>>> ' \
  "${TMPDIR:-/tmp}/qs-integ-upstream-merge-tree.txt" || true
```

Expected for the observed refs: `upstream/main` is one commit ahead, `qs-integ` is 17 commits ahead, and only `Makefile` plus `config/quickshell/core/Theme.qml` contain manual conflict markers. If upstream has moved and the conflict set expands, stop and update the plan.

- [ ] **Step 4: Record the pre-merge contract baseline**

Run:

```sh
tests/test-quickshell-bar.sh
git show upstream/main:tests/test-quickshell-design-system.sh >/dev/null
git diff --check
```

Expected: Phase 1 bar source contract passes, upstream contains its design-system test, and the local tree has no whitespace errors.

---

### Task 2: Merge Upstream and Resolve the Two Contracts

**Files:**
- Modify: `Makefile`
- Modify: `config/quickshell/core/Theme.qml`
- Accept from upstream: `.github/workflows/c-cpp.yml`
- Accept from upstream: `config/quickshell/core/MenuHeader.qml`
- Accept from upstream: `config/quickshell/core/MenuRow.qml`
- Accept from upstream: `config/quickshell/core/SectionLabel.qml`
- Accept from upstream: `config/quickshell/core/ShellButton.qml`
- Accept from upstream: `config/quickshell/core/ShellSurface.qml`
- Accept from upstream: `docs/OMARCHY-UI-ADAPTATION.md`
- Accept from upstream: `scripts/dwm-packages.sh`
- Accept from upstream: `tests/test-quickshell-design-system.sh`
- Test: `tests/test-quickshell-bar.sh`
- Test: `tests/test-quickshell-design-system.sh`

**Interfaces:**
- Consumes: upstream semantic tokens such as `popupBackground`, `menuHoverBackground`, `controlNormalFill`, spacing/type scales, and the existing bar-specific `omarchyBar*` tokens.
- Produces: one `Theme` singleton exposing both token families and one `make check` graph containing both bar and design-system gates.

- [ ] **Step 1: Start the non-rewriting merge**

Run:

```sh
git merge --no-ff --no-commit upstream/main
git status --short
git diff --name-only --diff-filter=U
```

Expected: the merge stops before commit; the only unmerged paths are `Makefile` and `config/quickshell/core/Theme.qml`.

- [ ] **Step 2: Resolve the `Makefile` test graph additively**

Keep upstream's target:

```make
check-quickshell-design-system:
	tests/test-quickshell-design-system.sh
```

Keep all three entries in the repository-wide `check` target:

```make
	$(MAKE) check-quickshell-bar
	$(MAKE) check-quickshell-design-system
	$(MAKE) check-quickshell-qml
```

The `.PHONY` continuation must contain all of these names exactly once:

```text
check-quickshell-bar
check-quickshell-bar-xvfb
check-quickshell-design-system
check-quickshell-qml
```

Do not drop any existing Phase 1, health, settings, network, LightDM, or Xvfb targets while removing the conflict markers.

- [ ] **Step 3: Resolve `Theme.qml` by preserving both token families**

Immediately after `shadow`, retain the fixed bar tokens and append upstream's semantic string roles:

```qml
readonly property string omarchyBarBackground: "#1a1b26"
readonly property string omarchyBarForeground: "#a9b1d6"
readonly property string omarchyBarInactive: "#a9b1d6"
readonly property string omarchyBarActive: "#7aa2f7"
readonly property string omarchyBarUrgent: "#f7768e"

readonly property string popupBackground: bg
readonly property string popupBorder: borderStrong
readonly property string popupText: text
readonly property string menuBackground: bg
readonly property string menuText: text
readonly property string menuMutedText: textMuted
readonly property string menuActionText: accent
readonly property string menuHoverBackground: surfaceHover
readonly property string menuHoverText: textStrong
readonly property string menuSelectedBackground: surfaceActive
readonly property string menuSelectedText: accentSecondary
readonly property string controlNormalFill: surface
readonly property string controlNormalBorder: border
readonly property string controlNormalText: text
readonly property string controlHoverFill: surfaceHover
readonly property string controlHoverBorder: borderStrong
readonly property string controlHoverText: text
readonly property string controlFocusFill: surface
readonly property string controlFocusBorder: accent
readonly property string controlFocusText: text
readonly property string controlSelectedFill: surfaceActive
readonly property string controlSelectedBorder: accentSecondary
readonly property string controlSelectedText: accentSecondary
readonly property string controlDisabledFill: barBackground
readonly property string controlDisabledBorder: border
readonly property string controlDisabledText: textMuted
```

Accept upstream's spacing/type/control scale and compatibility aliases, but keep the dedicated bar font size between the aliases:

```qml
readonly property int titleFontSize: fontTitleSize
readonly property int bodyFontSize: fontSubtitleSize
readonly property int panelFontSize: fontBodySize
readonly property int omarchyBarFontSize: 11
readonly property int smallFontSize: fontBodySmallSize
readonly property int tinyFontSize: fontCaptionSize
```

Do not derive `omarchyBar*` colors from hot-reloaded `themes.toml`; the accepted Phase 1 bar colors are intentionally fixed while upstream menu/control roles remain theme-derived.

- [ ] **Step 4: Verify the conflict resolution structurally before staging**

Run:

```sh
git diff --check
git diff --name-only --diff-filter=U
grep -RFnE '^(<<<<<<<|=======|>>>>>>>)' Makefile config/quickshell/core/Theme.qml || true
```

Expected: `git diff --check` succeeds and no conflict markers remain. Until Step 5 stages the resolutions, Git may still list the two paths as unmerged.

- [ ] **Step 5: Stage only the merge resolution and inspect the complete merge diff**

Run:

```sh
git add -- Makefile config/quickshell/core/Theme.qml
git status --short
git diff --cached --check
git diff --cached --stat
```

Expected: every path belongs to upstream commit integration or the two manual resolutions; there are no unrelated local files.

- [ ] **Step 6: Run focused contracts before committing**

Run:

```sh
make check-quickshell-bar
make check-quickshell-design-system
make check-quickshell-qml
make check-fedora-packages
make check-lightdm-config
make check-shell
make check-format
```

Expected: every target exits 0. If a target fails, preserve the uncommitted merge state, diagnose the first failure, and do not weaken either contract to make it pass.

- [ ] **Step 7: Create the merge commit without rewriting history**

Run:

```sh
git commit -m "merge: integrate upstream Quickshell design system"
git show --stat --oneline --decorate HEAD
git rev-list --parents -n 1 HEAD
```

Expected: the new commit has exactly two parents: the pre-merge `qs-integ` tip and the fetched `upstream/main` tip.

---

### Task 3: Validate the Integrated X11 Shell

**Files:**
- Verify: all files introduced or changed by the merge commit.
- Record: command output in the implementation report; do not edit Phase 2 panels.

**Interfaces:**
- Consumes: the two-parent merge commit from Task 2.
- Produces: automated evidence that upstream's shared design system and the Phase 1 bar coexist without build, packaging, QML, X11, or installer regressions.

- [ ] **Step 1: Run the focused static and package gates from a clean commit**

Run:

```sh
make check-quickshell-bar \
  check-quickshell-design-system \
  check-quickshell-qml \
  check-quickshell-network \
  check-quickshell-controls \
  check-quickshell-controlcenter \
  check-fedora-packages \
  check-kickstart \
  check-lightdm-config \
  check-shell \
  check-format
```

Expected: every target exits 0.

- [ ] **Step 2: Run clean build and nested-X11 bar validation**

Run:

```sh
scripts/run-tests make clean all
scripts/run-tests make check-quickshell-bar-xvfb
```

Expected: clean build succeeds; the Xvfb bar test passes. An exit 77 is a documented environment skip only when its named runtime dependency is unavailable and does not count as real-X11 acceptance.

- [ ] **Step 3: Run the full managed repository suite**

Run:

```sh
scripts/run-tests
```

Expected: all runnable tests pass; record any explicit environment skips verbatim. Do not claim skipped hardware or real-session behavior was validated.

- [ ] **Step 4: Verify history, ancestry, and worktree state**

Run:

```sh
git merge-base --is-ancestor upstream/main HEAD
git merge-base --is-ancestor 2a1474000d3c71ab110faf296ce00347e89eb798 HEAD
git rev-list --left-right --count upstream/main...HEAD
git status --short --branch
```

Expected: both ancestry checks exit 0, upstream has no commits missing from `HEAD`, the feature branch remains ahead by its feature/plan/merge commits, and the worktree is clean.

- [ ] **Step 5: Perform an independent scoped review**

Review the merge commit against both parents. Required review questions:

```text
Does Theme.qml retain every upstream semantic role and every fixed Phase 1 bar token?
Does Makefile run and declare both design-system and Phase 1 bar gates?
Did any automatic merge alter Phase 1 layout, X11 geometry, provider behavior, or introduce Wayland dependencies?
Are package-profile, CI, LightDM, and documentation changes internally consistent?
Were any tests weakened, deleted, or bypassed?
```

Expected: no unresolved correctness findings. Fix findings in a separate follow-up commit and rerun the affected gates plus `scripts/run-tests`.

- [ ] **Step 6: Stop for explicit push approval**

Report the merge SHA, both parent SHAs, test results, skips, review findings, and final divergence. Do not push until Abs explicitly approves.

---

### Task 4: Publish and Refresh the Fedora VM After Approval

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: explicit approval and the reviewed clean merge result.
- Produces: exact local/fork equality and a VM checkout ready for repeat acceptance.

- [ ] **Step 1: Push the existing branch without force**

Run:

```sh
git push origin qs-integ
git fetch --prune origin
```

Expected: ordinary fast-forward push; never use `--force` or `--force-with-lease`.

- [ ] **Step 2: Verify exact fork equality**

Run:

```sh
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/qs-integ)"
git rev-list --left-right --count HEAD...origin/qs-integ
```

Expected: equality test exits 0 and divergence is `0 0`.

- [ ] **Step 3: Fast-forward and verify the VM checkout**

Run in the Fedora VM:

```sh
cd ~/dwm-titus
git switch qs-integ
git pull --ff-only origin qs-integ
git rev-parse HEAD
tests/test-quickshell-bar-xvfb.sh
```

Expected: VM `HEAD` equals the published merge/follow-up tip and the Xvfb bar test passes.

- [ ] **Step 4: Repeat real-X11 Phase 1 acceptance before opening an upstream PR**

Run the managed installer/check flow from the VM checkout, restart the dwm X11 session if explicitly requested, and verify the existing Phase 1 checklist: fixed palette, 11 px bar type, exact layout, workspace behavior, RunningAppsArea, CTT Control Center action, dynamic Network/Volume icons, volume wheel, no tooltips, 30 px reservation, fullscreen stacking, one Quickshell process, and near-idle closed-state CPU.

Expected: every Phase 1 item passes or is recorded as a specific blocker. Do not open the upstream PR or start Phase 2 on an unaccepted merge.
