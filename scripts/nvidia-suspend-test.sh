#!/usr/bin/env bash
# nvidia-suspend-test.sh — Comprehensive NVIDIA suspend/resume readiness checker
# Tests all factors required for reliable suspend/resume with NVIDIA GPUs on Linux.
set -euo pipefail

# Use real grep, not rg alias
grep() { command grep "$@"; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0
FAIL=0
WARN=0

pass()  { PASS=$((PASS + 1)); echo -e "  ${GREEN}[PASS]${RESET} $1"; }
fail()  { FAIL=$((FAIL + 1)); echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn()  { WARN=$((WARN + 1)); echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
header(){ echo -e "\n${BOLD}=== $1 ===${RESET}"; }

# ─── GPU & Driver ───────────────────────────────────────────────────────────────
header "GPU & Driver Info"

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>/dev/null || echo "unknown")
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
    info "GPU: ${GPU_NAME}"
    info "Driver: ${DRIVER_VER}"
else
    fail "nvidia-smi not found — NVIDIA driver not installed or not in PATH"
fi

KERNEL=$(uname -r)
info "Kernel: ${KERNEL}"

if [[ -f /proc/driver/nvidia/version ]]; then
    MODULE_TYPE=$(grep -o "Open Kernel Module\|Kernel Module" /proc/driver/nvidia/version | head -1)
    info "Module type: ${MODULE_TYPE}"
else
    warn "/proc/driver/nvidia/version not found"
fi

# ─── NVIDIA Kernel Modules Loaded ────────────────────────────────────────────────
header "NVIDIA Kernel Modules"

REQUIRED_MODULES=(nvidia nvidia_modeset nvidia_drm)
OPTIONAL_MODULES=(nvidia_uvm)

for mod in "${REQUIRED_MODULES[@]}"; do
    if lsmod | grep -w "$mod" &>/dev/null; then
        pass "$mod loaded"
    else
        fail "$mod NOT loaded (required for suspend/resume)"
    fi
done

for mod in "${OPTIONAL_MODULES[@]}"; do
    if lsmod | grep -w "$mod" &>/dev/null; then
        pass "$mod loaded"
    else
        warn "$mod not loaded (optional, loaded on demand)"
    fi
done

# ─── DRM Modeset ─────────────────────────────────────────────────────────────────
header "DRM Kernel Mode Setting (KMS)"

# Check kernel command line
if grep -q "nvidia_drm.modeset=1" /proc/cmdline 2>/dev/null; then
    pass "nvidia_drm.modeset=1 set in kernel command line"
else
    # Check modprobe config
    if grep -rq "modeset=1" /etc/modprobe.d/*nvidia* 2>/dev/null; then
        pass "nvidia_drm modeset=1 set via modprobe.d"
    else
        fail "nvidia_drm.modeset=1 NOT set — required for suspend/resume"
    fi
fi

# Verify runtime value
MODESET_VAL=$(sudo cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "unreadable")
if [[ "$MODESET_VAL" == "Y" ]]; then
    pass "nvidia_drm modeset active at runtime (Y)"
elif [[ "$MODESET_VAL" == "N" ]]; then
    fail "nvidia_drm modeset is OFF at runtime — needs reboot after setting"
else
    warn "Could not read nvidia_drm modeset parameter: ${MODESET_VAL}"
fi

# Check fbdev
FBDEV_VAL=$(sudo cat /sys/module/nvidia_drm/parameters/fbdev 2>/dev/null || echo "unreadable")
if [[ "$FBDEV_VAL" == "Y" ]]; then
    pass "nvidia_drm fbdev enabled (Y)"
elif [[ "$FBDEV_VAL" == "N" ]]; then
    info "nvidia_drm fbdev disabled (optional, helps with framebuffer on resume)"
else
    info "Could not read nvidia_drm fbdev parameter"
fi

# ─── PreserveVideoMemoryAllocations ─────────────────────────────────────────────
header "PreserveVideoMemoryAllocations"

# Check modprobe config
if grep -rq "NVreg_PreserveVideoMemoryAllocations=1" /etc/modprobe.d/ 2>/dev/null; then
    pass "NVreg_PreserveVideoMemoryAllocations=1 configured in modprobe.d"
else
    fail "NVreg_PreserveVideoMemoryAllocations=1 NOT in /etc/modprobe.d/ — VRAM won't be preserved"
fi

# Check runtime value
if [[ -f /proc/driver/nvidia/params ]]; then
    PRESERVE_VAL=$(grep "PreserveVideoMemoryAllocations:" /proc/driver/nvidia/params 2>/dev/null | awk '{print $2}')
    if [[ "$PRESERVE_VAL" == "1" ]]; then
        pass "PreserveVideoMemoryAllocations active at runtime (1)"
    else
        fail "PreserveVideoMemoryAllocations is ${PRESERVE_VAL:-missing} at runtime — needs module reload or reboot"
    fi
else
    fail "/proc/driver/nvidia/params not found"
fi

# Check TemporaryFilePath
TEMP_PATH=$(grep -r "NVreg_TemporaryFilePath" /etc/modprobe.d/ 2>/dev/null | head -1 | sed -n 's/.*NVreg_TemporaryFilePath=\([^ ]*\).*/\1/p' || echo "")
if [[ -n "$TEMP_PATH" ]]; then
    if [[ -d "$TEMP_PATH" ]]; then
        pass "NVreg_TemporaryFilePath=${TEMP_PATH} (exists)"
    else
        warn "NVreg_TemporaryFilePath=${TEMP_PATH} but directory does not exist"
    fi
else
    info "NVreg_TemporaryFilePath not explicitly set (defaults to /tmp)"
fi

# ─── /proc/driver/nvidia/suspend ─────────────────────────────────────────────────
header "NVIDIA Suspend Interface"

if [[ -f /proc/driver/nvidia/suspend ]]; then
    pass "/proc/driver/nvidia/suspend exists"
else
    fail "/proc/driver/nvidia/suspend MISSING — nvidia suspend/resume cannot work"
fi

# ─── nvidia-sleep.sh ─────────────────────────────────────────────────────────────
header "nvidia-sleep.sh Script"

if [[ -x /usr/bin/nvidia-sleep.sh ]]; then
    pass "/usr/bin/nvidia-sleep.sh exists and is executable"
else
    fail "/usr/bin/nvidia-sleep.sh missing or not executable"
fi

# ─── Systemd Services ───────────────────────────────────────────────────────────
header "Systemd Suspend/Resume Services"

SERVICES=(nvidia-suspend nvidia-resume nvidia-hibernate)
for svc in "${SERVICES[@]}"; do
    ENABLED=$(systemctl is-enabled "${svc}.service" 2>/dev/null || echo "not-found")
    case "$ENABLED" in
        enabled) pass "${svc}.service enabled" ;;
        disabled) fail "${svc}.service DISABLED — run: sudo systemctl enable ${svc}.service" ;;
        *) fail "${svc}.service not found" ;;
    esac
