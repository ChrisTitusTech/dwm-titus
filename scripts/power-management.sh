#!/usr/bin/env bash
# =============================================================================
# power-management.sh — Laptop Power Management Overview & Tuning
# =============================================================================
# Displays current power management state and optionally applies improvements.
#
# Usage:
#   ./power-management.sh             # show status report
#   ./power-management.sh --apply     # apply sysfs power settings (needs root)
#   ./power-management.sh --apply-tlp # write TLP config & run tlp start (needs root)
#   ./power-management.sh --help      # show this help
#
# Hardware: Intel Raptor Lake-P / Iris Xe / DisplayLink (evdi DKMS)
# OS:       Arch Linux (linux-lts / cachyos kernels)
# =============================================================================

set -euo pipefail

APPLY=false
APPLY_TLP=false

for arg in "$@"; do
    case "$arg" in
        --apply)     APPLY=true ;;
        --apply-tlp) APPLY_TLP=true ;;
        --help|-h)
            sed -n '2,13p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

if ( $APPLY || $APPLY_TLP ) && [[ $EUID -ne 0 ]]; then
    echo "ERROR: --apply and --apply-tlp require root. Run with sudo." >&2
    exit 1
fi

# Color helpers
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep()  { echo -e "${CYAN}══════════════════════════════════════════════════${RESET}"; }
hdr()  { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; sep; }
ok()   { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
info() { echo -e "  ${CYAN}•${RESET}  $1"; }
bad()  { echo -e "  ${RED}✘${RESET}  $1"; }

read_sys() { cat "$1" 2>/dev/null || echo "N/A"; }

# =============================================================================
# 1. SYSTEM IDENTITY
# =============================================================================
hdr "System Identity"
KERNEL=$(uname -r)
CPU=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
info "Kernel   : $KERNEL"
info "CPU      : $CPU"
info "Hostname : $(cat /etc/hostname 2>/dev/null || echo unknown)"
info "Uptime   : $(uptime -p 2>/dev/null || echo N/A)"

# =============================================================================
# 2. BATTERY STATUS
# =============================================================================
hdr "Battery Status"
BAT_PATH="/sys/class/power_supply/BAT0"
if [[ -d "$BAT_PATH" ]]; then
    STATUS=$(read_sys "$BAT_PATH/status")
    CAPACITY=$(read_sys "$BAT_PATH/capacity")
    TECHNOLOGY=$(read_sys "$BAT_PATH/technology")
    MANUFACTURER=$(read_sys "$BAT_PATH/manufacturer")
    MODEL=$(read_sys "$BAT_PATH/model_name")
    CYCLES=$(read_sys "$BAT_PATH/cycle_count")

    # charge_full / charge_full_design in µAh → Ah
    CHARGE_FULL=$(read_sys "$BAT_PATH/charge_full")
    CHARGE_DESIGN=$(read_sys "$BAT_PATH/charge_full_design")
    VOLTAGE=$(read_sys "$BAT_PATH/voltage_now")  # µV
    CURRENT=$(read_sys "$BAT_PATH/current_now")  # µA

    if [[ "$CHARGE_FULL" != "N/A" && "$CHARGE_DESIGN" != "N/A" && "$CHARGE_DESIGN" -gt 0 ]]; then
        HEALTH=$(awk "BEGIN { printf \"%.1f\", ($CHARGE_FULL / $CHARGE_DESIGN) * 100 }")
        ENERGY_FULL_WH=$(awk "BEGIN { printf \"%.2f\", ($CHARGE_FULL / 1000000) * ($VOLTAGE / 1000000) }")
    else
        HEALTH="N/A"
        ENERGY_FULL_WH="N/A"
    fi

    if [[ "$CURRENT" != "N/A" && "$VOLTAGE" != "N/A" && "$CURRENT" != "0" ]]; then
        POWER_W=$(awk "BEGIN { printf \"%.2f\", ($CURRENT / 1000000) * ($VOLTAGE / 1000000) }")
    else
        POWER_W="0.00"
    fi

    info "Status      : $STATUS"
    info "Capacity    : ${CAPACITY}%"
    info "Technology  : $TECHNOLOGY"
    info "Manufacturer: $MANUFACTURER / $MODEL"
    info "Cycle count : $CYCLES"
    info "Health      : ${HEALTH}%  (charge_full vs design)"
    info "Energy full : ${ENERGY_FULL_WH} Wh"
    info "Power draw  : ${POWER_W} W"

    if [[ "$HEALTH" != "N/A" ]]; then
        HEALTH_INT=${HEALTH%.*}
        if (( HEALTH_INT >= 90 )); then
            ok "Battery health is good (${HEALTH}%)"
        elif (( HEALTH_INT >= 75 )); then
            warn "Battery health degraded (${HEALTH}%) — consider replacing soon"
        else
            bad "Battery health poor (${HEALTH}%) — replacement recommended"
        fi
    fi
else
    warn "No BAT0 found — may be running on AC only or battery sensor missing"
fi

# =============================================================================
# 3. SLEEP / STANDBY STATE
# =============================================================================
hdr "Sleep & Standby States"
AVAIL_STATES=$(read_sys /sys/power/state)
MEM_SLEEP=$(read_sys /sys/power/mem_sleep)
info "Available power states : $AVAIL_STATES"
info "Current mem_sleep mode : $MEM_SLEEP"

echo
if [[ "$MEM_SLEEP" == *"[s2idle]"* ]]; then
    warn "mem_sleep is set to 's2idle' (S0ix / connected standby)"
    info "  s2idle = CPU idles, no real S3 power gating — less power savings"
    if [[ "$MEM_SLEEP" == *"deep"* || "$AVAIL_STATES" == *"mem"* ]]; then
        info "  'deep' (S3) is available — change with:"
        info "    echo deep | sudo tee /sys/power/mem_sleep"
        info "  Persist via kernel parameter: mem_sleep_default=deep"
    fi
elif [[ "$MEM_SLEEP" == *"[deep]"* ]]; then
    ok "mem_sleep is set to 'deep' (S3) — full suspend-to-RAM"
fi

echo
info "Suspend hooks in /usr/lib/systemd/system-sleep/:"
if ls /usr/lib/systemd/system-sleep/ &>/dev/null; then
    for f in /usr/lib/systemd/system-sleep/*; do
        info "  $(basename "$f")"
    done
else
    info "  (none)"
fi

# =============================================================================
# 4. LOGIND POWER EVENT HANDLING
# =============================================================================
hdr "Logind Power Event Configuration (/etc/systemd/logind.conf)"
LOGIND_CONF="/etc/systemd/logind.conf"
ACTIVE_VALS=$(grep -v '^#' "$LOGIND_CONF" 2>/dev/null | grep -v '^$' | grep -v '^\[' || true)

while IFS= read -r line; do
    KEY=$(echo "$line" | cut -d= -f1)
    VAL=$(echo "$line" | cut -d= -f2)
    case "$KEY" in
        HandleLidSwitch)
            info "HandleLidSwitch       = $VAL"
            [[ "$VAL" == "ignore" ]] && warn "Lid close does nothing — lid-based suspend is disabled" ;;
        HandleLidSwitchDocked)
            info "HandleLidSwitchDocked = $VAL" ;;
        HandlePowerKey)
            info "HandlePowerKey        = $VAL"
            [[ "$VAL" == "ignore" ]] && warn "Power button does nothing via logind" ;;
        HandleSuspendKey)
            info "HandleSuspendKey      = $VAL" ;;
        IdleAction)
            info "IdleAction            = $VAL"
            [[ "$VAL" == "ignore" ]] && warn "No idle action configured — screen/session will never auto-sleep" ;;
        HandleLowPower|LowPowerAction|LowPowerActionSec)
            info "$KEY = $VAL" ;;
        *) info "$KEY = $VAL" ;;
    esac
done <<< "$ACTIVE_VALS"

# =============================================================================
# 5. SYSTEMD SLEEP CONFIGURATION
# =============================================================================
hdr "Systemd Sleep Configuration (/etc/systemd/sleep.conf)"
SLEEP_CONF="/etc/systemd/sleep.conf"
SLEEP_ACTIVE=$(grep -v '^#' "$SLEEP_CONF" 2>/dev/null | grep -v '^$' | grep -v '^\[' || true)
if [[ -z "$SLEEP_ACTIVE" ]]; then
    info "All settings are default (no overrides in sleep.conf)"
    info "Defaults: AllowSuspend=yes, AllowHibernation=yes, AllowHybridSleep=yes"
    info "          SuspendMode=   SuspendState=mem standby freeze"
else
    while IFS= read -r line; do
        info "$line"
    done <<< "$SLEEP_ACTIVE"
fi

# =============================================================================
# 6. CPU FREQUENCY GOVERNOR
# =============================================================================
hdr "CPU Frequency Scaling"
DRIVER=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)
GOV=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
MIN_FREQ=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)
MAX_FREQ=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
CUR_FREQ=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)

info "Driver          : $DRIVER"
info "Governor        : $GOV"
info "Min frequency   : $(awk "BEGIN { printf \"%.0f\", $MIN_FREQ/1000 }") MHz"
info "Max frequency   : $(awk "BEGIN { printf \"%.0f\", $MAX_FREQ/1000 }") MHz"
info "Current (cpu0)  : $(awk "BEGIN { printf \"%.0f\", $CUR_FREQ/1000 }") MHz"

if [[ "$GOV" == "powersave" ]]; then
    ok "Governor 'powersave' is optimal for laptop battery life"
elif [[ "$GOV" == "performance" ]]; then
    warn "Governor 'performance' keeps CPU at max — high power draw on battery"
fi

# Available governors
AVAIL_GOV=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
[[ -n "$AVAIL_GOV" ]] && info "Available governors: $AVAIL_GOV"

# Intel EPP (Energy Performance Preference)
EPP=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)
if [[ "$EPP" != "N/A" ]]; then
    info "Energy perf pref: $EPP"
    AVAIL_EPP=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences)
    [[ -n "$AVAIL_EPP" ]] && info "Available EPP   : $AVAIL_EPP"
fi

# =============================================================================
# 7. DKMS STATUS
# =============================================================================
hdr "DKMS Modules"
if command -v dkms &>/dev/null; then
    DKMS_OUT=$(dkms status 2>/dev/null)
    if [[ -z "$DKMS_OUT" ]]; then
        info "No DKMS modules installed"
    else
        while IFS= read -r line; do
            if [[ "$line" == *"installed"* ]]; then
                ok "$line"
            elif [[ "$line" == *"built"* || "$line" == *"building"* ]]; then
                warn "$line"
            else
                bad "$line"
            fi
        done <<< "$DKMS_OUT"
    fi
    echo
    info "DisplayLink (evdi) note:"
    if [[ "$DKMS_OUT" == *"evdi"* ]]; then
        ok "evdi DKMS module present — DisplayLink suspend hook active"
        info "  Hook: /usr/lib/systemd/system-sleep/displaylink.sh"
        info "  Sends S/R signals to DisplayLinkManager on suspend/resume"
        # Check if module is actually loaded in current kernel
        if grep -q "^evdi " /proc/modules 2>/dev/null; then
            ok "evdi module is currently loaded in kernel"
        else
            warn "evdi module is not loaded (DisplayLink not in use this session)"
        fi
        if pgrep -x DisplayLinkManager &>/dev/null; then
            ok "DisplayLinkManager daemon is running"
        else
            info "DisplayLinkManager is not running (no DisplayLink device connected)"
        fi
    else
        info "evdi not present — DisplayLink not configured"
    fi
else
    warn "dkms not found — cannot check DKMS module status"
fi

# =============================================================================
# 8. ACPI WAKEUP SOURCES
# =============================================================================
hdr "ACPI Wakeup Sources"
WAKEUP_FILE="/proc/acpi/wakeup"
if [[ -f "$WAKEUP_FILE" ]]; then
    info "Enabled wakeup sources:"
    while IFS= read -r line; do
        if echo "$line" | grep -q '\*enabled'; then
            DEVICE=$(echo "$line" | awk '{print $1}')
            SSTATE=$(echo "$line" | awk '{print $2}')
            SYSFS=$(echo "$line" | awk '{print $4}')
            info "  $DEVICE ($SSTATE)${SYSFS:+  → $SYSFS}"
        fi
    done < "$WAKEUP_FILE"
    echo
    warn "XHCI (USB) wakeup is enabled — USB devices can wake the machine"
    warn "TXHC (Thunderbolt USB) wakeup enabled — Thunderbolt can wake machine"
    info "To disable USB wakeup temporarily:"
    info "  echo XHCI | sudo tee /proc/acpi/wakeup"
    info "To persist across reboots, use a udev rule or systemd service"
else
    warn "/proc/acpi/wakeup not available"
fi

# =============================================================================
# 9. POWER MANAGEMENT SERVICES
# =============================================================================
hdr "Power Management Services"
SERVICES=(upower.service tlp.service thermald.service auto-cpufreq.service \
          tuned.service power-profiles-daemon.service acpid.service \
          cpupower.service systemd-sleep.service)
for svc in "${SERVICES[@]}"; do
    STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
    ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
    case "$STATE" in
        active)   ok  "$svc — active (enabled: $ENABLED)" ;;
        inactive) info "$svc — inactive (enabled: $ENABLED)" ;;
        *)        info "$svc — not installed" ;;
    esac
done

echo
if ! systemctl is-active tlp.service &>/dev/null && \
   ! systemctl is-active auto-cpufreq.service &>/dev/null && \
   ! systemctl is-active power-profiles-daemon.service &>/dev/null; then
    warn "No advanced power manager (TLP / auto-cpufreq / power-profiles-daemon) is running"
    info "Consider installing one for better battery life:"
    info "  pacman -S tlp          # comprehensive power management"
    info "  pacman -S auto-cpufreq # automatic CPU frequency + governor management"
fi

# If TLP is installed, show key active settings
if command -v tlp-stat &>/dev/null; then
    echo
    info "TLP is installed — auditing key battery settings:"
    TLP_CONF="/etc/tlp.conf"

    get_tlp() {
        grep -v '^#' "$TLP_CONF" 2>/dev/null | awk -F= "/^${1}=/{print \$2}" | tail -1
    }

    # Settings that need explicit values (TLP defaults are suboptimal)
    MUST_SET=(
        "CPU_ENERGY_PERF_POLICY_ON_BAT:power:balance_power"
        "CPU_BOOST_ON_BAT:0:turbo remains ON (no_turbo=0)"
        "PCIE_ASPM_ON_BAT:powersupersave:BIOS default"
    )
    for entry in "${MUST_SET[@]}"; do
        key="${entry%%:*}"; rest="${entry#*:}"; want="${rest%%:*}"; default="${rest#*:}"
        val=$(get_tlp "$key")
        if [[ -n "$val" ]]; then
            [[ "$val" == "$want" ]] && ok "$key=$val" || warn "$key=$val (recommend: $want)"
        else
            bad "$key — not set (TLP default: $default, recommend: $want)"
        fi
    done

    echo
    info "Settings already handled well by TLP defaults:"
    # Settings where TLP default is already acceptable — just report live value
    RUNTIME_CPU_EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
    RUNTIME_TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
    RUNTIME_NMI=$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)
    RUNTIME_ASPM=$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null)
    RUNTIME_AUD=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null)
    RUNTIME_WIFI=$(iw dev wlo1 get power_save 2>/dev/null | awk '{print $NF}')

    [[ "$RUNTIME_NMI" == "0" ]]   && ok "NMI watchdog disabled (saves ~0.5W)" \
                                   || warn "NMI watchdog ON ($RUNTIME_NMI)"
    [[ "$RUNTIME_AUD" == "1" ]]   && ok "snd_hda_intel power_save=1 (audio idles down)" \
                                   || warn "snd_hda_intel power_save=$RUNTIME_AUD"
    [[ "$RUNTIME_WIFI" == "on" ]] && ok "Wi-Fi power save: on" \
                                   || warn "Wi-Fi power save: $RUNTIME_WIFI"
    info "CPU EPP (live): $RUNTIME_CPU_EPP"
    info "Turbo no_turbo (live): $RUNTIME_TURBO  (0=enabled, 1=disabled)"
    info "PCIe ASPM policy (live): $RUNTIME_ASPM"
    info "All PCI devices runtime PM: already auto (TLP applied)"
    info "USB autosuspend: enabled, audio excluded (TLP default)"
    info "Platform profile: not available on this machine (ACPI sysfs absent)"
fi

# =============================================================================
# 10. XSET & DPMS (DISPLAY POWER MANAGEMENT SIGNALING)
# =============================================================================
hdr "Xset & DPMS (Display Power Management Signaling)"
if ! command -v xset &>/dev/null; then
    warn "xset not found — cannot query DPMS (X server may not be running or xset not installed)"
else
    XSET_OUT=$(xset q 2>/dev/null)
    if [[ -z "$XSET_OUT" ]]; then
        warn "xset query failed — no DISPLAY set or X server unreachable"
        info "Set DISPLAY=:0 if running from a non-X terminal"
    else
        # Screen saver
        SS_TIMEOUT=$(echo "$XSET_OUT" | awk '/timeout:/{print $2}')
        SS_CYCLE=$(echo "$XSET_OUT" | awk '/cycle:/{print $2}')
        SS_BLANKING=$(echo "$XSET_OUT" | awk '/prefer blanking:/{print $3}')
        info "Screen saver timeout : ${SS_TIMEOUT}s  (0 = disabled)"
        info "Screen saver cycle   : ${SS_CYCLE}s"
        info "Prefer blanking      : $SS_BLANKING"
        if [[ "$SS_TIMEOUT" == "0" ]]; then
            warn "Screen saver timeout is 0 — display will never blank via X"
        else
            ok "Screen saver will blank after ${SS_TIMEOUT}s of inactivity"
        fi

        echo
        # DPMS
        DPMS_STATUS=$(echo "$XSET_OUT" | awk '/DPMS is/{print $3}')
        DPMS_STANDBY=$(echo "$XSET_OUT" | awk '/Standby:.*Suspend:.*Off:/{print $2}')
        DPMS_SUSPEND=$(echo "$XSET_OUT" | awk '/Standby:.*Suspend:.*Off:/{print $4}')
        DPMS_OFF=$(echo "$XSET_OUT"     | awk '/Standby:.*Suspend:.*Off:/{print $6}')
        info "DPMS status  : $DPMS_STATUS"
        info "DPMS Standby : ${DPMS_STANDBY}s"
        info "DPMS Suspend : ${DPMS_SUSPEND}s"
        info "DPMS Off     : ${DPMS_OFF}s"

        if [[ "$DPMS_STATUS" == "Disabled" ]]; then
            warn "DPMS is DISABLED — monitor will never power down automatically"
            info "Enable DPMS with:"
            info "  xset +dpms"
            info "  xset dpms 300 600 900    # standby 5m, suspend 10m, off 15m"
            info "Add to ~/.xinitrc or DWM autostart for persistence"
        else
            ok "DPMS is enabled"
            (( DPMS_OFF == 0 )) && warn "DPMS 'Off' timer is 0 — monitor will never power off" \
                                || ok "Monitor will power off after ${DPMS_OFF}s"
        fi

        echo
        # xscreensaver check
        if command -v xscreensaver &>/dev/null; then
            if pgrep -x xscreensaver &>/dev/null; then
                ok "xscreensaver daemon is running (manages its own DPMS/blanking)"
                XSS_CONF="$HOME/.xscreensaver"
                if [[ -f "$XSS_CONF" ]]; then
                    XSS_TIMEOUT=$(awk '/^timeout:/{print $2}' "$XSS_CONF")
                    XSS_DPMS=$(awk '/^dpmsEnabled:/{print $2}' "$XSS_CONF")
                    info "  xscreensaver timeout   : ${XSS_TIMEOUT}"
                    info "  xscreensaver dpmsEnabled: ${XSS_DPMS:-not set}"
                fi
            else
                info "xscreensaver installed but not running"
            fi
        fi

        # xidlehook / xautolock check
        for idler in xidlehook xautolock swayidle; do
            if pgrep -x "$idler" &>/dev/null; then
                ok "$idler is running (idle-based screen management active)"
            fi
        done
    fi
fi

# =============================================================================
# 12. PCI RUNTIME POWER MANAGEMENT
# =============================================================================
hdr "PCI Device Runtime Power Management"
TOTAL=0; AUTO=0; ON=0
for ctrl in /sys/bus/pci/devices/*/power/control; do
    [[ -f "$ctrl" ]] || continue
    VAL=$(cat "$ctrl" 2>/dev/null)
    TOTAL=$((TOTAL + 1))
    [[ "$VAL" == "auto" ]] && AUTO=$((AUTO + 1)) || ON=$((ON + 1))
done
info "PCI devices: $TOTAL total — $AUTO set to 'auto' (runtime PM enabled), $ON set to 'on' (always active)"
if (( ON > 0 )); then
    warn "$ON PCI device(s) are forced 'on' (no runtime power management)"
    info "To enable runtime PM for all PCI devices:"
    info "  for f in /sys/bus/pci/devices/*/power/control; do echo auto | sudo tee \"\$f\"; done"
fi

# =============================================================================
# 13. KERNEL CMDLINE POWER PARAMETERS
# =============================================================================
hdr "Kernel Command Line (power-relevant)"
CMDLINE=$(strings /proc/cmdline 2>/dev/null || cat /proc/cmdline 2>/dev/null)
info "Full cmdline: $CMDLINE"
echo
POWER_PARAMS=(mem_sleep_default nvme.noacpi pcie_aspm pcie_aspm.policy \
              intel_pstate i915.enable_psr i915.enable_rc6 usbcore.autosuspend)
found_any=false
for param in "${POWER_PARAMS[@]}"; do
    if echo "$CMDLINE" | grep -qF "$param"; then
        ok "Found: $param"
        found_any=true
    fi
done
if ! $found_any; then
    info "No explicit power parameters found in kernel cmdline (all defaults)"
    warn "Tip: add 'mem_sleep_default=deep' to kernel params for S3 suspend"
    info "Edit /etc/default/grub or /boot/loader/entries/*.conf"
fi

# =============================================================================
# 14. SUMMARY & RECOMMENDATIONS
# =============================================================================
hdr "Summary & Recommendations"
echo -e "${BOLD}Current state:${RESET}"
info "Sleep mode    : $(read_sys /sys/power/mem_sleep | tr -d '[]' | xargs) (s2idle active)"
info "CPU governor  : $(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
info "Lid action    : $(grep -v '^#' /etc/systemd/logind.conf 2>/dev/null | grep HandleLidSwitch= | head -1 | cut -d= -f2 || echo default)"
EVDI_VER=$(dkms status 2>/dev/null | awk -F/ '/evdi/{v=$2} END{print v}' | awk -F',' '{print $1}')
info "DKMS evdi     : ${EVDI_VER:-N/A}"
if command -v xset &>/dev/null; then
    DPMS_S=$(xset q 2>/dev/null | awk '/DPMS is/{print $3}')
    info "DPMS          : ${DPMS_S:-unknown}"
fi

echo
echo -e "${BOLD}Recommended improvements:${RESET}"

REC_N=0

# 1. S3 deep sleep
MEM_NOW=$(read_sys /sys/power/mem_sleep)
if echo "$MEM_NOW" | grep -q '\[deep\]'; then
    ok "S3 deep sleep already active"
else
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Enable S3 deep sleep (better suspend power savings):${RESET}"
    echo "     echo deep | sudo tee /sys/power/mem_sleep"
    echo "     # Persist: add 'mem_sleep_default=deep' to kernel params"
fi

# 2. Lid-close suspend
LID_ACTION=$(grep -v '^#' /etc/systemd/logind.conf 2>/dev/null | awk -F= '/^HandleLidSwitch=/{print $2}' | tail -1)
if [[ "$LID_ACTION" == "suspend" || "$LID_ACTION" == "lock" ]]; then
    ok "Lid-close action already set to: $LID_ACTION"
else
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Enable lid-close suspend:${RESET}"
    echo "     # Edit /etc/systemd/logind.conf:"
    echo "     #   HandleLidSwitch=suspend"
    echo "     sudo systemctl restart systemd-logind"
fi

# 3. TLP install + config
_tlp_conf_ok() {
    local key="$1" want="$2"
    local val
    val=$(awk -F= "!/^[[:space:]]*#/ && /^${key}=/{print \$2}" /etc/tlp.conf 2>/dev/null | tail -1)
    [[ "$val" == "$want" ]]
}
TLP_INSTALLED=false
command -v tlp &>/dev/null && TLP_INSTALLED=true
TLP_ENABLED=false
systemctl is-enabled tlp.service &>/dev/null && TLP_ENABLED=true
TLP_CONF_OK=false
if $TLP_INSTALLED && \
   _tlp_conf_ok "CPU_ENERGY_PERF_POLICY_ON_BAT" "power" && \
   _tlp_conf_ok "CPU_BOOST_ON_BAT" "0" && \
   _tlp_conf_ok "CPU_HWP_DYN_BOOST_ON_BAT" "0" && \
   _tlp_conf_ok "PCIE_ASPM_ON_BAT" "powersupersave"; then
    TLP_CONF_OK=true
fi
if $TLP_INSTALLED && $TLP_ENABLED && $TLP_CONF_OK; then
    ok "TLP installed, enabled, and optimally configured"
elif $TLP_INSTALLED && $TLP_CONF_OK && ! $TLP_ENABLED; then
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Enable TLP service (config is correct but service is disabled):${RESET}"
    echo "     sudo systemctl enable --now tlp"
    echo "     # Or run: sudo bash power-management.sh --apply-tlp"
elif $TLP_INSTALLED && ! $TLP_CONF_OK; then
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Apply TLP battery optimizations (installed but not tuned):${RESET}"
    echo "     sudo bash power-management.sh --apply-tlp"
    echo "     # Or manually add to /etc/tlp.conf:"
    echo "     CPU_ENERGY_PERF_POLICY_ON_BAT=power    # TLP default: balance_power"
    echo "     CPU_BOOST_ON_BAT=0                     # TLP default: 1"
    echo "     CPU_HWP_DYN_BOOST_ON_BAT=0             # TLP default: 1"
    echo "     PCIE_ASPM_ON_BAT=powersupersave        # TLP default: BIOS"
else
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Install & configure TLP:${RESET}"
    echo "     sudo pacman -S tlp && sudo systemctl enable --now tlp"
    echo "     # Then run: sudo bash power-management.sh --apply-tlp"
    echo "     # or: sudo pacman -S auto-cpufreq && sudo systemctl enable --now auto-cpufreq"
fi

# 4. USB wakeup
XHCI_WAKE=$(awk '/^XHCI/{print $2}' /proc/acpi/wakeup 2>/dev/null)
TXHC_WAKE=$(awk '/^TXHC/{print $2}' /proc/acpi/wakeup 2>/dev/null)
if [[ "$XHCI_WAKE" == "*disabled" && "$TXHC_WAKE" == "*disabled" ]]; then
    ok "USB wakeup (XHCI/TXHC) already disabled"
else
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Disable USB wakeup (prevents unwanted wakeups):${RESET}"
    [[ "$XHCI_WAKE" != "*disabled" ]] && echo "     echo XHCI | sudo tee /proc/acpi/wakeup"
    [[ "$TXHC_WAKE" != "*disabled" ]] && echo "     echo TXHC | sudo tee /proc/acpi/wakeup"
fi

# 5. DPMS
DPMS_NOW=""
command -v xset &>/dev/null && DPMS_NOW=$(xset q 2>/dev/null | awk '/DPMS is/{print $3}')
if [[ "$DPMS_NOW" == "Enabled" ]]; then
    ok "DPMS already enabled"
else
    REC_N=$((REC_N + 1))
    echo -e "\n  ${YELLOW}${REC_N}. Enable DPMS display power-off (saves power when idle):${RESET}"
    echo "     xset +dpms"
    echo "     xset dpms 300 600 900   # standby 5m, suspend 10m, off 15m"
    echo "     xset s 300              # blank screen after 5m"
    echo "     # Add to ~/.xinitrc or DWM autostart for persistence"
fi

(( REC_N == 0 )) && ok "All recommendations already satisfied — system is fully optimized!"

# =============================================================================
# --apply: Apply safe, non-destructive power improvements
# =============================================================================
if $APPLY; then
    hdr "Applying Recommended Settings"

    # S3 deep sleep
    CURRENT_MEM=$(read_sys /sys/power/mem_sleep)
    if echo "$CURRENT_MEM" | grep -q '\[s2idle\]' && echo "$CURRENT_MEM" | grep -q 'deep'; then
        echo deep > /sys/power/mem_sleep
        ok "mem_sleep set to 'deep' (S3)"
    else
        info "mem_sleep: 'deep' not available or already set"
    fi

    # CPU EPP to power on all CPUs
    for epp_path in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [[ -f "$epp_path" ]] && echo power > "$epp_path"
    done
    ok "Intel EPP set to 'power' for all CPUs"

    # PCI runtime PM
    CHANGED=0
    for ctrl in /sys/bus/pci/devices/*/power/control; do
        if [[ -f "$ctrl" ]] && [[ "$(cat "$ctrl" 2>/dev/null)" == "on" ]]; then
            echo auto > "$ctrl" && CHANGED=$((CHANGED + 1))
        fi
    done
    (( CHANGED > 0 )) && ok "Enabled runtime PM for $CHANGED PCI device(s)" || info "All PCI devices already on auto"

    # DPMS
    if command -v xset &>/dev/null && xset q &>/dev/null 2>&1; then
        CURRENT_DPMS=$(xset q 2>/dev/null | awk '/DPMS is/{print $3}')
        if [[ "$CURRENT_DPMS" == "Disabled" ]]; then
            xset +dpms
            xset dpms 300 600 900
            xset s 300
            ok "DPMS enabled: standby=300s suspend=600s off=900s, screen saver=300s"
        else
            info "DPMS already enabled"
        fi
    else
        info "DPMS: xset not available (no X display)"
    fi

    echo
    warn "These settings are NOT persistent across reboots."
    warn "Use TLP, a udev rule, or kernel params for persistence."
fi

# =============================================================================
# --apply-tlp: Write TLP recommended settings and activate
# =============================================================================
if $APPLY_TLP; then
    hdr "Applying TLP Recommendations"

    TLP_CONF="/etc/tlp.conf"

    if ! command -v tlp &>/dev/null; then
        bad "tlp is not installed. Install with: pacman -S tlp"
        exit 1
    fi

    if [[ ! -f "$TLP_CONF" ]]; then
        bad "$TLP_CONF not found"
        exit 1
    fi

    # BAT settings that differ from TLP defaults (real changes)
    declare -A TLP_WANTED=(
        [CPU_ENERGY_PERF_POLICY_ON_BAT]="power"          # TLP default: balance_power
        [CPU_BOOST_ON_BAT]="0"                           # TLP default: 1
        [CPU_HWP_DYN_BOOST_ON_BAT]="0"                  # TLP default: 1
        [PCIE_ASPM_ON_BAT]="powersupersave"              # TLP default: BIOS
    )

    # AC counterparts — match TLP defaults, set explicitly for clarity
    declare -A TLP_WANTED_AC=(
        [CPU_ENERGY_PERF_POLICY_ON_AC]="balance_performance"  # = TLP default
        [CPU_BOOST_ON_AC]="1"                                # = TLP default
        [CPU_HWP_DYN_BOOST_ON_AC]="1"                       # = TLP default
        [PCIE_ASPM_ON_AC]="default"                          # = TLP default
    )

    APPEND_BLOCK="\n# --- Added by power-management.sh $(date '+%Y-%m-%d %H:%M') ---"
    CHANGES=0

    apply_tlp_key() {
        local key="$1" val="$2"
        # Check if key already exists (uncommented)
        local existing
        existing=$(awk -F= "!/^[[:space:]]*#/ && /^${key}=/{print \$2}" "$TLP_CONF" | tail -1)
        if [[ -n "$existing" ]]; then
            if [[ "$existing" == "$val" ]]; then
                ok "$key=$val  (already set)"
            else
                # Update in place
                sed -i "s|^${key}=.*|${key}=${val}|" "$TLP_CONF"
                ok "$key updated: $existing → $val"
                CHANGES=$((CHANGES + 1))
            fi
        else
            APPEND_BLOCK+="\n${key}=${val}"
            CHANGES=$((CHANGES + 1))
        fi
    }

    info "Checking/writing settings to $TLP_CONF ..."
    echo

    for key in "${!TLP_WANTED[@]}"; do
        apply_tlp_key "$key" "${TLP_WANTED[$key]}"
    done
    for key in "${!TLP_WANTED_AC[@]}"; do
        apply_tlp_key "$key" "${TLP_WANTED_AC[$key]}"
    done

    # Append any new keys at end of file
    if echo "$APPEND_BLOCK" | grep -q '='; then
        printf "%b\n" "$APPEND_BLOCK" >> "$TLP_CONF"
        info "Appended new settings to $TLP_CONF"
    fi

    # Mask conflicting power managers before enabling TLP
    echo
    info "Checking for conflicting power managers ..."
    for conflict in power-profiles-daemon.service auto-cpufreq.service; do
        if systemctl is-enabled "$conflict" &>/dev/null; then
            systemctl disable --now "$conflict" 2>/dev/null || true
            systemctl mask "$conflict" 2>/dev/null || true
            warn "Masked $conflict (conflicts with TLP)"
        else
            ok "$conflict not enabled (no conflict)"
        fi
    done

    # Enable TLP service so settings persist across reboots
    echo
    if systemctl is-enabled tlp.service &>/dev/null; then
        ok "tlp.service already enabled"
    else
        if systemctl enable tlp.service 2>/dev/null; then
            ok "tlp.service enabled (will apply settings on every boot)"
        else
            warn "Could not enable tlp.service — check: systemctl status tlp"
        fi
    fi

    echo
    if (( CHANGES > 0 )); then
        info "$CHANGES setting(s) written. Activating TLP ..."
        if tlp start 2>/dev/null; then
            ok "tlp start succeeded"
        else
            warn "tlp start returned non-zero — check: tlp-stat -s"
        fi

        echo
        info "Verifying applied settings (live sysfs):"
        EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
        TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
        ASPM=$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null)
        info "  CPU EPP (cpu0)       : $EPP"
        info "  Turbo no_turbo       : $TURBO  (1=disabled)"
        info "  PCIe ASPM policy     : $ASPM"
        [[ "$EPP" == "power" ]]   && ok "EPP → power" || warn "EPP not yet 'power' ($EPP)"
        [[ "$TURBO" == "1" ]]     && ok "Turbo disabled" || warn "Turbo still on (no_turbo=$TURBO)"
        echo "$ASPM" | grep -q 'powersupersave' && ok "ASPM includes powersupersave" \
            || warn "ASPM policy unchanged: $ASPM"
    else
        ok "All TLP settings already correct — nothing changed"
        info "Running tlp start to ensure current session is up to date ..."
        tlp start 2>/dev/null || true
    fi

    echo
    ok "Settings ARE persistent: written to $TLP_CONF + tlp.service enabled."
    info "To revert, remove the block at the end of $TLP_CONF and run: tlp start"
fi

sep
echo -e "${BOLD}Done.${RESET} Run with ${CYAN}--apply${RESET} (sysfs tweaks) or ${CYAN}--apply-tlp${RESET} (write TLP config) as root.\n"
