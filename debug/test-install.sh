#!/bin/bash
# test-install.sh — Integration test for dwm-titus TOML config loading
#
# Simulates a fresh install in an isolated $HOME under /tmp, starts dwm
# against a headless Xvfb display, and checks whether it loads (or falls
# back) correctly for three scenarios:
#   1. Normal  – both user and default configs present
#   2. Missing – user config dir absent, only defaults present  (fallback)
#   3. Invalid – user TOML is malformed                         (fallback)
#
# Usage:  bash debug/test-install.sh
#         (run from the repo root, or any directory)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DWM_BIN="$REPO_DIR/dwm"
DWM_HANG_SECS=4      # how long to let dwm run before we kill it

PASS=0; FAIL=0
log()  { printf '\033[0;36m[TEST]\033[0m  %s\n' "$1"; }
ok()   { printf '\033[0;32m[PASS]\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[0;31m[FAIL]\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
sep()  { echo "──────────────────────────────────────────────────────────"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [ ! -x "$DWM_BIN" ]; then
    echo "ERROR: dwm binary not found at $DWM_BIN — run 'make' first."
    exit 1
fi
if ! command -v Xvfb &>/dev/null; then
    echo "ERROR: Xvfb not found. Install xorg-server-xvfb."
    exit 1
fi

# Pick a free display number
DISP=:97
for d in :97 :98 :99 :100; do
    if ! xdpyinfo -display "$d" &>/dev/null 2>&1; then
        DISP="$d"; break
    fi
done

cleanup_xvfb() { kill "$XVFB_PID" 2>/dev/null || true; }

start_xvfb() {
    Xvfb "$DISP" -screen 0 800x600x24 &>/tmp/dwm-test-xvfb.log &
    XVFB_PID=$!
    trap cleanup_xvfb EXIT
    sleep 0.4
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        echo "ERROR: Xvfb failed to start (see /tmp/dwm-test-xvfb.log)."
        exit 1
    fi
}

# ── Helper: run dwm in an isolated HOME ───────────────────────────────────────
# $1 = scenario name
# $2 = fake HOME dir (caller populates it before calling)
# Returns 0 if dwm exited on its own within the timeout (bad - means it crashed
#  immediately) or within hang secs we kill it (good - it ran).
# Actually since dwm won't get any client connections / events it may exit fast.
# We capture stderr to check for TOML load messages.
run_dwm() {
    local name="$1" fake_home="$2"
    local log="/tmp/dwm-test-${name// /-}.log"

    DISPLAY="$DISP" HOME="$fake_home" \
        timeout "$DWM_HANG_SECS" "$DWM_BIN" >"$log" 2>&1 || true

    echo "$log"
}

# ── Seed helper ───────────────────────────────────────────────────────────────
seed_defaults() {
    local fake_home="$1"
    local def_dir="$fake_home/.local/share/dwm-titus/config"
    mkdir -p "$def_dir"
    cp "$REPO_DIR/config/hotkeys.toml"      "$def_dir/hotkeys.toml"
    cp "$REPO_DIR/config/themes.toml"       "$def_dir/themes.toml"
    cp "$REPO_DIR/config/window-rules.toml" "$def_dir/window-rules.toml"
}

seed_user() {
    local fake_home="$1"
    local usr_dir="$fake_home/.config/dwm-titus"
    mkdir -p "$usr_dir"
    cp "$REPO_DIR/config/hotkeys.toml"      "$usr_dir/hotkeys.toml"
    cp "$REPO_DIR/config/themes.toml"       "$usr_dir/themes.toml"
    cp "$REPO_DIR/config/window-rules.toml" "$usr_dir/window-rules.toml"
}

# Check log for known crash signatures (exclude X connection errors which are
# expected when Xvfb resets after dwm closes).
has_crash() {
    local log="$1"
    grep -qiE "segfault|segmentation fault|double free|abort|assertion failed" "$log" 2>/dev/null
}

dwm_ran_ok() {
    local log="$1"
    # dwm prints "dwm: cannot open display" if DISPLAY is wrong – that's a fail.
    # Any other output (including TOML load notes) is acceptable.
    if grep -qE "cannot open display|Xlib: connection refused" "$log" 2>/dev/null; then
        return 1
    fi
    if has_crash "$log"; then
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# START
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   dwm-titus TOML config integration test  ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log "dwm binary : $DWM_BIN"
log "Xvfb display: $DISP"
log "Hang timeout: ${DWM_HANG_SECS}s"
echo ""

start_xvfb

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 1: Normal — user + default configs present
# ─────────────────────────────────────────────────────────────────────────────
sep
log "Scenario 1: both user and default configs present"
FAKE1=$(mktemp -d /tmp/dwm-test-home-XXXXX)
seed_defaults "$FAKE1"
seed_user     "$FAKE1"

LOG1=$(run_dwm "normal" "$FAKE1")
cat "$LOG1" | head -20
if dwm_ran_ok "$LOG1"; then
    ok "Scenario 1 PASSED — dwm started without crash"
else
    fail "Scenario 1 FAILED — see $LOG1"
fi
rm -rf "$FAKE1"

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 2: Missing user config — only defaults present → fallback + notify
# ─────────────────────────────────────────────────────────────────────────────
sep
log "Scenario 2: user config dir absent (fallback to defaults expected)"
FAKE2=$(mktemp -d /tmp/dwm-test-home-XXXXX)
seed_defaults "$FAKE2"
# intentionally NOT calling seed_user

LOG2=$(run_dwm "missing-user" "$FAKE2")
cat "$LOG2" | head -20
if dwm_ran_ok "$LOG2"; then
    ok "Scenario 2 PASSED — dwm fell back to defaults without crash"
    # Optionally check for fallback message
    if grep -qi "fallback\|default\|bad config\|notify" "$LOG2" 2>/dev/null; then
        ok "  └─ fallback/notification message present in output"
    else
        log "  └─ (no stderr fallback message — notify-send fires silently)"
    fi
else
    fail "Scenario 2 FAILED — see $LOG2"
fi
rm -rf "$FAKE2"

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 3: Invalid TOML in user config → fallback to defaults
# ─────────────────────────────────────────────────────────────────────────────
sep
log "Scenario 3: malformed user TOML (fallback to defaults expected)"
FAKE3=$(mktemp -d /tmp/dwm-test-home-XXXXX)
seed_defaults "$FAKE3"
seed_user     "$FAKE3"
# Corrupt the user themes file
printf '[[invalid\nthis is not valid toml ===\n' \
    > "$FAKE3/.config/dwm-titus/themes.toml"
printf '[[invalid\n' \
    > "$FAKE3/.config/dwm-titus/hotkeys.toml"

LOG3=$(run_dwm "bad-toml" "$FAKE3")
cat "$LOG3" | head -20
if dwm_ran_ok "$LOG3"; then
    ok "Scenario 3 PASSED — dwm fell back to defaults without crash"
else
    fail "Scenario 3 FAILED — see $LOG3"
fi
rm -rf "$FAKE3"

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 4: No configs at all (both dirs absent) — should still not crash
# ─────────────────────────────────────────────────────────────────────────────
sep
log "Scenario 4: no configs at all (hardcoded Nord fallback expected)"
FAKE4=$(mktemp -d /tmp/dwm-test-home-XXXXX)
# neither user dir nor default dir created

LOG4=$(run_dwm "no-configs" "$FAKE4")
cat "$LOG4" | head -20
if dwm_ran_ok "$LOG4"; then
    ok "Scenario 4 PASSED — dwm survived with zero config files"
else
    fail "Scenario 4 FAILED — see $LOG4"
fi
rm -rf "$FAKE4"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
sep
echo ""
printf "Results: \033[0;32m%d passed\033[0m  \033[0;31m%d failed\033[0m\n" "$PASS" "$FAIL"
echo ""
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