done

# Check dependency wiring
header "Service Dependency Wiring"

SUSPEND_DEPS=$(systemctl list-dependencies systemd-suspend.service 2>/dev/null || echo "")
if echo "$SUSPEND_DEPS" | grep -q "nvidia-suspend"; then
    pass "nvidia-suspend.service wired to systemd-suspend.service"
else
    fail "nvidia-suspend.service NOT a dependency of systemd-suspend.service"
fi

if echo "$SUSPEND_DEPS" | grep -q "nvidia-resume"; then
    pass "nvidia-resume.service wired to systemd-suspend.service"
else
    fail "nvidia-resume.service NOT a dependency of systemd-suspend.service"
fi

# ─── nvidia-persistenced ─────────────────────────────────────────────────────────
header "NVIDIA Persistence Daemon"

PERSIST_ENABLED=$(systemctl is-enabled nvidia-persistenced.service 2>/dev/null || echo "not-found")
PERSIST_ACTIVE=$(systemctl is-active nvidia-persistenced.service 2>/dev/null || echo "inactive")

if [[ "$PERSIST_ENABLED" == "enabled" ]]; then
    pass "nvidia-persistenced.service enabled"
else
    fail "nvidia-persistenced.service NOT enabled — run: sudo systemctl enable nvidia-persistenced.service"
fi

if [[ "$PERSIST_ACTIVE" == "active" ]]; then
    pass "nvidia-persistenced.service running"
else
    fail "nvidia-persistenced.service NOT running — run: sudo systemctl start nvidia-persistenced.service"
fi

# ─── Initramfs / Early KMS ───────────────────────────────────────────────────────
header "Initramfs (Early KMS)"

if [[ -f /etc/mkinitcpio.conf ]]; then
    MODULES_LINE=$(grep "^MODULES=" /etc/mkinitcpio.conf 2>/dev/null | head -1)
    info "mkinitcpio MODULES: ${MODULES_LINE}"

    MISSING_MODS=()
    for mod in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        if echo "$MODULES_LINE" | grep -qw "$mod"; then
            pass "$mod in MODULES array"
        else
            MISSING_MODS+=("$mod")
            fail "$mod NOT in MODULES array"
        fi
    done

    if [[ ${#MISSING_MODS[@]} -gt 0 ]]; then
        info "Fix: Add to MODULES in /etc/mkinitcpio.conf, then run: sudo mkinitcpio -P"
    fi

    # Check hooks
    HOOKS_LINE=$(grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null | head -1)
    if echo "$HOOKS_LINE" | grep -qw "kms"; then
        pass "kms hook present in HOOKS"
    else
        warn "kms hook not in HOOKS — early KMS won't start for in-tree drivers"
    fi
else
    info "Not an mkinitcpio system (may use dracut or other initramfs generator)"

    # Check dracut
    if [[ -f /etc/dracut.conf ]] || [[ -d /etc/dracut.conf.d ]]; then
        info "dracut detected — ensure nvidia modules are included"
        if grep -rq "nvidia" /etc/dracut.conf.d/ 2>/dev/null; then
            pass "nvidia referenced in dracut config"
        else
            warn "nvidia not found in dracut config — may need add_drivers+=\" nvidia nvidia_modeset nvidia_uvm nvidia_drm \""
        fi
    fi
fi

# Verify modules in current initramfs image
INITRAMFS="/boot/initramfs-$(uname -r | sed 's/-[0-9]*-/-/').img"
# Try common naming patterns
for img in "/boot/initramfs-linux-lts.img" "/boot/initramfs-linux.img" "/boot/initramfs-$(uname -r).img" "$INITRAMFS"; do
    if [[ -f "$img" ]]; then
        INITRAMFS="$img"
        break
    fi
done

if [[ -f "$INITRAMFS" ]] && command -v lsinitcpio &>/dev/null; then
    info "Checking initramfs: ${INITRAMFS}"
    NVIDIA_KO=$(lsinitcpio "$INITRAMFS" 2>/dev/null | grep "nvidia.*\.ko" | grep -v firmware || true)
    if [[ -n "$NVIDIA_KO" ]]; then
        FOUND_COUNT=$(echo "$NVIDIA_KO" | wc -l)
        pass "${FOUND_COUNT} nvidia module(s) found in initramfs"
        while IFS= read -r line; do
            info "  ${line}"
        done <<< "$NVIDIA_KO"
    else
        fail "NO nvidia .ko modules in initramfs — display may not recover on resume"
    fi
elif [[ -f "$INITRAMFS" ]] && command -v lsinitrd &>/dev/null; then
    info "Checking initramfs (dracut): ${INITRAMFS}"
    NVIDIA_KO=$(lsinitrd "$INITRAMFS" 2>/dev/null | grep "nvidia.*\.ko" || true)
    if [[ -n "$NVIDIA_KO" ]]; then
        pass "nvidia modules found in initramfs (dracut)"
    else
        fail "NO nvidia modules in initramfs (dracut)"
    fi
else
    warn "Could not verify initramfs contents (image not found or no lsinitcpio/lsinitrd)"
fi

# ─── Sleep Mode ──────────────────────────────────────────────────────────────────
header "System Sleep Configuration"

if [[ -f /sys/power/state ]]; then
    STATES=$(cat /sys/power/state 2>/dev/null)
    info "Available sleep states: ${STATES}"
    if echo "$STATES" | grep -qw "mem"; then
        pass "S3 (mem) sleep supported"
    else
        warn "S3 (mem) sleep not available — only: ${STATES}"
    fi
fi

if [[ -f /sys/power/mem_sleep ]]; then
    MEM_SLEEP=$(cat /sys/power/mem_sleep 2>/dev/null)
    info "mem_sleep modes: ${MEM_SLEEP}"
    if echo "$MEM_SLEEP" | grep -q "\[deep\]"; then
        pass "Deep sleep (S3) is the active mode"
    elif echo "$MEM_SLEEP" | grep -q "\[s2idle\]"; then
        warn "s2idle is active — S3 deep sleep is preferred for NVIDIA. Check BIOS settings."
    fi
fi

# ─── S0ix Power Management ──────────────────────────────────────────────────────
header "S0ix / Modern Standby"

if [[ -f /proc/driver/nvidia/params ]]; then
    S0IX_VAL=$(grep "EnableS0ixPowerManagement:" /proc/driver/nvidia/params 2>/dev/null | awk '{print $2}')
    MEM_SLEEP_ACTIVE=$(cat /sys/power/mem_sleep 2>/dev/null || echo "")
    if echo "$MEM_SLEEP_ACTIVE" | grep -q "\[s2idle\]"; then
        if [[ "$S0IX_VAL" == "1" ]]; then
            pass "EnableS0ixPowerManagement=1 (correct for s2idle systems)"
        else
            warn "s2idle is active but EnableS0ixPowerManagement=${S0IX_VAL:-0} — may need NVreg_EnableS0ixPowerManagement=1"
        fi
    else
        info "EnableS0ixPowerManagement=${S0IX_VAL:-0} (not needed for S3/deep sleep)"
    fi
fi

# ─── Display Server ─────────────────────────────────────────────────────────────
header "Display Server"

SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
info "Session type: ${SESSION_TYPE}"

if [[ "$SESSION_TYPE" == "wayland" ]]; then
    info "Wayland session — suspend/resume typically handled by compositor"
elif [[ "$SESSION_TYPE" == "x11" ]]; then
    info "X11 session — nvidia-sleep.sh handles VT switching on suspend/resume"
fi

# Check display manager
for dm in sddm gdm lightdm; do
    if systemctl is-active "${dm}.service" &>/dev/null; then
        info "Display manager: ${dm}"
        break
    fi
done

# ─── Recent Suspend/Resume Logs ──────────────────────────────────────────────────
header "Recent Suspend/Resume Journal Entries"

JOURNAL_ENTRIES=$(journalctl -b -u nvidia-suspend.service -u nvidia-resume.service --no-pager -n 20 2>/dev/null || echo "")
if [[ -n "$JOURNAL_ENTRIES" && "$JOURNAL_ENTRIES" != *"No entries"* && "$JOURNAL_ENTRIES" != *"-- No entries --"* ]]; then
    info "Last nvidia suspend/resume log entries:"
    echo "$JOURNAL_ENTRIES" | while IFS= read -r line; do
        echo "    $line"
    done
else
    info "No nvidia suspend/resume entries in current boot journal"
fi

# Check for PM errors
PM_ERRORS=$(journalctl -b --grep="PM:.*failed\|nvidia.*error\|nvidia.*fail" --no-pager -n 10 2>/dev/null || echo "")
if [[ -n "$PM_ERRORS" && "$PM_ERRORS" != *"No entries"* && "$PM_ERRORS" != *"-- No entries --"* ]]; then
    warn "Power management errors found in journal:"
    echo "$PM_ERRORS" | tail -5 | while IFS= read -r line; do
        echo "    $line"
    done
fi

# ─── DKMS Status ─────────────────────────────────────────────────────────────────
header "DKMS Status"

if command -v dkms &>/dev/null; then
    DKMS_OUT=$(dkms status 2>/dev/null || echo "")
    if [[ -n "$DKMS_OUT" ]]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "installed"; then
                info "DKMS: ${line}"
            elif echo "$line" | grep -q "broken\|error"; then
                fail "DKMS issue: ${line}"
            fi
        done <<< "$DKMS_OUT"
    else
        info "No DKMS modules registered"
    fi
else
    info "DKMS not installed"
fi

# Check nvidia module matches kernel
if [[ -d "/usr/lib/modules/${KERNEL}/extramodules" ]]; then
    if [[ -f "/usr/lib/modules/${KERNEL}/extramodules/nvidia.ko.zst" ]] || \
       [[ -f "/usr/lib/modules/${KERNEL}/extramodules/nvidia.ko.gz" ]] || \
       [[ -f "/usr/lib/modules/${KERNEL}/extramodules/nvidia.ko" ]]; then
        pass "nvidia module exists for running kernel ${KERNEL}"
    else
        fail "nvidia module NOT found for running kernel ${KERNEL}"
    fi
fi

# ─── USB Autosuspend (common wake issue) ─────────────────────────────────────────
header "USB Autosuspend (wake issues)"

if [[ -f /etc/modprobe.d/disable-usb-autosuspend.conf ]]; then
    info "USB autosuspend config found: /etc/modprobe.d/disable-usb-autosuspend.conf"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  NVIDIA Suspend/Resume Test Summary${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}  ${YELLOW}WARN: ${WARN}${RESET}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All critical checks passed!${RESET}"
    echo -e "  System should be ready for NVIDIA suspend/resume."
    echo -e "  Test with: ${CYAN}systemctl suspend${RESET}"
else
    echo -e "  ${RED}${BOLD}${FAIL} critical issue(s) found.${RESET}"
    echo -e "  Fix the FAIL items above, then reboot and re-run this script."
fi

if [[ $WARN -gt 0 ]]; then
    echo -e "  ${YELLOW}${WARN} warning(s) — review if suspend/resume still fails.${RESET}"
fi
echo ""

exit $FAIL
